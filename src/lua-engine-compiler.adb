with Lua.Chunks;
with Ada.Containers;
with Lua.Lexers; use Lua.Lexers;
with Lua.Syntax;
with Lua.Syntax_Trees; use Lua.Syntax_Trees;
with Lua.Canonical_Compiler;
with Lua.Engine.Canonical;

package body Lua.Engine.Compiler is
   use type Ada.Containers.Count_Type;
   use type Lua.Syntax.Check_Status;
   use type Registers.Vector;

   type Target is record
      Symbol : Natural := 0;
      Table_Reg, Key_Reg : Natural := 0;
   end record;
   package Targets is new Lua.Storage.Vectors (Target);
   type Loop_Context is record
      Depth : Natural;
      Breaks : Registers.Vector;
   end record;
   package Loops is new Lua.Storage.Vectors (Loop_Context);

   type Label_Site is record
      Id : Node_Id;
      PC : Positive;
      Depth : Natural;
   end record;
   package Label_Lists is new Lua.Storage.Vectors (Label_Site);

   function Compile_Private
     (State : in out World; Source, Name : String) return Prototype_Access;
   function Compile_Canonical
     (State : in out World; Source, Name : String) return Prototype_Access;
   function Compile_Binary
     (State : in out World; Source : String) return Prototype_Access;

   function Compile
     (State : in out World; Source, Name : String) return Prototype_Access
   is
   begin
      if Source'Length > 0 and then
        Source (Source'First) = Character'Val (27)
      then
         return Compile_Binary (State, Source);
      elsif State.Canonical_Compilation then
         return Compile_Canonical (State, Source, Name);
      end if;
      return Compile_Private (State, Source, Name);
   end Compile;

   function Compile_Binary
     (State : in out World; Source : String) return Prototype_Access
   is
      Decoded : Lua.Chunks.Decode_Result := Lua.Chunks.Decode
        (Source, Lua.Storage.Reference (State.Memory),
         (Input_Bytes => State.Bounds.Source_Bytes,
          Depth => State.Bounds.Syntax_Depth,
          Instructions => State.Bounds.Instructions,
          String_Bytes => State.Bounds.String_Bytes,
          others => <>));
      use type Lua.Chunks.Status;
   begin
      --  Decoding owns no runtime values. Adopt only a complete checked graph;
      --  a malformed header, truncated prototype or limit failure leaves no
      --  half-visible closure, globals, stack or retained compiler arena.
      case Decoded.Outcome is
         when Lua.Chunks.Succeeded =>
            return Canonical.Adopt_Program (State, Decoded.Code);
         when Lua.Chunks.Memory_Failure =>
            Record_Memory_Error (State);
            raise Language_Error;
         when Lua.Chunks.Bad_Format | Lua.Chunks.Resource_Limit =>
            State.Current.Failure_Class := Syntax_Failure;
            State.Current.Failure_At := (others => 1);
            Fail (State, "bad binary format (" &
              Lua.Chunks.Message (Decoded.Error) & ")",
              Resource => Decoded.Outcome = Lua.Chunks.Resource_Limit);
            return null;
      end case;
   end Compile_Binary;

   function Compile_Canonical
     (State : in out World; Source, Name : String) return Prototype_Access
   is
      Unit : Compilation_Unit;
      Was_Compiling : constant Boolean := State.Compiling;
      Code : Prototype_Access;
   begin
      State.Compiling := True;
      Parse (Unit, Source, Name,
             (State.Bounds.Source_Bytes, State.Bounds.Tokens,
              State.Bounds.Syntax_Nodes, State.Bounds.Syntax_Depth),
             Memory => Lua.Storage.Reference (State.Memory));
      if Unit.Result.Status /= Lua.Syntax.Success then
         State.Current.Failure_At :=
           (Offset => 1, Line => Unit.Result.Error.Line,
            Column => Unit.Result.Error.Column);
         State.Current.Failure_Class := Syntax_Failure;
         Fail (State, Lua.Syntax_Trees.Text (Unit, Unit.Result.Error.Message),
               Resource => Unit.Result.Status = Lua.Syntax.Resource_Error);
      end if;
      declare
         Lowered : Lua.Canonical_Compiler.Compilation_Result :=
           Lua.Canonical_Compiler.Compile
             (Unit, Lua.Storage.Reference (State.Memory), Name,
              Bounds => (Nesting => State.Bounds.Syntax_Depth, others => <>));
         use type Lua.Canonical_Compiler.Status;
      begin
         case Lowered.Outcome is
            when Lua.Canonical_Compiler.Succeeded =>
               Code := Canonical.Adopt_Program (State, Lowered.Code);
            when Lua.Canonical_Compiler.Memory_Failure =>
               Record_Memory_Error (State);
               raise Language_Error;
            when Lua.Canonical_Compiler.Compiler_Limit |
              Lua.Canonical_Compiler.Resource_Limit =>
               State.Current.Failure_At := Lowered.Location;
               State.Current.Failure_Class := Syntax_Failure;
               Fail (State, Lua.Canonical_Compiler.Message (Lowered.Error),
                 Resource => Lowered.Outcome =
                   Lua.Canonical_Compiler.Resource_Limit);
         end case;
      end;
      if Code.Register_Count > State.Bounds.Registers then
         Fail (State, "register limit exceeded", Resource => True);
      end if;
      State.Entry_Code := Code;
      State.Compiling := Was_Compiling;
      return Code;
   exception
      when others =>
         State.Compiling := Was_Compiling;
         raise;
   end Compile_Canonical;

   function Compile_Private
     (State : in out World; Source, Name : String) return Prototype_Access
   is
      Unit : Compilation_Unit;
      Was_Compiling : constant Boolean := State.Compiling;
      Current : Prototype_Access;
      Next_Register : Positive := 1;
      Scope_Depth : Natural := 0;
      Symbol_Base : constant Positive := State.Next_Symbol;
      Site : Source_Location;
      Loop_Stack : Loops.Vector;
      Label_Places : Label_Lists.Vector;
      Built_Programs : Prototypes.Vector;

      function Fetch (Id : Node_Id) return Node is
        (Unit.Tree (Positive (Id)));
      --  The legacy packet metadata still owns Unbounded_String fields.
      --  Materialize only at that lowering boundary; parser/token storage is
      --  already allocator-owned. Canonical metadata uses borrowed queries.
      function Runtime_Text (Item : Text_Ref) return Unbounded_String is
        (To_Unbounded_String (Lua.Syntax_Trees.Text (Unit, Item)));
      function Symbol (Id : Symbol_Id) return Positive is
        (Symbol_Base + Positive (Id) - 1);
      function New_Registers return Registers.Vector;
      function New_Registers return Registers.Vector is
      begin
         return Result : Registers.Vector do
            Result.Set_Owner (Lua.Storage.Reference (State.Memory));
         end return;
      end New_Registers;
      function New_Loop (Depth : Natural) return Loop_Context;
      function New_Loop (Depth : Natural) return Loop_Context is
      begin
         return (Depth, New_Registers);
      end New_Loop;
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
      procedure Call_Name (Id : Node_Id; Code : in out Instruction);

      procedure Call_Name (Id : Node_Id; Code : in out Instruction) is
         Item : constant Node := Fetch (Id);
      begin
         --  Names describe the call site, not a mutable function property.
         --  The same closure can be called through unrelated table fields.
         if Item.Kind = Name_Reference then
            Code.Text := Runtime_Text (Item.Text);
            Code.Name_Kind := To_Unbounded_String
              ((if Item.Symbol = No_Symbol then "global"
                elsif Current.Capture_Symbols.Contains (Symbol (Item.Symbol))
                then "upvalue" else "local"));
         elsif Item.Kind in Index_Expression | Method_Expression and then
           Fetch (Item.Children (2)).Kind = Literal and then
           Fetch (Item.Children (2)).Value.Kind = String_Literal
         then
            Code.Text := Runtime_Text
              (Fetch (Item.Children (2)).Value.Text);
            Code.Name_Kind := To_Unbounded_String
              ((if Item.Kind = Method_Expression then "method" else "field"));
         end if;
      end Call_Name;

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
         Result : Registers.Vector := New_Registers;
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
                     Text => Runtime_Text (Item.Text), others => <>));
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
         Saved_Site : constant Source_Location := Site;
         Saved_Loops : constant Loops.Vector := Loop_Stack;
         Child : constant Prototype_Access :=
           New_Program (State);
         Result : Positive;
      begin
         --  Publish partial prototypes immediately: runtime ownership must
         --  reclaim them even when lowering exhausts a register budget.
         Built_Programs.Append (Child);
         Child.Name := Outer.Name;
         Child.Function_Node := Natural (Id);
         Child.First_Line := Item.Site.Line;
         Child.Last_Line := Item.End_Line;
         Child.Environment_Symbol := Outer.Environment_Symbol;
         Child.Vararg := Item.Flag;
         if Item.Symbol /= No_Symbol then
            Child.Vararg_Name := Symbol (Item.Symbol);
         end if;
         for Parameter of Item.Symbols loop
            Child.Parameters.Append (Symbol (Parameter));
         end loop;
         for Capture of Item.Captures loop
            Child.Capture_Symbols.Append (Symbol (Capture));
         end loop;
         Current := Child;
         Next_Register := 1;
         Scope_Depth := 0;
         Loop_Stack.Clear;
         Block (Item.Children (1), Own_Scope => False);
         Site.Line := Child.Last_Line;
         Put ((Op => Return_Values, others => <>));
         --  Resolution already propagates captures through each parent.
         Current := Outer;
         Next_Register := Saved_Register;
         Scope_Depth := Saved_Depth;
         Loop_Stack := Saved_Loops;
         Site := Saved_Site;
         Result := New_Register;
         Put ((Op => Make_Closure, A => Result,
               Nested => Child, others => <>));
         return Result;
      end Function_Body;

      function Expression (Id : Node_Id) return Positive is
         Item : constant Node := Fetch (Id);
         Result, Left, Right : Positive;
         Branch : Natural := 0;
         Inputs : Registers.Vector := New_Registers;
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
                           Text => Runtime_Text (Item.Value.Text),
                           others => <>));
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
               declare
                  Code : Instruction :=
                    (Op => Call_Function, A => Result, B => Left,
                     Inputs => Inputs, others => <>);
               begin
                  Call_Name (Item.Children (1), Code);
                  Put (Code);
               end;
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
         Inputs : Registers.Vector := New_Registers;
         Lvalues : Targets.Vector;
         Left, Right, Initial, Bound, Step, Control, Branch, Start : Positive;
         Finish : Registers.Vector := New_Registers;
         Loop_Item : Loop_Context;
      begin
         Lvalues.Set_Owner (Lua.Storage.Reference (State.Memory));
         Site := Item.Site;
         case Item.Kind is
            when Empty_Statement => null;
            when Label_Statement =>
               Label_Places.Append
                 (Label_Site'(Id, Current.Code.Last_Index + 1, Scope_Depth));
               Put ((Op => No_Operation, others => <>));
            when Goto_Statement =>
               for Live of Item.Symbols loop
                  Inputs.Append (Symbol (Live));
               end loop;
               Put ((Op => Goto_Label, D => Natural (Item.Target),
                     Inputs => Inputs, others => <>));
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
                                    Text => Runtime_Text (Name.Name),
                                    others => <>));
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
                        if Unit.Names
                          (Positive (Item.Symbols (Index))).Mode = Closing_Name
                        then
                           Current.Uses_Closing := True;
                           Put ((Op => Register_Close,
                                 B => Symbol (Item.Symbols (Index)),
                                 Text => Runtime_Text (Unit.Names
                                   (Positive (Item.Symbols (Index))).Name),
                                 others => <>));
                        end if;
                     end loop;
                  end if;
               end if;
            when Return_Statement =>
               if not Item.Children.Is_Empty then
                  Inputs := List (Item.Children (1));
               end if;
               if not Current.Uses_Closing and then
                 Inputs.Length = 1 and then
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
                 (New_Loop (Scope_Depth));
               Block (Item.Children (2));
               Put ((Op => Jump, Target => Start, others => <>));
               Patch (Branch, Natural (Current.Code.Length) + 1);
               Close_Loop;
            when Repeat_Statement =>
               Start := Natural (Current.Code.Length) + 1;
               Loop_Stack.Append
                 (New_Loop (Scope_Depth));
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
                        Inputs => Registers.To_Vector
                          (Lua.Storage.Reference (State.Memory), Bound, 1) &
                          Registers.To_Vector
                          (Lua.Storage.Reference (State.Memory), Step, 1),
                        others => <>));
                  Bound := Left;
                  Step := Right;
               else
                  Inputs := List (Item.Children (1));
                  Control := Pick (Inputs, 1);
                  Bound := Pick (Inputs, 2);
                  Step := Pick (Inputs, 3);
                  Current.Uses_Closing := True;
                  --  The fourth iterator value belongs to one scope around
                  --  the entire loop, outside each fresh iteration binding.
                  Put ((Op => Enter_Scope, others => <>));
                  Scope_Depth := Scope_Depth + 1;
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
                 (New_Loop (Scope_Depth));
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
               if Item.Kind = Generic_For then
                  Put ((Op => Leave_Scope, others => <>));
                  Scope_Depth := Scope_Depth - 1;
               end if;
            when others =>
               raise Program_Error with "non-statement syntax node";
         end case;
      end Statement;
   begin
      Built_Programs.Set_Owner (Lua.Storage.Reference (State.Memory));
      Loop_Stack.Set_Owner (Lua.Storage.Reference (State.Memory));
      Label_Places.Set_Owner (Lua.Storage.Reference (State.Memory));
      State.Compiling := True;
      Parse (Unit, Source, Name,
             (State.Bounds.Source_Bytes, State.Bounds.Tokens,
              State.Bounds.Syntax_Nodes, State.Bounds.Syntax_Depth),
             Memory => Lua.Storage.Reference (State.Memory));
      if Unit.Result.Status /= Lua.Syntax.Success then
         State.Current.Failure_At :=
           (Offset => 1, Line => Unit.Result.Error.Line,
            Column => Unit.Result.Error.Column);
         State.Current.Failure_Class := Syntax_Failure;
         Fail (State, Lua.Syntax_Trees.Text (Unit, Unit.Result.Error.Message),
               Resource => Unit.Result.Status = Lua.Syntax.Resource_Error);
      end if;
      if Natural (Unit.Names.Length) >= Positive'Last - Symbol_Base then
         Fail (State, "lexical symbol limit exceeded", Resource => True);
      end if;
      State.Next_Symbol := Symbol_Base + Natural (Unit.Names.Length);
      Current := New_Program (State);
      Built_Programs.Append (Current);
      Current.Name := To_Unbounded_String (Name);
      Current.Vararg := True;
      Current.Is_Main := True;
      Current.Environment_Symbol := Symbol (Unit.Environment);
      Block (Unit.Root, Own_Scope => False);
      Put ((Op => Return_Values, others => <>));
      --  Resolve forward and backward branches only after every function has
      --  been lowered. Node IDs are compilation-local; never rewrite older
      --  prototypes retained by the session from a preceding source chunk.
      for Program of Built_Programs loop
         declare
         begin
            --  Preserve source names independently of the temporary AST.
            --  Debug lookup consults only this prototype's local/capture set.
            for Index in Unit.Names.First_Index .. Unit.Names.Last_Index loop
               if Natural (Unit.Names (Index).Owner) = Program.Function_Node
                 or else Program.Capture_Symbols.Contains
                   (Symbol (Symbol_Id (Index)))
               then
                  Program.Names.Append
                    (Symbol_Name'(Symbol (Symbol_Id (Index)),
                                  Runtime_Text (Unit.Names (Index).Name)));
               end if;
            end loop;
            for PC in Program.Code.First_Index .. Program.Code.Last_Index loop
               declare
                  Code : Instruction := Program.Code (PC);
               begin
                  if Code.Op = Goto_Label then
                     for Label of Label_Places loop
                        if Natural (Label.Id) = Code.D then
                           Code.Target := Label.PC;
                           Code.A := Label.Depth;
                           exit;
                        end if;
                     end loop;
                     pragma Assert (Code.Target /= 0);
                     Program.Code.Replace_Element (PC, Code);
                  end if;
               end;
            end loop;
         end;
      end loop;
      State.Entry_Code := Current;
      State.Compiling := Was_Compiling;
      return Current;
   exception
      when others =>
         State.Compiling := Was_Compiling;
         raise;
   end Compile_Private;
end Lua.Engine.Compiler;
