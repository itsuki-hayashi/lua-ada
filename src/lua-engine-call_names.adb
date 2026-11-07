with Lua.Opcodes;
with Lua.Prototypes;
with Lua.Engine.Canonical;

package body Lua.Engine.Call_Names is
   use Lua.Opcodes;
   use type Lua.Prototypes.Prototype_Access;
   use type Lua.Prototypes.String_Id;
   use type System.Address;

   Unknown_Name : aliased constant String := "?" & Character'Val (0);
   Integer_Index : aliased constant String :=
     "integer index" & Character'Val (0);
   Iterator_Name : aliased constant String :=
     "for iterator" & Character'Val (0);
   Unknown_Bytes : constant Byte_String := (Unknown_Name'Address, 1);

   --  The enum order is the pinned ltm.h TMS word contract used by MMBIN
   --  C fields. These immutable NUL-terminated markers support both Lua
   --  materialization and allocation-free C debug borrows.
   type Metamethod_Event is
     (Index_Event,
      Newindex_Event,
      GC_Event,
      Mode_Event,
      Length_Event,
      Equal_Event,
      Add_Event,
      Subtract_Event,
      Multiply_Event,
      Modulo_Event,
      Power_Event,
      Divide_Event,
      Floor_Divide_Event,
      Bit_And_Event,
      Bit_Or_Event,
      Bit_Xor_Event,
      Shift_Left_Event,
      Shift_Right_Event,
      Unary_Minus_Event,
      Bit_Not_Event,
      Less_Event,
      Less_Equal_Event,
      Concatenate_Event,
      Call_Event,
      Close_Event);
   type Name_Access is access constant String;
   Index_Text : aliased constant String :=
     "index" & Character'Val (0);
   Newindex_Text : aliased constant String :=
     "newindex" & Character'Val (0);
   GC_Text : aliased constant String :=
     "gc" & Character'Val (0);
   Mode_Text : aliased constant String :=
     "mode" & Character'Val (0);
   Length_Text : aliased constant String :=
     "len" & Character'Val (0);
   Equal_Text : aliased constant String :=
     "eq" & Character'Val (0);
   Add_Text : aliased constant String :=
     "add" & Character'Val (0);
   Subtract_Text : aliased constant String :=
     "sub" & Character'Val (0);
   Multiply_Text : aliased constant String :=
     "mul" & Character'Val (0);
   Modulo_Text : aliased constant String :=
     "mod" & Character'Val (0);
   Power_Text : aliased constant String :=
     "pow" & Character'Val (0);
   Divide_Text : aliased constant String :=
     "div" & Character'Val (0);
   Floor_Divide_Text : aliased constant String :=
     "idiv" & Character'Val (0);
   Bit_And_Text : aliased constant String :=
     "band" & Character'Val (0);
   Bit_Or_Text : aliased constant String :=
     "bor" & Character'Val (0);
   Bit_Xor_Text : aliased constant String :=
     "bxor" & Character'Val (0);
   Shift_Left_Text : aliased constant String :=
     "shl" & Character'Val (0);
   Shift_Right_Text : aliased constant String :=
     "shr" & Character'Val (0);
   Unary_Minus_Text : aliased constant String :=
     "unm" & Character'Val (0);
   Bit_Not_Text : aliased constant String :=
     "bnot" & Character'Val (0);
   Less_Text : aliased constant String :=
     "lt" & Character'Val (0);
   Less_Equal_Text : aliased constant String :=
     "le" & Character'Val (0);
   Concatenate_Text : aliased constant String :=
     "concat" & Character'Val (0);
   Call_Text : aliased constant String :=
     "call" & Character'Val (0);
   Close_Text : aliased constant String :=
     "close" & Character'Val (0);
   Event_Names : constant array (Metamethod_Event) of Name_Access :=
     [Index_Event => Index_Text'Access,
      Newindex_Event => Newindex_Text'Access,
      GC_Event => GC_Text'Access,
      Mode_Event => Mode_Text'Access,
      Length_Event => Length_Text'Access,
      Equal_Event => Equal_Text'Access,
      Add_Event => Add_Text'Access,
      Subtract_Event => Subtract_Text'Access,
      Multiply_Event => Multiply_Text'Access,
      Modulo_Event => Modulo_Text'Access,
      Power_Event => Power_Text'Access,
      Divide_Event => Divide_Text'Access,
      Floor_Divide_Event => Floor_Divide_Text'Access,
      Bit_And_Event => Bit_And_Text'Access,
      Bit_Or_Event => Bit_Or_Text'Access,
      Bit_Xor_Event => Bit_Xor_Text'Access,
      Shift_Left_Event => Shift_Left_Text'Access,
      Shift_Right_Event => Shift_Right_Text'Access,
      Unary_Minus_Event => Unary_Minus_Text'Access,
      Bit_Not_Event => Bit_Not_Text'Access,
      Less_Event => Less_Text'Access,
      Less_Equal_Event => Less_Equal_Text'Access,
      Concatenate_Event => Concatenate_Text'Access,
      Call_Event => Call_Text'Access,
      Close_Event => Close_Text'Access];
   Finalizer_Text : aliased constant String := "__gc" & Character'Val (0);

   function Finalizer_Name return Byte_String is
     ((Finalizer_Text'Address, Finalizer_Text'Length - 1));
   function Hook_Name return Byte_String is (Unknown_Bytes);

   function Event_Name (Event : Metamethod_Event) return Borrowed_Identity;
   function Event_Name (Event : Metamethod_Event) return Borrowed_Identity is
     ((Event_Names (Event).all'Address, Event_Names (Event)'Length - 1),
      Metamethod_Call);

   function Kind_Image (Kind : Name_Kind) return String is
     (case Kind is
         when Unknown => "", when Local_Binding => "local",
         when Upvalue_Binding => "upvalue", when Constant_Value => "constant",
         when Global_Field => "global", when Table_Field => "field",
         when Method_Call => "method", when Iterator_Call => "for iterator",
         when Metamethod_Call => "metamethod", when Hook_Call => "hook");

   function Resolve_Name
     (State : in out World; Caller : Frame_Access; Operand_Index : Natural)
      return Borrowed_Identity;
   function Resolve_Name
     (State : in out World; Caller : Frame_Access; Operand_Index : Natural)
      return Borrowed_Identity
   is
      Code : Prototype_Access renames Caller.Code;
      Model : constant Lua.Prototypes.Prototype_Access := Code.Canonical_Node;
      PC : constant Natural := Natural'Max (1, Caller.PC - 1) - 1;
      Instruction : Word;
      Op : Opcode;
      function Part (Item : Word; Id : Field) return Natural;
      procedure Charge;
      function Text (Id : Lua.Prototypes.String_Id; Kind : Name_Kind)
                     return Borrowed_Identity;
      function Literal_Name (Index : Natural) return Borrowed_Identity;
      function Resolve
        (Register_Id, Before : Natural; Expanded : Boolean)
         return Borrowed_Identity;
      function Is_Environment
        (Register_Id, Before : Natural; Is_Upvalue : Boolean) return Boolean;
      function Setter (Register_Id, Before : Natural) return Natural;
      --  Setter returns PC+1; zero represents an ambiguous/missing write.

      function Part (Item : Word; Id : Field) return Natural is
         Result : constant Operand_Result := Get (Item, Id);
      begin
         return (if Result.Status = Success and then Result.Value >= 0 then
                   Result.Value else 0);
      end Part;

      procedure Charge is
      begin
         if State.Policy = Bounded then
            if State.Steps >= State.Bounds.Instructions then
               Fail (State, "instruction limit exceeded", Resource => True);
            end if;
            State.Steps := State.Steps + 1;
         end if;
      end Charge;

      function Text (Id : Lua.Prototypes.String_Id; Kind : Name_Kind)
                     return Borrowed_Identity
      is
      begin
         if Id = Lua.Prototypes.No_String then
            return (Unknown_Bytes, Kind);
         end if;
         return
           ((Lua.Prototypes.String_Address (Code.Canonical_Owner.Model, Id),
             Lua.Prototypes.String_Length (Code.Canonical_Owner.Model, Id)),
            Kind);
      end Text;

      function Literal_Name (Index : Natural) return Borrowed_Identity is
      begin
         if Index < Natural (Code.Canonical_Constants.Length) and then
           Code.Canonical_Constants (Index + 1).Kind = String_Kind
         then
            return (Code.Canonical_Constants (Index + 1).Reference.Bytes,
                    Constant_Value);
         end if;
         return (Unknown_Bytes, Unknown);
      end Literal_Name;

      function Setter (Register_Id, Before : Natural) return Natural is
         Found : Natural := 0;
         Limit : Natural := Before;
         Conditional_Until : Long_Long_Integer := 0;
         Item : Word;
         Operation_Id : Opcode;
         Destination : Long_Long_Integer;
         Base : Natural;
         Changes : Boolean;
      begin
         if Before > 0 and then Before < Model.Code.Last_Index and then
           Valid (Model.Code (Before + 1)) and then
           Lua.Opcodes.Operation (Model.Code (Before + 1)) in
             Op_MMBIN | Op_MMBINI | Op_MMBINK
         then
            --  A reached metamethod companion means its preceding arithmetic
            --  operation did not write the result. In-place lowering can use
            --  that same register as an operand, so treating the failed word
            --  as a setter would erase its actual field/upvalue provenance.
            --  This is ldebug.c:findsetreg's testMMMode(lastpc) adjustment.
            Limit := Before - 1;
         end if;
         --  Forward edges can make an apparent last setter conditional. Keep
         --  that uncertainty rather than attributing a name from one branch.
         --  This follows pinned ldebug's reaching-write rule over real words.
         for Index in 0 .. Integer (Limit) - 1 loop
            Charge;
            Item := Model.Code (Index + 1);
            if not Valid (Item) then return 0; end if;
            Operation_Id := Lua.Opcodes.Operation (Item);
            Base := Part (Item, A);
            case Operation_Id is
               when Op_LOADNIL =>
                  Changes := Register_Id in Base .. Base + Part (Item, B);
               when Op_TFORCALL => Changes := Register_Id >= Base + 2;
               when Op_CALL | Op_TAILCALL => Changes := Register_Id >= Base;
               when Op_JMP =>
                  Destination := Long_Long_Integer (Index) + 1 +
                    Long_Long_Integer (Get (Item, SJ).Value);
                  if Destination <= Long_Long_Integer (Limit) then
                     Conditional_Until := Long_Long_Integer'Max
                       (Conditional_Until, Destination);
                  end if;
                  Changes := False;
               when others =>
                  Changes := Describe (Operation_Id).Sets_A and then
                    Register_Id = Base;
            end case;
            if Changes then
               Found := (if Long_Long_Integer (Index) < Conditional_Until
                         then 0 else Index + 1);
            end if;
         end loop;
         return Found;
      end Setter;

      function Is_Environment
        (Register_Id, Before : Natural; Is_Upvalue : Boolean) return Boolean
      is
         Name : Borrowed_Identity;
      begin
         if Is_Upvalue then
            if Register_Id >= Natural (Model.Upvalues.Length) then
               return False;
            end if;
            Name := Text (Model.Upvalues (Register_Id + 1).Name,
                          Upvalue_Binding);
         else
            Name := Resolve (Register_Id, Before, Expanded => False);
         end if;
         return Name.Kind in Local_Binding | Upvalue_Binding and then
           Name.Item = "_ENV";
      end Is_Environment;

      function Resolve
        (Register_Id, Before : Natural; Expanded : Boolean)
         return Borrowed_Identity
      is
         Register : Natural := Register_Id;
         Limit : Natural := Before;
         Set_At : Natural;
         Item : Word;
         Operation_Id : Opcode;
         Name : Byte_String;
         Key_Name : Borrowed_Identity;
         Kind : Name_Kind;
      begin
         loop
            Name := Canonical.Local_Bytes (Code, Register + 1, Limit);
            if Name.Address /= System.Null_Address then
               return (Name, Local_Binding);
            end if;
            Set_At := Setter (Register, Limit);
            if Set_At = 0 then return (others => <>); end if;
            Item := Model.Code (Set_At);
            Operation_Id := Lua.Opcodes.Operation (Item);
            Limit := Set_At - 1;
            case Operation_Id is
               when Op_MOVE =>
                  if Part (Item, B) >= Part (Item, A) then
                     return (others => <>);
                  end if;
                  --  Aliases move toward an earlier register and instruction.
                  --  An iterative walk cannot grow the Ada stack or cycle.
                  Register := Part (Item, B);
               when Op_GETUPVAL =>
                  if Part (Item, B) >= Natural (Model.Upvalues.Length) then
                     return (others => <>);
                  end if;
                  return Text (Model.Upvalues (Part (Item, B) + 1).Name,
                               Upvalue_Binding);
               when Op_LOADK => return Literal_Name (Part (Item, Bx));
               when Op_LOADKX =>
                  if Set_At < Model.Code.Last_Index then
                     return Literal_Name (Part (Model.Code (Set_At + 1), Ax));
                  end if;
                  return (others => <>);
               when Op_GETTABUP | Op_GETTABLE | Op_GETVARG | Op_GETI |
                 Op_GETFIELD | Op_SELF =>
                  if not Expanded then return (others => <>); end if;
                  if Operation_Id in Op_GETTABLE | Op_GETVARG then
                     Key_Name := Resolve (Part (Item, C), Limit, False);
                     if Key_Name.Kind /= Constant_Value then
                        Key_Name := (Unknown_Bytes, Unknown);
                     end if;
                  elsif Operation_Id = Op_GETI then
                     Key_Name :=
                       ((Integer_Index'Address, Integer_Index'Length - 1),
                        Unknown);
                  else
                     Key_Name := Literal_Name (Part (Item, C));
                  end if;
                  Kind := (if Operation_Id = Op_SELF then Method_Call
                           elsif Operation_Id = Op_GETI then Table_Field
                           elsif Is_Environment (Part (Item, B), Limit,
                             Operation_Id = Op_GETTABUP) then Global_Field
                           else Table_Field);
                  return (Key_Name.Item, Kind);
               when others => return (others => <>);
            end case;
         end loop;
      end Resolve;
   begin
      if Model = null or else PC >= Model.Code.Last_Index then
         return (others => <>);
      end if;
      Instruction := Model.Code (PC + 1);
      if not Valid (Instruction) then return (others => <>); end if;
      Op := Lua.Opcodes.Operation (Instruction);
      if Operand_Index /= 0 then
         --  Arithmetic fallbacks retain their original argument order. An
         --  immediate/constant can be flipped in front of its register; only
         --  the register has a source binding to explain in the diagnostic.
         case Op is
            when Op_MMBIN =>
               return Resolve
                 (Part (Instruction, (if Operand_Index = 1 then A else B)),
                  PC, Expanded => True);
            when Op_MMBINI | Op_MMBINK =>
               if (Operand_Index = 1) = (Part (Instruction, K) = 0) then
                  return Resolve (Part (Instruction, A), PC, True);
               end if;
            when Op_BNOT | Op_UNM | Op_LEN =>
               return Resolve (Part (Instruction, B), PC, True);
            when Op_GETTABUP | Op_SETTABUP =>
               --  These two operations index the actual upvalue cell
               --  directly. varinfo checks that identity before registers;
               --  do not describe its key as the failing table object.
               declare
                  Index : constant Natural := Part
                    (Instruction, (if Op = Op_GETTABUP then B else A));
               begin
                  if Index >= Natural (Model.Upvalues.Length) then
                     return (others => <>);
                  end if;
                  return Text
                    (Model.Upvalues (Index + 1).Name, Upvalue_Binding);
               end;
            when Op_GETTABLE | Op_GETI | Op_GETFIELD | Op_SELF =>
               return Resolve (Part (Instruction, B), PC, True);
            when Op_SETTABLE | Op_SETI | Op_SETFIELD =>
               return Resolve (Part (Instruction, A), PC, True);
            when Op_CONCAT =>
               if Caller.Canonical_Pending = Concat_Canonical_Result and then
                 Caller.Canonical_Concat_Last > 0
               then
                  --  A handler can complete several earlier folds before
                  --  this pair fails. Use its actual remaining register pair,
                  --  not the original instruction's rightmost operands.
                  return Resolve
                    (Caller.Canonical_Concat_Last -
                       (if Operand_Index = 1 then 1 else 0), PC, True);
               end if;
            when others => null;
         end case;
         return (others => <>);
      end if;
      case Op is
         when Op_CALL | Op_TAILCALL =>
            return Resolve (Part (Instruction, A), PC, Expanded => True);
         when Op_TFORCALL =>
            return ((Iterator_Name'Address, Iterator_Name'Length - 1),
                    Iterator_Call);
         when Op_SELF | Op_GETTABUP | Op_GETTABLE | Op_GETI | Op_GETFIELD =>
            return Event_Name (Index_Event);
         when Op_SETTABUP | Op_SETTABLE | Op_SETI | Op_SETFIELD =>
            return Event_Name (Newindex_Event);
         when Op_MMBIN | Op_MMBINI | Op_MMBINK =>
            if Part (Instruction, C) <=
              Metamethod_Event'Pos (Metamethod_Event'Last)
            then
               return Event_Name
                 (Metamethod_Event'Val (Part (Instruction, C)));
            end if;
            return (others => <>);
         when Op_UNM => return Event_Name (Unary_Minus_Event);
         when Op_BNOT => return Event_Name (Bit_Not_Event);
         when Op_LEN => return Event_Name (Length_Event);
         when Op_CONCAT => return Event_Name (Concatenate_Event);
         when Op_EQ => return Event_Name (Equal_Event);
         when Op_LT | Op_LTI | Op_GTI => return Event_Name (Less_Event);
         when Op_LE | Op_LEI | Op_GEI => return Event_Name (Less_Equal_Event);
         when Op_CLOSE | Op_RETURN => return Event_Name (Close_Event);
         when others => return (others => <>);
      end case;
   end Resolve_Name;

   function C_Name_View (Item : Borrowed_Identity) return Borrowed_Identity;
   function C_Name_View (Item : Borrowed_Identity) return Borrowed_Identity is
      Result : Borrowed_Identity := Item;
   begin
      --  Lua debug names and varinfo cross a C string boundary upstream.
      --  A string-literal field key may contain NUL even though identifiers
      --  cannot. Retain the immutable owner/address and shorten only this
      --  borrowed view; the original Lua key keeps all its counted bytes.
      if Item.Item.Address /= System.Null_Address and then
        Item.Item.Size /= 0
      then
         declare
            Text : String (1 .. Item.Item.Size)
              with Import, Address => Item.Item.Address;
         begin
            for Index in Text'Range loop
               if Text (Index) = Character'Val (0) then
                  Result.Item.Size := Index - 1;
                  exit;
               end if;
            end loop;
         end;
      end if;
      return Result;
   end C_Name_View;

   function Name_Image (Item : Borrowed_Identity) return String is
     (To_String (C_Name_View (Item).Item));

   function View_From_Caller
     (State : in out World; Caller : Frame_Access)
      return Borrowed_Identity is
     (Resolve_Name (State, Caller, 0));

   function Materialize
     (State : in out World; Item : Borrowed_Identity) return Identity;
   function Materialize
     (State : in out World; Item : Borrowed_Identity) return Identity is
     ((if Item.Item.Address = System.Null_Address then Nil_Value else
         New_String (State, Name_Image (Item))), Item.Kind);

   function From_Caller
     (State : in out World; Caller : Frame_Access) return Identity is
     (Materialize (State, View_From_Caller (State, Caller)));

   function View_From_Operand
     (State : in out World; Caller : Frame_Access; Index : Arithmetic_Operand)
      return Borrowed_Identity is
     (Resolve_Name (State, Caller, Index));
end Lua.Engine.Call_Names;
