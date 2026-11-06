with Ada.Containers;
with Lua.Lexers; use Lua.Lexers;
with Lua.Syntax;
with Lua.Syntax_Trees; use Lua.Syntax_Trees;

package body Lua.Engine.Compiler is
   use type Ada.Containers.Count_Type;
   use type Lua.Syntax.Check_Status;
   use type Registers.Vector;

   function Compile
     (State : in out World; Source, Name : String) return Prototype_Access
   is
      Unit : Compilation_Unit;
      Current : Prototype_Access;
      Next_Register : Positive := 1;
      Scope_Depth : Natural := 0;
      Symbol_Base : constant Positive := State.Next_Symbol;
      Site : Source_Location;
      type Target is record
         Symbol : Natural := 0;
         Table_Reg, Key_Reg : Natural := 0;
      end record;
      package Targets is new Ada.Containers.Vectors (Positive, Target);
      type Loop_Context is record
         Depth : Natural;
         Breaks : Registers.Vector;
      end record;
      package Loops is new Ada.Containers.Vectors (Positive, Loop_Context);
      Loop_Stack : Loops.Vector;

      function Fetch (Id : Node_Id) return Node is
        (Unit.Tree (Positive (Id)));
      function Symbol (Id : Symbol_Id) return Positive is
        (Symbol_Base + Positive (Id) - 1);
      function New_Register return Positive;
      function Emit (Code : Instruction) return Positive;
      procedure Put (Code : Instruction);
      procedure Patch (Index : Positive; Destination : Natural);
      function Expression (Id : Node_Id) return Positive;
      function List (Id : Node_Id) return Registers.Vector;
      function Pick (Inputs : Registers.Vector; Index : Positive)
                     return Positive;
      function Address (Id : Node_Id) return Target;
      procedure Store (Where : Target; Register_Id : Positive);
      procedure Block (Id : Node_Id; Own_Scope : Boolean := True);
      procedure Statement (Id : Node_Id);
      function Function_Body (Id : Node_Id) return Positive;
      procedure Close_Loop;

      function New_Register return Positive is
         Result : constant Positive := Next_Register;
      begin
         if Result > State.Bounds.Registers then
            State.Current.Failure_At := Site;
            Fail (State, "register limit exceeded", Resource => True);
         end if;
         Next_Register := Next_Register + 1;
         Current.Register_Count := Natural'Max
           (Current.Register_Count, Result);
         return Result;
      end New_Register;

      function Emit (Code : Instruction) return Positive is
         Item : Instruction := Code;
      begin
         Item.Location := Site;
         Current.Code.Append (Item);
         return Current.Code.Last_Index;
      end Emit;

      procedure Put (Code : Instruction) is
         Ignored : constant Positive := Emit (Code);
         pragma Unreferenced (Ignored);
      begin
         null;
      end Put;

      procedure Patch (Index : Positive; Destination : Natural) is
         Item : Instruction := Current.Code (Index);
      begin
         Item.Target := Destination;
         Current.Code.Replace_Element (Index, Item);
      end Patch;

      function List (Id : Node_Id) return Registers.Vector is
         Result : Registers.Vector;
      begin
         --  The machine's packet convention expands only the final register
         --  in these source-ordered lists. Scalar adjustment stays explicit.
         if Id /= No_Node then
            for Item of Fetch (Id).Children loop
               Result.Append (Expression (Item));
            end loop;
         end if;
         return Result;
      end List;

      function Pick (Inputs : Registers.Vector; Index : Positive)
                     return Positive
      is
         Result : constant Positive := New_Register;
      begin
         Put ((Op => Pick_Value, A => Result, B => Index,
               Inputs => Inputs, others => <>));
         return Result;
      end Pick;

      function Address (Id : Node_Id) return Target is
         Item : constant Node := Fetch (Id);
         Result : Target;
      begin
         --  Capture receiver/key values before any RHS evaluation or stores.
         --  This descriptor is an lvalue, not a speculative table read.
         Site := Item.Site;
         if Item.Kind = Name_Reference then
            if Item.Symbol /= No_Symbol then
               Result.Symbol := Symbol (Item.Symbol);
            else
               Result.Table_Reg := New_Register;
               Put ((Op => Read_Local, A => Result.Table_Reg,
                     B => Symbol (Item.Environment), others => <>));
               Result.Key_Reg := New_Register;
               Put ((Op => Load_String, A => Result.Key_Reg,
                     Text => Item.Text, others => <>));
            end if;
         else
            Result.Table_Reg := Expression (Item.Children (1));
            Result.Key_Reg := Expression (Item.Children (2));
         end if;
         return Result;
      end Address;

      procedure Store (Where : Target; Register_Id : Positive) is
      begin
         if Where.Symbol /= 0 then
            Put ((Op => Write_Local, A => Register_Id, B => Where.Symbol,
                  others => <>));
         else
            Put ((Op => Set_Item, A => Where.Table_Reg, B => Where.Key_Reg,
                  C => Register_Id, others => <>));
         end if;
      end Store;

      function Function_Body (Id : Node_Id) return Positive is
         Item : constant Node := Fetch (Id);
         Outer : constant Prototype_Access := Current;
         Saved_Register : constant Positive := Next_Register;
         Saved_Depth : constant Natural := Scope_Depth;
         Saved_Loops : constant Loops.Vector := Loop_Stack;
         Child : constant Prototype_Access := new Prototype;
         Result : Positive;
      begin
         --  Publish partial prototypes immediately: runtime ownership must
         --  reclaim them even when lowering exhausts a register budget.
         State.Programs.Append (Child);
         Child.Name := Outer.Name;
         Child.Environment_Symbol := Outer.Environment_Symbol;
         Child.Vararg := Item.Flag;
         if Item.Symbol /= No_Symbol then
            Child.Vararg_Name := Symbol (Item.Symbol);
         end if;
         for Parameter of Item.Symbols loop
            Child.Parameters.Append (Symbol (Parameter));
         end loop;
         Current := Child;
         Next_Register := 1;
         Scope_Depth := 0;
         Loop_Stack.Clear;
         Block (Item.Children (1), Own_Scope => False);
         Put ((Op => Return_Values, others => <>));
         Current := Outer;
         Next_Register := Saved_Register;
         Scope_Depth := Saved_Depth;
         Loop_Stack := Saved_Loops;
         Result := New_Register;
         Put ((Op => Make_Closure, A => Result,
               Nested => Child, others => <>));
         return Result;
      end Function_Body;

      function Expression (Id : Node_Id) return Positive is
         Item : constant Node := Fetch (Id);
         Result, Left, Right : Positive;
         Branch : Natural := 0;
         Inputs : Registers.Vector;
         Where : Target;
         Sequence : Positive := 1;
      begin
         --  This pass consumes resolved syntax only. It cannot invent lexical
         --  declarations or accept/reject grammar differently from Check.
         --  Child order encodes Lua's evaluation order, including retained
         --  lvalue addresses and short-circuit branch placement.
         Site := Item.Site;
         if Item.Kind = Function_Expression then
            return Function_Body (Id);
         end if;
         Result := New_Register;
         case Item.Kind is
            when Literal =>
               case Item.Value.Kind is
                  when Integer_Literal =>
                     Put ((Op => Load_Value, A => Result,
                           Literal => (Integer_Kind,
                                       Item.Value.Numeric.Integer_Item),
                           others => <>));
                  when Float_Literal =>
                     Put ((Op => Load_Value, A => Result,
                           Literal => (Real_Kind,
                                       Item.Value.Numeric.Real_Item),
                           others => <>));
                  when String_Literal =>
                     Put ((Op => Load_String, A => Result,
                           Text => Item.Value.Text, others => <>));
                  when True_Word | False_Word =>
                     Put ((Op => Load_Value, A => Result,
                           Literal => (Boolean_Kind,
                                       Item.Value.Kind = True_Word),
                           others => <>));
                  when Varargs =>
                     Put ((Op => Read_Varargs, A => Result, others => <>));
                  when others =>
                     Put ((Op => Load_Value, A => Result, others => <>));
               end case;
            when Name_Reference | Index_Expression =>
               Where := Address (Id);
               if Where.Symbol /= 0 then
                  Put ((Op => Read_Local, A => Result, B => Where.Symbol,
                        others => <>));
               else
                  Put ((Op => Get_Item, A => Result, B => Where.Table_Reg,
                        C => Where.Key_Reg, others => <>));
               end if;
            when Parenthesized =>
               Left := Expression (Item.Children (1));
               Put ((Op => Move_First, A => Result, B => Left, others => <>));
            when Unary_Expression =>
               Left := Expression (Item.Children (1));
               Site := Item.Site;
               Put ((Op => Unary, A => Result, B => Left,
                     Operator => Item.Operator, others => <>));
            when Binary_Expression =>
               Left := Expression (Item.Children (1));
               if Item.Operator in And_Word | Or_Word then
                  Put ((Op => Move_First, A => Result, B => Left,
                        others => <>));
                  Branch := Emit
                    ((Op => (if Item.Operator = And_Word then Jump_False
                             else Jump_True), A => Left, others => <>));
               end if;
               Right := Expression (Item.Children (2));
               Site := Item.Site;
               if Branch /= 0 then
                  Put ((Op => Move_First, A => Result, B => Right,
                        others => <>));
                  Patch (Branch, Natural (Current.Code.Length) + 1);
               else
                  Put ((Op => Binary, A => Result, B => Left, C => Right,
                        Operator => Item.Operator, others => <>));
               end if;
            when Call_Expression =>
               declare
                  Callee : constant Node := Fetch (Item.Children (1));
               begin
                  if Callee.Kind = Method_Expression then
                     Left := Expression (Callee.Children (1));
                     Right := New_Register;
                     Put ((Op => Move_First, A => Right, B => Left,
                           others => <>));
                     Inputs.Append (Right);
                     Right := Expression (Callee.Children (2));
                     declare
                        Function_Reg : constant Positive := New_Register;
                     begin
                        Put ((Op => Get_Item, A => Function_Reg, B => Left,
                              C => Right, others => <>));
                        Left := Function_Reg;
                     end;
                  else
                     Left := Expression (Item.Children (1));
                  end if;
               end;
               for Argument of List (Item.Children (2)) loop
                  Inputs.Append (Argument);
               end loop;
               Site := Item.Site;
               Put ((Op => Call_Function, A => Result, B => Left,
                     Inputs => Inputs, others => <>));
            when Table_Expression =>
               Put ((Op => New_Table, A => Result, others => <>));
               for Index in Item.Children.First_Index ..
                 Item.Children.Last_Index
               loop
                  declare
                     Field : constant Node := Fetch (Item.Children (Index));
                  begin
                     if Field.Children.Length = 1 then
                        Left := Expression (Field.Children (1));
                        Inputs.Clear;
                        Inputs.Append (Left);
                        Put ((Op => Set_Sequence, A => Result, B => Sequence,
                              C => Boolean'Pos
                                (Index = Item.Children.Last_Index),
                              Inputs => Inputs, others => <>));
                        Sequence := Sequence + 1;
                     else
                        Left := Expression (Field.Children (1));
                        Right := Expression (Field.Children (2));
                        Put ((Op => Set_Item, A => Result, B => Left,
                              C => Right, others => <>));
                     end if;
                  end;
               end loop;
            when others =>
               raise Program_Error with "non-expression syntax node";
         end case;
         return Result;
      end Expression;

      procedure Block (Id : Node_Id; Own_Scope : Boolean := True) is
      begin
         if Own_Scope then
            Put ((Op => Enter_Scope, others => <>));
            Scope_Depth := Scope_Depth + 1;
         end if;
         for Item of Fetch (Id).Children loop
            declare
               Mark : constant Positive := Next_Register;
            begin
               Statement (Item);
               --  Clear dead packets before recycling registers; otherwise
               --  stale references keep unreachable heap graphs alive.
               if Next_Register > Mark then
                  Put ((Op => Clear_Registers, A => Mark,
                        B => Next_Register - 1, others => <>));
               end if;
               Next_Register := Mark;
            end;
         end loop;
         if Own_Scope then
            Put ((Op => Leave_Scope, others => <>));
            Scope_Depth := Scope_Depth - 1;
         end if;
      end Block;

      procedure Close_Loop is
      begin
         for Site of Loop_Stack.Last_Element.Breaks loop
            Patch (Site, Natural (Current.Code.Length) + 1);
         end loop;
         Loop_Stack.Delete_Last;
      end Close_Loop;

      procedure Statement (Id : Node_Id) is
         Item : constant Node := Fetch (Id);
         Inputs : Registers.Vector;
         Lvalues : Targets.Vector;
         Left, Right, Initial, Bound, Step, Control, Branch, Start : Positive;
         Finish : Registers.Vector;
         Loop_Item : Loop_Context;
      begin
         Site := Item.Site;
         case Item.Kind is
            when Empty_Statement => null;
            when Block_Statement => Block (Id);
            when Call_Statement =>
               Left := Expression (Item.Children (1));
            when Assignment =>
               if Fetch (Item.Children.Last_Element).Kind =
                 Function_Expression
               then
                  Lvalues.Append (Address (Item.Children (1)));
                  Inputs.Append (Expression (Item.Children (2)));
                  if Item.Flag then
                     Put ((Op => Check_Global,
                           A => Lvalues (1).Table_Reg,
                           B => Lvalues (1).Key_Reg, others => <>));
                  end if;
               else
                  for Index in 1 .. Item.Children.Last_Index - 1 loop
                     Lvalues.Append (Address (Item.Children (Index)));
                  end loop;
                  Inputs := List (Item.Children.Last_Element);
               end if;
               for Index in reverse Lvalues.First_Index ..
                 Lvalues.Last_Index
               loop
                  Store (Lvalues (Index), Pick (Inputs, Index));
               end loop;
            when Declaration =>
               if not Item.Children.Is_Empty and then
                 Fetch (Item.Children (1)).Kind = Function_Expression
               then
                  --  A local recursive function sees its predeclared cell.
                  Left := New_Register;
                  Put ((Op => Load_Value, A => Left, others => <>));
                  Put ((Op => Declare_Local, A => Left,
                        B => Symbol (Item.Symbols (1)), others => <>));
                  Left := Expression (Item.Children (1));
                  Put ((Op => Write_Local, A => Left,
                        B => Symbol (Item.Symbols (1)), others => <>));
               else
                  if Item.Flag and then not Item.Children.Is_Empty then
                     for Id of Item.Symbols loop
                        declare
                           Name : constant Lua.Syntax_Trees.Binding :=
                             Unit.Names (Positive (Id));
                           Where : Target;
                        begin
                           if Name.Kind /= Collective_Name then
                              Where.Table_Reg := New_Register;
                              Put ((Op => Read_Local,
                                    A => Where.Table_Reg,
                                    B => Symbol (Item.Environment),
                                    others => <>));
                              Where.Key_Reg := New_Register;
                              Put ((Op => Load_String, A => Where.Key_Reg,
                                    Text => Name.Name, others => <>));
                              Lvalues.Append (Where);
                           end if;
                        end;
                     end loop;
                  end if;
                  if not Item.Children.Is_Empty then
                     Inputs := List (Item.Children (1));
                  end if;
                  if Item.Flag then
                     if not Item.Children.Is_Empty then
                        for Index in reverse Lvalues.First_Index ..
                          Lvalues.Last_Index
                        loop
                           Put ((Op => Check_Global,
                                 A => Lvalues (Index).Table_Reg,
                                 B => Lvalues (Index).Key_Reg, others => <>));
                           Store (Lvalues (Index), Pick (Inputs, Index));
                        end loop;
                     end if;
                  else
                     for Index in Item.Symbols.First_Index ..
                       Item.Symbols.Last_Index
                     loop
                        Put ((Op => Declare_Local,
                              A => Pick (Inputs, Index),
                              B => Symbol (Item.Symbols (Index)),
                              others => <>));
                     end loop;
                  end if;
               end if;
            when Return_Statement =>
               if not Item.Children.Is_Empty then
                  Inputs := List (Item.Children (1));
               end if;
               if Inputs.Length = 1 and then
                 Current.Code.Last_Element.Op = Call_Function and then
                 Current.Code.Last_Element.A = Inputs (1)
               then
                  declare
                     Code : Instruction := Current.Code.Last_Element;
                  begin
                     Code.Op := Tail_Call;
                     Current.Code.Replace_Element
                       (Current.Code.Last_Index, Code);
                  end;
               else
                  Put ((Op => Return_Values, Inputs => Inputs, others => <>));
               end if;
            when Break_Statement =>
               Loop_Item := Loop_Stack.Last_Element;
               for Index in Loop_Item.Depth + 1 .. Scope_Depth loop
                  Put ((Op => Leave_Scope, others => <>));
               end loop;
               Loop_Item.Breaks.Append (Emit ((Op => Jump, others => <>)));
               Loop_Stack.Replace_Element
                 (Loop_Stack.Last_Index, Loop_Item);
            when If_Statement =>
               declare
                  Index : Positive := 1;
               begin
                  while Index < Item.Children.Last_Index loop
                     Left := Expression (Item.Children (Index));
                     Branch := Emit
                       ((Op => Jump_False, A => Left, others => <>));
                     Block (Item.Children (Index + 1));
                     Finish.Append (Emit ((Op => Jump, others => <>)));
                     Patch (Branch, Natural (Current.Code.Length) + 1);
                     Index := Index + 2;
                  end loop;
                  if Index = Item.Children.Last_Index then
                     Block (Item.Children (Index));
                  end if;
                  for Site of Finish loop
                     Patch (Site, Natural (Current.Code.Length) + 1);
                  end loop;
               end;
            when While_Statement =>
               Start := Natural (Current.Code.Length) + 1;
               Left := Expression (Item.Children (1));
               Branch := Emit
                 ((Op => Jump_False, A => Left, others => <>));
               Loop_Stack.Append
                 (Loop_Context'(Scope_Depth, Registers.Empty_Vector));
               Block (Item.Children (2));
               Put ((Op => Jump, Target => Start, others => <>));
               Patch (Branch, Natural (Current.Code.Length) + 1);
               Close_Loop;
            when Repeat_Statement =>
               Start := Natural (Current.Code.Length) + 1;
               Loop_Stack.Append
                 (Loop_Context'(Scope_Depth, Registers.Empty_Vector));
               Put ((Op => Enter_Scope, others => <>));
               Scope_Depth := Scope_Depth + 1;
               Block (Item.Children (1), Own_Scope => False);
               Left := Expression (Item.Children (2));
               Put ((Op => Leave_Scope, others => <>));
               Scope_Depth := Scope_Depth - 1;
               Put ((Op => Jump_False, A => Left,
                     Target => Start, others => <>));
               Close_Loop;
            when Numeric_For | Generic_For =>
               if Item.Kind = Numeric_For then
                  Initial := Expression (Item.Children (1));
                  Bound := Expression (Item.Children (2));
                  if Item.Children.Length = 4 then
                     Step := Expression (Item.Children (3));
                  else
                     Step := New_Register;
                     Put ((Op => Load_Value, A => Step,
                           Literal => (Integer_Kind, 1), others => <>));
                  end if;
                  Left := New_Register;
                  Right := New_Register;
                  Control := New_Register;
                  Put ((Op => For_Initialize, A => Control,
                        B => Left, C => Right, D => Initial,
                        Inputs => Registers.To_Vector (Bound, 1) &
                          Registers.To_Vector (Step, 1), others => <>));
                  Bound := Left;
                  Step := Right;
               else
                  Inputs := List (Item.Children (1));
                  Control := Pick (Inputs, 1);
                  Bound := Pick (Inputs, 2);
                  Step := Pick (Inputs, 3);
                  Put ((Op => Check_Iterator, A => Pick (Inputs, 4),
                        others => <>));
               end if;
               Start := Natural (Current.Code.Length) + 1;
               if Item.Kind = Generic_For then
                  Inputs.Clear;
                  Inputs.Append (Bound);
                  Inputs.Append (Step);
                  Initial := New_Register;
                  Put ((Op => Call_Function, A => Initial, B => Control,
                        Inputs => Inputs, others => <>));
                  Put ((Op => Move_First, A => Step, B => Initial,
                        others => <>));
                  Branch := Emit ((Op => Jump_Nil, A => Step, others => <>));
               else
                  Branch := Emit ((Op => For_Test, A => Control,
                                   B => Bound, C => Step, others => <>));
               end if;
               Loop_Stack.Append
                 (Loop_Context'(Scope_Depth, Registers.Empty_Vector));
               Put ((Op => Enter_Scope, others => <>));
               Scope_Depth := Scope_Depth + 1;
               Inputs.Clear;
               Inputs.Append (Initial);
               for Index in Item.Symbols.First_Index ..
                 Item.Symbols.Last_Index
               loop
                  Put ((Op => Declare_Local,
                        B => Symbol (Item.Symbols (Index)),
                        A => (if Item.Kind = Generic_For
                              then Pick (Inputs, Index) else Control),
                        others => <>));
               end loop;
               Block (Item.Children.Last_Element, Own_Scope => False);
               Put ((Op => Leave_Scope, others => <>));
               Scope_Depth := Scope_Depth - 1;
               if Item.Kind = Generic_For then
                  Put ((Op => Jump, Target => Start, others => <>));
               else
                  Left := Emit ((Op => For_Advance, A => Control,
                                 B => Bound, C => Step, Target => Start,
                                 others => <>));
                  declare
                     Code : Instruction := Current.Code (Left);
                  begin
                     Code.D := Natural (Current.Code.Length) + 1;
                     Current.Code.Replace_Element (Left, Code);
                  end;
               end if;
               Patch (Branch, Natural (Current.Code.Length) + 1);
               Close_Loop;
            when others =>
               raise Program_Error with "non-statement syntax node";
         end case;
      end Statement;
   begin
      Parse (Unit, Source, Name,
             (State.Bounds.Source_Bytes, State.Bounds.Tokens,
              State.Bounds.Syntax_Nodes, State.Bounds.Syntax_Depth));
      if Unit.Result.Status /= Lua.Syntax.Success then
         State.Current.Failure_At :=
           (Offset => 1, Line => Unit.Result.Error.Line,
            Column => Unit.Result.Error.Column);
         State.Current.Is_Syntax := Unit.Result.Status =
           Lua.Syntax.Syntax_Error;
         Fail (State, To_String (Unit.Result.Error.Message),
               Resource => Unit.Result.Status = Lua.Syntax.Resource_Error);
      end if;
      if Unit.Unsupported /= No_Node then
         State.Current.Failure_At := Fetch (Unit.Unsupported).Site;
         State.Current.Is_Unsupported := True;
         Fail (State, "unsupported feature: " &
               (case Fetch (Unit.Unsupported).Kind is
                   when Goto_Statement => "goto execution",
                   when Label_Statement => "label execution",
                   when others => "to-be-closed local execution"));
      end if;
      if Natural (Unit.Names.Length) >= Positive'Last - Symbol_Base then
         Fail (State, "lexical symbol limit exceeded", Resource => True);
      end if;
      State.Next_Symbol := Symbol_Base + Natural (Unit.Names.Length);
      Current := new Prototype;
      State.Programs.Append (Current);
      Current.Name := To_Unbounded_String (Name);
      Current.Vararg := True;
      Current.Is_Main := True;
      Current.Environment_Symbol := Symbol (Unit.Environment);
      Block (Unit.Root, Own_Scope => False);
      Put ((Op => Return_Values, others => <>));
      return Current;
   end Compile;
end Lua.Engine.Compiler;
