with Ada.Containers;
with Lua.Lexers; use Lua.Lexers;

package body Lua.Engine.Compiler is
   use type Ada.Containers.Count_Type;
   use type Registers.Vector;

   type Name_Kind is (Local_Name, Global_Name, Collective_Name);
   type Name_Binding is record
      --  The name is only for lookup during compilation. Runtime access uses
      --  a unique symbol, so shadowing cannot retarget an existing closure.
      Name     : Unbounded_String;
      Kind     : Name_Kind := Local_Name;
      Symbol   : Natural := 0;
      Constant_Name : Boolean := False;
   end record;
   package Names is new Ada.Containers.Vectors (Positive, Name_Binding);

   type Target_Kind is (No_Target, Cell_Target, Index_Target);
   type Expression is record
      --  Expressions carry their computed result and, when assignable, an
      --  lvalue recipe. Retaining receiver/key registers makes parallel
      --  assignment independent of subsequent writes to those variables.
      Register_Id : Positive := 1;
      Target      : Target_Kind := No_Target;
      Symbol      : Natural := 0;
      Table_Reg   : Natural := 0;
      Key_Reg     : Natural := 0;
      Read_At     : Natural := 0;
      Read_Only   : Boolean := False;
      Multiple    : Boolean := False;
      Site        : Source_Location;
   end record;
   package Expressions is new Ada.Containers.Vectors (Positive, Expression);

   type Loop_Context is record
      Depth  : Natural := 0;
      Breaks : Registers.Vector;
   end record;
   package Loops is new Ada.Containers.Vectors (Positive, Loop_Context);

   function Compile
     (State : in out World; Source, Name : String) return Prototype_Access
   is
      Scanned : constant Scan_Result := Scan (Source, State.Bounds.Tokens);
      Position : Positive := 1;
      Current : Prototype_Access;
      Active : Names.Vector;
      Loop_Stack : Loops.Vector;
      Next_Register : Positive := 1;
      Scope_Depth : Natural := 0;
      Parse_Depth : Natural := 0;

      function Kind return Token_Kind is (Scanned.Tokens (Position).Kind);
      function Text return String is
        (To_String (Scanned.Tokens (Position).Text));
      function Next_Kind return Token_Kind is
        (Scanned.Tokens (Positive'Min
           (Position + 1, Scanned.Tokens.Last_Index)).Kind);
      function Is_Name return Boolean is
        (Kind in Identifier | Global_Word);
      function Here return Source_Location is
        (Scanned.Tokens (Position).Location);

      procedure Error (Message : String);
      procedure Advance;
      function Take (Expected : Token_Kind) return Boolean;
      procedure Expect (Expected : Token_Kind);
      function Read_Name return Unbounded_String;
      function New_Symbol return Positive;
      function New_Register return Positive;
      function Emit
        (Code : Instruction; At_Location : Source_Location := Here)
         return Positive;
      procedure Put
        (Code : Instruction; At_Location : Source_Location := Here);
      procedure Patch (At_Index : Positive; Target : Natural);
      function Resolve (Name : Unbounded_String) return Name_Binding;
      function Name_Expression (Name : Unbounded_String) return Expression;
      function Global_Target (Name : Unbounded_String) return Expression;
      procedure Store (Target : Expression; Source_Reg : Positive);
      function Attribute (Default : Boolean := False) return Boolean;
      function Parse_Expression (Minimum : Natural := 0) return Expression;
      function Prefix return Expression;
      function Function_Body (Method : Boolean := False) return Expression;
      function Table_Constructor return Expression;
      function Expression_List return Registers.Vector;
      procedure Block (New_Scope : Boolean := True);
      procedure Statement;
      procedure Function_Statement (Global : Boolean := False);
      procedure Declaration (Global : Boolean := False);
      procedure While_Statement;
      procedure Repeat_Statement;
      procedure For_Statement;
      procedure If_Statement;
      procedure Assignment_Or_Call;
      procedure Close_Loop (Finish : Positive);
      function Pick (Inputs : Registers.Vector; Index : Positive)
                     return Positive;

      procedure Error (Message : String) is
      begin
         State.Failure_At := Here;
         State.Is_Syntax := True;
         Fail (State, Message);
      end Error;

      procedure Advance is
      begin
         if Position < Scanned.Tokens.Last_Index then
            Position := Position + 1;
         end if;
      end Advance;

      function Take (Expected : Token_Kind) return Boolean is
      begin
         if Kind = Expected then
            Advance;
            return True;
         end if;
         return False;
      end Take;

      procedure Expect (Expected : Token_Kind) is
      begin
         if not Take (Expected) then
            Error (Token_Kind'Image (Expected) & " expected");
         end if;
      end Expect;

      function Read_Name return Unbounded_String is
         Result : constant Unbounded_String :=
           Scanned.Tokens (Position).Text;
      begin
         if not Is_Name then
            Error ("name expected");
         end if;
         Advance;
         return Result;
      end Read_Name;

      function New_Symbol return Positive is
         Result : constant Positive := State.Next_Symbol;
      begin
         if Result = Positive'Last then
            Fail (State, "lexical symbol limit exceeded", Resource => True);
         end if;
         State.Next_Symbol := Result + 1;
         return Result;
      end New_Symbol;

      function New_Register return Positive is
         Result : constant Positive := Next_Register;
      begin
         if Result > State.Bounds.Registers then
            Fail (State, "register limit exceeded", Resource => True);
         end if;
         Next_Register := Result + 1;
         Current.Register_Count := Natural'Max
           (Current.Register_Count, Result);
         return Result;
      end New_Register;

      function Emit
        (Code : Instruction; At_Location : Source_Location := Here)
         return Positive
      is
         Item : Instruction := Code;
      begin
         Item.Location := At_Location;
         Current.Code.Append (Item);
         return Current.Code.Last_Index;
      end Emit;

      procedure Put
        (Code : Instruction; At_Location : Source_Location := Here)
      is
         Ignored : constant Positive := Emit (Code, At_Location);
         pragma Unreferenced (Ignored);
      begin
         null;
      end Put;

      procedure Patch (At_Index : Positive; Target : Natural) is
         Item : Instruction := Current.Code (At_Index);
      begin
         Item.Target := Target;
         Current.Code.Replace_Element (At_Index, Item);
      end Patch;

      function Resolve (Name : Unbounded_String) return Name_Binding is
         Named_Global : Boolean := False;
         Collective : Boolean := False;
         Read_Only : Boolean := False;
      begin
         --  Resolve against declarations active at this source point, not
         --  names that happen to exist later at runtime. Unique cell symbols
         --  distinguish shadowed locals captured by earlier closures.
         for Binding of reverse Active loop
            if Binding.Kind = Collective_Name then
               if not Collective then
                  Collective := True;
                  Read_Only := Binding.Constant_Name;
               end if;
            elsif Binding.Name = Name then
               return Binding;
            elsif Binding.Kind = Global_Name then
               Named_Global := True;
            end if;
         end loop;
         if Named_Global and then not Collective then
            Error ("variable '" & To_String (Name) & "' not declared");
         end if;
         return (Name, Global_Name, 0, Read_Only);
      end Resolve;

      function Global_Target (Name : Unbounded_String) return Expression is
         Environment_Name : constant Name_Binding :=
           Resolve (To_Unbounded_String ("_ENV"));
         Table_Reg : constant Positive := New_Register;
         Key_Reg : constant Positive := New_Register;
      begin
         if Environment_Name.Kind /= Local_Name then
            Error ("_ENV must resolve to a lexical environment");
         end if;
         Put ((Op => Read_Local, A => Table_Reg,
               B => Environment_Name.Symbol, others => <>));
         Put ((Op => Load_String, A => Key_Reg, Text => Name, others => <>));
         return (Register_Id => Table_Reg, Target => Index_Target,
                 Table_Reg => Table_Reg, Key_Reg => Key_Reg,
                 Site => Scanned.Tokens
                   (Positive'Max (1, Position - 1)).Location, others => <>);
      end Global_Target;

      function Name_Expression (Name : Unbounded_String) return Expression is
         Binding : constant Name_Binding := Resolve (Name);
         Result : Expression;
      begin
         if Binding.Kind = Local_Name then
            Result.Register_Id := New_Register;
            Result.Target := Cell_Target;
            Result.Symbol := Binding.Symbol;
            Result.Read_At := Emit
              ((Op => Read_Local, A => Result.Register_Id,
                B => Binding.Symbol, others => <>));
         else
            Result := Global_Target (Name);
            Result.Register_Id := New_Register;
            Result.Read_At := Emit
              ((Op => Get_Item, A => Result.Register_Id,
                B => Result.Table_Reg, C => Result.Key_Reg, others => <>));
         end if;
         Result.Read_Only := Binding.Constant_Name;
         return Result;
      end Name_Expression;

      procedure Store (Target : Expression; Source_Reg : Positive) is
      begin
         if Target.Read_Only then
            Error ("attempt to assign to a const variable");
         end if;
         case Target.Target is
            when Cell_Target =>
               Put ((Op => Write_Local, A => Source_Reg,
                     B => Target.Symbol, others => <>));
            when Index_Target =>
               Put ((Op => Set_Item, A => Target.Table_Reg,
                     B => Target.Key_Reg, C => Source_Reg, others => <>),
                    Target.Site);
            when No_Target => Error ("assignment target expected");
         end case;
      end Store;

      function Attribute (Default : Boolean := False) return Boolean is
         Name : Unbounded_String;
      begin
         if not Take (Less) then
            return Default;
         end if;
         Name := Read_Name;
         Expect (Greater);
         if Name = "close" then
            Error ("<close> is outside the M1 language subset");
         elsif Name /= "const" then
            Error ("unknown variable attribute");
         end if;
         return True;
      end Attribute;

      function Pick (Inputs : Registers.Vector; Index : Positive)
                     return Positive
      is
         Result : constant Positive := New_Register;
      begin
         Put ((Op => Pick_Value, A => Result, B => Index,
               Inputs => Inputs, others => <>));
         return Result;
      end Pick;

      function Expression_List return Registers.Vector is
         Result : Registers.Vector;
         Item : Expression;
      begin
         loop
            Item := Parse_Expression;
            Result.Append (Item.Register_Id);
            exit when not Take (Comma);
         end loop;
         return Result;
      end Expression_List;

      function Function_Body (Method : Boolean := False) return Expression is
         Outer : constant Prototype_Access := Current;
         Saved_Register : constant Positive := Next_Register;
         Saved_Depth : constant Natural := Scope_Depth;
         Saved_Names : constant Ada.Containers.Count_Type := Active.Length;
         Saved_Loops : constant Loops.Vector := Loop_Stack;
         Child : constant Prototype_Access := new Prototype;
         Result : Expression;
         Parameter : Name_Binding;
      begin
         --  Prototype ownership transfers immediately to the world. Failed
         --  parsing can therefore discard the entire partial function graph.
         State.Programs.Append (Child);
         Child.Name := Outer.Name;
         Child.Environment_Symbol := Outer.Environment_Symbol;
         Current := Child;
         Next_Register := 1;
         Scope_Depth := 0;
         Loop_Stack.Clear;
         Expect (Left_Paren);
         if Method then
            Parameter := (To_Unbounded_String ("self"), Local_Name,
                          New_Symbol, False);
            Active.Append (Parameter);
            Child.Parameters.Append (Parameter.Symbol);
         end if;
         if Kind /= Right_Paren then
            loop
               if Take (Varargs) then
                  Child.Vararg := True;
                  if Is_Name then
                     Parameter := (Read_Name, Local_Name, New_Symbol, True);
                     Active.Append (Parameter);
                     Child.Vararg_Name := Parameter.Symbol;
                  end if;
                  exit;
               end if;
               Parameter := (Read_Name, Local_Name, New_Symbol, False);
               Active.Append (Parameter);
               Child.Parameters.Append (Parameter.Symbol);
               exit when not Take (Comma);
            end loop;
         end if;
         Expect (Right_Paren);
         Block (New_Scope => False);
         Expect (End_Word);
         Put ((Op => Return_Values, others => <>));
         --  The outer compiler resumes exactly where the function literal
         --  occurred. The runtime closure will capture its active environment.
         Active.Set_Length (Saved_Names);
         Current := Outer;
         Next_Register := Saved_Register;
         Scope_Depth := Saved_Depth;
         Loop_Stack := Saved_Loops;
         Result.Register_Id := New_Register;
         Put ((Op => Make_Closure, A => Result.Register_Id,
               Nested => Child, others => <>));
         return Result;
      end Function_Body;

      function Table_Constructor return Expression is
         Result : Expression;
         List_Index : Positive := 1;
         Key, Item : Expression;
         Sequence : Boolean;
         Inputs : Registers.Vector;
      begin
         Expect (Left_Brace);
         Result.Register_Id := New_Register;
         Put ((Op => New_Table, A => Result.Register_Id, others => <>));
         while Kind /= Right_Brace loop
            Sequence := False;
            if Take (Left_Bracket) then
               Key := Parse_Expression;
               Expect (Right_Bracket);
               Expect (Assign);
               Item := Parse_Expression;
            elsif Is_Name and then Next_Kind = Assign then
               Key.Register_Id := New_Register;
               Put ((Op => Load_String, A => Key.Register_Id,
                     Text => Read_Name, others => <>));
               Expect (Assign);
               Item := Parse_Expression;
            else
               Sequence := True;
               Item := Parse_Expression;
            end if;
            if Kind in Comma | Semicolon then
               Advance;
            elsif Kind /= Right_Brace then
               Error ("table field separator expected");
            end if;
            if Sequence then
               Inputs.Clear;
               Inputs.Append (Item.Register_Id);
               Put ((Op => Set_Sequence, A => Result.Register_Id,
                     B => List_Index,
                     C => Boolean'Pos (Kind = Right_Brace),
                     Inputs => Inputs, others => <>));
               List_Index := List_Index + 1;
            else
               Put ((Op => Set_Item, A => Result.Register_Id,
                     B => Key.Register_Id, C => Item.Register_Id,
                     others => <>));
            end if;
         end loop;
         Expect (Right_Brace);
         return Result;
      end Table_Constructor;

      function Prefix return Expression is
         Result : Expression;
         Index : Expression;
         Name : Unbounded_String;
         Arguments : Registers.Vector;
         Self_Reg : Natural;
         Has_Index : Boolean;
         Output : Positive;
         Call_Site : Source_Location;
         Access_Site : Source_Location;
      begin
         --  Prefix/postfix parsing resolves the receiver once. Lvalue
         --  descriptors retain its table/key registers separately from the
         --  final read, which assignments can cancel without re-evaluation.
         if Is_Name then
            Result := Name_Expression (Read_Name);
         elsif Take (Left_Paren) then
            Result := Parse_Expression;
            Expect (Right_Paren);
            Output := New_Register;
            Put ((Op => Move_First, A => Output, B => Result.Register_Id,
                  others => <>));
            Result := (Register_Id => Output, others => <>);
         else
            Error ("expression expected");
         end if;
         loop
            Self_Reg := 0;
            Access_Site := Here;
            Has_Index := True;
            if Take (Left_Bracket) then
               Index := Parse_Expression;
               Expect (Right_Bracket);
            elsif Kind in Dot | Colon then
               if Kind = Colon then
                  Self_Reg := New_Register;
                  Put ((Op => Move_First, A => Self_Reg,
                        B => Result.Register_Id, others => <>));
               end if;
               Advance;
               Name := Read_Name;
               Index.Register_Id := New_Register;
               Put ((Op => Load_String, A => Index.Register_Id,
                     Text => Name, others => <>));
            else
               exit when Kind not in Left_Paren | String_Literal | Left_Brace;
               Has_Index := False;
            end if;
            if Has_Index then
               Output := New_Register;
               Result := (Register_Id => Output, Target => Index_Target,
                          Table_Reg => Result.Register_Id,
                          Key_Reg => Index.Register_Id, Site => Access_Site,
                          others => <>);
               Result.Read_At := Emit
                 ((Op => Get_Item, A => Output, B => Result.Table_Reg,
                   C => Result.Key_Reg, others => <>), Access_Site);
            end if;
            --  A plain field selection may have more postfixes. A colon
            --  selection must immediately consume its method arguments.
            if not Has_Index or else Self_Reg /= 0 then
               Call_Site := Here;
               Arguments.Clear;
               if Self_Reg /= 0 then
                  Arguments.Append (Self_Reg);
               end if;
               if Take (Left_Paren) then
                  if Kind /= Right_Paren then
                     declare
                        Parsed : constant Registers.Vector := Expression_List;
                     begin
                        for Register_Id of Parsed loop
                           Arguments.Append (Register_Id);
                        end loop;
                     end;
                  end if;
                  Expect (Right_Paren);
               elsif Kind in String_Literal | Left_Brace then
                  Index := Parse_Expression (Minimum => 12);
                  Arguments.Append (Index.Register_Id);
               else
                  Error ("function arguments expected");
               end if;
               Output := New_Register;
               Result.Read_At := Emit
                 ((Op => Call_Function, A => Output, B => Result.Register_Id,
                   Inputs => Arguments, others => <>), Call_Site);
               Result.Register_Id := Output;
               Result.Target := No_Target;
               Result.Multiple := True;
               Result.Read_Only := False;
            end if;
         end loop;
         return Result;
      end Prefix;

      function Parse_Expression (Minimum : Natural := 0) return Expression is
         Result, Right : Expression;
         Operator : Token_Kind;
         Priority : Natural;
         Output : Positive;
         Branch : Natural;
         Number : Lua.Numbers.Number;
         Operator_Site : Source_Location;
      begin
         --  Precedence climbing keeps the grammar compact without an AST
         --  execution backend. Power/concatenation recurse at lower binding
         --  strength on the right; and/or emit branches before compiling
         --  the RHS so its side effects occur only when that branch runs.
         Parse_Depth := Parse_Depth + 1;
         if Parse_Depth > 200 then
            Fail (State, "parser nesting limit exceeded", Resource => True);
         end if;
         if Kind in Minus | Not_Word | Length | Bit_Xor then
            Operator := Kind;
            Operator_Site := Here;
            Advance;
            Right := Parse_Expression (11);
            Result.Register_Id := New_Register;
            Put ((Op => Unary, A => Result.Register_Id,
                  B => Right.Register_Id, Operator => Operator, others => <>),
                 Operator_Site);
         elsif Kind in Nil_Word | True_Word | False_Word |
           Number_Literal | String_Literal | Varargs
         then
            Result.Register_Id := New_Register;
            case Kind is
               when Nil_Word =>
                  Put ((Op => Load_Value, A => Result.Register_Id,
                        others => <>));
               when True_Word | False_Word =>
                  Put ((Op => Load_Value, A => Result.Register_Id,
                        Literal => (Boolean_Kind, Kind = True_Word),
                        others => <>));
               when String_Literal =>
                  Put ((Op => Load_String, A => Result.Register_Id,
                        Text => Scanned.Tokens (Position).Text,
                        others => <>));
               when Number_Literal =>
                  Number := Lua.Numbers.Read (Text);
                  case Number.Kind is
                     when Lua.Numbers.Invalid => Error ("malformed number");
                     when Lua.Numbers.Integer_Number =>
                        Put ((Op => Load_Value, A => Result.Register_Id,
                              Literal => (Integer_Kind, Number.Integer_Item),
                              others => <>));
                     when Lua.Numbers.Real_Number =>
                        Put ((Op => Load_Value, A => Result.Register_Id,
                              Literal => (Real_Kind, Number.Real_Item),
                              others => <>));
                  end case;
               when Varargs =>
                  if not Current.Vararg then
                     Error ("cannot use '...' outside a vararg function");
                  end if;
                  Result.Read_At := Emit
                    ((Op => Read_Varargs, A => Result.Register_Id,
                      others => <>));
                  Result.Multiple := True;
               when others => null;
            end case;
            Advance;
         elsif Take (Function_Word) then
            Result := Function_Body;
         elsif Kind = Left_Brace then
            Result := Table_Constructor;
         else
            Result := Prefix;
         end if;
         loop
            Operator := Kind;
            Operator_Site := Here;
            Priority := (case Operator is
               when Or_Word => 1, when And_Word => 2,
               when Equal | Not_Equal | Less | Less_Equal |
                    Greater | Greater_Equal => 3,
               when Bit_Or => 4, when Bit_Xor => 5, when Bit_And => 6,
               when Shift_Left | Shift_Right => 7,
               when Concatenate => 8, when Plus | Minus => 9,
               when Star | Slash | Floor_Divide | Percent => 10,
               when Power => 12, when others => 0);
            exit when Priority <= Minimum;
            Advance;
            Output := New_Register;
            Branch := 0;
            if Operator in And_Word | Or_Word then
               Put ((Op => Move_First, A => Output,
                     B => Result.Register_Id, others => <>));
               Branch := Emit
                 ((Op => (if Operator = And_Word then Jump_False
                          else Jump_True), A => Result.Register_Id,
                   others => <>));
            end if;
            Right := Parse_Expression
              (if Operator in Power | Concatenate then Priority - 1
               else Priority);
            if Branch /= 0 then
               Put ((Op => Move_First, A => Output,
                     B => Right.Register_Id, others => <>));
               Patch (Branch, Natural (Current.Code.Length) + 1);
            else
               Put ((Op => Binary, A => Output, B => Result.Register_Id,
                     C => Right.Register_Id, Operator => Operator,
                     others => <>), Operator_Site);
            end if;
            Result := (Register_Id => Output, others => <>);
         end loop;
         Parse_Depth := Parse_Depth - 1;
         return Result;
      end Parse_Expression;

      procedure Block (New_Scope : Boolean := True) is
         Saved : constant Ada.Containers.Count_Type := Active.Length;
         Was_Return : Boolean;
      begin
         Parse_Depth := Parse_Depth + 1;
         if Parse_Depth > 200 then
            Fail (State, "parser nesting limit exceeded", Resource => True);
         end if;
         if New_Scope then
            Put ((Op => Enter_Scope, others => <>));
            Scope_Depth := Scope_Depth + 1;
         end if;
         while Kind not in End_Of_Input | End_Word | Else_Word |
           Elseif_Word | Until_Word
         loop
            Was_Return := Kind = Return_Word;
            declare
               Mark : constant Positive := Next_Register;
            begin
               --  Statement temporaries may be recycled after their final
               --  use. Clear packets as well as recycling register numbers:
               --  stale heap references would otherwise keep garbage alive.
               Statement;
               if Next_Register > Mark then
                  Put ((Op => Clear_Registers, A => Mark,
                        B => Next_Register - 1, others => <>));
               end if;
               Next_Register := Mark;
            end;
            exit when Was_Return;
         end loop;
         if New_Scope then
            Put ((Op => Leave_Scope, others => <>));
            Scope_Depth := Scope_Depth - 1;
            Active.Set_Length (Saved);
         end if;
         Parse_Depth := Parse_Depth - 1;
      end Block;

      procedure Declaration (Global : Boolean := False) is
         Pending : Names.Vector;
         Targets : Expressions.Vector;
         Initializers : Registers.Vector;
         Default_Const : constant Boolean := Attribute;
         Item : Name_Binding;
         Has_Initializer : Boolean;
      begin
         --  Collect pending declarations without adding them to Active.
         --  Initializers therefore see the previous lexical bindings, as
         --  required for constructs such as local x = x. Global declarations
         --  retain _ENV/key recipes before any right-to-left stores occur.
         if Global and then Take (Star) then
            Active.Append
              (Name_Binding'(Null_Unbounded_String, Collective_Name,
                             0, Default_Const));
            return;
         end if;
         loop
            Item.Name := Read_Name;
            Item.Kind := (if Global then Global_Name else Local_Name);
            Item.Symbol := (if Global then 0 else New_Symbol);
            Item.Constant_Name := Attribute (Default_Const);
            Pending.Append (Item);
            if Global then
               Targets.Append (Global_Target (Item.Name));
            end if;
            exit when not Take (Comma);
         end loop;
         Has_Initializer := Take (Assign);
         if Has_Initializer then
            Initializers := Expression_List;
         end if;
         if Global then
            --  Capture all lvalues before evaluating stores. Lua stores a
            --  multiple assignment right-to-left, including global checks.
            for Index in reverse Pending.First_Index .. Pending.Last_Index
            loop
               if Has_Initializer then
                  Put ((Op => Check_Global, A => Targets (Index).Table_Reg,
                        B => Targets (Index).Key_Reg, others => <>));
                  Store (Targets (Index), Pick (Initializers, Index));
               end if;
            end loop;
         else
            for Index in Pending.First_Index .. Pending.Last_Index loop
               Put ((Op => Declare_Local, A => Pick (Initializers, Index),
                     B => Pending (Index).Symbol, others => <>));
            end loop;
         end if;
         for Binding of Pending loop
            Active.Append (Binding);
         end loop;
      end Declaration;

      procedure Function_Statement (Global : Boolean := False) is
         Name : constant Unbounded_String := Read_Name;
         Target : Expression;
         Item : Expression;
         Field : Unbounded_String;
         Method : Boolean := False;
         Key : Positive;
         Output : Positive;
      begin
         if Global then
            Active.Append (Name_Binding'(Name, Global_Name, 0, False));
            Target := Global_Target (Name);
         else
            Target := Name_Expression (Name);
         end if;
         while Kind in Dot | Colon loop
            Method := Kind = Colon;
            Advance;
            Field := Read_Name;
            Key := New_Register;
            Put ((Op => Load_String, A => Key, Text => Field, others => <>));
            Output := New_Register;
            Target := (Register_Id => Output, Target => Index_Target,
                       Table_Reg => Target.Register_Id,
                       Key_Reg => Key, others => <>);
            Target.Read_At := Emit
              ((Op => Get_Item, A => Output, B => Target.Table_Reg,
                C => Key, others => <>));
            exit when Method;
         end loop;
         if Target.Read_At /= 0 then
            declare
               Read : Instruction := Current.Code (Target.Read_At);
            begin
               Read.Op := No_Operation;
               Current.Code.Replace_Element (Target.Read_At, Read);
            end;
         end if;
         Item := Function_Body (Method);
         if Global then
            Put ((Op => Check_Global, A => Target.Table_Reg,
                  B => Target.Key_Reg, others => <>));
         end if;
         Store (Target, Item.Register_Id);
      end Function_Statement;

      procedure Close_Loop (Finish : Positive) is
      begin
         for Site of Loop_Stack.Last_Element.Breaks loop
            Patch (Site, Finish);
         end loop;
         Loop_Stack.Delete_Last;
      end Close_Loop;

      procedure While_Statement is
         Start : constant Positive := Natural (Current.Code.Length) + 1;
         Condition : Expression;
         Exit_Site : Positive;
      begin
         Condition := Parse_Expression;
         Expect (Do_Word);
         Exit_Site := Emit
           ((Op => Jump_False, A => Condition.Register_Id, others => <>));
         Loop_Stack.Append
           (Loop_Context'(Scope_Depth, Registers.Empty_Vector));
         Block;
         Expect (End_Word);
         Put ((Op => Jump, Target => Start, others => <>));
         Patch (Exit_Site, Natural (Current.Code.Length) + 1);
         Close_Loop (Natural (Current.Code.Length) + 1);
      end While_Statement;

      procedure Repeat_Statement is
         Start : constant Positive := Natural (Current.Code.Length) + 1;
         Saved : constant Ada.Containers.Count_Type := Active.Length;
         Condition : Expression;
      begin
         Loop_Stack.Append
           (Loop_Context'(Scope_Depth, Registers.Empty_Vector));
         Put ((Op => Enter_Scope, others => <>));
         Scope_Depth := Scope_Depth + 1;
         Block (New_Scope => False);
         Expect (Until_Word);
         --  Repeat's condition shares the body's lexical scope. Block(false)
         --  must retain those declarations until this expression is compiled.
         Condition := Parse_Expression;
         Put ((Op => Leave_Scope, others => <>));
         Scope_Depth := Scope_Depth - 1;
         Put ((Op => Jump_False, A => Condition.Register_Id,
               Target => Start, others => <>));
         Active.Set_Length (Saved);
         Close_Loop (Natural (Current.Code.Length) + 1);
      end Repeat_Statement;

      procedure If_Statement is
         Condition : Expression;
         Branch : Positive;
         Finish : Registers.Vector;
      begin
         --  Each failed condition jumps to the next arm. Successful arms
         --  share a patched exit list, avoiding execution of later branches.
         loop
            Condition := Parse_Expression;
            Expect (Then_Word);
            Branch := Emit
              ((Op => Jump_False, A => Condition.Register_Id, others => <>));
            Block;
            Finish.Append (Emit ((Op => Jump, others => <>)));
            Patch (Branch, Natural (Current.Code.Length) + 1);
            exit when not Take (Elseif_Word);
         end loop;
         if Take (Else_Word) then
            Block;
         end if;
         Expect (End_Word);
         for Site of Finish loop
            Patch (Site, Natural (Current.Code.Length) + 1);
         end loop;
      end If_Statement;

      procedure For_Statement is
         Names_List : Names.Vector;
         First_Name : constant Unbounded_String := Read_Name;
         Initial, Limit, Step : Expression;
         Inputs : Registers.Vector;
         Saved : constant Ada.Containers.Count_Type := Active.Length;
         Control, Bound, Delta_Reg : Positive;
         Start, Exit_Site, Advance_Site : Positive;
         Item : Name_Binding;
         Generic_Loop : Boolean;
      begin
         --  Evaluate controls in the surrounding scope before introducing
         --  loop locals. Numeric loops hold private control registers;
         --  generic loops retain iterator/state/control separately from the
         --  visible variables, which Lua code is allowed to assign.
         Item := (First_Name, Local_Name, New_Symbol, False);
         Names_List.Append (Item);
         Generic_Loop := not Take (Assign);
         if not Generic_Loop then
            Initial := Parse_Expression;
            Expect (Comma);
            Limit := Parse_Expression;
            if Take (Comma) then
               Step := Parse_Expression;
            else
               Step.Register_Id := New_Register;
               Put ((Op => Load_Value, A => Step.Register_Id,
                     Literal => (Integer_Kind, 1), others => <>));
            end if;
            Control := New_Register;
            Bound := New_Register;
            Delta_Reg := New_Register;
            Put ((Op => For_Initialize, A => Control,
                  B => Bound, C => Delta_Reg, D => Initial.Register_Id,
                  Inputs => Registers.To_Vector (Limit.Register_Id, 1) &
                    Registers.To_Vector (Step.Register_Id, 1), others => <>));
         else
            while Take (Comma) loop
               Item := (Read_Name, Local_Name, New_Symbol, False);
               Names_List.Append (Item);
            end loop;
            Expect (In_Word);
            Inputs := Expression_List;
            Control := Pick (Inputs, 1);
            Bound := Pick (Inputs, 2);
            Delta_Reg := Pick (Inputs, 3);
            Put ((Op => Check_Iterator, A => Pick (Inputs, 4), others => <>));
         end if;
         Expect (Do_Word);
         Start := Natural (Current.Code.Length) + 1;
         if Generic_Loop then
            Inputs.Clear;
            Inputs.Append (Bound);
            Inputs.Append (Delta_Reg);
            Initial.Register_Id := New_Register;
            Put ((Op => Call_Function, A => Initial.Register_Id, B => Control,
                  Inputs => Inputs, others => <>));
            Put ((Op => Move_First, A => Delta_Reg,
                  B => Initial.Register_Id, others => <>));
            Exit_Site := Emit
              ((Op => Jump_Nil, A => Delta_Reg, others => <>));
         else
            Exit_Site := Emit
              ((Op => For_Test, A => Control, B => Bound,
                C => Delta_Reg, others => <>));
         end if;
         Loop_Stack.Append
           (Loop_Context'(Scope_Depth, Registers.Empty_Vector));
         --  Enter a fresh environment on every iteration. Closures created
         --  in the body must retain that iteration's cells after it ends.
         Put ((Op => Enter_Scope, others => <>));
         Scope_Depth := Scope_Depth + 1;
         Inputs.Clear;
         Inputs.Append (Initial.Register_Id);
         for Index in Names_List.First_Index .. Names_List.Last_Index loop
            Item := Names_List (Index);
            Active.Append (Item);
            Put ((Op => Declare_Local, B => Item.Symbol,
                  A => (if Generic_Loop then Pick (Inputs, Index)
                        else Control), others => <>));
         end loop;
         Block (New_Scope => False);
         Expect (End_Word);
         Put ((Op => Leave_Scope, others => <>));
         Scope_Depth := Scope_Depth - 1;
         Active.Set_Length (Saved);
         if Generic_Loop then
            Put ((Op => Jump, Target => Start, others => <>));
         else
            Advance_Site := Emit
              ((Op => For_Advance, A => Control, B => Bound,
                C => Delta_Reg, Target => Start, others => <>));
            declare
               Code : Instruction := Current.Code (Advance_Site);
            begin
               Code.D := Natural (Current.Code.Length) + 1;
               Current.Code.Replace_Element (Advance_Site, Code);
            end;
         end if;
         Patch (Exit_Site, Natural (Current.Code.Length) + 1);
         Close_Loop (Natural (Current.Code.Length) + 1);
      end For_Statement;

      procedure Assignment_Or_Call is
         Targets : Expressions.Vector;
         Item : Expression := Prefix;
         Inputs : Registers.Vector;
      begin
         if Kind not in Assign | Comma then
            if not Item.Multiple then
               Error ("only function calls may be expression statements");
            end if;
            return;
         end if;
         loop
            if Item.Target = No_Target or else Item.Read_Only then
               Error ("invalid or const assignment target");
            end if;
            if Item.Read_At /= 0 then
               declare
                  Read : Instruction := Current.Code (Item.Read_At);
               begin
                  Read.Op := No_Operation;
                  Current.Code.Replace_Element (Item.Read_At, Read);
               end;
            end if;
            Targets.Append (Item);
            exit when not Take (Comma);
            Item := Prefix;
         end loop;
         Expect (Assign);
         Inputs := Expression_List;
         --  RHS packets and index operands were all evaluated first. Stores
         --  therefore cannot change another target's address or RHS value.
         for Index in reverse Targets.First_Index .. Targets.Last_Index loop
            Store (Targets (Index), Pick (Inputs, Index));
         end loop;
      end Assignment_Or_Call;

      procedure Statement is
         Item : Expression;
         Binding : Name_Binding;
         Inputs : Registers.Vector;
         Site : Positive;
         Loop_Item : Loop_Context;
      begin
         if Take (Semicolon) then
            return;
         elsif Take (If_Word) then
            If_Statement;
         elsif Take (While_Word) then
            While_Statement;
         elsif Take (Repeat_Word) then
            Repeat_Statement;
         elsif Take (For_Word) then
            For_Statement;
         elsif Take (Do_Word) then
            Block;
            Expect (End_Word);
         elsif Take (Function_Word) then
            Function_Statement;
         elsif Take (Local_Word) then
            if Take (Function_Word) then
               Binding := (Read_Name, Local_Name, New_Symbol, False);
               Active.Append (Binding);
               Site := New_Register;
               Put ((Op => Load_Value, A => Site, others => <>));
               Put ((Op => Declare_Local, A => Site,
                     B => Binding.Symbol, others => <>));
               Item := Function_Body;
               Put ((Op => Write_Local, A => Item.Register_Id,
                     B => Binding.Symbol, others => <>));
            else
               Declaration;
            end if;
         elsif Kind = Identifier and then Text = "global" and then
           Next_Kind in Function_Word | Star | Less | Identifier
         then
            Advance;
            if Take (Function_Word) then
               Function_Statement (Global => True);
            else
               Declaration (Global => True);
            end if;
         elsif Take (Break_Word) then
            if Loop_Stack.Is_Empty then
               Error ("break outside a loop");
            end if;
            Loop_Item := Loop_Stack.Last_Element;
            for Index in Loop_Item.Depth + 1 .. Scope_Depth loop
               Put ((Op => Leave_Scope, others => <>));
            end loop;
            Loop_Item.Breaks.Append (Emit ((Op => Jump, others => <>)));
            Loop_Stack.Replace_Element (Loop_Stack.Last_Index, Loop_Item);
         elsif Take (Return_Word) then
            if Kind not in Semicolon | End_Of_Input | End_Word |
              Else_Word | Elseif_Word | Until_Word
            then
               Inputs := Expression_List;
            end if;
            if Inputs.Length = 1 and then not Current.Code.Is_Empty and then
              Current.Code.Last_Element.Op = Call_Function and then
              Current.Code.Last_Element.A = Inputs.First_Element
            then
               declare
                  Code : Instruction := Current.Code.Last_Element;
               begin
                  Code.Op := Tail_Call;
                  Current.Code.Replace_Element (Current.Code.Last_Index, Code);
               end;
            else
               Put ((Op => Return_Values, Inputs => Inputs, others => <>));
            end if;
            if Kind = Semicolon then
               Advance;
            end if;
         elsif Kind in Goto_Word | Double_Colon then
            Error ("goto and labels are outside the M1 language subset");
         else
            Assignment_Or_Call;
         end if;
      end Statement;
   begin
      if Scanned.Status /= Success then
         State.Failure_At := Scanned.Location;
         State.Is_Syntax := Scanned.Status = Syntax_Error;
         Fail (State, To_String (Scanned.Message),
               Resource => Scanned.Status = Resource_Error);
      end if;
      Current := new Prototype;
      State.Programs.Append (Current);
      Current.Name := To_Unbounded_String (Name);
      Current.Vararg := True;
      Current.Is_Main := True;
      Current.Environment_Symbol := New_Symbol;
      Active.Append
        (Name_Binding'(To_Unbounded_String ("_ENV"), Local_Name,
                       Current.Environment_Symbol, False));
      Block (New_Scope => False);
      Expect (End_Of_Input);
      Put ((Op => Return_Values, others => <>));
      return Current;
   end Compile;
end Lua.Engine.Compiler;
