with Lua.Diagnostic_Text;
with Lua.Engine.Finalizers;
with Lua.Engine.Garbage_Collection;
with Lua.Engine.IO_Libraries;
with Lua.Engine.Operating_System;
with Ada.Characters.Latin_1;
with Ada.Containers;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Unchecked_Deallocation;
with System.Address_To_Access_Conversions;
with Interfaces;
with Interfaces.C;
with Lua.Integers;
with Lua.Lexers; use Lua.Lexers;
with Lua.Platform_Numerics;
with Lua.Prototypes;
with Lua.Runtime_Configuration;
with Lua.Engine.Strings;
with Lua.Engine.Packing;
with Lua.Engine.Unicode;
with Lua.Engine.Core_Libraries;
with Lua.Engine.Pattern_Drivers;
with Lua.Engine.Loaders;
with Lua.Engine.Native_Modules;
with Lua.Engine.Format_Drivers;
with Lua.Engine.Diagnostics;
with Lua.Engine.Table_Drivers;
with Lua.Engine.Sorting;
with Lua.Engine.Inspection;
with Lua.Engine.Hooks;
with Lua.Engine.Canonical;
with Lua.Engine.C_Operators;
with Lua.Engine.Call_Names;
with Lua.Engine.Stacks;
with Lua.Engine.Stack_Views;
with Lua.Engine.Foreign;
with Lua.Engine.Warnings;
with Lua.Engine.External_Releases;
with Lua.Engine.Mathematics;

package body Lua.Engine.Machine is
   function Collector_Drain_Address return System.Address
     with Import, Convention => C,
          External_Name => "lua_ada_collector_drain_address";
   Collector_Transport : constant System.Address := Collector_Drain_Address;
   --  A process-lifetime borrow of the actual C pump address. Recognizing it
   --  before its first scheduler step preserves public call/return hooks;
   --  guard ownership, real stack windows and native charging stay intact.

   function Reader_Portal_Address return System.Address
     with Import, Convention => C,
          External_Name => "lua_ada_reader_portal_address";

   Warning_On : aliased constant String := "@on" & Character'Val (0);
   Warning_Off : aliased constant String := "@off" & Character'Val (0);
   GC_Warning_Start_Text : aliased constant String :=
     "error in " & ASCII.NUL;
   GC_Warning_Start : constant Byte_String :=
     (GC_Warning_Start_Text'Address,
      GC_Warning_Start_Text'Length - 1);
   GC_Warning_Where_Text : aliased constant String :=
     "__gc" & ASCII.NUL;
   GC_Warning_Where : constant Byte_String :=
     (GC_Warning_Where_Text'Address,
      GC_Warning_Where_Text'Length - 1);
   GC_Warning_Open_Text : aliased constant String :=
     " (" & ASCII.NUL;
   GC_Warning_Open : constant Byte_String :=
     (GC_Warning_Open_Text'Address,
      GC_Warning_Open_Text'Length - 1);
   GC_Warning_Close_Text : aliased constant String :=
     ")" & ASCII.NUL;
   GC_Warning_Close : constant Byte_String :=
     (GC_Warning_Close_Text'Address,
      GC_Warning_Close_Text'Length - 1);
   GC_Warning_Nonstring_Text : aliased constant String :=
     "error object is not a string" & ASCII.NUL;
   GC_Warning_Nonstring : constant Byte_String :=
     (GC_Warning_Nonstring_Text'Address,
      GC_Warning_Nonstring_Text'Length - 1);

   --  The VM is the only executor of compiled chunks. Registers hold result
   --  packets rather than plain values; every primitive explicitly chooses
   --  scalar or expanding consumption. Lua calls use the owned frame vector,
   --  leaving the Ada call stack independent of user recursion depth.
   use type Ada.Containers.Count_Type;
   use type Ada.Exceptions.Exception_Id;
   use type Integer_Value;
   use type Lua.Prototypes.Prototype_Access;
   use type System.Address;
   use type Interfaces.C.unsigned_long_long;
   use type Interfaces.C.int;
   use type Real_Value;
   use type Interfaces.Unsigned_64;
   use type Lua.Numbers.Number_Kind;

   function First (Packet : Values.Vector) return Value is
     (if Packet.Is_Empty then Nil_Value else Packet.First_Element);

   function Scalar (Activation : Frame_Access;
     Register_Id : Natural)
                    return Value is
     (if Register_Id = 0 then Nil_Value
      else First (Activation.Slots (Register_Id)));

   function Code_Length (Activation : Frame_Access) return Natural is
     (if Activation.Code.Canonical_Node /= null then
         Natural (Activation.Code.Canonical_Node.Code.Length)
      else Natural (Activation.Code.Code.Length));
   function Line_At (Activation : Frame_Access; PC : Positive)
                     return Natural is
     (if Activation.Code.Canonical_Node /= null then
         Canonical.Source_Line (Activation, PC - 1)
      else Activation.Code.Code (PC).Location.Line);
   --  Both backends use one-based execution PCs. Canonical debug records use
   --  zero-based word offsets, and stripped chunks intentionally return zero.

   procedure Put_Packet
     (State : in out World; Activation : Frame_Access; Register_Id : Positive;
      Packet : Values.Vector);
   procedure Put_One
     (State : in out World; Activation : Frame_Access; Register_Id :
       Positive; Item : Value);
   function Flatten
     (Activation : Frame_Access; Inputs : Registers.Vector;
      Expand_Last : Boolean := True) return Values.Vector;
   function Numeric (State : in out World; Item : Value)
                     return Lua.Numbers.Number;
   function Integral
     (State : in out World; Item : Value; Operand_Index : Natural := 0)
      return Integer_Value;
   function Primitive_Integer (Item : Value) return Boolean is
     (Item.Kind = Integer_Kind or else
      (Item.Kind = Real_Kind and then Item.Real_Data >= -(2.0 ** 63) and then
       Item.Real_Data < 2.0 ** 63 and then
       Real_Value'Truncation (Item.Real_Data) = Item.Real_Data));
   --  A numeric type alone does not make bitwise arithmetic primitive. A
   --  nonintegral float must still get its numeric type's metamethod before
   --  the conversion diagnostic is issued by the fallback operation.
   procedure Put_Packet
     (State : in out World; Activation : Frame_Access; Register_Id : Positive;
      Packet : Values.Vector)
   is
      --  Coercion belongs at the primitive operation boundary, not in the
      --  stored value. A numeric string remains a string for type/identity.
   begin
      declare
         Old_Extra : constant Natural := Natural'Max
           (1, Natural (Activation.Slots (Register_Id).Length)) - 1;
         New_Extra : constant Natural :=
           Natural'Max (1, Natural (Packet.Length)) - 1;
         Delta_Slots : constant Integer := New_Extra - Old_Extra;
      begin
         --  One scalar slot is already charged by the prototype. Expanding
         --  packets charge their additional live slots, including duplicates
         --  retained by separate registers in this private backend.
         if Delta_Slots > 0 and then Delta_Slots >
           Lua.Runtime_Configuration.Maximum_Stack - Natural'Min
             (Lua.Runtime_Configuration.Maximum_Stack,
              State.Current.Stack_Slots)
         then
            Fail (State, "stack overflow");
         end if;
         Root_Barrier (State, Packet);
         Activation.Slots.Replace_Element (Register_Id, Packet);
         Activation.Slot_Cost := Activation.Slot_Cost + Delta_Slots;
         State.Current.Stack_Slots :=
           State.Current.Stack_Slots + Delta_Slots;
      end;
   end Put_Packet;

   procedure Put_One
     (State : in out World; Activation : Frame_Access; Register_Id :
       Positive; Item : Value)
   is
      Packet : Values.Vector := Owned_Values (State);
   begin
      Packet.Append (Item);
      Put_Packet (State, Activation, Register_Id, Packet);
   end Put_One;

   function Flatten
     (Activation : Frame_Access; Inputs : Registers.Vector;
      Expand_Last : Boolean := True) return Values.Vector
   is
      Result : Values.Vector := Owned_Values (Activation.Memory);
   begin
      --  Nonfinal expressions contribute one value, including nil for zero
      --  results. Only the final unparenthesized call/vararg packet expands.
      for Index in Inputs.First_Index .. Inputs.Last_Index loop
         if Expand_Last and then Index = Inputs.Last_Index then
            for Item of Activation.Slots (Inputs (Index)) loop
               Result.Append (Item);
            end loop;
         else
            Result.Append (Scalar (Activation, Inputs (Index)));
         end if;
      end loop;
      return Result;
   end Flatten;

   procedure Operation_Error
     (State : in out World; Message : String; Operand_Index : Natural := 0;
      Following : String := "");
   procedure Operation_Error
     (State : in out World; Message : String; Operand_Index : Natural := 0;
      Following : String := "")
   is
      Description : Unbounded_String := To_Unbounded_String (Message);
      Caller : Frame_Access;
      use type Call_Names.Name_Kind;
   begin
      --  Pinned ldebug.c inserts operand varinfo into the message and then
      --  luaG_runerror attributes only its actual Lua CI. Synthetic operation
      --  phases borrow that immediate owner; a primitive fault can also
      --  arise directly in the current canonical Lua activation (integer
      --  division by zero). C/library operations never search older Lua
      --  frames for a convenient binding or source line.
      if not State.Current.Stack.Is_Empty and then
        not State.Current.Stack.Last_Element.Is_Native
      then
         Caller := State.Current.Stack.Last_Element;
      elsif State.Current.Stack.Length >= 2 then
         declare
            Helper : constant Frame_Access := State.Current.Stack.Last_Element;
         begin
            Caller := State.Current.Stack (State.Current.Stack.Last_Index - 1);
            if not Helper.Is_Native or else Caller.Is_Native or else
              To_String (Helper.Native_Name) not in
                "@binary" | "@unary" | "@get" | "@set"
            then
               Caller := null;
            end if;
         end;
      end if;
      if Caller /= null and then Operand_Index /= 0 and then
        Caller.Code.Canonical_Node /= null
      then
         declare
            Name : constant Call_Names.Borrowed_Identity :=
              Call_Names.View_From_Operand (State, Caller, Operand_Index);
         begin
            if Name.Kind /= Call_Names.Unknown then
               Append (Description, " (" &
                 Call_Names.Kind_Image (Name.Kind) & " '" &
                 Call_Names.Name_Image (Name) & "')");
            end if;
         end;
      end if;
      Append (Description, Following);
      if Caller /= null then
         declare
            Line : constant Natural := Line_At
              (Caller, Positive'Max (1, Caller.PC - 1));
            Prefix : constant String := Inspection.Short_Source
              ((if Caller.Code.Canonical_Node /= null then
                  To_String (Canonical.Source_Bytes (Caller.Code))
                else To_String (Caller.Code.Name))) & ":" &
              (if Line = 0 then "?" else Ada.Strings.Fixed.Trim
                 (Line'Image, Ada.Strings.Both)) & ": ";
         begin
            Fail (State, Prefix & To_String (Description));
         end;
      end if;
      --  A native caller must not borrow a binding or location from an older
      --  Lua frame. luaG_runerror adds source only to its actual Lua CI.
      Fail (State, To_String (Description));
   end Operation_Error;

   procedure Operand_Error
     (State : in out World; Item : Value; Operation : String;
      Operand_Index : Natural);
   procedure Operand_Error
     (State : in out World; Item : Value; Operation : String;
      Operand_Index : Natural) is
   begin
      Operation_Error
        (State, "attempt to " & Operation & " a " &
         Diagnostic_Type (State, Item) & " value", Operand_Index);
   end Operand_Error;

   procedure For_Error
     (State : in out World; Kind : For_Failure_Kind;
      Item : Value := Nil_Value) is
   begin
      --  forprep's caller has already selected the real failing operand in
      --  pinned validation order. Reuse the same raw type-name and actual
      --  Lua-source policy as other primitive faults, without giving loop
      --  controls a fabricated local/field varinfo annotation.
      if Kind = Zero_Step then
         Operation_Error (State, "'for' step is zero");
      else
         Operation_Error
           (State, "bad 'for' " &
            (case Kind is
                when Initial_Not_Number => "initial value",
                when Limit_Not_Number => "limit",
                when others => "step") & " (number expected, got " &
            Diagnostic_Type (State, Item) & ")");
      end if;
   end For_Error;

   function Numeric (State : in out World; Item : Value)
                     return Lua.Numbers.Number
   is
      Result : Lua.Numbers.Number;
   begin
      case Item.Kind is
         when Integer_Kind =>
            return (Lua.Numbers.Integer_Number, Item.Integer_Data);
         when Real_Kind => return (Lua.Numbers.Real_Number, Item.Real_Data);
         when String_Kind =>
            Result := Read_Number (State, Item.Reference.Bytes);
            if Result.Kind /= Lua.Numbers.Invalid then
               return Result;
            end if;
         when others => null;
      end case;
      Fail (State, "attempt to perform arithmetic on a " &
              Diagnostic_Type (State, Item) & " value");
      return (Kind => Lua.Numbers.Invalid);
   end Numeric;

   function Integral
     (State : in out World; Item : Value; Operand_Index : Natural := 0)
      return Integer_Value
   is
      Number : constant Lua.Numbers.Number := Numeric (State, Item);
      Real : Real_Value;
   begin
      if Number.Kind = Lua.Numbers.Integer_Number then
         return Number.Integer_Item;
      end if;
      Real := Number.Real_Item;
      if Real /= Real or else Real < -2.0 ** 63 or else Real >= 2.0 ** 63
        or else Real_Value'Truncation (Real) /= Real
      then
         --  luaG_tointerror inserts varinfo after "number", before the
         --  conversion explanation. The native phase has already tried the
         --  applicable handler; resolve the actual failed operand only.
         Operation_Error
           (State, "number", Operand_Index,
            Following => " has no integer representation");
      end if;
      return Integer_Value (Real);
   end Integral;

   function Binary_Value
     (State : in out World; Operator : Token_Kind; Left, Right : Value)
      return Value
   is
      L, R : Lua.Numbers.Number;
      FL, FR, Result : Real_Value;
      IL, IR : Integer_Value;
      function Bits (Item : Integer_Value) return Interfaces.Unsigned_64 is
        (if Item >= 0 then Interfaces.Unsigned_64 (Item) else
           Interfaces.Unsigned_64 (Item - Integer_Value'First) + 2 ** 63);
      function Signed (Item : Interfaces.Unsigned_64) return Integer_Value is
        (if Item < 2 ** 63 then Integer_Value (Item) else
           Integer_Value'First + Integer_Value (Item - 2 ** 63));
      function Ordered (A, B : Value) return Boolean;

      function Ordered (A, B : Value) return Boolean is
      begin
         if A.Kind = String_Kind and then B.Kind = String_Kind then
            return A.Reference.Bytes < B.Reference.Bytes;
         elsif A.Kind in Integer_Kind | Real_Kind and then
           B.Kind in Integer_Kind | Real_Kind
         then
            return Lua.Numbers.Less (Numeric (State, A), Numeric (State, B));
         end if;
         declare
            A_Type : constant String := Diagnostic_Type (State, A);
            B_Type : constant String := Diagnostic_Type (State, B);
         begin
            --  Native order errors distinguish two values with the same
            --  diagnostic name from two different named categories. This
            --  also honors a table/userdata's actual raw __name spelling.
            Operation_Error (State, "attempt to compare " &
              (if A_Type = B_Type then "two " & A_Type & " values"
               else A_Type & " with " & B_Type));
         end;
         return False;
      end Ordered;
   begin
      if Operator in Equal | Not_Equal then
         return (Boolean_Kind,
                 Engine.Equal (Left, Right) = (Operator = Equal));
      elsif Operator in Less | Less_Equal | Greater | Greater_Equal then
         case Operator is
            when Less => return (Boolean_Kind, Ordered (Left, Right));
            when Greater => return (Boolean_Kind, Ordered (Right, Left));
            when Less_Equal =>
               return (Boolean_Kind, Ordered (Left, Right) or else
                         Engine.Equal (Left, Right));
            when others =>
               return (Boolean_Kind, Ordered (Right, Left) or else
                         Engine.Equal (Left, Right));
         end case;
      elsif Operator = Concatenate then
         if Left.Kind not in String_Kind | Integer_Kind | Real_Kind or else
           Right.Kind not in String_Kind | Integer_Kind | Real_Kind
         then
            if Left.Kind in String_Kind | Integer_Kind | Real_Kind then
               Operand_Error (State, Right, "concatenate", 2);
            else
               Operand_Error (State, Left, "concatenate", 1);
            end if;
         end if;
         --  luaV_concat reuses a string adjoining the ordinary short empty
         --  string. External empty strings intentionally take the ordinary
         --  copy path; the upstream isemptystr shortcut excludes them.
         if Right.Kind = String_Kind and then
           Right.Reference.Bytes.Size = 0 and then
           not Right.Reference.External_String
         then
            return (if Left.Kind = String_Kind then Left else
                      New_String (State, Image (State.Current.Memory, Left)));
         elsif Left.Kind = String_Kind and then
           Left.Reference.Bytes.Size = 0 and then
           not Left.Reference.External_String
         then
            return (if Right.Kind = String_Kind then Right else
                      New_String (State, Image (State.Current.Memory, Right)));
         end if;
         if Image (State.Current.Memory, Left)'Length >
           State.Bounds.String_Bytes - Natural'Min
             (Image (State.Current.Memory, Right)'Length,
              State.Bounds.String_Bytes)
         then
            Fail (State, "string byte limit exceeded", Resource => True);
         end if;
         return New_String
           (State, Image (State.Current.Memory, Left) &
            Image (State.Current.Memory, Right));
      elsif Operator in Bit_And | Bit_Or | Bit_Xor | Shift_Left | Shift_Right
      then
         --  Base argument conversion may accept numeric strings, but Lua's
         --  primitive bitwise operators do not. Keep that policy separate
         --  from Integral, which also serves tonumber/select/error arguments.
         if Left.Kind = String_Kind or else Right.Kind = String_Kind then
            Fail (State, "attempt to perform bitwise operation on a string");
         end if;
         IL := Integral (State, Left, 1);
         IR := Integral (State, Right, 2);
         case Operator is
            when Bit_And =>
               return (Integer_Kind, Signed (Bits (IL) and Bits (IR)));
            when Bit_Or =>
               return (Integer_Kind, Signed (Bits (IL) or Bits (IR)));
            when Bit_Xor =>
               return (Integer_Kind, Signed (Bits (IL) xor Bits (IR)));
            when Shift_Left =>
               return (Integer_Kind, Lua.Integers.Shift_Left (IL, IR));
            when others =>
               return (Integer_Kind, Lua.Integers.Shift_Right (IL, IR));
         end case;
      end if;
      L := Numeric (State, Left);
      R := Numeric (State, Right);
      if L.Kind = Lua.Numbers.Integer_Number and then
        R.Kind = Lua.Numbers.Integer_Number and then
        Operator in Plus | Minus | Star | Floor_Divide | Percent
      then
         IL := L.Integer_Item;
         IR := R.Integer_Item;
         case Operator is
            when Plus => return (Integer_Kind, Lua.Integers.Add (IL, IR));
            when Minus =>
               return (Integer_Kind, Lua.Integers.Subtract (IL, IR));
            when Star => return (Integer_Kind, Lua.Integers.Multiply (IL, IR));
            when Floor_Divide =>
               return (Integer_Kind, Lua.Integers.Floor_Divide (IL, IR));
            when others =>
               return (Integer_Kind, Lua.Integers.Modulo (IL, IR));
         end case;
      end if;
      FL := Lua.Numbers.To_Real (L);
      FR := Lua.Numbers.To_Real (R);
      case Operator is
         when Plus => Result := FL + FR;
         when Minus => Result := FL - FR;
         when Star => Result := FL * FR;
         when Slash | Floor_Divide | Percent =>
            if Operator = Percent then
               --  Host fmod supplies its native domain NaNs and preserves
               --  signed zero. Lua then adjusts a nonzero residue toward the
               --  divisor's sign. A quotient/product formula loses precision
               --  and can overflow even when the remainder is small.
               Result := Real_Value (Lua.Platform_Numerics.Remainder
                 (Interfaces.C.double (FL), Interfaces.C.double (FR)));
               if (Result > 0.0 and then FR < 0.0) or else
                 (Result < 0.0 and then FR > 0.0)
               then
                  Result := Result + FR;
               end if;
            else
               --  Ada's checked division cannot expose zero divisors as Lua
               --  values. The narrow host adapter retains target NaN signs
               --  and payloads; every ordinary Ada check stays enabled.
               Result := Real_Value (Lua.Platform_Numerics.Divide
                 (Interfaces.C.double (FL), Interfaces.C.double (FR)));
            end if;
            if Operator = Floor_Divide and then Result = Result
              and then abs Result <= Real_Value'Last
            then
               Result := Real_Value'Floor (Result);
            end if;
         when Power =>
            --  Preserve host libm rounding and all signed-zero/infinity
            --  cases. The differential matrix checks these systematically.
            Result := Real_Value (Lua.Platform_Numerics.Power
              (Interfaces.C.double (FL), Interfaces.C.double (FR)));
         when others => raise Program_Error with "invalid binary opcode";
      end case;
      return (Real_Kind, Result);
   exception
      when Lua.Integers.Arithmetic_Error =>
         --  Both integer primitives reject zero, but their Lua diagnostics
         --  identify the operation separately (lvm.c:775 and lvm.c:795).
         Operation_Error (State, (if Operator = Floor_Divide then
                 "attempt to divide by zero" else
                 "attempt to perform 'n%0'"));
         return Nil_Value;
   end Binary_Value;

   procedure Concatenate_Primitives
     (State : in out World; First : Positive; Last : in out Natural)
   is
      Context : constant Context_Access := State.Current;
      Builder : Owned_Buffer;
      Left, Right, Result, Item : Value;
      Lower, Total : Natural;
      Retried : Boolean;
      procedure Charge (Count : Natural := 1);
      function Convert (Index : Positive) return Value;
      function Short_Empty (Item : Value) return Boolean;

      procedure Charge (Count : Natural := 1) is
      begin
         if State.Policy = Bounded then
            if Count > State.Bounds.Instructions -
              Natural'Min (State.Steps, State.Bounds.Instructions)
            then
               Fail (State, "instruction limit exceeded", Resource => True);
            end if;
            State.Steps := State.Steps + Count;
         end if;
      end Charge;

      function Convert (Index : Positive) return Value is
         Item : Value := Stacks.Read (Context, Index);
      begin
         if Item.Kind in Integer_Kind | Real_Kind then
            Item := New_String (State, Image (Context.Memory, Item));
            --  Native tostring updates this actual operand before trying
            --  the next one. Publish immediately: emergency collection or
            --  a later refusal must not observe an invented copied packet.
            Stacks.Write (State, Context, Index, Item);
         end if;
         return Item;
      end Convert;

      function Short_Empty (Item : Value) return Boolean is
        (Item.Kind = String_Kind and then Item.Reference.Bytes.Size = 0
         and then not Item.Reference.External_String);
   begin
      if First > Last or else Last > Context.Foreign_Top then
         raise Program_Error with "invalid C concatenation interval";
      end if;
      Builder.Set_Owner (Lua.Storage.Reference (State.Memory));
      while Last > First loop
         Left := Stacks.Read (Context, Last - 1);
         Right := Stacks.Read (Context, Last);
         exit when
           Left.Kind not in String_Kind | Integer_Kind | Real_Kind or else
           Right.Kind not in String_Kind | Integer_Kind | Real_Kind;
         Charge;
         Right := Convert (Last);
         Lower := Last - 1;
         if Short_Empty (Right) then
            Result := Convert (Lower);
         elsif Short_Empty (Left) then
            Result := Right;
         else
            --  Pinned luaV_concat collects the whole convertible suffix.
            --  Pairwise materialization creates quadratically many bytes
            --  and one string object per operand. Keep only the real input
            --  slots, convert from right to left and build one final value.
            Total := Right.Reference.Bytes.Size;
            Lower := Last;
            loop
               Item := Stacks.Read (Context, Lower - 1);
               exit when Item.Kind not in
                 String_Kind | Integer_Kind | Real_Kind;
               if Lower /= Last then Charge; end if;
               Item := Convert (Lower - 1);
               if Total > State.Bounds.String_Bytes or else
                 Item.Reference.Bytes.Size > State.Bounds.String_Bytes -
                   Total
               then
                  Fail (State, "string byte limit exceeded",
                        Resource => True);
               end if;
               Total := Total + Item.Reference.Bytes.Size;
               Lower := Lower - 1;
               exit when Lower = First;
            end loop;
            Builder.Clear;
            Retried := False;
            loop
               begin
                  Builder.Reserve_Capacity (Total);
                  exit;
               exception
                  when Lua.Storage.Allocation_Error =>
                     if not Retry_Allocation (State, Retried) then
                        raise;
                     end if;
               end;
            end loop;
            for Index in Lower .. Last loop
               Item := Stacks.Read (Context, Index);
               Charge (Item.Reference.Bytes.Size);
               declare
                  --  Immutable bytes remain rooted by their actual scalar
                  --  slots throughout managed builder/result allocation.
                  --  This borrowed view avoids an input-sized Ada String
                  --  temporary and never escapes this synchronous append.
                  Text : constant String (1 .. Item.Reference.Bytes.Size)
                    with Import, Address => Item.Reference.Bytes.Address;
               begin
                  Append (Builder, Text);
               end;
            end loop;
            Result := New_String (State, Builder);
         end if;
         --  Publish the result before removing the consumed right edge.
         --  Any later handler reads the remaining original slots afresh;
         --  debug.setlocal mutations cannot be hidden by an old snapshot.
         Stacks.Write (State, Context, Lower, Result);
         Foreign.Set_Concatenation_Top (State, Lower);
         Last := Lower;
      end loop;
   end Concatenate_Primitives;

   function Unary_Value
     (State : in out World; Operator : Token_Kind; Item : Value) return Value
   is
      Number : Lua.Numbers.Number;
   begin
      case Operator is
         when Not_Word => return (Boolean_Kind, not Truth (Item));
         when Length =>
            if Item.Kind = String_Kind then
               return (Integer_Kind,
                       Integer_Value (Lua.Engine.Length
                         (Item.Reference.Bytes)));
            elsif Item.Kind = Table_Kind then
               return (Integer_Kind, Integer_Value (Table_Length (Item)));
            end if;
            Operand_Error (State, Item, "get length of", 1);
         when Minus =>
            Number := Numeric (State, Item);
            if Number.Kind = Lua.Numbers.Integer_Number then
               return (Integer_Kind,
                       Lua.Integers.Negate (Number.Integer_Item));
            end if;
            return (Real_Kind, -Number.Real_Item);
         when Bit_Xor =>
            if Item.Kind = String_Kind then
               Fail
                 (State, "attempt to perform bitwise operation on a string");
            end if;
            return (Integer_Kind,
                    Lua.Integers.Subtract (-1, Integral (State, Item, 1)));
         when others => raise Program_Error with "invalid unary opcode";
      end case;
      return Nil_Value;
   end Unary_Value;

   function Ensure_Stack
     (State : in out World; Context : not null Context_Access;
      Last : Natural; Raise_Error : Boolean := True) return Boolean
   is
      Maximum : constant Positive := Lua.Runtime_Configuration.Maximum_Stack;
      Bound : Natural := Context.Stack_Allocated_Bound;

      procedure Handling_Overflow;
      procedure Handling_Overflow is
      begin
         --  luaD_errerr bypasses message handling. Reuse the actual stable
         --  bootstrap error object rather than allocate a replacement string
         --  while the error reserve itself has already been exhausted.
         Context.Failure := State.Handling_Error_Value;
         Root_Barrier (State, Context.Failure);
         Context.Has_Failure_Value := True;
         Context.Failure_Class := Handling_Failure;
         Context.Failure_Handled := True;
         Set_Failure_Text (State, Context, "error in error handling");
         raise Language_Error;
      end Handling_Overflow;
   begin
      if Last < Bound then
         --  Actual vector capacity can be greater, but it never changes this
         --  semantic test. The five physical extras are not general Lua slots.
         Stacks.Reserve (State, Context, Bound + Extra_Stack);
         return True;
      elsif Context.Stack_Error_Phase = Error_Stack then
         if Raise_Error then Handling_Overflow; end if;
         return False;
      elsif Last < Maximum then
         --  Use the pinned 1.5 growth policy and mathematical needed extent.
         --  Maximum is configuration-derived, never adjusted for a fixture.
         Bound := Natural'Min
           (Maximum, Natural'Max (Bound + Bound / 2, Last + 1));
         Stacks.Reserve (State, Context, Bound + Extra_Stack);
         Context.Stack_Allocated_Bound := Bound;
         return True;
      else
         --  Install the error reserve before raising ordinary stack overflow,
         --  so a real handler/closer can run there. A refusal while reserving
         --  it remains a memory error, never permission to use another owner.
         Stacks.Reserve
           (State, Context, Maximum + Error_Stack_Reserve + Extra_Stack);
         Context.Stack_Allocated_Bound := Maximum + Error_Stack_Reserve;
         Context.Stack_Error_Phase := Error_Stack;
         if Raise_Error then Fail (State, "stack overflow"); end if;
         return False;
      end if;
   exception
      when Lua.Storage.Allocation_Error =>
         if Raise_Error then raise; end if;
         --  lua_checkstack is explicitly nonthrowing on allocator refusal.
         --  Keep the old semantic bound/values and consume only the genuine
         --  provider witness; physical Ada exhaustion remains a host abort.
         Lua.Storage.Acknowledge_Refusal (State.Memory);
         return False;
      when Program_Error =>
         if Raise_Error or else
           not Lua.Storage.Refusal_Pending (State.Memory)
         then
            raise;
         end if;
         Lua.Storage.Acknowledge_Refusal (State.Memory);
         return False;
   end Ensure_Stack;

   procedure Shrink_Error_Stack
     (State : in out World; Context : not null Context_Access)
   is
      pragma Unreferenced (State);
      Maximum : constant Positive := Lua.Runtime_Configuration.Maximum_Stack;
      In_Use : Natural := Natural'Max
        (Context.Stack_Used, Context.Foreign_Top);
   begin
      if Context.Stack_Error_Phase = Normal_Stack then return; end if;
      --  Unlike ordinary return, shrinking is infrequent and must consider
      --  ancestors' current reservations too. A smaller child ci.top cannot
      --  hide an older live window when deciding whether overflow has ended.
      for Activation of Context.Stack loop
         if Activation.Has_Stack_Window then
            In_Use := Natural'Max
              (In_Use, Activation.Stack_Base +
                 Activation.Stack_Window_Length);
         end if;
      end loop;
      --  stackinuse counts through exclusive ci.top and one additional row;
      --  our stored bounds are inclusive offsets, hence this explicit +2.
      if In_Use > Maximum - 2 then return; end if;
      In_Use := In_Use + 2;
      Context.Stack_Allocated_Bound :=
        (if In_Use > Maximum / 2 then Maximum else In_Use * 2);
      Context.Stack_Error_Phase := Normal_Stack;
   end Shrink_Error_Stack;

   procedure Resize_Stack_Window
     (State : in out World; Activation : Frame_Access; Count : Natural)
   is
      Context : Context_Access;
      Last : Natural;
      Available : Boolean;
   begin
      if Activation = null or else Activation.Context = null or else
        Activation.Lifecycle /= Active
      then
         raise Program_Error with "invalid scalar stack window owner";
      end if;
      Context := Activation.Context;
      if Count > Natural'Last - Activation.Stack_Base
      then
         --  A mathematical request larger than our representation follows
         --  the same overflow path without overflowing Ada index arithmetic.
         Last := Natural'Last;
      else
         Last := Activation.Stack_Base + Count;
      end if;
      Available := Ensure_Stack (State, Context, Last);
      if not Available then
         raise Program_Error with "raising stack reservation returned false";
      end if;
      --  No new top/link is visible until both scalar and cell storage are
      --  initialized. A provider refusal therefore preserves the previous
      --  current window and lets ordinary protected recovery inspect it.
      if not Activation.Has_Stack_Window then
         Activation.Previous_Stack_Window := Context.Stack_Window;
         Activation.Saved_Stack_Used := Context.Stack_Used;
         Activation.Saved_Foreign_Top := Context.Foreign_Top;
         Activation.Has_Stack_Window := True;
         Context.Stack_Window := Activation;
      end if;
      Activation.Stack_Window_Length := Count;
      if Context.Stack_Window = Activation then
         Context.Stack_Used := Last;
      end if;
      --  In particular do not clear a shrinking parent's tail here: a live
      --  child can overlap it. Collector union tracing and actual retirement
      --  own clearing; raw capacity is never a second set of live roots.
   end Resize_Stack_Window;

   function Reserve_Native_Results
     (State : in out World; Activation : not null Frame_Access;
      Count : Natural) return Boolean
   is
      Needed : constant Natural :=
        (if Count > Natural'Last - Activation.Stack_Live_Top then
            Natural'Last else Activation.Stack_Live_Top + Count);
   begin
      if not Activation.Is_Native or else
        not Activation.Has_Stack_Window
      then
         raise Program_Error with "native results have no scalar window";
      end if;
      if not Ensure_Stack
        (State, Activation.Context, Needed, Raise_Error => False)
      then
         return False;
      end if;
      Resize_Stack_Window
        (State, Activation, Natural'Max
           (Activation.Stack_Window_Length, Needed - Activation.Stack_Base));
      return True;
   end Reserve_Native_Results;

   procedure Open_Stack_Window
     (State : in out World; Activation : not null Frame_Access;
      Function_Value : Value; Arguments : Values.Vector;
      Call_Base : Natural; Has_Call_Window : Boolean);
   procedure Retire_Stack_Window
     (Activation : not null Frame_Access);

   procedure Open_Stack_Window
     (State : in out World; Activation : not null Frame_Access;
      Function_Value : Value; Arguments : Values.Vector;
      Call_Base : Natural; Has_Call_Window : Boolean)
   is
      Context : constant Context_Access := Activation.Context;
      Caller : constant Frame_Access := Context.Stack_Window;
      Argument_Count : constant Natural := Natural (Arguments.Length);
      Width : Natural;
      Physical_Last : Natural;
      Available : Boolean;
   begin
      if Activation.Has_Stack_Window or else Context /= State.Current then
         raise Program_Error with "stack window was already published";
      end if;
      if Has_Call_Window and then Call_Base = 0 then
         raise Program_Error with "zero is not a physical call window";
      elsif Has_Call_Window then
         Activation.Stack_Base := Call_Base;
      elsif Caller = null then
         --  The base C context reserves its minimum free capacity but has no
         --  visible activation. A root function is placed after its actual
         --  host prefix, rather than after unused physical/reserved slots.
         Activation.Stack_Base := Context.Foreign_Top + 1;
      elsif Caller.Is_Native or else Caller.Warning_Borrow_Depth /= 0 then
         --  A library's explicit callback request models pushing the callee
         --  after its live C arguments/temporaries. Hidden VM helpers instead
         --  run above the current real ci.top, matching Protect's top reset.
         Activation.Stack_Base := Caller.Stack_Live_Top + 1;
      else
         Activation.Stack_Base := Context.Stack_Used + 1;
      end if;
      Activation.Call_Base := Activation.Stack_Base;
      if Activation.Is_Native then
         Width :=
           (if Argument_Count > Natural'Last - Minimum_C_Stack then
               Natural'Last else Argument_Count + Minimum_C_Stack);
      else
         Width := Natural (Activation.Code.Canonical_Node.Max_Stack);
      end if;
      --  Excess Lua arguments can initially extend beyond maxstack before
      --  VARARGPREP/discard adjustment. Physical initialization must cover
      --  them too; their packet remains rooted until that setup completes.
      if Natural'Max (Width, Argument_Count) >
          Natural'Last - Activation.Stack_Base
      then
         Physical_Last := Natural'Last;
      else
         Physical_Last := Activation.Stack_Base +
           Natural'Max (Width, Argument_Count);
      end if;
      Available := Ensure_Stack (State, Context, Physical_Last);
      if not Available then
         raise Program_Error with "raising stack reservation returned false";
      end if;
      Resize_Stack_Window (State, Activation, Width);
      --  The callee and all arguments are already explicit operation/frame
      --  roots. Slot copies perform no allocation after publication, so an
      --  overlapping call window never needs borrowed vector references.
      Stacks.Write (State, Context, Activation.Stack_Base, Function_Value);
      for Index in 1 .. Argument_Count loop
         Stacks.Write (State, Context, Activation.Stack_Base + Index,
                       Arguments (Index));
      end loop;
      Activation.Stack_Live_Top := Activation.Stack_Base + Argument_Count;
      if Has_Call_Window and then Caller /= null then
         if Caller.Is_Native then
            Caller.Stack_Live_Top := Activation.Stack_Base - 1;
         else
            Caller.Canonical_GC_Top :=
              Activation.Stack_Base - Caller.Stack_Base;
         end if;
      end if;
   end Open_Stack_Window;

   procedure Retire_Stack_Window
     (Activation : not null Frame_Access)
   is
      Context : constant Context_Access := Activation.Context;
      Previous : Frame_Access;
      Last : Natural;
   begin
      if not Activation.Has_Stack_Window then
         --  Hidden protection/close/hook holders own their packets but have
         --  no scalar reservation. In particular they cannot restore stale
         --  saved tops after a real parent grows for open returned results.
         return;
      elsif Context.Stack_Window /= Activation then
         raise Program_Error with "retiring a noncurrent real stack window";
      end if;
      Previous := Activation.Previous_Stack_Window;
      Last := Natural'Max
        (Activation.Stack_Base + Activation.Stack_Window_Length,
         Activation.Stack_Live_Top);
      --  The actual call interval, including a hidden-vararg prefix, belongs
      --  to this departing frame. Outgoing values must already be rooted in
      --  a result/error holder before this allocation-free clear occurs.
      Stacks.Clear_Range
        (Context,
         Natural'Max (Activation.Call_Base, Context.Closing_Stack_Prefix + 1),
         Last);
      Context.Stack_Window := Previous;
      Context.Stack_Used :=
        Natural'Max
          (Context.Closing_Stack_Prefix,
           (if Previous = null then Activation.Saved_Stack_Used else
              Previous.Stack_Base + Previous.Stack_Window_Length));
      Context.Foreign_Top :=
        Natural'Max
          (Context.Closing_Stack_Prefix,
           (if Previous = null then Activation.Saved_Foreign_Top
            elsif Previous.Is_Native or else
              Previous.Warning_Borrow_Depth /= 0
            then Previous.Stack_Live_Top else
              Previous.Stack_Base + Previous.Canonical_Top));
      Activation.Previous_Stack_Window := null;
      Activation.Has_Stack_Window := False;
      --  Retain physical capacity. Clearing everything above an old parent
      --  reservation would be wrong during overlapping child execution; only
      --  this detached interval was owned here. Union GC clears other gaps.
   end Retire_Stack_Window;

   procedure Begin_Hook_View
     (State : in out World; Context : not null Context_Access;
      Token : Callback_Identity)
   is
      Guard : constant Frame_Access := Context.Foreign_Activation;
      Window : constant Frame_Access := Context.Hook_Frame;
      Base : constant Natural := Context.Foreign_Base;
      Top : constant Natural := Context.Foreign_Top;
      Width : Natural;
      Available : Boolean;
   begin
      if Context /= State.Current or else Guard = null or else
        not Guard.Is_C_Hook_Transport or else not Guard.Foreign_Entered or
        else Guard.Native_Stage /= 1 or else
        Guard.all'Address /= Token.Activation or else
        Guard.Foreign_Ticket /= Token.Serial or else
        Guard.Hook_View.Context /= null or else Window = null or else
        Context.Stack_Window /= Guard or else
        Guard.Previous_Stack_Window /= Window
      then
         raise Program_Error with "invalid C hook stack-view entry";
      end if;
      --  The C trampoline has consumed its event/line scalars. Its metadata
      --  stays on the activation stack as the genuine guard owner, but no
      --  private reservation may overlap the interrupted CI's C API writes.
      Stack_Views.Prepare_Hook (State, Window);
      Width := Natural'Max
        (Window.Stack_Window_Length,
         (if Window.Is_Native then
             Window.Stack_Live_Top - Window.Stack_Base
          else Window.Stack_Window_Length));
      if Width > Natural'Last - Window.Stack_Base - Minimum_C_Stack then
         Fail (State, "stack overflow");
      end if;
      --  Reserve storage while the original C transport still owns a valid
      --  error slot. After retirement, publishing the borrowed view and its
      --  minimum C reservation cannot fail half way through a transition.
      Available := Ensure_Stack
        (State, Context, Window.Stack_Base + Width + Minimum_C_Stack);
      if not Available then
         raise Program_Error with "raising hook reservation returned false";
      end if;
      Retire_Stack_Window (Guard);
      Context.Foreign_Base := Base;
      Context.Foreign_Top := Top;
      Stack_Views.Borrow
        (State, Context, Window, Guard.Hook_View, Hook_View);
      Resize_Stack_Window (State, Window, Width + Minimum_C_Stack);
   end Begin_Hook_View;

   procedure End_Hook_View
     (State : in out World; Context : not null Context_Access;
      Token : Callback_Identity)
   is
      Guard : constant Frame_Access := Context.Foreign_Activation;
   begin
      if Guard = null or else not Guard.Is_C_Hook_Transport or else
        not Guard.Foreign_Entered or else
        Guard.all'Address /= Token.Activation or else
        Guard.Foreign_Ticket /= Token.Serial
      then
         raise Program_Error with "invalid C hook stack-view completion";
      end if;
      Stack_Views.Restore (State, Guard.Hook_View);
   end End_Hook_View;

   procedure Set_Native_Top
     (State : in out World; Activation : not null Frame_Access;
      Count : Natural)
   is
      Context : constant Context_Access := Activation.Context;
      Window : constant Frame_Access :=
        (if Context.Foreign_Activation = Activation and then
            Context.Foreign_View /= null
         then Context.Foreign_View else Activation);
      Old_Top : constant Natural := Activation.Stack_Live_Top;
      New_Top : Natural;
   begin
      if (not Activation.Is_Native and then
          Context.Foreign_View /= Activation) or else
        Context /= State.Current or else Context.Stack_Window /= Window
      then
         raise Program_Error with "native top requires its current window";
      end if;
      if Count > Natural'Last - Activation.Stack_Base then
         Fail (State, "stack overflow");
      end if;
      New_Top := Activation.Stack_Base + Count;
      Resize_Stack_Window
        (State, Window,
         Natural'Max (Window.Stack_Window_Length, Count));
      --  Preserve both views until all potentially allocating growth has
      --  succeeded. Shrinking the owned packet removes stale argument roots;
      --  clearing actual slots then detaches any cells above the new top.
      if Activation.Is_Native and then Window.Hook_View_Depth = 0 and then
        Activation.Foreign_Handler = System.Null_Address
      then
         Activation.Native_Arguments.Set_Length
           (Ada.Containers.Count_Type (Count));
      end if;
      if New_Top < Old_Top then
         Stacks.Clear_Range (Context, New_Top + 1, Old_Top);
      else
         for Index in Old_Top + 1 .. New_Top loop
            Stacks.Write (State, Context, Index, Nil_Value);
         end loop;
      end if;
      Activation.Stack_Live_Top := New_Top;
      Window.Stack_Live_Top := New_Top;
      Context.Foreign_Top := New_Top;
   end Set_Native_Top;

   procedure Push_Native_Value
     (State : in out World; Activation : not null Frame_Access;
      Item : Value)
   is
      Context : constant Context_Access := Activation.Context;
      Window : constant Frame_Access :=
        (if Context.Foreign_Activation = Activation and then
            Context.Foreign_View /= null
         then Context.Foreign_View else Activation);
      Count : constant Natural :=
        Activation.Stack_Live_Top - Activation.Stack_Base;
   begin
      --  Reservation can trigger emergency collection. Retain an existing
      --  value before it becomes part of the actual activation's root range.
      Pin (State, Item);
      Set_Native_Top (State, Activation, Count + 1);
      if Activation.Is_Native and then
        Window.Hook_View_Depth = 0 and then
        Activation.Foreign_Handler = System.Null_Address
      then
         Replace_Root
           (State, Activation.Native_Arguments,
            Count + 1, Item);
      end if;
      Stacks.Write
        (State, Activation.Context, Activation.Stack_Live_Top, Item);
   end Push_Native_Value;

   procedure Publish_Builtin_Window
     (State : in out World; Owner : not null Frame_Access);
   --  Move the hidden builtin's authoritative working prefix to its actual
   --  public C owner without ending that owner's execution. The phase window
   --  retires; any later success continuation must borrow the real cells.
   procedure Publish_Builtin_Window
     (State : in out World; Owner : not null Frame_Access)
   is
      Context : constant Context_Access := State.Current;
      Phase : constant Frame_Access := Context.Stack.Last_Element;
      Window : constant Frame_Access :=
        (if Context.Foreign_Activation = Owner and then
            Context.Foreign_View /= null
         then Context.Foreign_View else Owner);
      Count, Last : Natural;
      Item : Value;
   begin
      if Context.Stack_Window = Window then return; end if;
      if (not Owner.Is_Native and then Context.Foreign_View /= Owner) or else
        not Phase.Native_Builtin_Direct or else
        not Phase.Has_Stack_Window or else Context.Stack_Window /= Phase or
        else Phase.Previous_Stack_Window /= Window or else
        Phase.Stack_Base <= Owner.Stack_Base
      then
         raise Program_Error with "invalid builtin window ownership";
      end if;
      Count := Phase.Stack_Live_Top - Phase.Stack_Base;
      Last := Owner.Stack_Base + Count;
      if State.Policy = Bounded then
         if Count > State.Bounds.Instructions -
           Natural'Min (State.Steps, State.Bounds.Instructions)
         then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         State.Steps := State.Steps + Count;
      end if;
      --  Preserve both real prefixes until reservation succeeds. The C
      --  body remains active below its synchronous builtin invocation; its
      --  original function slot, close metadata and guard are never retired.
      Resize_Stack_Window
        (State, Window, Natural'Max (Window.Stack_Window_Length, Count));
      for Index in 1 .. Count loop
         Item := Stacks.Read (Context, Phase.Stack_Base + Index);
         Stacks.Write (State, Context, Owner.Stack_Base + Index, Item);
      end loop;
      Owner.Stack_Live_Top := Last;
      Window.Stack_Live_Top := Last;
      --  The destination begins below the private source, so ascending
      --  writes are safe even if a grown prefix overlaps it. Those moved
      --  rows now belong to Owner; retire only the remaining source tail.
      Phase.Call_Base := Natural'Max (Phase.Call_Base, Last + 1);
      Retire_Stack_Window (Phase);
      Phase.Native_Arguments.Clear;
      Phase.Native_Captures.Clear;
   end Publish_Builtin_Window;

   procedure Prepare_Argument_Diagnostic
     (State : in out World; Owner : not null Frame_Access) is
   begin
      --  Failure uses the same neutral physical transfer as a successful
      --  reader portal. This wrapper retains its stricter contract: after
      --  publishing the failing request, its old operation never resumes.
      Publish_Builtin_Window (State, Owner);
   end Prepare_Argument_Diagnostic;

   procedure Release_Frame (State : in out World; Item : in out Frame_Access);
   procedure Release_Frame (State : in out World; Item : in out Frame_Access)
   is
      Deferred : Frame_Access;
      Previous, Next : Frame_Access;
   begin
      --  Typed host aborts can abandon a pending C transfer. These scopes
      --  own no live C body. A retained failed-coroutine traceback can still
      --  own real windows; discard its error view first and walk scopes from
      --  youngest to oldest. Never invoke Lua closing during a host abort.
      if Item.Pending_Error_Transfer then
         Retire_Stack_Window (Item);
         Item.Context.Foreign_Activation := Item.Error_Guard_Owner;
         Item.Context.Foreign_Base := Item.Error_Guard_Owner.Stack_Base;
         Item.Context.Foreign_View := Item.Foreign_Previous_View;
      end if;
      Stack_Views.Restore (State, Item.Hook_View, Abandon => True);
      Deferred := Item.Deferred_Error_Head;
      while Deferred /= null loop
         Next := Deferred.Deferred_Error_Next;
         Deferred.Deferred_Error_Next := Previous;
         Previous := Deferred;
         Deferred := Next;
      end loop;
      Item.Deferred_Error_Head := Previous;
      while Item.Deferred_Error_Head /= null loop
         Deferred := Item.Deferred_Error_Head;
         Item.Deferred_Error_Head := Deferred.Deferred_Error_Next;
         Item.Deferred_Error_Count := Item.Deferred_Error_Count - 1;
         Item.Context.Deferred_Error_Depth :=
           Item.Context.Deferred_Error_Depth - 1;
         Deferred.Deferred_Error_Next := null;
         if Deferred.Deferred_Error_Head /= null then
            raise Program_Error with "nested deferred scope ownership";
         end if;
         Release_Frame (State, Deferred);
      end loop;
      Warnings.Discard (State, Item);
      if Item.Finalizer_Charge then
         --  Host aborts abandon callbacks without executing cleanup. Restore
         --  the precise owner policy before releasing its current roots.
         Item.Context.Finalizer_Hook_Suppression :=
           Item.Context.Finalizer_Hook_Suppression - 1;
         Item.Finalizer_Charge := False;
         if State.Current.Failure_Class = Host_Abort then
            Finalizers.Abandon_Current (State);
         else
            --  Process exit can abandon an in-progress callback too. Its
            --  completed Lua finalization must not acquire host-abort-only
            --  fallback resource ownership merely because frames retire.
            Finalizers.Finish_Current (State);
         end if;
      end if;
      if Item.Foreign_Entered then
         --  A failed foreign callback can be retired by ordinary Lua error
         --  unwinding. Restore its C-stack window exactly as normal callback
         --  completion does; never leave a dangling active-frame identity.
         State.Current.Foreign_Top := Item.Saved_Foreign_Top;
         State.Current.Foreign_Base := Item.Foreign_Previous_Base;
         State.Current.Foreign_Activation := Item.Foreign_Previous_Frame;
         State.Current.Foreign_View := Item.Foreign_Previous_View;
         Item.Foreign_Entered := False;
      end if;
      if Item.Is_Native and then Item.Native_Name = "@hook" then
         State.Current.Hook_Active := False;
         if State.Current.Has_Failure_Value then
            State.Current.Hook_Yield_Pending := False;
         end if;
         State.Current.Hook_Frame := null;
      elsif Item.Unwind_Charge then
         State.Current.Cleanup_Depth := State.Current.Cleanup_Depth - 1;
      elsif Item.Message_Charge then
         State.Current.Message_Depth := State.Current.Message_Depth - 1;
      end if;
      State.Current.Stack_Slots := State.Current.Stack_Slots - Item.Slot_Cost;
      if Item.Blocks_Yield then
         State.Current.Non_Yieldable := State.Current.Non_Yieldable - 1;
      end if;
      if Item.Native_Charge then
         State.Current.Native_Depth := State.Current.Native_Depth - 1;
         State.Native_Depth := State.Native_Depth - 1;
      end if;
      Retire_Stack_Window (Item);
      if State.Current.Base_C_Frame = Item then
         State.Current.Foreign_Activation := null;
         State.Current.Foreign_View := null;
         State.Current.Foreign_Base := 0;
      end if;
      Return_Frame (Item);
   end Release_Frame;

   procedure Retire_Frame_Execution
     (State : in out World; Item : not null Frame_Access) is
      Context : constant Context_Access := Item.Context;
   begin
      if Item.Logically_Unwound then return; end if;
      if Item.Foreign_Entered and then Item.Native_Stage = 1 then
         raise Program_Error with "abandoning a live foreign body";
      elsif Item.Warning_Borrow_Depth /= 0 then
         raise Program_Error with "abandoning a live C stack borrow";
      end if;
      --  Freeze the actual departing values and detach lexical cells before
      --  their scalar interval is reused by a closer. A handler may mutate a
      --  closed upvalue without replacing another slot's pending close value.
      if Item.Code /= null and then Item.Code.Canonical_Node /= null then
         Canonical.Prepare_Close (State, Item, 0);
      else
         for Index in Item.Closers.First_Index .. Item.Closers.Last_Index loop
            declare
               Closing_Entry : Close_Entry := Item.Closers (Index);
            begin
               if not Closing_Entry.Frozen then
                  Closing_Entry.Frozen_Value := Closing_Entry.Cell.Cell_Value;
                  Closing_Entry.Frozen := True;
                  Item.Closers.Replace_Element (Index, Closing_Entry);
               end if;
            end;
         end loop;
      end if;
      --  These charges belong to execution, not to retained cleanup roots.
      --  Clearing each ownership bit makes later physical release idempotent
      --  and prevents stale C barriers/depth from rejecting a real closer.
      if Item.Native_Charge then
         Context.Native_Depth := Context.Native_Depth - 1;
         State.Native_Depth := State.Native_Depth - 1;
         Item.Native_Charge := False;
      end if;
      if Item.Blocks_Yield then
         Context.Non_Yieldable := Context.Non_Yieldable - 1;
         Item.Blocks_Yield := False;
      end if;
      if Item.Message_Charge then
         Context.Message_Depth := Context.Message_Depth - 1;
         Item.Message_Charge := False;
      end if;
      if Item.Unwind_Charge then
         Context.Cleanup_Depth := Context.Cleanup_Depth - 1;
         Item.Unwind_Charge := False;
      end if;
      if Item.Is_Native and then Item.Native_Name = "@hook" then
         Context.Hook_Active := False;
         Context.Hook_Frame := null;
         Context.Hook_Suspended := False;
         Context.Hook_Yield_Pending := False;
      end if;
      if Item.Foreign_Entered then
         if Context.Foreign_Activation = Item then
            Stack_Views.Restore (State, Item.Hook_View, Abandon => True);
            Context.Foreign_Top := Item.Saved_Foreign_Top;
            Context.Foreign_Base := Item.Foreign_Previous_Base;
            Context.Foreign_Activation := Item.Foreign_Previous_Frame;
            Context.Foreign_View := Item.Foreign_Previous_View;
         end if;
         Item.Foreign_Entered := False;
      end if;
      --  The actual physical window retires only after its cells/closers
      --  own their values. A caller-controlled close prefix may retain lower
      --  scalar slots during pending handlers; capacity stays owned.
      Retire_Stack_Window (Item);
      Item.Native_Arguments.Clear;
      Item.Native_Results.Clear;
      Item.Native_Captures.Clear;
      Item.Error_Packet.Clear;
      Item.Unwind_Results.Clear;
      Item.Varargs.Clear;
      for Index in 1 .. Item.Active_Registers loop
         Item.Slots (Index).Clear;
      end loop;
      Item.Active_Registers := 0;
      Context.Stack_Slots := Context.Stack_Slots - Item.Slot_Cost;
      Item.Slot_Cost := 0;
      Item.Callee := Nil_Value;
      Item.Native_Self := null;
      Item.Vararg_Table := null;
      Item.Unwind_Error := Nil_Value;
      Item.Message_Handler := Nil_Value;
      Item.Warning_Root := Nil_Value;
      Item.Logically_Unwound := True;
   end Retire_Frame_Execution;

   function Pending_Closing_Level
     (Item : not null Frame_Access) return Natural
   is
      Last : Natural := Item.C_Closing_Level;
      Deferred : Frame_Access := Item.Deferred_Error_Head;
   begin
      for Closing of Item.Closers loop
         Last := Natural'Max (Last, Closing.Stack_Level);
      end loop;
      while Deferred /= null loop
         Last := Natural'Max (Last, Pending_Closing_Level (Deferred));
         Deferred := Deferred.Deferred_Error_Next;
      end loop;
      return Last;
   end Pending_Closing_Level;

   procedure Set_Closing_Stack_Prefix
     (State : in out World; Level : Natural)
   is
      Context : constant Context_Access := State.Current;
      Window : constant Frame_Access := Context.Stack_Window;
      Used : Natural;
      Top : Natural;
   begin
      --  A nested cleanup can restore a lower floor while an outer closer
      --  still has a genuine window above it. Preserve that actual window;
      --  clearing the old prefix tail here would destroy its live locals.
      --  The normal ordered union trace clears only truly abandoned gaps.
      if Window = null then
         Used := Natural'Max (Minimum_C_Stack, Context.Host_Stack_Top);
         Top := Context.Host_Stack_Top;
      else
         Used := Window.Stack_Base + Window.Stack_Window_Length;
         Top :=
           (if Window.Is_Native then Window.Stack_Live_Top else
              Window.Stack_Base + Window.Canonical_Top);
      end if;
      Context.Closing_Stack_Prefix := Level;
      Context.Stack_Used := Natural'Max (Used, Level);
      Context.Foreign_Top := Natural'Max (Top, Level);
   end Set_Closing_Stack_Prefix;

   procedure Reserve_Frame (State : in out World; Cost : Natural);
   procedure Reserve_Frame (State : in out World; Cost : Natural) is
      Maximum : constant Positive :=
        (Lua.Runtime_Configuration.Maximum_Stack +
           (if State.Current.Cleanup_Depth > 0 then 4_096 else 0));
      Required : constant Ada.Containers.Count_Type :=
        State.Current.Stack.Length + Ada.Containers.Count_Type
          (State.Current.Deferred_Error_Depth) + 1 +
        (if State.Current.Foreign_State /= System.Null_Address and then
            not State.Current.C_Reset_Active
         then Ada.Containers.Count_Type (Reset_Continuation_Frames) else 0);
   begin
      --  This cost belongs only to the retained private packet comparator.
      --  Canonical and native frames pass zero: their exact absolute scalar
      --  extent goes through Ensure_Stack and its typed error-stack phase.
      --  Metadata depth remains a distinct explicit embedding quota; an
      --  internal protection holder invents no extra Lua register window.
      if Cost > Maximum or else
        State.Current.Stack_Slots > Maximum - Cost
      then
         Fail (State, "stack overflow");
      end if;
      if Natural (State.Current.Stack.Length) +
          State.Current.Deferred_Error_Depth >= State.Bounds.Call_Depth
      then
         Fail (State, "call depth limit exceeded", Resource => True);
      end if;
      --  Reserve before publication, including detached scope restoration.
      --  Ordinary C-visible calls also leave bounded reset-phase headroom;
      --  their existing TBC owners remain retained when reset borrows the
      --  prepared continuation records after provider refusal.
      if Required > State.Current.Stack.Capacity then
         State.Current.Stack.Reserve_Capacity (Required);
      end if;
   end Reserve_Frame;

   procedure Clear_Frames
     (State : in out World; Retained_Depth : Natural := 0) is
   begin
      while Natural (State.Current.Stack.Length) > Retained_Depth loop
         declare
            Item : Frame_Access := State.Current.Stack.Last_Element;
         begin
            State.Current.Stack.Delete_Last;
            Release_Frame (State, Item);
         end;
      end loop;
      --  A host abort discards execution continuations without running Lua
      --  cleanup. Neither a pending C-ACK error nor its abandoned scalar
      --  prefix may leak into a later drive of this same owned context.
      State.Current.Error_Recovery_Pending := False;
      State.Current.Error_Recovery_Floor := 0;
      Set_Closing_Stack_Prefix (State, 0);
   end Clear_Frames;

   package World_Addresses is new
     System.Address_To_Access_Conversions (World);

   procedure Prepare
     (Self : in out Driver; Universe : not null World_View;
      Retained_Depth : Natural := 0);
   procedure Start_Borrowed
     (Self : in out Driver; Universe : not null World_View;
      Code : Prototype_Access; Function_Value : Value;
      Arguments : Values.Vector);
   procedure Abandon (Self : Driver);
   procedure Scheduler_Step (Self : in out Driver);

   procedure Dispatch
     (Self : Driver; Function_Value : Value; Arguments : Values.Vector;
      Destination : Natural; Tail : Boolean := False;
      Protected_Call : Natural := 0;
      Call_Name : Unbounded_String := Null_Unbounded_String;
      Name_Kind : Unbounded_String := Null_Unbounded_String;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False);
   procedure Complete
     (Self : Driver; Result : Values.Vector; Independent : Boolean := False);
   procedure Recover
     (Self : Driver; Prefix_Floor : Natural := Natural'Last);
   function Active_Handler (Self : Driver) return Value;
   procedure Invoke_Message_Handler (Self : Driver; Handler : Value);
   procedure Execute_Instruction (Self : Driver);
   procedure Execute_Private_Instruction (Self : Driver);
   procedure Start_Unwind
     (Self : Driver; Owner : Frame_Access; Reason : Unwind_Reason;
      Results : Values.Vector := Values.Empty_Vector;
      Depth : Natural := 0; PC : Natural := 0;
      Live : Registers.Vector := Registers.Empty_Vector;
      Prefix_Floor : Natural := Natural'Last);
   procedure Native_Step (Self : Driver);
   procedure Hook_Event
     (Self : Driver; Event : String; Line : Natural := 0;
      Target : Frame_Access := null);
   function Before_Step (Self : Driver) return Boolean;
   procedure Schedule
     (Self : Driver; Name : String; Arguments : Values.Vector;
      Destination : Natural;
      Operator : Token_Kind := End_Of_Input; Direct : Boolean := False);
   procedure Schedule_Builtin
     (Self : Driver; Id : Native_Kind; Arguments : Values.Vector;
      Destination : Natural; Caller : Frame_Access);
   function Native
     (Self : Driver; Function_Id : Native_Kind; Arguments : Values.Vector)
      return Values.Vector;
   function Wrap
     (State : in out World; Result : Values.Vector; Count : Natural;
      Success : Boolean := True) return Values.Vector;
   procedure Raise_Value
     (Self : Driver; Item : Value; Level : Natural := 1);
   procedure Push_Frame
     (Self : Driver; Function_Value : Value; Arguments : Values.Vector;
      Destination, Protection : Natural;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False);
   procedure Deliver
     (Self : Driver; Activation : Frame_Access; Destination : Natural;
      Packet : Values.Vector; Failure : Failure_Kind := No_Failure;
      Handler_Called : Boolean := False);

   procedure Deliver
     (Self : Driver; Activation : Frame_Access; Destination : Natural;
      Packet : Values.Vector; Failure : Failure_Kind := No_Failure;
      Handler_Called : Boolean := False)
   is
      State : World renames Self.Universe.all;
   begin
      --  A callback resumes its owning native activation instead of
      --  writing a Lua register. This is the single return-channel bridge.
      if Activation.Native_Tail_State = Waiting_Native_Tail then
         Copy_Roots
           (State, Activation.Native_Results,
            Packet);
         Activation.Native_Tail_State := Ready_Native_Tail;
      elsif Activation.Is_Native then
         Copy_Roots
           (State, Activation.Native_Results,
            Packet);
         Activation.Result_Failure_Class := Failure;
         Activation.Result_Handler_Called := Handler_Called;
         if Activation.Native_Name = "@foreign.boundary" and then
           not Packet.Is_Empty and then Packet.First_Element.Kind =
             Boolean_Kind and then not Packet.First_Element.Boolean_Data
         then
            Activation.Native_Aux :=
              (if Failure = Memory_Failure then 4
               elsif Failure = Handling_Failure then 5 else 2);
         end if;
      elsif Activation.Code.Canonical_Node /= null then
         --  Scalar canonical registers have their own fixed/open-result and
         --  conditional continuations. Never insert private packet registers
         --  into this activation or bypass its pending result adjustment.
         Canonical.Deliver (State, Activation, Packet);
      elsif Destination /= 0 then
         Put_Packet (State, Activation, Destination, Packet);
      end if;
   end Deliver;

   procedure Schedule
     (Self : Driver; Name : String; Arguments : Values.Vector;
      Destination : Natural;
      Operator : Token_Kind := End_Of_Input; Direct : Boolean := False)
   is
      State : World renames Self.Universe.all;
      Activation : Frame_Access;
   begin
      Reserve_Frame (State, 0);
      if not Direct and then Name (Name'First) /= '@' and then
        State.Native_Depth >=
        (if State.Current.Message_Depth > 0 then
            Lua.Runtime_Configuration.Maximum_C_Calls / 10 * 11
         else Lua.Runtime_Configuration.Maximum_C_Calls)
      then
         Fail (State, "C stack overflow");
      end if;
      Activation := New_Frame (State, State.Current);
      State.Current.Stack.Append (Activation);
      --  The reserved activation stack owns partial construction before any
      --  managed argument copy can fail. Rollback uses the same release path
      --  as ordinary unwinding, balancing every slot/depth charge exactly.
      begin
         --  A visible native call receives its actual scalar window in
         --  Dispatch. Internal holders consume no semantic Lua stack slots.
         Activation.Slot_Cost := 0;
         Activation.Native_Charge := not Direct and then
           Name (Name'First) /= '@';
         if Activation.Native_Charge then
            State.Native_Depth := State.Native_Depth + 1;
            State.Current.Native_Depth := State.Current.Native_Depth + 1;
         end if;
         --  Native continuation storage does not make a C boundary yieldable.
         --  pairs uses lua_callk, whereas math comparison and the standard
         --  string arithmetic fallback use non-continuation C calls. User
         --  arithmetic overrides still run through ordinary VM dispatch.
         Activation.Blocks_Yield := Name in "string.gsub" | "string.format" |
           "base.tostring" | "base.print" | "ipairs.iterator" |
           "math.min" | "math.max" | "table.concat" | "table.insert" |
           "table.remove" | "table.move" | "table.unpack" | "table.sort" |
           "base.load" | "base.loadfile" | "base.require" |
           "package.preload_searcher" | "package.lua_searcher" |
           "package.c_searcher" | "package.croot_searcher" |
           "package.loadlib" or else
           (Name'Length > 6 and then
            Name (Name'First .. Name'First + 5) = "arith.");
         if Activation.Blocks_Yield then
            State.Current.Non_Yieldable := State.Current.Non_Yieldable + 1;
         end if;
         Activation.Is_Native := True;
         Activation.Native_Name := To_Unbounded_String
           ((if Direct then "@builtin.direct" else Name));
         Activation.Native_Builtin_Direct := Direct;
         --  Empty default packets have no allocator owner. Copy their values
         --  into this frame's existing owned buffer rather than assigning the
         --  vector and discarding its owner/cached capacity. A later internal
         --  phase may reserve arguments even when this initial list is empty.
         Activation.Native_Arguments.Clear;
         Activation.Native_Arguments.Set_Owner (Activation.Memory);
         Append_Root
           (State, Activation.Native_Arguments,
            Arguments);
         Activation.Transfer_Count := Natural (Arguments.Length);
         Activation.Native_Operator := Operator;
         Activation.Call_Site := State.Current.Failure_At;
         Activation.Return_To := Destination;
      exception
         when others =>
            State.Current.Stack.Delete_Last;
            Release_Frame (State, Activation);
            raise;
      end;
   end Schedule;

   procedure Schedule_Builtin
     (Self : Driver; Id : Native_Kind; Arguments : Values.Vector;
      Destination : Natural; Caller : Frame_Access)
   is
      State : World renames Self.Universe.all;
      Activation : Frame_Access;
   begin
      --  A C library pointer called directly is part of its current C
      --  activation. Preserve that public frame, its actual cells and the
      --  native-depth count while an explicit hidden phase drives callbacks.
      Schedule (Self, Lua.Builtin_Registry.Implementation (Id), Arguments,
                Destination, Direct => True);
      Activation := State.Current.Stack.Last_Element;
      Activation.Native_Id := Id;
      Activation.Callee :=
        (if Caller = null then (Native_Kind_Value, Id) else Caller.Callee);
      Root_Barrier (State, Activation.Callee);
      if Caller /= null then
         Activation.Native_Self := Caller.Native_Self;
         Root_Barrier (State, Activation.Native_Self);
         if Caller.Native_Self /= null then
            for Cell of Caller.Native_Self.Captures loop
               Append_Root
                 (State, Activation.Native_Captures, Cell.Cell_Value);
            end loop;
         end if;
      end if;
      Open_Stack_Window
        (State, Activation, Activation.Callee, Arguments, 0, False);
   end Schedule_Builtin;

   procedure Hook_Event
     (Self : Driver; Event : String; Line : Natural := 0;
      Target : Frame_Access := null) is
      State : World renames Self.Universe.all;
      Args : Values.Vector := Owned_Values (State);
      Callback : constant Value := Hooks.Callback (State, State.Current);
      Is_Foreign : constant Boolean :=
        State.Current.Foreign_Hook /= System.Null_Address;
   begin
      --  A Lua hook installation and its callback mapping are independent.
      --  Public registry edits may remove/replace the entry, or leave a
      --  non-function there. Pinned hookf ignores those non-functions without
      --  disabling the actual mask/count controls. Root a callable before
      --  constructing any argument that can trigger collection.
      if Callback.Kind not in Closure_Kind | Native_Closure_Kind |
        Native_Kind_Value | Foreign_Function_Kind
      then
         return;
      end if;
      Pin (State, Callback);
      --  The continuation suppresses hooks until the entire callback
      --  returns. Its owned arguments and function remain collector roots.
      Args.Append (New_String (State, Event));
      Args.Append
        ((if Event = "line" and then Line > 0 then
             (Integer_Kind, Integer_Value (Line))
          else Nil_Value));
      --  A return continuation is already above its departing owner. The
      --  event still identifies that real owner, never the helper carrying
      --  its result packet. Other events target the current activation.
      State.Current.Hook_Frame :=
        (if Target /= null then Target else State.Current.Stack.Last_Element);
      State.Current.Hook_Transfer := Event in "call" | "tail call" |
        "return";
      State.Current.Hook_Active := True;
      Schedule (Self, "@hook", Values.Empty_Vector, 0);
      State.Current.Stack.Last_Element.Blocks_Yield :=
        not Is_Foreign or else State.Current.Hook_Transfer;
      if State.Current.Stack.Last_Element.Blocks_Yield then
         State.Current.Non_Yieldable := State.Current.Non_Yieldable + 1;
      end if;
      --  This is a real hook call, not a call expression in the interrupted
      --  function. Pinned ldebug.c:funcnamefromcall reports hook '?' for the
      --  callback while its caller carries CIST_HOOKED. Preserve that origin
      --  across our explicit @hook continuation instead of inferring a name
      --  from the interrupted opcode.
      Dispatch
        (Self, Callback, Args, 0,
         Call_Name => To_Unbounded_String ("?"),
         Name_Kind => To_Unbounded_String ("hook"));
      State.Current.Stack.Last_Element.Is_C_Hook_Transport := Is_Foreign;
   end Hook_Event;

   function Before_Step (Self : Driver) return Boolean is
      State : World renames Self.Universe.all;
      Item : constant Frame_Access := State.Current.Stack.Last_Element;
      function Wants (Mask : Character) return Boolean is
        (Hooks.Enabled (State.Current) and then
         (if State.Current.Foreign_Hook /= System.Null_Address then
             (State.Current.Foreign_Hook_Mask /
                (case Mask is when 'c' => 1, when 'r' => 2,
                   when 'l' => 4, when others => 8)) mod 2 /= 0
          else Ada.Strings.Fixed.Index
            (To_String (State.Current.Hook_Mask), "" & Mask) /= 0));
      Suppressed : constant Boolean := State.Current.Hook_Active or else
        State.Current.Finalizer_Hook_Suppression /= 0;
      Line : Natural;
   begin
      if Item.Is_C_Collector_Transport then
         return False;
      end if;
      if not Item.Entry_Hook_Done and then not Item.Is_Native and then
        Item.Code.Canonical_Node /= null and then Item.Code.Vararg and then
        Item.PC = 1
      then
         return False;
      end if;
      if not Item.Entry_Hook_Done then
         Item.Entry_Hook_Done := True;
         if (not Item.Is_Native or else
              Element (Item.Native_Name, 1) /= '@') and then
           not Suppressed and then Wants ('c')
         then
            Hook_Event
              (Self, (if Item.Is_Tail_Call then "tail call" else "call"));
            return True;
         end if;
      end if;
      if not Item.Is_Native and then Item.PC <= Code_Length (Item)
      then
         if Item.Hook_PC /= Item.PC then
            Item.Hook_PC := Item.PC;
            if Hooks.Enabled (State.Current) and then
              State.Current.Hook_Count > 0
            then
               if State.Current.Hook_Remaining > 1 then
                  State.Current.Hook_Remaining :=
                    State.Current.Hook_Remaining - 1;
               else
                  State.Current.Hook_Remaining := State.Current.Hook_Count;
                  --  luaG_traceexec still decrements/resets the real count
                  --  while luaD_hook disallows callback reentry. Lua code in
                  --  a hook/finalizer therefore changes the remaining period
                  --  even though it cannot recursively invoke another hook.
                  if not Suppressed then
                     Hook_Event (Self, "count");
                     return True;
                  end if;
               end if;
            end if;
         end if;
         Line := Line_At (Item, Item.PC);
         if not Item.Line_Hook_Checked and then
           (Line /= Item.Hook_Line or else Item.PC <= Item.Last_Executed_PC)
         then
            Item.Line_Hook_Checked := True;
            Item.Hook_Line := Line;
            if not Suppressed and then Wants ('l') then
               Hook_Event (Self, "line", Line);
               return True;
            end if;
         end if;
      end if;
      return False;
   end Before_Step;

   procedure Start_Unwind
     (Self : Driver; Owner : Frame_Access; Reason : Unwind_Reason;
      Results : Values.Vector := Values.Empty_Vector;
      Depth : Natural := 0; PC : Natural := 0;
      Live : Registers.Vector := Registers.Empty_Vector;
      Prefix_Floor : Natural := Natural'Last)
   is
      State : World renames Self.Universe.all;
      Driver : Frame_Access;
   begin
      --  Publish all outgoing values before callbacks can collect. The
      --  owner remains on the stack until closing has completely finished.
      State.Current.Cleanup_Depth := State.Current.Cleanup_Depth + 1;
      begin
         Schedule (Self, "@unwind", Values.Empty_Vector, 0);
      exception
         when others =>
            State.Current.Cleanup_Depth := State.Current.Cleanup_Depth - 1;
            raise;
      end;
      Driver := State.Current.Stack.Last_Element;
      Driver.Unwind_Charge := True;
      Driver.Unwind := Reason;
      Driver.Unwind_Owner := Owner;
      Driver.Unwind_Depth := Depth;
      Driver.Unwind_PC := PC;
      Driver.Unwind_Live := Live;
      Driver.Unwind_Previous_Prefix :=
        (if Prefix_Floor = Natural'Last then
            State.Current.Closing_Stack_Prefix else Prefix_Floor);
      if Reason = Return_Exit and then Owner.Has_Stack_Window and then
        Owner.Return_Window_Published
      then
         declare
            Count : constant Natural := Owner.Transfer_Count;
            Prefix : constant Natural := Owner.Protection;
            Work : constant Ada.Containers.Count_Type :=
              Owner.Native_Arguments.Length + Owner.Native_Results.Length +
              Owner.Native_Captures.Length + Owner.Unwind_Results.Length +
              Owner.Error_Packet.Length + Ada.Containers.Count_Type (Count) +
              Ada.Containers.Count_Type (Prefix);
         begin
            if Count > Natural'Last - Prefix then
               Fail (State, "stack overflow");
            elsif State.Policy = Bounded then
               if Work > Ada.Containers.Count_Type
                 (State.Bounds.Instructions - Natural'Min
                    (State.Steps, State.Bounds.Instructions))
               then
                  Fail (State, "instruction limit exceeded", True);
               end if;
               State.Steps := State.Steps + Natural (Work);
            end if;
            --  Outgoing values already belong to actual scalar cells. Keep
            --  the largest existing packet buffer for reconstruction, not
            --  another copy of those values. Reserve before the first close
            --  handler; later readback/cleanup cannot allocate under refusal.
            if Owner.Unwind_Results.Capacity >
              Owner.Native_Results.Capacity
            then
               Move_Roots
                 (State, Owner.Native_Results, Owner.Unwind_Results);
            end if;
            if Owner.Native_Arguments.Capacity >
              Owner.Native_Results.Capacity
            then
               Move_Roots
                 (State, Owner.Native_Results, Owner.Native_Arguments);
            end if;
            if Owner.Error_Packet.Capacity > Owner.Native_Results.Capacity
            then
               Move_Roots
                 (State, Owner.Native_Results, Owner.Error_Packet);
            end if;
            if Driver.Unwind_Results.Capacity >
              Owner.Native_Results.Capacity
            then
               Move_Roots
                 (State, Owner.Native_Results, Driver.Unwind_Results);
            end if;
            Owner.Native_Results.Reserve_Capacity
              (Ada.Containers.Count_Type (Count + Prefix));
            Owner.Native_Arguments.Clear;
            Owner.Native_Results.Clear;
            Owner.Native_Captures.Clear;
            Owner.Unwind_Results.Clear;
            Owner.Error_Packet.Clear;
            Driver.Unwind_Results.Clear;
         end;
      else
         --  Error/scope exits and the migration packet backend retain their
         --  existing independent packet lifetime. They do not describe a
         --  published canonical/native return span that closers may edit.
         Copy_Roots (State, Driver.Unwind_Results, Results);
      end if;
      if Owner.Code /= null and then
        Owner.Code.Canonical_Node /= null
      then
         --  Error and explicit coroutine-close paths also detach open cells
         --  before a handler can mutate them. Normal CLOSE/RETURN has already
         --  frozen the same departing slots; preparation is idempotent.
         Canonical.Prepare_Close
           (State, Owner,
            (if Reason in Return_Exit | Error_Exit | Coroutine_Exit then 0
             else Depth));
      else
         --  Freeze just the declarations leaving in this transfer, before any
         --  handler executes. Closed upvalues and departing stack slots are
         --  distinct Lua storage: debug.setupvalue may replace a closed cell
         --  while the original slot still waits for its own close callback.
         --  Outer declarations remain live and must retain later mutations.
         for Index in reverse Owner.Closers.First_Index ..
           Owner.Closers.Last_Index
         loop
            declare
               Closing : Close_Entry renames Owner.Closers (Index);
            begin
               exit when not
                 (Reason in Return_Exit | Error_Exit | Coroutine_Exit or else
                  Closing.Depth > Depth or else
                  (Reason = Jump_Exit and then Closing.Symbol /= 0 and then
                   not Live.Contains (Closing.Symbol)));
               if not Closing.Frozen then
                  Closing.Frozen_Value :=
                    (if Closing.Stack_Level /= 0 then
                        Stacks.Read (Owner.Context, Closing.Stack_Level)
                     else Closing.Cell.Cell_Value);
                  Closing.Frozen := True;
               end if;
            end;
         end loop;
      end if;
      if Reason in Error_Exit | Coroutine_Exit then
         Driver.Unwind_Error := State.Current.Failure;
         Root_Barrier (State, Driver.Unwind_Error);
         Driver.Unwind_Has_Error := State.Current.Has_Failure_Value;
         Driver.Unwind_Failure_Class := State.Current.Failure_Class;
         Driver.Unwind_Handler_Called := State.Current.Failure_Handled;
         if Reason = Coroutine_Exit then
            --  Explicit coroutine reset/close uses nonyieldable protected
            --  closing. Error cleanup through a continuation-capable pcall
            --  instead inherits only the genuine surviving C barriers.
            Driver.Blocks_Yield := True;
            State.Current.Non_Yieldable := State.Current.Non_Yieldable + 1;
         end if;
      end if;
   end Start_Unwind;

   function Wrap
     (State : in out World; Result : Values.Vector; Count : Natural;
      Success : Boolean := True) return Values.Vector
   is
      Packet : Values.Vector := Owned_Values (State);
   begin
      --  Flatten chains such as pcall(pcall, f) without recursive Ada
      --  calls. Each successful outer protection contributes one true.
      for Index in 1 .. Count loop
         Packet.Append
           (Value'(Boolean_Kind, Success or else Index < Count));
      end loop;
      for Item of Result loop
         Packet.Append (Item);
      end loop;
      return Packet;
   end Wrap;

   procedure Raise_Value
     (Self : Driver; Item : Value; Level : Natural := 1) is
      State : World renames Self.Universe.all;
      Error_Value : Value := Item;
   begin
      --  Lua 5.5 normalizes nil errors before protected-call delivery.
      --  Preserve other arbitrary values, including false and tables.
      if Item.Kind = String_Kind and then Level in 1 ..
        Natural (State.Current.Stack.Length)
      then
         declare
            Activation : Frame_Access;
            Remaining : Positive := Level;
            Skip_Raiser : Boolean := True;
         begin
            --  Internal holders are scheduler transport, not public debug
            --  levels. luaL_where contributes a location only for a real Lua
            --  caller; a C caller (including testC/pcallk) adds no fabricated
            --  '(native)' source prefix to an arbitrary error string.
            for Candidate of reverse State.Current.Stack loop
               if not Candidate.Is_Native or else
                 Length (Candidate.Native_Name) = 0 or else
                 Element (Candidate.Native_Name, 1) /= '@'
               then
                  if Skip_Raiser then
                     --  The error/assert/wrap activation itself is level
                     --  zero. The requested level begins at its caller.
                     Skip_Raiser := False;
                  elsif Remaining = 1 then
                     Activation := Candidate;
                     exit;
                  else
                     Remaining := Remaining - 1;
                  end if;
               end if;
            end loop;
            if Activation /= null and then not Activation.Is_Native then
               declare
                  Line : constant Positive := Positive'Max
                    (1, Line_At (Activation,
                        Positive'Max (1, Activation.PC - 1)));
               begin
                  Error_Value := New_String
                    (State,
                     Inspection.Short_Source
                       ((if Activation.Code.Canonical_Node /= null then
                         To_String (Canonical.Source_Bytes (Activation.Code))
                         else To_String (Activation.Code.Name))) & ":" &
                     Ada.Strings.Fixed.Trim (Line'Image, Ada.Strings.Both) &
                     ": " & Image (State.Current.Memory, Item));
               end;
            end if;
         end;
      end if;
      State.Current.Failure := Error_Value;
      Root_Barrier (State, State.Current.Failure);
      State.Current.Has_Failure_Value := True;
      Lua.Diagnostic_Text.Clear (State.Current.Failure_Text);
      State.Current.Failure_Class := Language_Failure;
      State.Current.Failure_Handled := False;
      raise Language_Error;
   end Raise_Value;

   function Native
     (Self : Driver; Function_Id : Native_Kind; Arguments : Values.Vector)
      return Values.Vector
   is
      State : World renames Self.Universe.all;
      Result : Values.Vector := Owned_Values (State);
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Arguments.Length) then Arguments (Index)
         else Nil_Value);
      procedure Require (Count : Positive);
      procedure Require_Table;
      Item : Value;
      Number : Lua.Numbers.Number;
      Index : Integer_Value;

      procedure Require (Count : Positive) is
      begin
         if Natural (Arguments.Length) < Count then
            Fail (State, "missing argument to base function");
         end if;
      end Require;

      procedure Require_Table is
      begin
         Require (1);
         if Arg (1).Kind /= Table_Kind then
            Fail (State, "table expected");
         end if;
      end Require_Table;
   begin
      case Function_Id is
         when Print_Function =>
            --  Both delivery policies use the same quota and byte producer.
            --  This legacy primitive has no tostring continuation; ordinary
            --  Lua-visible print below performs its callbacks explicitly.
            for Position in Arguments.First_Index .. Arguments.Last_Index
            loop
               if Position > 1 then
                  Emit_Output (State, [Ada.Characters.Latin_1.HT]);
               end if;
               Emit_Output
                 (State, Image (State.Current.Memory, Arg (Position)));
            end loop;
            Emit_Output (State, [Ada.Characters.Latin_1.LF]);
            Flush_Output (State);
         when Assert_Function =>
            --  luaB_assert checks presence separately from truth. An absent
            --  first argument is a real auxiliary argument error; explicit
            --  nil still follows the ordinary assertion/message path below.
            if Arguments.Is_Empty then
               Diagnostics.Argument_Error (State, 1, "value expected");
            end if;
            if not Truth (Arg (1)) then
               if Arguments.Length >= 2 then
                  Raise_Value (Self, Arg (2));
               else
                  Raise_Value (Self, New_String (State, "assertion failed!"));
               end if;
            end if;
            return Arguments;
         when Error_Function =>
            Index := (if Arguments.Length >= 2 and then
                        Arg (2).Kind /= Nil_Kind then
                        Integral (State, Arg (2)) else 1);
            Raise_Value
              (Self, Arg (1), (if Index > 0 and then
                Index <= Integer_Value (State.Current.Stack.Length)
                then Natural (Index) else 0));
         when Type_Function =>
            Require (1);
            Result.Append (New_String (State, Type_Name (Arg (1))));
         when Tostring_Function =>
            Require (1);
            Result.Append
              (New_String (State, Image (State.Current.Memory, Arg (1))));
         when Tonumber_Function =>
            Require (1);
            if Arguments.Length >= 2 and then Arg (2).Kind /= Nil_Kind then
               Index := Integral (State, Arg (2));
               if Index not in 2 .. 36 or else
                 Arg (1).Kind /= String_Kind
               then
                  Fail (State, "base 2..36 and string expected");
               end if;
               Number := Read_Number
                 (State, Arg (1).Reference.Bytes,
                  Base => Natural (Index));
            elsif Arg (1).Kind in Integer_Kind | Real_Kind then
               Result.Append (Arg (1));
               return Result;
            elsif Arg (1).Kind = String_Kind then
               Number := Read_Number (State, Arg (1).Reference.Bytes);
            else
               Number := (Kind => Lua.Numbers.Invalid);
            end if;
            case Number.Kind is
               when Lua.Numbers.Invalid => Result.Append (Nil_Value);
               when Lua.Numbers.Integer_Number =>
                  Result.Append (Value'(Integer_Kind, Number.Integer_Item));
               when Lua.Numbers.Real_Number =>
                  Result.Append (Value'(Real_Kind, Number.Real_Item));
            end case;
         when Select_Function =>
            Require (1);
            if Arg (1).Kind = String_Kind and then
              Length (Arg (1).Reference.Bytes) > 0
              and then Element (Arg (1).Reference.Bytes, 1) = '#'
            then
               Result.Append
                 (Value'(Integer_Kind,
                         Integer_Value (Arguments.Length) - 1));
            else
               Index := Integral (State, Arg (1));
               if Index < 0 then
                  Index := Integer_Value (Arguments.Length) + Index;
               end if;
               if Index < 1 then
                  Fail (State, "index out of range");
               end if;
               if Index < Integer_Value (Arguments.Length) then
                  for Position in Positive (Index) + 1 ..
                    Arguments.Last_Index
                  loop
                     Result.Append (Arguments (Position));
                  end loop;
               end if;
            end if;
         when Next_Function =>
            Require_Table;
            return Next (State, Arg (1), Arg (2));
         when Pairs_Function | Ipairs_Function =>
            --  Both functions require a present argument, but neither checks
            --  its type here. The returned iterator validates its state when
            --  first called; explicit nil is therefore distinct from absence.
            Require (1);
            Result.Append
              (Value'(Native_Kind_Value,
                (if Function_Id = Pairs_Function then Next_Function
                 else Ipairs_Step)));
            Result.Append (Arg (1));
            Result.Append
              ((if Function_Id = Pairs_Function then Nil_Value
                else (Integer_Kind, 0)));
         when Ipairs_Step =>
            Require_Table;
            Index := Lua.Integers.Add (Integral (State, Arg (2)), 1);
            Item := Get (Arg (1), (Integer_Kind, Index));
            if Item.Kind /= Nil_Kind then
               Result.Append (Value'(Integer_Kind, Index));
            end if;
            Result.Append (Item);
         when Rawequal_Function =>
            Require (2);
            Result.Append
              (Value'(Boolean_Kind, Engine.Equal (Arg (1), Arg (2))));
         when Rawget_Function =>
            Require_Table;
            Require (2);
            Result.Append (Get (Arg (1), Arg (2)));
         when Rawset_Function =>
            Require_Table;
            Require (3);
            Set (State, Arg (1), Arg (2), Arg (3));
            Result.Append (Arg (1));
         when Rawlen_Function =>
            Require (1);
            if Arg (1).Kind = String_Kind then
               Index := Integer_Value (Lua.Engine.Length
                 (Arg (1).Reference.Bytes));
            elsif Arg (1).Kind = Table_Kind then
               Index := Integer_Value (Table_Length (Arg (1)));
            else
               Fail (State, "table or string expected");
            end if;
            Result.Append (Value'(Integer_Kind, Index));
         when Pcall_Function =>
            raise Program_Error with "pcall must use frame dispatch";
         when others =>
            raise Program_Error with "named builtin used primitive driver";
      end case;
      return Result;
   end Native;

   procedure Push_Frame
     (Self : Driver; Function_Value : Value; Arguments : Values.Vector;
      Destination, Protection : Natural;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False)
   is
      State : World renames Self.Universe.all;
      Item : Frame_Access;
      Prototype : constant Prototype_Access :=
        Function_Value.Reference.Code;
   begin
      --  A frame owns its fresh lexical scope and register packets.
      --  Publish it before parameter/vararg setup so the central cleanup
      --  path also owns partially initialized activations after failure.
      Reserve_Frame
        (State, (if Prototype.Canonical_Node /= null then 0 else
           Natural'Max (20, Prototype.Register_Count) +
             Natural (Arguments.Length)));
      Item := New_Frame (State, State.Current);
      Item.Slot_Cost :=
        (if Prototype.Canonical_Node /= null then 0 else
           Natural'Max (20, Prototype.Register_Count) +
             Natural (Arguments.Length));
      State.Current.Stack_Slots :=
        State.Current.Stack_Slots + Item.Slot_Cost;
      Item.Code := Prototype;
      Code_Barrier (State, Item.Code);
      Item.Callee := Function_Value;
      Root_Barrier (State, Item.Callee);
      Item.Transfer_Count := Natural (Prototype.Parameters.Length);
      Item.Return_To := Destination;
      Item.Protection := Protection;
      State.Current.Stack.Append (Item);
      if Prototype.Canonical_Node /= null then
         --  Publishing the frame first gives partial scalar-register setup
         --  the same exception-safe owner as private parameter setup. Ordered
         --  upvalues already belong to the callee; no lexical environment or
         --  second set of packet registers is created for canonical code.
         Item.Transfer_Count := Natural
           (Prototype.Canonical_Node.Parameters);
         Open_Stack_Window
           (State, Item, Function_Value, Arguments,
            Call_Base, Has_Call_Window);
         Canonical.Initialize_Frame (State, Item, Arguments);
         return;
      end if;
      Item.Scope := New_Environment
        (State, Function_Value.Reference.Capture);
      Root_Barrier (State, Item.Scope);
      Prepare_Private_Registers (Item, Prototype.Register_Count);
      if Prototype.Is_Main and then
        Function_Value.Reference.Capture = null
      then
         --  Host chunks start with a fresh global-environment binding.
         --  Loaded chunks already capture their persistent _ENV cell:
         --  shadowing it here would discard assignments between calls and
         --  split the binding observed by their nested Lua closures.
         Declare_Local (State, Item.Scope, Prototype.Environment_Symbol,
                        Global_Environment (State));
      end if;
      for Position in Prototype.Parameters.First_Index ..
        Prototype.Parameters.Last_Index
      loop
         Declare_Local
           (State, Item.Scope, Prototype.Parameters (Position),
            (if Position <= Natural (Arguments.Length) then
               Arguments (Position) else Nil_Value));
      end loop;
      if Prototype.Vararg then
         for Position in Natural (Prototype.Parameters.Length) + 1 ..
           Natural (Arguments.Length)
         loop
            Append_Root
              (State, Item.Varargs,
               Arguments (Position));
         end loop;
      end if;
      if Prototype.Vararg_Name /= 0 then
         --  Named varargs have one authoritative mutable table. Keeping
         --  a second packet would make ... ignore later writes to t.n
         --  or t[i], and would retain values removed from that table.
         declare
            Table : constant Value := New_Table (State);
         begin
            for Position in Item.Varargs.First_Index ..
              Item.Varargs.Last_Index
            loop
               Set (State, Table, (Integer_Kind, Integer_Value (Position)),
                    Item.Varargs (Position));
            end loop;
            Set (State, Table, New_String (State, "n"),
                 (Integer_Kind, Integer_Value (Item.Varargs.Length)));
            Declare_Local (State, Item.Scope, Prototype.Vararg_Name, Table);
            Item.Vararg_Table := Table.Reference;
            Root_Barrier (State, Item.Vararg_Table);
            Item.Varargs.Clear;
         end;
      end if;
   end Push_Frame;

   procedure Publish_Native_Return
     (State : in out World; Activation : not null Frame_Access;
      Result, Retained_Result : Values.Vector);
   procedure Publish_Native_Return
     (State : in out World; Activation : not null Frame_Access;
      Result, Retained_Result : Values.Vector) is separate;

   procedure Complete_Packet
     (Self : Driver; Result, Packet : Values.Vector);
   procedure Complete_Packet
     (Self : Driver; Result, Packet : Values.Vector) is
      State : World renames Self.Universe.all;
      Activation : Frame_Access := State.Current.Stack.Last_Element;
      Destination : constant Natural := Activation.Return_To;
      Policy : constant Completion_Policy := Activation.Completion;
      Public_Protection : constant Boolean := Activation.Is_Native and then
        (Activation.Native_Name = "base.pcall" or else
         Activation.Native_Name = "base.xpcall");
      procedure Complete_Owned (Source : in out Values.Vector);

      procedure Complete_Owned (Source : in out Values.Vector) is
         Caller : Frame_Access;
      begin
         --  A permanently refusing protected call resumes with its reserved
         --  error vector. That vector belongs to the departing activation:
         --  retiring the metadata first would clear the packet. Keep this
         --  actual owner traced while moving/borrowing its values directly
         --  into the caller, without allocating another result workspace.
         if State.Current.Stack.Length > 1 and then
           (State.Current /= Self.Root_Context or else
            Natural (State.Current.Stack.Length) - 1 > Self.Entry_Depth)
         then
            Caller := State.Current.Stack
              (State.Current.Stack.Last_Index - 1);
         end if;
         Retire_Stack_Window (Activation);
         if Caller /= null then
            if Policy = Deliver_Results then
               if Activation.Reset_Reserve then
                  --  These bounded reset owners must retain their reserved
                  --  buffers across multiple close callbacks under refusal.
                  --  Copy into the already reserved caller before retiring
                  --  the source; moving would exhaust the next callback's
                  --  packet capacity even though no new values are needed.
                  Deliver (Self, Caller, Destination, Source);
               else
                  Deliver_Owned (Self, Caller, Destination, Source);
               end if;
            end if;
         else
            State.Current.Transfer.Kind := Completed;
            Move_Roots (State, State.Current.Transfer.Results, Source);
         end if;
         State.Current.Stack.Delete_Last;
         Release_Frame (State, Activation);
      end Complete_Owned;
   begin
      if External_Releases.Pending (State) then
         --  Collection can finish inside the operation that is returning.
         --  Its external allocators must still observe this real frame and
         --  result owner. Retain an explicit packet, return from Step, then
         --  finish only after the guarded release portal has acknowledged it.
         Copy_Roots (State, Activation.Unwind_Results, Result);
         Activation.External_Return_Pending := True;
         Activation.External_Return_Independent :=
           Result'Address = Packet'Address;
         return;
      end if;
      Pin (State, Result);
      Pin (State, Packet);
      if Activation.Is_Native and then
        Activation.Has_Stack_Window and then
        not Activation.Return_Window_Published and then
        Activation.Foreign_Handler = System.Null_Address and then
        Length (Activation.Native_Name) > 0 and then
        Element (Activation.Native_Name, 1) /= '@'
      then
         if Public_Protection then
            --  This public C builtin returns its status boolean as well as
            --  the protected child's raw values. Other protected holders
            --  still expose only their actual function's unwrapped range.
            Publish_Native_Return (State, Activation, Packet, Result);
         else
            Publish_Native_Return (State, Activation, Result, Result);
         end if;
      end if;
      if not State.Current.Hook_Active and then
        State.Current.Finalizer_Hook_Suppression = 0 and then
        not Activation.Is_C_Collector_Transport and then
        not Activation.Return_Hook_Done and then
        Hooks.Enabled (State.Current) and then
        (if State.Current.Foreign_Hook /= System.Null_Address then
            (State.Current.Foreign_Hook_Mask / 2) mod 2 /= 0
         else Ada.Strings.Fixed.Index
           (To_String (State.Current.Hook_Mask), "r") /= 0) and then
        (not Activation.Is_Native or else
           Element (Activation.Native_Name, 1) /= '@')
      then
         --  Keep the departing scalar window as the authoritative result
         --  owner. A return hook can replace its values through get/setlocal;
         --  copied packets would both lose those edits and retain discarded
         --  weak objects during callback collection. Reserve reconstruction
         --  storage before entering the hook, then drop only the copies.
         Activation.Return_Hook_Done := True;
         if not Activation.Return_Window_Published then
            Activation.Transfer_Count := Natural
              ((if Public_Protection then Packet.Length else Result.Length));
         end if;
         if Activation.Has_Stack_Window then
            declare
               Prefix : constant Natural :=
                 (if Public_Protection then 0 else Activation.Protection);
               Count : constant Natural := Activation.Transfer_Count;
               Work : constant Ada.Containers.Count_Type :=
                 Activation.Native_Arguments.Length +
                 Activation.Native_Results.Length +
                 Activation.Native_Captures.Length +
                 Activation.Unwind_Results.Length +
                 Activation.Error_Packet.Length +
                 Ada.Containers.Count_Type (Count) +
                 Ada.Containers.Count_Type (Prefix);
            begin
               if Count > Natural'Last - Prefix then
                  Fail (State, "stack overflow");
               elsif State.Policy = Bounded then
                  if Work > Ada.Containers.Count_Type
                    (State.Bounds.Instructions - Natural'Min
                       (State.Steps, State.Bounds.Instructions))
                  then
                     Fail (State, "instruction limit exceeded", True);
                  end if;
                  State.Steps := State.Steps + Natural (Work);
               end if;
               Activation.Native_Results.Reserve_Capacity
                 (Ada.Containers.Count_Type (Count + Prefix));
            end;
         end if;
         Schedule (Self, "@return.hook", Values.Empty_Vector, 0);
         if Activation.Has_Stack_Window then
            Activation.Native_Arguments.Clear;
            Activation.Native_Results.Clear;
            Activation.Native_Captures.Clear;
            Activation.Unwind_Results.Clear;
            Activation.Error_Packet.Clear;
         else
            --  The migration packet backend has no scalar return window.
            --  Preserve its existing continuation lifetime independently;
            --  native/canonical result-slot behavior uses the branch above.
            Copy_Roots
              (State, State.Current.Stack.Last_Element.Unwind_Results,
               Result);
         end if;
         Hook_Event (Self, "return", Target => Activation);
         return;
      end if;
      if Packet'Address = Activation.Native_Results'Address then
         Complete_Owned (Activation.Native_Results);
         return;
      end if;
      --  Packet owns outgoing values independently of this activation. No
      --  collection occurs until the caller's destination owns them again.
      --  The outermost chunk has no consumer and intentionally discards it.
      State.Current.Stack.Delete_Last;
      Release_Frame (State, Activation);
      if not State.Current.Stack.Is_Empty and then
        (State.Current /= Self.Root_Context or else
         Natural (State.Current.Stack.Length) > Self.Entry_Depth)
      then
         if Policy = Deliver_Results then
            Deliver
              (Self, State.Current.Stack.Last_Element, Destination, Packet);
         end if;
      else
         State.Current.Transfer.Kind := Completed;
         Copy_Roots
           (State, State.Current.Transfer.Results,
            Packet);
      end if;
   end Complete_Packet;

   procedure Complete
     (Self : Driver; Result : Values.Vector; Independent : Boolean := False)
   is
      State : World renames Self.Universe.all;
      Protection : constant Natural :=
        State.Current.Stack.Last_Element.Protection;
   begin
      if Independent and Protection = 0 then
         --  A driver action owns its packet outside the retiring frame.
         --  Borrow it through synchronous delivery instead of allocating an
         --  identical wrapped packet. This permits collectgarbage to return
         --  after finalizers were deferred by a genuinely refusing allocator.
         Complete_Packet (Self, Result, Result);
      else
         declare
            Packet : constant Values.Vector :=
              Wrap (State, Result, Protection);
         begin
            Complete_Packet (Self, Result, Packet);
         end;
      end if;
   end Complete;

   procedure Dispatch
     (Self : Driver; Function_Value : Value; Arguments : Values.Vector;
      Destination : Natural; Tail : Boolean := False;
      Protected_Call : Natural := 0;
      Call_Name : Unbounded_String := Null_Unbounded_String;
      Name_Kind : Unbounded_String := Null_Unbounded_String;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False)
   is
      State : World renames Self.Universe.all;
      Function_Item : Value := Function_Value;
      Expanded_Args : Values.Vector := Owned_Values (State);
      Protection : Natural := Protected_Call;
      Return_To : Natural := Destination;
      Effective_Base : Natural := Call_Base;
      Use_Window : Boolean := Has_Call_Window;
      Native_Tail : Boolean := False;
      Call_Metamethod_Count : Natural := 0;
      Packet : Values.Vector := Owned_Values (State);
      procedure Bad_Call;
      procedure Bad_Call is
         use type Call_Names.Name_Kind;
         Caller : constant Frame_Access :=
           Inspection.Logical_Frame (State, State.Current, 0);
         Origin : Call_Names.Borrowed_Identity;
         Description : Unbounded_String := To_Unbounded_String
           ("attempt to call a " & Diagnostic_Type (State, Function_Item) &
            " value");
      begin
         --  luaG_callerror asks about the real caller before a callee exists.
         --  Failed owners retained for closing have already unwound; public
         --  C protection frames contribute neither a Lua source nor an opcode.
         if Length (Name_Kind) > 0 then
            Append (Description, " (" & To_String (Name_Kind) & " '" &
              To_String (Call_Name) & "')");
         else
            if State.Current.Hook_Active and then
              Caller = State.Current.Hook_Frame
            then
               Origin := (Call_Names.Hook_Name, Call_Names.Hook_Call);
            elsif not State.Current.Stack.Is_Empty and then
              State.Current.Stack.Last_Element.Is_Native and then
              State.Current.Stack.Last_Element.Native_Name =
                "@finalizer.invoke"
            then
               --  This is the actual finalizer controller's pending call.
               --  Its invalid handler has no activation to carry the normal
               --  entry marker; CIST_HOOKED still takes priority over FIN.
               Origin :=
                 (Call_Names.Finalizer_Name, Call_Names.Metamethod_Call);
            elsif Caller /= null and then not Caller.Is_Native then
               Origin := Call_Names.View_From_Caller (State, Caller);
            end if;
            if Origin.Kind /= Call_Names.Unknown then
               Append (Description, " (" &
                 Call_Names.Kind_Image (Origin.Kind) & " '" &
                 Call_Names.Name_Image (Origin) & "')");
            end if;
         end if;
         if Caller /= null and then not Caller.Is_Native then
            declare
               Line : constant Natural := Line_At
                 (Caller, Positive'Max (1, Caller.PC - 1));
               Prefix : constant String := Inspection.Short_Source
                 ((if Caller.Code.Canonical_Node /= null then
                     To_String (Canonical.Source_Bytes (Caller.Code))
                   else To_String (Caller.Code.Name))) & ":" &
                 (if Line = 0 then "?" else Ada.Strings.Fixed.Trim
                    (Line'Image, Ada.Strings.Both)) & ": ";
            begin
               Fail (State, Prefix & To_String (Description));
            end;
         end if;
         Fail (State, To_String (Description));
      end Bad_Call;
      procedure Activate (Args : Values.Vector);
      procedure Activate (Args : Values.Vector) is
         Native_Tail_Owner : Frame_Access := null;
      begin
         Pin (State, Function_Item);
         Pin (State, Args);
         if Tail then
            declare
               Old : Frame_Access := State.Current.Stack.Last_Element;
            begin
               if Function_Item.Kind = Closure_Kind then
                  --  Pinned Lua tail reuse retains the original frame's
                  --  __call count even when the replacement's receiver
                  --  chain differs. Only a separate native tail frame
                  --  reports the new chain's count (luaD_pretailcall).
                  Call_Metamethod_Count := Old.Call_Metamethod_Count;
                  Return_To := Old.Return_To;
                  Protection := Protection + Old.Protection;
                  if Old.Has_Stack_Window then
                     Effective_Base := Old.Call_Base;
                     Use_Window := True;
                  end if;
                  State.Current.Stack.Delete_Last;
                  Release_Frame (State, Old);
               else
                  --  Native tail calls keep the Lua caller inspectable until
                  --  the native result/error returns. A later scheduler phase
                  --  performs its return; no Ada executor activation recurses.
                  Old.Native_Tail_State := Waiting_Native_Tail;
                  Native_Tail_Owner := Old;
                  Native_Tail := True;
                  Return_To := 0;
               end if;
            end;
         end if;
         if Function_Item.Kind = Closure_Kind then
            Push_Frame
              (Self, Function_Item, Args, Return_To, Protection,
               Effective_Base, Use_Window);
            State.Current.Stack.Last_Element.Is_Tail_Call := Tail;
         elsif Function_Item.Kind = Foreign_Function_Kind then
            Schedule (Self, "foreign.callback", Args, Return_To);
            State.Current.Stack.Last_Element.Protection := Protection;
            State.Current.Stack.Last_Element.Callee := Function_Item;
            Root_Barrier (State, State.Current.Stack.Last_Element.Callee);
            State.Current.Stack.Last_Element.Foreign_Handler :=
              Function_Item.Identity;
            State.Current.Stack.Last_Element.Is_C_Collector_Transport :=
              Function_Item.Identity = Collector_Transport;
         elsif Function_Item.Kind = Native_Kind_Value then
            Schedule
              (Self, Lua.Builtin_Registry.Implementation
                 (Function_Item.Native_Data), Args, Return_To);
            State.Current.Stack.Last_Element.Protection := Protection;
            State.Current.Stack.Last_Element.Native_Id :=
              Function_Item.Native_Data;
            State.Current.Stack.Last_Element.Callee := Function_Item;
            Root_Barrier (State, State.Current.Stack.Last_Element.Callee);
         else
            declare
               Builtin : constant Lua.Builtin_Registry.Lookup :=
                 Lua.Builtin_Registry.Find
                   (To_String (Function_Item.Reference.Native_Name));
            begin
               Schedule
                 (Self, (if Function_Item.Reference.Foreign_Handler /=
                           System.Null_Address then "foreign.callback"
                         elsif Builtin.Exists then
                           Lua.Builtin_Registry.Implementation (Builtin.Id)
                         else To_String
                           (Function_Item.Reference.Native_Name)),
                  Args, Return_To);
               if Builtin.Exists then
                  State.Current.Stack.Last_Element.Native_Id := Builtin.Id;
               end if;
            end;
            State.Current.Stack.Last_Element.Protection := Protection;
            if Function_Item.Reference.Foreign_Handler = System.Null_Address
            then
               for Cell of Function_Item.Reference.Captures loop
                  Append_Root
                    (State, State.Current.Stack.Last_Element.Native_Captures,
                     Cell.Cell_Value);
               end loop;
            end if;
            --  Foreign callbacks read real mutable upvalue cells. Copying
            --  their old values into another root packet would keep replaced
            --  weak values alive until the C callback returns.
            State.Current.Stack.Last_Element.Callee := Function_Item;
            Root_Barrier (State, State.Current.Stack.Last_Element.Callee);
            State.Current.Stack.Last_Element.Native_Self :=
              Function_Item.Reference;
            Root_Barrier (State, State.Current.Stack.Last_Element.Native_Self);
            State.Current.Stack.Last_Element.Foreign_Handler :=
              Function_Item.Reference.Foreign_Handler;
            State.Current.Stack.Last_Element.Is_C_Collector_Transport :=
              Function_Item.Reference.Foreign_Handler = Collector_Transport;
         end if;
         --  Publish the number of inserted receivers on the actual callee,
         --  after either frame construction path. It describes this logical
         --  frame, never a previous use of a cached activation, and therefore
         --  survives yields without borrowing Dispatch locals.
         State.Current.Stack.Last_Element.Call_Metamethod_Count :=
           Call_Metamethod_Count;
         if Function_Item.Kind /= Closure_Kind then
            Open_Stack_Window
              (State, State.Current.Stack.Last_Element,
               Function_Item, Args, Effective_Base, Use_Window);
         end if;
         if not Tail or else Native_Tail then
            if Length (Call_Name) > 0 then
               --  The real activation owns the C debug borrow before its
               --  origin is published. Canonical inferred names continue to
               --  borrow their immutable prototype bytes instead; ordinary
               --  calls with no explicit origin allocate no mirror buffer.
               State.Current.Stack.Last_Element.Call_Name_Bytes.Set_Value
                 (To_String (Call_Name));
            end if;
            State.Current.Stack.Last_Element.Call_Name := Call_Name;
            State.Current.Stack.Last_Element.Name_Kind := Name_Kind;
         end if;
         if Native_Tail_Owner /= null then
            --  A native tail call retains the actual Lua CI until the C
            --  result/error returns, including its visible locals/cells.
            --  The new callee now owns its argument window and packet;
            --  retire only the old call request, whose stale copies would
            --  otherwise outlive debug mutations of every real caller slot.
            Native_Tail_Owner.Native_Arguments.Clear;
            Native_Tail_Owner.Native_Captures.Clear;
         end if;
      end Activate;
   begin
      Pin (State, Function_Value);
      Pin (State, Arguments);
      --  Ordinary non-tail calls borrow their already rooted input until the
      --  new activation publishes its own slots/packet. Copy only when a
      --  receiver chain must mutate arguments, or tail replacement could
      --  release their original owner. This also keeps error closing usable
      --  under refusal: a fresh temporary argument copy is unnecessary.
      if not Tail and then Function_Item.Kind in Closure_Kind |
        Native_Closure_Kind | Native_Kind_Value | Foreign_Function_Kind
      then
         Activate (Arguments);
         return;
      end if;
      Copy_Roots (State, Expanded_Args, Arguments);
      --  pcall is a frame boundary, not a recursive invocation of Run.
      --  Tail calls replace the current frame while retaining the outer
      --  protected-return contract and the caller's destination register.
      declare
         Hops : Natural := 0;
         Handler : Value;
      begin
         loop
            if Function_Item.Kind in Closure_Kind |
              Native_Closure_Kind | Native_Kind_Value | Foreign_Function_Kind
            then
               exit;
            else
               Handler := Metafield (State, Function_Item, "__call");
               if Handler.Kind = Nil_Kind then
                  Bad_Call;
               end if;
               Hops := Hops + 1;
               if Hops > 15 then
                  Fail (State, "call metamethod chain too long");
               end if;
               Expanded_Args.Prepend (Function_Item);
               Function_Item := Handler;
            end if;
         end loop;
         Call_Metamethod_Count := Hops;
      end;
      Activate (Expanded_Args);
   exception
      when Language_Error | Lua.Storage.Allocation_Error =>
         if Lua.Storage.Refusal_Pending (State.Memory) then
            Record_Memory_Error (State);
         end if;
         if Protection = 0 or else (State.Current.Failure_Class =
           Host_Abort)
         then
            raise;
         end if;
         if not State.Current.Has_Failure_Value then
            State.Current.Failure :=
              Ensure_Error_Object (State, State.Current);
            Root_Barrier (State, State.Current.Failure);
         end if;
         Packet.Clear;
         Packet.Append (State.Current.Failure);
         Packet := Wrap (State, Packet, Protection, Success => False);
         if Tail then
            Complete (Self, Packet);
         else
            Deliver
              (Self, State.Current.Stack.Last_Element, Destination, Packet);
         end if;
         State.Current.Failure := Nil_Value;
         Root_Barrier (State, State.Current.Failure);
         State.Current.Has_Failure_Value := False;
         State.Current.Failure_Class := No_Failure;
   end Dispatch;

   function Recovery_Protection (Item : Frame_Access) return Boolean;
   function Recovery_Protection (Item : Frame_Access) return Boolean is
     (not Item.Logically_Unwound and then Item.Protection > 0 and then
      (not Item.Is_Native or else Item.Native_Name /= "@close.invoke" or else
       Item.Unwind = Coroutine_Exit) and then
      (not Item.Is_Native or else Item.Native_Name /= "@foreign.boundary" or
         else not Item.Foreign_Suspended or else Item.Foreign_Protected));

   function Active_Handler (Self : Driver) return Value is
      State : World renames Self.Universe.all;
   begin
      --  A pcall without a handler shadows outer handlers. Internal close
      --  protection explicitly copies this nearest active dynamic boundary.
      for Activation of reverse State.Current.Stack loop
         if Recovery_Protection (Activation) then
            return Activation.Message_Handler;
         end if;
      end loop;
      return Nil_Value;
   end Active_Handler;

   procedure Invoke_Message_Handler (Self : Driver; Handler : Value) is
      State : World renames Self.Universe.all;
      Arguments : Values.Vector := Owned_Values (State);
      Limit : constant Natural :=
        Lua.Runtime_Configuration.Maximum_C_Calls;
   begin
      if State.Current.Message_Depth >= Limit / 10 * 11 then
         --  Overflow uses a bootstrap root, requiring no new allocation.
         --  Handler recursion is explicit state rather than abandoned stacks.
         State.Current.Failure := State.Handling_Error_Value;
         Root_Barrier (State, State.Current.Failure);
         State.Current.Has_Failure_Value := True;
         State.Current.Failure_Class := Handling_Failure;
         State.Current.Failure_Handled := True;
         Lua.Diagnostic_Text.Clear (State.Current.Failure_Text);
         return;
      elsif State.Current.Message_Depth + 1 = Limit then
         State.Current.Failure := New_String (State, "C stack overflow");
         Root_Barrier (State, State.Current.Failure);
         State.Current.Has_Failure_Value := True;
         Set_Failure_Text (State, State.Current, "C stack overflow");
      end if;
      Arguments.Append (State.Current.Failure);
      Pin (State, Handler);
      Pin (State, Arguments);
      Arguments.Prepend (Handler);
      Schedule (Self, "@message.handler", Arguments, 0);
      State.Current.Message_Depth := State.Current.Message_Depth + 1;
      State.Current.Stack.Last_Element.Message_Charge := True;
      State.Current.Stack.Last_Element.Blocks_Yield := True;
      State.Current.Non_Yieldable := State.Current.Non_Yieldable + 1;
      --  Leave the same protected holder below this call. Recursive handler
      --  errors invoke it again; a successful transformation then unwinds the
      --  entire failed handler chain once, without nested pcall wrappers.
      --  Dispatch belongs to the next step. Its own native-depth/allocation
      --  failure must reenter ordinary scheduler recovery, rather than escape
      --  from this Recover activation as an unhandled root failure.
   end Invoke_Message_Handler;

   procedure Recover
     (Self : Driver; Prefix_Floor : Natural := Natural'Last) is
      State : World renames Self.Universe.all;
      Context : constant Context_Access := State.Current;
      Protected_Index : Natural := 0;
      Floor : Natural :=
        (if Prefix_Floor = Natural'Last then Context.Closing_Stack_Prefix
         else Prefix_Floor);
      Preserved : Natural;
      Destination : Natural;
      Protection : Natural;
      Failure : Failure_Kind;
      Handler_Called : Boolean;
      Retain_Traceback : Boolean := False;
   begin
      --  Resource exhaustion is a host execution boundary: allowing Lua
      --  pcall to catch it could restart an exhausted instruction budget.
      --  Ordinary errors unwind only to the nearest protected VM frame.
      if (State.Current.Failure_Class = Host_Abort) then
         raise Language_Error;
      end if;
      if not State.Current.Has_Failure_Value then
         State.Current.Failure :=
           Ensure_Error_Object (State, State.Current);
         Root_Barrier (State, State.Current.Failure);
         State.Current.Has_Failure_Value := True;
      end if;
      if not State.Current.Failure_Handled and then
        State.Current.Failure_Class not in Memory_Failure | Handling_Failure
      then
         declare
            Handler : constant Value := Active_Handler (Self);
         begin
            if Handler.Kind /= Nil_Kind then
               Invoke_Message_Handler (Self, Handler);
               if State.Current.Failure_Class /= Handling_Failure then
                  return;
               end if;
            end if;
         end;
      end if;
      if State.Current.Failure.Kind = Nil_Kind then
         --  Lua 5.5 normalizes nil after the handler sees the original object,
         --  including the absent first result from a successful handler.
         State.Current.Failure := New_String (State, "<no error object>");
         Root_Barrier (State, State.Current.Failure);
         Set_Failure_Text (State, State.Current, "<no error object>");
      end if;
      for Index in reverse State.Current.Stack.First_Index ..
        State.Current.Stack.Last_Index
      loop
         if Recovery_Protection (State.Current.Stack (Index)) then
            Protected_Index := Index;
            exit;
         end if;
      end loop;
      --  callk supplies a continuation for suspension, not protection from
      --  errors. A suspended unprotected transport proves its original C
      --  body has already left its guard; only an outer real protection may
      --  close this path. Record that abandoned body before retirement/reset.
      for Index in Protected_Index + 1 .. Context.Stack.Last_Index loop
         declare
            Item : constant Frame_Access := Context.Stack (Index);
         begin
            if Item.Is_Native and then Item.Native_Name = "@foreign.boundary"
              and then Item.Foreign_Suspended and then
              not Item.Foreign_Protected
            then
               Item.Foreign_Previous_Frame.Native_Stage := 3;
            end if;
         end;
      end loop;
      if Protected_Index = 0 and then
        (Context /= Self.Root_Context or else Context.C_Resuming)
      then
         --  An unhandled coroutine error leaves its pending scopes for the
         --  subsequent explicit reset/close operation.
         raise Language_Error;
      end if;
      if Protected_Index > 0 and then
        Context.Stack (Protected_Index).Error_Guard_Owner /= null
      then
         Retain_Traceback := Context /= Self.Root_Context or else
           Context.C_Resuming;
         for Index in 1 .. Protected_Index - 1 loop
            if Recovery_Protection (Context.Stack (Index)) then
               Retain_Traceback := False;
               exit;
            end if;
         end loop;
      end if;
      --  A failed closer abandons its original return controller too. Its
      --  saved outer floor, rather than the current selected close slot,
      --  belongs to this fresh recovery through the genuine protected call.
      for Index in Protected_Index + 1 .. Context.Stack.Last_Index loop
         declare
            Item : constant Frame_Access := Context.Stack (Index);
         begin
            if Item.Is_Native and then Item.Native_Name = "@unwind" then
               Floor := Natural'Min (Floor, Item.Unwind_Previous_Prefix);
            end if;
         end;
      end loop;
      Preserved := Floor;
      if Retain_Traceback then
         --  lua_resume does not reset CI/locals on an unhandled error. Keep
         --  its actual error-time top intact across the returning C guard;
         --  explicit reset will later close cells and truncate for handlers.
         Preserved := Natural'Max (Preserved, Context.Foreign_Top);
      end if;
      for Index in Protected_Index + 1 .. Context.Stack.Last_Index loop
         declare
            Item : constant Frame_Access := Context.Stack (Index);
         begin
            Preserved := Natural'Max
              (Preserved, Pending_Closing_Level (Item));
         end;
      end loop;
      --  Lua closes upvalues and abandons all execution above its protected
      --  floor before invoking error closers. The physical prefix below the
      --  highest pending TBC slot remains real storage, preserving ordinary
      --  locals there during collection without retaining dead return tails.
      Set_Closing_Stack_Prefix (State, Preserved);
      if Protected_Index > 0 and then
        Context.Stack (Protected_Index).Error_Guard_Owner /= null
      then
         declare
            Guard : constant Frame_Access := Context.Stack (Protected_Index);
            Item : Frame_Access;
         begin
            Guard.Error_Previous_Prefix := Floor;
            Guard.Deferred_Error_Traceback := Retain_Traceback;
            while Context.Stack.Last_Index > Protected_Index loop
               Item := Context.Stack.Last_Element;
               if not Retain_Traceback then
                  Retire_Frame_Execution (State, Item);
               end if;
               Context.Stack.Delete_Last;
               Item.Deferred_Error_Next := Guard.Deferred_Error_Head;
               Guard.Deferred_Error_Head := Item;
               Guard.Deferred_Error_Count := Guard.Deferred_Error_Count + 1;
               Context.Deferred_Error_Depth :=
                 Context.Deferred_Error_Depth + 1;
            end loop;
            --  Transfer the reserved false/error packet to the C boundary.
            --  Its actual callback remains live until the typed C guard
            --  reports completion; no Lua closer may run before that ACK.
            Guard.Error_Packet.Clear;
            Append_Root (State, Guard.Error_Packet, (Boolean_Kind, False));
            Append_Root (State, Guard.Error_Packet, Context.Failure);
            Move_Roots (State, Guard.Native_Results, Guard.Error_Packet);
            Guard.Result_Failure_Class := Context.Failure_Class;
            Guard.Result_Handler_Called := Context.Failure_Handled;
            Guard.Native_Aux :=
              (if Context.Failure_Class = Memory_Failure then 4
               elsif Context.Failure_Class = Handling_Failure then 5 else 2);
            Guard.Protection := 0;
            Guard.Native_Stage := 1;
            Context.Failure := Nil_Value;
            Context.Has_Failure_Value := False;
            Context.Failure_Class := No_Failure;
            Context.Failure_Handled := False;
            return;
         end;
      end if;
      for Index in reverse Protected_Index + 1 .. Context.Stack.Last_Index
      loop
         Retire_Frame_Execution (State, Context.Stack (Index));
      end loop;
      for Index in reverse Protected_Index + 1 .. Context.Stack.Last_Index
      loop
         if not Context.Stack (Index).Closers.Is_Empty or else
           Context.Stack (Index).C_Closing_Level /= 0
         then
            while Context.Stack.Last_Index > Index loop
               declare
                  Old : Frame_Access := Context.Stack.Last_Element;
               begin
                  Context.Stack.Delete_Last;
                  Release_Frame (State, Old);
               end;
            end loop;
            Start_Unwind
              (Self, Context.Stack.Last_Element, Error_Exit,
               Prefix_Floor => Floor);
            return;
         end if;
      end loop;
      Set_Closing_Stack_Prefix (State, Floor);
      if Protected_Index = 0 then raise Language_Error; end if;
      Destination := State.Current.Stack (Protected_Index).Return_To;
      Protection := State.Current.Stack (Protected_Index).Protection;
      Failure := State.Current.Failure_Class;
      Handler_Called := State.Current.Failure_Handled;
      declare
         Holder : Frame_Access := State.Current.Stack (Protected_Index);
         Caller : Frame_Access;
      begin
         if Holder.Error_Packet.Capacity < 2 then
            --  Public pcall already owns a nonempty argument packet before
            --  entering its protected phase. After the failing operation has
            --  unwound, that packet is no longer an execution input: actual
            --  C scalar slots retain the inspectable arguments. Adopt its
            --  existing capacity for false/error instead of allocating a
            --  second recovery vector while the provider refuses growth.
            --  A prior completion can have moved that buffer to Results;
            --  either move is allocation-free and leaves the holder traced.
            if Holder.Native_Arguments.Capacity >= 2 then
               Move_Roots
                 (State, Holder.Error_Packet, Holder.Native_Arguments);
            elsif Holder.Native_Results.Capacity >= 2 then
               Move_Roots
                 (State, Holder.Error_Packet, Holder.Native_Results);
            end if;
         end if;
         if Protection /= 1 or else Holder.Error_Packet.Capacity < 2 then
            raise Program_Error with "unreserved protected failure holder";
         end if;
         Holder.Error_Packet.Clear;
         Append_Root
           (State, Holder.Error_Packet,
            Value'(Boolean_Kind, False));
         Append_Root
           (State, Holder.Error_Packet,
            State.Current.Failure);
         while Natural (State.Current.Stack.Length) > Protected_Index loop
            declare
               Old : Frame_Access := State.Current.Stack.Last_Element;
            begin
               State.Current.Stack.Delete_Last;
               Release_Frame (State, Old);
            end;
         end loop;
         if Holder.Retain_On_Failure or else
           (Holder.Is_Native and then
            (Native_Operation_Name (Holder) = "base.pcall" or else
             Native_Operation_Name (Holder) = "base.xpcall"))
         then
            --  Move into the same live holder without allocating. A C
            --  sentinel's pump consumes it; a public pcall/xpcall resumes
            --  its own return phase so hooks can inspect the real status and
            --  error slots before that logical C activation is retired.
            Holder.Protection := 0;
            Move_Roots (State, Holder.Native_Results, Holder.Error_Packet);
            Holder.Result_Failure_Class := Failure;
            Holder.Result_Handler_Called := Handler_Called;
            Holder.Native_Aux :=
              (if Failure = Memory_Failure then 4
               elsif Failure = Handling_Failure then 5 else 2);
            Holder.Native_Stage := 1;
         else
            if Protected_Index > 1 then
               Caller := State.Current.Stack (Protected_Index - 1);
            else
               State.Current.Protected_Failure_Class := Failure;
               State.Current.Protected_Handler_Called := Handler_Called;
            end if;
            --  The source holder remains traced during publication. Native
            --  and root destinations take ownership; canonical scalar writes
            --  borrow it before retirement, including an allocation failure.
            --  Release its departing scalar interval first: the caller's
            --  destination overlaps this call's original function/arguments.
            --  The still-stacked holder keeps Error_Packet rooted, but its
            --  later metadata retirement must not erase newly returned data.
            Retire_Stack_Window (Holder);
            if Holder.Reset_Reserve and then Caller /= null then
               Deliver (Self, Caller, Destination, Holder.Error_Packet,
                        Failure, Handler_Called);
            else
               Deliver_Owned (Self, Caller, Destination, Holder.Error_Packet,
                              Failure, Handler_Called);
            end if;
            State.Current.Stack.Delete_Last;
            Release_Frame (State, Holder);
         end if;
      end;
      State.Current.Failure := Nil_Value;
      Root_Barrier (State, State.Current.Failure);
      State.Current.Has_Failure_Value := False;
      State.Current.Failure_Class := No_Failure;
      State.Current.Failure_Handled := False;
      Shrink_Error_Stack (State, State.Current);
   end Recover;

   function Try_Push_Finalizers
     (Self : Driver; Silent : Boolean := False) return Boolean;
   function Try_Start_Finalizer
     (Self : Driver; Activation : Frame_Access) return Boolean;
   procedure Advance_Finalizers (Self : Driver);

   function Try_Push_Finalizers
     (Self : Driver; Silent : Boolean := False) return Boolean
   is
      State : World renames Self.Universe.all;
      Before : constant Natural := Natural (State.Current.Stack.Length);
   begin
      if State.Finalizer_Active then return False; end if;
      --  A failed minimum-stack/CI check ends this drain opportunity, just
      --  as pinned GCScallfin enters pause. Retrying before the caller's
      --  next instruction would starve the code needed to release space.
      State.Finalizers_Requested := False;
      if not Finalizers.Has_Pending (State) then return False; end if;
      --  This is an internal activation, not an allocated Lua closure. A
      --  failed optional CI allocation leaves every target queued. Explicit
      --  embedding quotas and physical host failures still abort execution.
      Schedule (Self, "@gc.finalize", Values.Empty_Vector, 0);
      State.Current.Stack.Last_Element.Completion :=
        (if Silent then Resume_Caller else Deliver_Results);
      return True;
   exception
      when Error : Lua.Storage.Allocation_Error | Program_Error =>
         if Ada.Exceptions.Exception_Identity (Error) =
           Program_Error'Identity and then
           not Lua.Storage.Refusal_Pending (State.Memory)
         then
            raise;
         end if;
         while Natural (State.Current.Stack.Length) > Before loop
            declare
               Old : Frame_Access := State.Current.Stack.Last_Element;
            begin
               State.Current.Stack.Delete_Last;
               Release_Frame (State, Old);
            end;
         end loop;
         Lua.Storage.Acknowledge_Refusal (State.Memory);
         return False;
   end Try_Push_Finalizers;

   function Try_Start_Finalizer
     (Self : Driver; Activation : Frame_Access) return Boolean
   is
      State : World renames Self.Universe.all;
      Before : constant Natural := Natural (State.Current.Stack.Length);
      Holder : Frame_Access;
   begin
      if State.Native_Depth >=
        Lua.Runtime_Configuration.Maximum_C_Calls - 2 or else
        State.Current.Foreign_Top > Natural'Last - Initial_Stack_Size
      then
         return False;
      end if;
      if not Ensure_Stack
        (State, State.Current,
         State.Current.Foreign_Top + Initial_Stack_Size,
         Raise_Error => False)
      then
         return False;
      end if;
      --  Reserve every helper-owned packet before consuming the pending
      --  obligation. This is the Ada CI equivalent of checkminstack: a
      --  persistent refusal defers callbacks rather than losing an object or
      --  trying to report a Lua allocation error from an unprotected phase.
      Schedule (Self, "@finalizer.invoke", Values.Empty_Vector, 0);
      Holder := State.Current.Stack.Last_Element;
      Holder.Native_Arguments.Reserve_Capacity (2);
      Holder.Error_Packet.Reserve_Capacity (2);
      Finalizers.Begin_Next (State);
      if Finalizers.Current_Handler (State).Kind = Nil_Kind then
         --  Enrollment survives removal, but a removed handler is skipped.
         Finalizers.Finish_Current (State);
         State.Current.Stack.Delete_Last;
         Release_Frame (State, Holder);
         return True;
      end if;
      Append_Root
        (State, Holder.Native_Arguments,
         Finalizers.Current_Handler (State));
      Append_Root
        (State, Holder.Native_Arguments,
         Finalizers.Current_Target (State));
      Holder.Protection := 1;
      Holder.Blocks_Yield := True;
      State.Current.Non_Yieldable := State.Current.Non_Yieldable + 1;
      --  Only the actual handler is non-yieldable/hook-suppressed. Pinned
      --  GCTM restores both policies before invoking a warning callback.
      Activation.Finalizer_Charge := True;
      Activation.Finalizer_Phase := Waiting_Finalizer_Handler;
      State.Current.Finalizer_Hook_Suppression :=
        State.Current.Finalizer_Hook_Suppression + 1;
      State.Finalizer_Active := True;
      return True;
   exception
      when Error : Lua.Storage.Allocation_Error | Program_Error =>
         if Ada.Exceptions.Exception_Identity (Error) =
           Program_Error'Identity and then
           not Lua.Storage.Refusal_Pending (State.Memory)
         then
            raise;
         end if;
         while Natural (State.Current.Stack.Length) > Before loop
            declare
               Old : Frame_Access := State.Current.Stack.Last_Element;
            begin
               State.Current.Stack.Delete_Last;
               Release_Frame (State, Old);
            end;
         end loop;
         Lua.Storage.Acknowledge_Refusal (State.Memory);
         return False;
   end Try_Start_Finalizer;

   procedure Advance_Finalizers (Self : Driver) is
      State : World renames Self.Universe.all;
      Activation : constant Frame_Access := State.Current.Stack.Last_Element;
      Error_Value : Value;
      procedure Fragment (Bytes : Byte_String; More : Boolean);
      procedure Fragment (Bytes : Byte_String; More : Boolean) is
      begin
         --  The caller passes package-level NUL-terminated constants. Their
         --  storage outlives any asynchronous warning acknowledgment; no
         --  transient concatenated Ada String is retained by a C callback.
         Emit_Warning
           (State, Bytes, To_Continue => More);
      end Fragment;
   begin
      case Activation.Finalizer_Phase is
         when Choosing_Finalizer =>
            if not Finalizers.Has_Pending (State) or else
              not Try_Start_Finalizer (Self, Activation)
            then
               State.Finalizers_Requested := False;
               Complete (Self, Values.Empty_Vector);
            end if;
         when Waiting_Finalizer_Handler =>
            State.Current.Finalizer_Hook_Suppression :=
              State.Current.Finalizer_Hook_Suppression - 1;
            Activation.Finalizer_Charge := False;
            Finalizers.Finish_Current (State);
            if Activation.Native_Results.Is_Empty or else
              Truth (Activation.Native_Results.First_Element)
            then
               Activation.Native_Results.Clear;
               Activation.Finalizer_Phase := Choosing_Finalizer;
            else
               --  Match luaE_warnerror's five observable fragments. The
               --  failed packet roots its original error through every C
               --  warning callback, including nested Lua/GC reentry.
               Fragment (GC_Warning_Start, True);
               Activation.Finalizer_Phase := Warning_Where;
            end if;
         when Warning_Where =>
            Fragment (GC_Warning_Where, True);
            Activation.Finalizer_Phase := Warning_Open;
         when Warning_Open =>
            Fragment (GC_Warning_Open, True);
            Activation.Finalizer_Phase := Warning_Error;
         when Warning_Error =>
            Error_Value :=
              (if Activation.Native_Results.Length >= 2 then
                  Activation.Native_Results (2) else Nil_Value);
            if Error_Value.Kind = String_Kind then
               Emit_Warning (State, Error_Value, To_Continue => True);
            else
               Fragment (GC_Warning_Nonstring, True);
            end if;
            Activation.Finalizer_Phase := Warning_Close;
         when Warning_Close =>
            Fragment (GC_Warning_Close, False);
            Activation.Native_Results.Clear;
            Activation.Finalizer_Phase := Choosing_Finalizer;
      end case;
   end Advance_Finalizers;

   procedure Native_Step (Self : Driver) is
      State : World renames Self.Universe.all;
      Activation : constant Frame_Access :=
        State.Current.Stack.Last_Element;
      Name : constant String := Native_Operation_Name (Activation);
      Is_C_Reset : constant Boolean := State.Current.C_Reset_Active;
      Is_Self_Reset : constant Boolean :=
        Is_C_Reset and then State.Current.C_Reset_Self;
      API_Operation : constant C_Operators.Lookup_Result :=
        C_Operators.Find (Name);
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Activation.Native_Arguments.Length)
         then Activation.Native_Arguments (Index) else Nil_Value);
      Packet : Values.Vector := Owned_Values (State);
      Left : Value := Arg (1);
      Right : Value := Arg (2);
      Handler : Value;
      Event : Unbounded_String;
      Operator : Token_Kind := Activation.Native_Operator;
      Primitive : Boolean := False;
      Action : Native_Action := New_Action (State);
      Library_Step : Boolean := True;
      procedure Return_Native (Item : Value);
      procedure Invoke (Function_Value : Value; Args : Values.Vector);
      procedure Finish_Protected_Return;
      procedure Return_Native (Item : Value) is
         Result : Values.Vector := Owned_Values (State);
      begin
         Result.Append (Item);
         Complete (Self, Result);
      end Return_Native;
      procedure Finish_Protected_Return is
         Prefix : constant Natural := Activation.Protection;
         Count : constant Natural :=
           Natural (Activation.Native_Results.Length);
      begin
         if Prefix > 0 then
            if Prefix > Natural'Last - Count then
               Fail (State, "stack overflow");
            end if;
            --  Keep protection and the original raw packet intact until
            --  the complete success prefix fits. A refused growth must use
            --  the existing protected memory-error recovery, not publish a
            --  partial status or turn that failure into a success value.
            Activation.Native_Results.Reserve_Capacity
              (Ada.Containers.Count_Type (Count + Prefix));
            for Index in 1 .. Prefix loop
               Activation.Native_Results.Prepend
                 (Value'(Boolean_Kind, True));
            end loop;
            --  This actual publication phase, rather than the first value's
            --  contents, records that status wrapping has finished. Return
            --  hooks/yields and a raw false child result cannot add it twice.
            Activation.Protection := 0;
         end if;
         Complete (Self, Activation.Native_Results, Independent => True);
      end Finish_Protected_Return;
      procedure Invoke (Function_Value : Value; Args : Values.Vector) is
      begin
         --  Publish the resume phase before dispatch: immediate builtins
         --  may return immediately; Lua closures suspend this frame.
         Activation.Native_Stage := 1;
         Dispatch (Self, Function_Value, Args, 0);
         if Name in "@binary" | "@unary" | "@get" | "@set" then
            --  The actual handler activation now owns its arguments. These
            --  metadata-only operator holders need only the returned packet;
            --  a stale input copy would keep objects alive after a handler
            --  drops its parameters and edits the real caller's slots.
            Activation.Native_Arguments.Clear;
         end if;
      end Invoke;
   begin
      State.Current.Failure_At := Activation.Call_Site;
      --  Stateful libraries own their continuation phase. Dispatch their
      --  requested callback through this same activation stack, so neither
      --  Lua nesting nor a protected error creates a second VM or budget.
      if Activation.Warning_Failed then
         Activation.Warning_Failed := False;
         raise Language_Error;
      end if;
      if Name = "foreign.callback" or else Activation.Load_Reader_Portal then
         if Activation.Native_Stage = 0 then
            if Activation.Foreign_Handler = System.Null_Address then
               raise Program_Error with "foreign callback has no handler";
            end if;
            if State.Next_Foreign_Ticket =
              Interfaces.C.unsigned_long_long'Last
            then
               Fail (State, "foreign callback identity exhausted",
                     Resource => True);
            end if;
            State.Next_Foreign_Ticket := State.Next_Foreign_Ticket + 1;
            Activation.Foreign_Ticket := State.Next_Foreign_Ticket;
            if Activation.Load_Reader_Portal and then
              Activation.Native_Builtin_Direct and then
              State.Current.Foreign_Activation /= null
            then
               --  A saved builtin pointer is still executing its original
               --  C body. Publish this hidden phase's current scalar prefix
               --  into that actual owner before discarding duplicate roots.
               --  The phase remains the genuine new portal guard/token;
               --  it borrows the public owner's cells, not a copied window.
               Publish_Builtin_Window
                 (State, State.Current.Foreign_Activation);
            end if;
            Activation.Foreign_Base := Activation.Stack_Base;
            Activation.Foreign_Previous_Base := State.Current.Foreign_Base;
            Activation.Foreign_Previous_Frame :=
              State.Current.Foreign_Activation;
            Activation.Foreign_Previous_View := State.Current.Foreign_View;
            Activation.Foreign_Entered := True;
            State.Current.Foreign_Base := Activation.Stack_Base;
            State.Current.Foreign_Top := Activation.Stack_Live_Top;
            State.Current.Foreign_Activation := Activation;
            State.Current.Foreign_View := null;
            if Activation.Load_Reader_Portal and then
              Activation.Native_Builtin_Direct and then
              not Activation.Has_Stack_Window
            then
               Stack_Views.Borrow
                 (State, State.Current, State.Current.Stack_Window,
                  Activation.Hook_View, Hook_View);
            end if;
            --  Actual scalar slots now own every argument. Keeping a stale
            --  packet would retain C arguments removed/replaced by the host
            --  and invalidate weak observations during callback collection.
            Activation.Native_Arguments.Clear;
            Activation.Native_Captures.Clear;
            Activation.Native_Stage := 1;
            --  Returning exposes an explicit C request. Invoking its function
            --  pointer here would let longjmp cross these live Ada frames.
         elsif Activation.Native_Stage = 5 then
            declare
               Context : constant Context_Access := State.Current;
               Top : constant Natural :=
                 Activation.Stack_Live_Top -
                   Activation.Foreign_Yield_Count;
            begin
               --  Resume arguments replace the yielded tail of the C stack.
               --  Prefix arguments/upvalues remain actual rooted slots for K.
               Set_Native_Top
                 (State, Activation, Top - Activation.Stack_Base);
               Context.Foreign_Top := Top;
               for Item of Activation.Native_Results loop
                  Push_Native_Value (State, Activation, Item);
               end loop;
               Context.Foreign_Top := Activation.Stack_Live_Top;
               Activation.Foreign_Yield_Count := 0;
               if Activation.Foreign_Continuation = System.Null_Address then
                  Context.Foreign_Top := Activation.Saved_Foreign_Top;
                  Context.Foreign_Base := Activation.Foreign_Previous_Base;
                  Context.Foreign_Activation :=
                    Activation.Foreign_Previous_Frame;
                  Context.Foreign_View := Activation.Foreign_Previous_View;
                  Activation.Foreign_Entered := False;
                  Activation.Native_Stage := 2;
               else
                  Activation.Foreign_KStatus := 1;
                  --  K observes the reconstructed scalar C stack. Retaining
                  --  shadow argument/result packets would keep values alive
                  --  after K removes them from its actual public window.
                  Activation.Native_Arguments.Clear;
                  Activation.Native_Results.Clear;
                  Activation.Native_Stage := 1;
               end if;
            end;
         elsif Activation.Native_Stage = 2 then
            if Activation.Closers.Is_Empty and then
              Activation.C_Closing_Level = 0
            then
               if Activation.Load_Reader_Portal then
                  --  Reader code may have permanently refused provider
                  --  growth. Its already reserved packet owns raw results;
                  --  add only private protection statuses in that capacity.
                  --  Keep Protection through return-hook reconstruction:
                  --  the real C window still exposes only its raw tuple.
                  Activation.Native_Results.Prepend
                    (Value'(Boolean_Kind, True),
                     Ada.Containers.Count_Type (Activation.Protection));
                  Complete_Packet
                    (Self, Activation.Native_Results,
                     Activation.Native_Results);
               else
                  Complete (Self, Activation.Native_Results);
               end if;
            else
               Start_Unwind
                 (Self, Activation, Return_Exit, Activation.Native_Results);
            end if;
         elsif Activation.Native_Stage = 3 then
            raise Language_Error;
         else
            raise Program_Error with "foreign callback awaits its C pump";
         end if;
         return;
      elsif Name = "@foreign.close" then
         if Activation.Native_Stage = 0 then
            declare
               Owner : Frame_Access;
               Identity : constant Value := Activation.Native_Captures (1);
               Depth : constant Value := Activation.Native_Captures (2);
            begin
               for Candidate of State.Current.Stack loop
                  if Candidate.all'Address = Identity.Identity then
                     Owner := Candidate;
                     exit;
                  end if;
               end loop;
               if Owner = null or else Depth.Kind /= Integer_Kind then
                  raise Program_Error with "inactive foreign close owner";
               end if;
               --  This helper is entered only after the C dispatcher has
               --  returned. The normal iterative close driver can therefore
               --  invoke Lua/C handlers without crossing a live Ada frame.
               Activation.Native_Stage := 1;
               Start_Unwind
                 (Self, Owner, C_Slot_Exit,
                  Depth => Natural (Depth.Integer_Data));
            end;
         else
            Complete (Self, Values.Empty_Vector);
         end if;
         return;
      elsif Name = "@foreign.boundary" then
         if Activation.Foreign_Suspended then
            if Activation.Native_Stage = 0 then
               --  A successful child delivers raw results. Error recovery
               --  has already installed its false/error packet at stage one.
               Copy_Roots
                 (State, Activation.Native_Results,
                  Wrap (State, Activation.Native_Results, 1));
               Activation.Native_Stage := 1;
            end if;
            declare
               Caller : constant Frame_Access :=
                 Activation.Foreign_Previous_Frame;
               Success : constant Boolean :=
                 Activation.Native_Results.First_Element.Boolean_Data;
               Count : constant Natural :=
                 (if not Success then 1
                  elsif Activation.Foreign_Wanted = -1 then
                    Natural (Activation.Native_Results.Length) - 1
                  else Natural (Activation.Foreign_Wanted));
               Old : Frame_Access := Activation;
               Context : constant Context_Access := State.Current;
            begin
               --  The suspended C body has no live C stack. Its protected
               --  child now owns a complete packet; publish the adjusted
               --  results directly into the retained caller window before
               --  retiring the holder and requesting the saved K function.
               Context.Foreign_Base := Caller.Stack_Base;
               Set_Native_Top
                 (State, Caller, Activation.Native_Index - Caller.Stack_Base);
               Context.Foreign_Top := Activation.Native_Index;
               Context.Foreign_Activation := Caller;
               Context.Foreign_View := Activation.Foreign_Previous_View;
               for Index in 1 .. Count loop
                  Push_Native_Value
                    (State, Caller,
                     (if Index < Natural (Activation.Native_Results.Length)
                      then Activation.Native_Results (Index + 1)
                      else Nil_Value));
               end loop;
               Context.Foreign_Top := Caller.Stack_Live_Top;
               Caller.Native_Arguments.Clear;
               Caller.Native_Results.Clear;
               if not Success and then not Activation.Foreign_Protected then
                  --  callk retains a continuation for suspension, not an
                  --  error handler. Its child failure must unwind this C
                  --  activation and reach an outer real protected boundary.
                  Context.Failure := Stacks.Read
                    (Context, Context.Foreign_Top);
                  Root_Barrier (State, Context.Failure);
                  Context.Has_Failure_Value := True;
                  Lua.Diagnostic_Text.Clear (Context.Failure_Text);
                  Context.Failure_Class := Activation.Result_Failure_Class;
                  Context.Failure_Handled := Activation.Result_Handler_Called;
                  Caller.Native_Stage := 3;
               else
                  Caller.Foreign_KStatus :=
                    (if Success then 1 else Interfaces.C.int
                       (Natural'Max (2, Activation.Native_Aux)));
                  Caller.Native_Stage := 1;
               end if;
               State.Current.Stack.Delete_Last;
               Release_Frame (State, Old);
            end;
            return;
         end if;
         --  A protected child has delivered one wrapped packet. Leave it in
         --  this sentinel until the nested C pump publishes the results onto
         --  the caller's C stack, then explicitly removes the sentinel.
         Copy_Roots
           (State, Activation.Native_Results,
            Wrap (State, Activation.Native_Results, 1));
         Activation.Native_Stage := 1;
         return;
      elsif Name = "@gc.finalize" then
         Advance_Finalizers (Self);
         return;
      elsif Name in "@foreign.entry" | "@close.invoke" |
        "@finalizer.invoke"
      then
         if Activation.Native_Stage = 0 then
            Handler := Arg (1);
            --  The holder already owns handler/self/error. Remove only the
            --  handler and borrow the remaining rooted packet through
            --  dispatch, rather than allocating a fresh callback argument
            --  vector on a possibly permanently refusing failure path.
            Activation.Native_Arguments.Delete_First;
            Activation.Native_Stage := 1;
            if Activation.Native_Builtin_Direct then
               Schedule_Builtin
                 (Self, Handler.Native_Data, Activation.Native_Arguments, 0,
                  Activation.Foreign_Previous_Frame);
            else
               Dispatch (Self, Handler, Activation.Native_Arguments, 0,
                         Call_Base => Activation.Native_Index,
                         Has_Call_Window => Activation.Native_Aux /= 0);
               --  Record the actual finalizer entry without allocating a
               --  name buffer while collection is active. Read-only C
               --  inspection borrows its static marker; ordinary nested
               --  calls and Lua tail replacements have independent origins.
               State.Current.Stack.Last_Element.Is_Finalizer_Call :=
                 Name = "@finalizer.invoke";
               if Name = "@close.invoke" then
                  --  Close method results are discarded by the real call,
                  --  before any helper packet is materialized. C return
                  --  hooks still inspect their authoritative scalar slots.
                  State.Current.Stack.Last_Element.Completion :=
                    Resume_Caller;
               end if;
            end if;
            Activation.Native_Arguments.Clear;
         else
            if Name = "@close.invoke" and then
              Activation.Protection = 1 and then State.Current.C_Reset_Active
            then
               --  This explicit reset catches replacement errors per closer.
               --  A normally returned method has no results: publish its
               --  actual success status from the holder's reserved packet.
               Activation.Native_Results.Clear;
               Append_Root
                 (State, Activation.Native_Results, (Boolean_Kind, True));
               Activation.Protection := 0;
               Complete_Packet
                 (Self, Values.Empty_Vector, Activation.Native_Results);
            elsif Name = "@foreign.entry" then
               --  The C body and its closers have already returned. Publish
               --  the internal success prefix in retained storage, just as
               --  the public protected-call driver does. A fresh Wrap vector
               --  here would turn a successful warmed return into NOMEM.
               Finish_Protected_Return;
            else
               Complete (Self, Activation.Native_Results);
            end if;
         end if;
         return;
      elsif Name = "@reader.error" then
         --  Foreign lua_load catches reader errors inside the active
         --  protected parser. Its inherited message handler still runs
         --  before return, through this same driver's normal error protocol.
         --  The original object receives no invented source prefix, and
         --  internal @ phases never become public logical stack frames.
         Raise_Value (Self, Arg (1), Level => 0);
      elsif Name = "@message.handler" then
         if Activation.Native_Stage = 0 then
            Packet.Append (Arg (2));
            Activation.Native_Stage := 1;
            Dispatch (Self, Arg (1), Packet, 0);
            return;
         end if;
         --  Its raw target returned normally. Recursive handler errors never
         --  resume this phase: they return to the same protected holder and
         --  the eventual successful transformation retires the failed chain.
         Left := First (Activation.Native_Results);
         Pin (State, Left);
         State.Current.Stack.Delete_Last;
         declare
            Old : Frame_Access := Activation;
         begin
            State.Current.Failure_At := Old.Call_Site;
            Release_Frame (State, Old);
         end;
         State.Current.Failure := Left;
         Root_Barrier (State, State.Current.Failure);
         State.Current.Has_Failure_Value := True;
         State.Current.Failure_Class := Language_Failure;
         State.Current.Failure_Handled := True;
         Lua.Diagnostic_Text.Clear (State.Current.Failure_Text);
         Recover (Self);
         return;
      elsif Name = "base.primitive" then
         Complete (Self, Native
           (Self, Activation.Native_Id, Activation.Native_Arguments));
         return;
      elsif Name = "base.pcall" then
         if Activation.Native_Stage = 0 then
            if Activation.Native_Arguments.Is_Empty then
               Fail (State, "value expected");
            end if;
            --  The activation already owns this rooted C argument packet.
            --  Keep its function as an operation root and remove only that
            --  first element in place. A fresh controlled copy allocated
            --  before pcall established protection, so provider refusal
            --  escaped the very call intended to catch it.
            Handler := Activation.Native_Arguments.First_Element;
            Pin (State, Handler);
            Activation.Native_Arguments.Delete_First;
            --  The argument packet will be empty after callee publication,
            --  and Recover can adopt its capacity if this target fails.
            --  Keeping that real owned reserve avoids allocating an unused
            --  parallel error packet before protection is established.
            Activation.Native_Arguments.Reserve_Capacity (2);
            Activation.Protection := Activation.Protection + 1;
            Activation.Native_Stage := 1;
            Stacks.Write
              (State, State.Current, Activation.Stack_Base + 1,
               (Boolean_Kind, True));
            Dispatch (Self, Handler, Activation.Native_Arguments, 0,
                      Call_Base => Activation.Stack_Base + 2,
                      Has_Call_Window => True);
            Activation.Native_Arguments.Clear;
         else
            Finish_Protected_Return;
         end if;
         return;
      elsif Name = "@hook" then
         State.Current.Hook_Active := False;
         Complete (Self, Values.Empty_Vector);
         return;
      elsif Name = "@return.hook" then
         declare
            Old : Frame_Access := Activation;
            Owner : constant Frame_Access := State.Current.Stack
              (State.Current.Stack.Last_Index - 1);
            Public_Protection : constant Boolean := Owner.Is_Native and then
              (Owner.Native_Name = "base.pcall" or else
               Owner.Native_Name = "base.xpcall");
            Prefix : constant Natural :=
              (if Public_Protection then 0 else Owner.Protection);
         begin
            if not Owner.Has_Stack_Window then
               Packet := Activation.Unwind_Results;
               State.Current.Stack.Delete_Last;
               Release_Frame (State, Old);
               Complete (Self, Packet);
               return;
            end if;
            --  The hook has returned; its own physical window has retired.
            --  Rebuild from the exact source range while that real callee
            --  still owns it. Internal protection contributes its separate
            --  true prefix once. Public pcall/xpcall already expose their
            --  complete tuple, including a status cell the hook may edit.
            if Owner.Native_Results.Capacity < Ada.Containers.Count_Type
              (Owner.Transfer_Count + Prefix)
            then
               raise Program_Error with "return hook packet capacity lost";
            end if;
            Owner.Native_Results.Clear;
            for Index in 1 .. Prefix loop
               Append_Root
                 (State, Owner.Native_Results, (Boolean_Kind, True));
            end loop;
            for Index in 1 .. Owner.Transfer_Count loop
               Append_Root
                 (State, Owner.Native_Results,
                  Stacks.Read (State.Current,
                    Owner.Stack_Base + Owner.Transfer_First + Index - 1));
            end loop;
            State.Current.Stack.Delete_Last;
            Release_Frame (State, Old);
            --  This is the already adjusted delivery packet. Complete must
            --  not wrap it again or replay an operation's result publisher.
            Complete_Packet
              (Self, Owner.Native_Results, Owner.Native_Results);
         end;
         return;
      elsif Name = "@close.thread" then
         if State.Current.Stack.Length = 1 then
            State.Current.Stack.Delete_Last;
            declare
               Old : Frame_Access := Activation;
            begin
               Release_Frame (State, Old);
            end;
            State.Current.Transfer.Kind :=
              (if State.Current.Has_Failure_Value then Lua_Raised
               else Completed);
            State.Current.Transfer.Target := 0;
            State.Current.Transfer.Results.Clear;
            if State.Current.Has_Failure_Value and then not Is_C_Reset then
               Append_Root (State, State.Current.Transfer.Results,
                            State.Current.Failure);
            end if;
            Root_Barrier (State, State.Current.Transfer.Results);
            if State.Current.C_Reset_Active then
               State.Current.C_Reset_Error :=
                 State.Current.Has_Failure_Value;
               Set_Closing_Stack_Prefix (State, 0);
               if State.Current.Has_Failure_Value then
                  --  resetthread publishes its genuine error at the base
                  --  slot before a self-close throws to its outer resume.
                  --  That resume adds another copy; Lua's resume library
                  --  consumes its terminal copy, leaving this base value.
                  Stacks.Write (State, State.Current, 1,
                                State.Current.Failure);
                  State.Current.Foreign_Top := 1;
                  State.Current.Host_Stack_Top := 1;
                  if State.Current.C_Reset_Self then
                     State.Current.Resume_Return_Top := 1;
                  end if;
               end if;
               if State.Current.C_Reset_Self then
                  State.Native_Depth :=
                    State.Current.C_Reset_Return_Depth;
               end if;
               State.Current.C_Reset_Requested := False;
               State.Current.C_Reset_Active := False;
            end if;
            if not Is_Self_Reset and then not Is_C_Reset then
               State.Current.Failure := Nil_Value;
               Root_Barrier (State, State.Current.Failure);
               State.Current.Has_Failure_Value := False;
            end if;
         elsif Activation.Native_Stage = 1 then
            declare
               Owner : Frame_Access := State.Current.Stack
                 (State.Current.Stack.Last_Index - 1);
            begin
               State.Current.Stack.Delete
                 (State.Current.Stack.Last_Index - 1);
               Release_Frame (State, Owner);
               Activation.Native_Stage := 0;
            end;
         else
            declare
               Owner : constant Frame_Access := State.Current.Stack
                 (State.Current.Stack.Last_Index - 1);
            begin
               Activation.Native_Stage := 1;
               Start_Unwind
                 (Self, Owner, Coroutine_Exit,
                  Prefix_Floor =>
                    (if State.Current.C_Reset_Active then 0
                     else Natural'Last));
            end;
         end if;
         return;
      elsif Name = "@unwind" then
         declare
            Owner : constant Frame_Access := Activation.Unwind_Owner;
            Reason : Unwind_Reason := Activation.Unwind;
            Closing : Close_Entry;
            Need_Close : Boolean;
         begin
            if Activation.Native_Stage = 1 then
               if Reason = Coroutine_Exit and then
                 not Activation.Native_Results (1).Boolean_Data
               then
                  Activation.Unwind_Error :=
                    Activation.Native_Results (2);
                  Root_Barrier (State, Activation.Unwind_Error);
                  Activation.Unwind_Has_Error := True;
                  Activation.Unwind_Failure_Class :=
                    Activation.Result_Failure_Class;
                  Activation.Unwind_Handler_Called :=
                    Activation.Result_Handler_Called;
                  if Reason /= Coroutine_Exit then
                     Reason := Error_Exit;
                     Activation.Unwind := Reason;
                  end if;
                  if Reason = Coroutine_Exit and then
                    not Activation.Blocks_Yield
                  then
                     Activation.Blocks_Yield := True;
                     State.Current.Non_Yieldable :=
                       State.Current.Non_Yieldable + 1;
                  end if;
               end if;
               Activation.Native_Results.Clear;
               Activation.Native_Stage := 0;
            end if;
            while not Owner.Closers.Is_Empty or else
              Owner.C_Closing_Level /= 0
            loop
               if Owner.C_Closing_Level /= 0 then
                  Closing :=
                    (Cell => null, Stack_Level => Owner.C_Closing_Level,
                     Depth => Owner.C_Closing_Level, others => <>);
               else
                  Closing := Owner.Closers.Last_Element;
               end if;
               Need_Close := Reason in Return_Exit | Error_Exit |
                 Coroutine_Exit or else
                 Closing.Depth > Activation.Unwind_Depth or else
                 (Reason = Jump_Exit and then Closing.Symbol /= 0 and then
                  not Activation.Unwind_Live.Contains (Closing.Symbol));
               exit when not Need_Close;
               if Owner.Logically_Unwound then
                  Set_Closing_Stack_Prefix
                    (State, Natural'Max
                       (Activation.Unwind_Previous_Prefix,
                        Closing.Stack_Level));
               end if;
               if Owner.C_Closing_Level /= 0 then
                  Owner.C_Closing_Level := State.Current.C_Close_Links
                    (Closing.Stack_Level).Previous;
                  State.Current.C_Close_Links.Replace_Element
                    (Closing.Stack_Level, (Previous => 0));
               else
                  Owner.Closers.Delete_Last;
               end if;
               Left :=
                 (if Closing.Frozen then Closing.Frozen_Value
                  elsif Closing.Stack_Level /= 0 then
                    Stacks.Read (Owner.Context, Closing.Stack_Level)
                  else Closing.Cell.Cell_Value);
               if Truth (Left) then
                  Handler := Metafield (State, Left, "__close");
                  --  Re-read the current handler, including nil/noncallable
                  --  replacements. The protected real dispatch raises its
                  --  call error and lets outer closers observe that new error.
                  Activation.Native_Arguments.Clear;
                  Append_Root
                    (State, Activation.Native_Arguments, Handler);
                  Append_Root
                    (State, Activation.Native_Arguments, Left);
                  --  Lua 5.5 supplies only self on normal close. A genuine
                  --  error adds its second argument; an explicit nil value
                  --  would change select('#', ...) in a C/Lua close handler.
                  if Activation.Unwind_Has_Error then
                     Append_Root
                       (State, Activation.Native_Arguments,
                        Activation.Unwind_Error);
                  end if;
                  Activation.Native_Stage := 1;
                  --  Protection is a cleanup boundary, not a public pcall
                  --  activation. Logical debug frames expose the original
                  --  owner or its surrounding protected native caller.
                  declare
                     Message_Handler : constant Value :=
                       Active_Handler (Self);
                  begin
                     Schedule
                       (Self, "@close.invoke", Activation.Native_Arguments, 0);
                     Activation.Native_Arguments.Clear;
                     if Reason = Coroutine_Exit then
                        --  Explicit reset catches each replacement error
                        --  without allowing suspension. Other close errors
                        --  already return through the genuine protected
                        --  floor; a second false/error packet would both
                        --  invent protection and allocate during failure.
                        State.Current.Stack.Last_Element.Error_Packet
                          .Reserve_Capacity (2);
                        State.Current.Stack.Last_Element.Protection := 1;
                     end if;
                     State.Current.Stack.Last_Element.Unwind := Reason;
                     if Reason = Error_Exit and then
                       Closing.Stack_Level /= 0
                     then
                        --  prepcallclosemth places the real error object at
                        --  level+1 and pushes the handler at level+2. Reuse
                        --  those departed slots after execution retirement;
                        --  the active closer receives its genuine window.
                        Stacks.Write
                          (State, State.Current, Closing.Stack_Level + 1,
                           Activation.Unwind_Error);
                        State.Current.Stack.Last_Element.Native_Index :=
                          Closing.Stack_Level + 2;
                        State.Current.Stack.Last_Element.Native_Aux := 1;
                     end if;
                     State.Current.Stack.Last_Element.Message_Handler :=
                       Message_Handler;
                     Root_Barrier
                       (State,
                        State.Current.Stack.Last_Element.Message_Handler);
                  end;
                  return;
               end if;
            end loop;
            declare
               Results : constant Values.Vector :=
                 Activation.Unwind_Results;
               Error_Value : constant Value := Activation.Unwind_Error;
               Failed : constant Boolean := Activation.Unwind_Has_Error;
               Failure : constant Failure_Kind :=
                 Activation.Unwind_Failure_Class;
               Handler_Called : constant Boolean :=
                 Activation.Unwind_Handler_Called;
               Depth : constant Natural := Activation.Unwind_Depth;
               PC : constant Natural := Activation.Unwind_PC;
               Live : constant Registers.Vector := Activation.Unwind_Live;
               Previous_Prefix : constant Natural :=
                 Activation.Unwind_Previous_Prefix;
               Old : Frame_Access := Activation;
            begin
               State.Current.Stack.Delete_Last;
               Release_Frame (State, Old);
               if Reason in Error_Exit | Coroutine_Exit then
                  State.Current.Failure := Error_Value;
                  Root_Barrier (State, State.Current.Failure);
                  State.Current.Has_Failure_Value := Failed;
                  Lua.Diagnostic_Text.Clear (State.Current.Failure_Text);
                  State.Current.Failure_Class := Failure;
                  State.Current.Failure_Handled := Handler_Called;
               end if;
               case Reason is
                  when Return_Exit =>
                     Set_Closing_Stack_Prefix (State, Previous_Prefix);
                     if Owner.Has_Stack_Window and then
                       Owner.Return_Window_Published
                     then
                        declare
                           Count : constant Natural := Owner.Transfer_Count;
                           Prefix : constant Natural := Owner.Protection;
                        begin
                           --  Every closer has completed. The original
                           --  source cells, including their edits, remain
                           --  rooted until the normal delivery retires this
                           --  frame. Internal status prefixes are separate
                           --  from that actual return span and appear once.
                           if Owner.Native_Results.Capacity <
                             Ada.Containers.Count_Type (Count + Prefix)
                           then
                              raise Program_Error with
                                "close return packet capacity lost";
                           end if;
                           Owner.Native_Results.Clear;
                           for Index in 1 .. Prefix loop
                              Append_Root
                                (State, Owner.Native_Results,
                                 (Boolean_Kind, True));
                           end loop;
                           for Index in 1 .. Count loop
                              Append_Root
                                (State, Owner.Native_Results,
                                 Stacks.Read
                                   (State.Current, Owner.Stack_Base +
                                    Owner.Transfer_First + Index - 1));
                           end loop;
                           Complete_Packet
                             (Self, Owner.Native_Results,
                              Owner.Native_Results);
                        end;
                     else
                        Complete (Self, Results);
                     end if;
                  when Scope_Exit =>
                     if Owner.Code.Canonical_Node = null then
                        Owner.Scope := Owner.Scope.Parent;
                        Root_Barrier (State, Owner.Scope);
                        Owner.Scope_Depth := Owner.Scope_Depth - 1;
                     end if;
                     --  Canonical CLOSE uses register lifetime boundaries,
                     --  not the private backend's lexical environment chain.
                  when Jump_Exit =>
                     while Owner.Scope_Depth > Depth loop
                        Owner.Scope := Owner.Scope.Parent;
                        Root_Barrier (State, Owner.Scope);
                        Owner.Scope_Depth := Owner.Scope_Depth - 1;
                     end loop;
                     for Index in reverse Owner.Scope.Locals.First_Index ..
                       Owner.Scope.Locals.Last_Index
                     loop
                        if not Live.Contains
                          (Owner.Scope.Locals (Index).Symbol)
                        then
                           Owner.Scope.Locals.Delete (Index);
                        end if;
                     end loop;
                     Owner.PC := PC;
                  when Error_Exit =>
                     Recover (Self, Prefix_Floor => Previous_Prefix);
                  when Coroutine_Exit | C_Slot_Exit => null;
                  when No_Unwind => raise Program_Error;
               end case;
            end;
         end;
         return;
      end if;
      if Name'Length >= 10 and then
        Name (Name'First .. Name'First + 9) = "coroutine."
      then
         if Name in "coroutine.create" | "coroutine.wrap" then
            if Left.Kind not in Closure_Kind | Native_Closure_Kind |
              Native_Kind_Value | Foreign_Function_Kind
            then
               Fail (State, "function expected");
            end if;
            Handler := New_Thread (State, Left);
            if Name = "coroutine.wrap" then
               Handler := New_Native
                 (State, "coroutine.wrapped", One_Value
                   (State, Handler, 1));
            end if;
            Return_Native (Handler);
         elsif Name = "coroutine.running" then
            Packet.Append (Value'(Thread_Kind, State.Current.Thread));
            Packet.Append (Value'(Boolean_Kind,
                                  State.Current = State.Main_Context));
            Complete (Self, Packet);
         elsif Name = "coroutine.yield" then
            if Activation.Native_Stage = 0 then
               if (State.Current = State.Main_Context and then
                   not State.Current.C_Resuming) or else
                 (State.Current.Resumer = null and then
                   not State.Current.C_Resuming) or else
                 State.Current.Non_Yieldable > 0 or else
                 State.Current.Phase = Closing
               then
                  Fail (State,
                    (if State.Current = State.Main_Context and then
                        not State.Current.C_Resuming then
                       "attempt to yield from outside a coroutine"
                     else "attempt to yield across a C-call boundary"));
               end if;
               Activation.Native_Stage := 1;
               State.Current.Transfer.Kind := Yielded;
               Copy_Roots
                 (State, State.Current.Transfer.Results,
                  Activation.Native_Arguments);
            else
               Complete (Self, Activation.Native_Results);
            end if;
         else
            declare
               Thread : Value := Left;
               Context : Context_Access;
               Args : Values.Vector :=
                 Owned_Values (State, Activation.Native_Arguments);
            begin
               if Name = "coroutine.wrapped" then
                  Thread := Activation.Native_Captures (1);
               elsif Name in "coroutine.isyieldable" |
                 "coroutine.close" and then
                 Activation.Native_Arguments.Is_Empty
               then
                  Thread := (Thread_Kind, State.Current.Thread);
               end if;
               if Thread.Kind /= Thread_Kind then
                  Fail (State, "thread expected");
               end if;
               Context := State.Contexts (Thread.Reference.Context_Index);
               if Name = "coroutine.status" then
                  Return_Native (New_String
                    (State,
                     (case Context.Status is
                         when New_Context | Suspended_Context =>
                           "suspended",
                         when Running_Context => "running",
                         when Normal_Context => "normal",
                         when Dead_Context => "dead")));
               elsif Name = "coroutine.isyieldable" then
                  --  This queries yield barriers, not resume validity.
                  --  A dead context retains error frames for inspection
                  --  and close, but their abandoned barriers do not count.
                  Return_Native ((Boolean_Kind,
                           Context /= State.Main_Context and then
                           Context.Phase /= Closing and then
                           (Context.Status = Dead_Context or else
                            Context.Non_Yieldable = 0)));
               elsif Name in "coroutine.resume" | "coroutine.wrapped" then
                  if Activation.Native_Stage = 2 then
                     --  wrap closes a failed body before raising. A close
                     --  error replaces the body's error, just as in Lua.
                     Packet := Activation.Native_Results;
                     Raise_Value
                       (Self, (if Packet (1).Boolean_Data then
                           Activation.Unwind_Error else Packet (2)));
                  elsif Activation.Native_Stage = 1 then
                     Packet := Activation.Native_Results;
                     if Name = "coroutine.wrapped" then
                        if not Packet (1).Boolean_Data then
                           if Activation.Result_Failure_Class = No_Failure
                           then
                              --  auxresume could not reserve the caller's
                              --  result area. The child itself succeeded or
                              --  yielded; wrapping must raise this message
                              --  without closing a healthy suspended body.
                              Raise_Value (Self, Packet (2));
                              return;
                           end if;
                           Activation.Unwind_Error := Packet (2);
                           Root_Barrier (State, Activation.Unwind_Error);
                           Activation.Native_Stage := 2;
                           State.Current.Transfer :=
                             (Kind => Close_Requested,
                              Results => Values.Empty_Vector,
                              Target => Thread.Reference.Context_Index);
                           Root_Barrier
                             (State, State.Current.Transfer.Results);
                           return;
                        end if;
                        Packet.Delete_First;
                     end if;
                     Complete (Self, Packet);
                  elsif Context = State.Main_Context or else
                    Context.Status not in New_Context | Suspended_Context
                  then
                     Handler := New_String
                       (State, (if Context.Status = Dead_Context then
                          "cannot resume dead coroutine" else
                          "cannot resume non-suspended coroutine"));
                     if Name = "coroutine.wrapped" then
                        Raise_Value (Self, Handler);
                     end if;
                     Packet.Append (Value'(Boolean_Kind, False));
                     Packet.Append (Handler);
                     Complete (Self, Packet);
                  else
                     if Name = "coroutine.resume" then
                        Args.Delete_First;
                     end if;
                     Activation.Native_Stage := 1;
                     State.Current.Transfer :=
                       (Kind => Resume_Requested, Results => Args,
                        Target => Thread.Reference.Context_Index);
                     Root_Barrier (State, State.Current.Transfer.Results);
                  end if;
               elsif Name = "coroutine.close" then
                  if Activation.Native_Stage = 1 then
                     Complete (Self, Activation.Native_Results);
                     return;
                  end if;
                  if Context.Status = Normal_Context then
                     Fail (State, "cannot close a normal coroutine");
                  elsif Context = State.Main_Context then
                     Fail (State, "cannot close main thread");
                  elsif Context = State.Current then
                     --  Closing oneself never returns to the abandoned
                     --  Lua/native frames, even from inside __close.
                     Context.Phase := Closing;
                     Schedule (Self, "@close.thread", Values.Empty_Vector, 0);
                     return;
                  end if;
                  --  Close requests are consumed by the same scheduler;
                  --  the scope-exit driver supplies user cleanup below.
                  Activation.Native_Stage := 1;
                  State.Current.Transfer :=
                    (Kind => Close_Requested,
                     Results => Values.Empty_Vector,
                     Target => Thread.Reference.Context_Index);
                  Root_Barrier (State, State.Current.Transfer.Results);
               else
                  raise Program_Error with "unknown coroutine operation";
               end if;
            end;
         end if;
         return;
      end if;
      if Name'Length > 6 and then Name (1 .. 6) = "debug." then
         Complete (Self, Inspection.Inspect (State, Activation));
         return;
      end if;
      if Name = "base.collectgarbage" then
         Garbage_Collection.Advance (State, Activation, Action);
      elsif Name'Length > 3 and then Name (1 .. 3) = "io." then
         Action := IO_Libraries.Advance (State, Activation);
      elsif Name'Length > 3 and then Name (1 .. 3) = "os." then
         --  Calendar table metamethods run across the native OS operation,
         --  which cannot retain a suspended C calendar conversion.
         if not Activation.Blocks_Yield then
            Activation.Blocks_Yield := True;
            State.Current.Non_Yieldable := State.Current.Non_Yieldable + 1;
         end if;
         Action := Operating_System.Advance (State, Activation);
      elsif Name = "@host.display" then
         --  Resolve print through the real environment lookup, including
         --  __index. The activation retains the chunk results across that
         --  lookup and the subsequent call, so neither phase borrows a
         --  transient host packet or reenters the executor.
         if Activation.Native_Stage = 0 then
            Packet.Append (Global_Environment (State));
            Packet.Append (New_String (State, "print"));
            Activation.Native_Stage := 1;
            Schedule (Self, "@get", Packet, 0);
         elsif Activation.Native_Stage = 1 then
            Handler := First (Activation.Native_Results);
            Activation.Native_Stage := 2;
            Dispatch (Self, Handler, Activation.Native_Arguments, 0);
         else
            Complete (Self, Values.Empty_Vector);
         end if;
         return;
      elsif Name in "@host.package.env" | "@host.package.noenv" then
         Set (State, (Table_Kind, State.Foreign_Registry),
              New_String (State, "LUA_NOENV"),
              (if Name = "@host.package.noenv" then (Boolean_Kind, True)
               else Nil_Value));
         Handler := Get (Global_Environment (State),
                         New_String (State, "package"));
         if Handler.Kind /= Table_Kind then
            Fail (State, "'package' must be a table");
         end if;
         Native_Modules.Configure_Paths
           (State, Handler, Native_Defaults => True);
         Complete (Self, Values.Empty_Vector);
         return;
      elsif Name in "@host.warning.on" | "@host.warning.off" then
         --  CLI/host controls call the warning mechanism, not the global
         --  warn function which user code can replace. Static message bytes
         --  outlive every deferred C callback; the hidden activation owns the
         --  existing allocation-free event until its guard acknowledges it.
         if Activation.Native_Stage = 0 then
            Activation.Native_Stage := 1;
            if Name = "@host.warning.on" then
               Warnings.Emit
                 (State, Byte_String'(Warning_On (Warning_On'First)'Address,
                          Warning_On'Length - 1));
            else
               Warnings.Emit
                 (State, Byte_String'(Warning_Off (Warning_Off'First)'Address,
                          Warning_Off'Length - 1));
            end if;
         else
            Complete (Self, Values.Empty_Vector);
         end if;
         return;
      elsif Name = "base.warn" then
         Action := Warnings.Advance (State, Activation);
      elsif Name = "table.create" then
         Complete (Self, Sorting.Create (State, Activation.Native_Arguments));
         return;
      elsif Name = "table.sort" then
         Action := Sorting.Advance (State, Activation);
      elsif Name in "string.gmatch" | "gmatch.iterator" | "string.gsub" then
         Action := Pattern_Drivers.Advance (State, Activation);
      elsif Name = "string.format" then
         Action := Format_Drivers.Advance (State, Activation);
      elsif Name in "table.concat" | "table.insert" | "table.remove" |
        "table.move" | "table.unpack"
      then
         Action := Table_Drivers.Advance (State, Activation);
      elsif Name in "base.load" | "base.loadfile" | "base.dofile" |
        "base.require" | "package.searchpath" |
        "package.preload_searcher" | "package.lua_searcher" |
        "package.c_searcher" | "package.croot_searcher" | "package.loadlib"
      then
         Action := Loaders.Advance (State, Activation);
      else
         Library_Step := False;
         Action.Kind := Continue_Step;
      end if;
      if State.Exit_Phase = Exit_Requested then
         --  os.exit has no Lua return path, even behind pcall. The next
         --  scheduler step consumes its typed request before any results.
         return;
      elsif Action.Kind = Finished then
         Complete (Self, Action.Results, Independent => True);
         return;
      elsif Action.Kind = Drain_Finalizers then
         --  The requesting library already saved its result/resume phase.
         --  Optional inability to run a finalizer leaves that queue intact.
         if Try_Push_Finalizers (Self) then null; end if;
         return;
      elsif Action.Kind = Start_Reader_Portal then
         --  Keep the real base.load identity, native charge and hook state.
         --  The next scheduler step exposes an ordinary guarded C request;
         --  it never enters a parser or invokes the reader from this Step.
         Activation.Load_Reader_Portal := True;
         Activation.Foreign_Handler := Reader_Portal_Address;
         return;
      elsif Action.Kind = Invoke then
         if Action.Operator /= End_Of_Input then
            --  Library continuations use the same primitive/metamethod
            --  operation as canonical instructions. Their captures already
            --  retain operands while this helper and any handler execute.
            Schedule
              (Self, (if Action.Operator = Length then "@unary" else
                        "@binary"), Action.Arguments, 0,
               Operator => Action.Operator);
         else
            Dispatch (Self, Action.Function_Value, Action.Arguments, 0);
         end if;
         return;
      elsif Library_Step then
         return;
      end if;
      if Activation.Native_Stage = 1 and then
        (Name in "@set" | "@invoke" | "@get" | "@binary" | "@unary" or else
         (Name'Length > 6 and then Name (1 .. 6) = "arith."))
      then
         if Name = "@set" then
            Complete (Self, Values.Empty_Vector);
         elsif Name = "@invoke" then
            Complete (Self, Activation.Native_Results);
         elsif Name = "@binary" and then
           Activation.Native_Operator in Equal | Not_Equal |
             Less | Less_Equal | Greater | Greater_Equal
         then
            Return_Native ((Boolean_Kind,
                     Truth (First (Activation.Native_Results)) xor
                     (Activation.Native_Operator = Not_Equal)));
         else
            Return_Native (First (Activation.Native_Results));
         end if;
         return;
      end if;
      if Name = "@invoke" then
         Handler := First (Activation.Native_Captures);
         Invoke (Handler, Activation.Native_Arguments);
      elsif API_Operation.Found then
         if Activation.Native_Stage = 0 then
            --  This metadata holder is private transport, not a public C
            --  activation. Actual caller operands stay below its function
            --  slot while the ordinary shared operator dispatches handlers.
            Activation.Native_Stage := 1;
            Schedule
              (Self,
               (if C_Operators.Unary (API_Operation.Kind) then "@unary"
                else "@binary"), Activation.Native_Arguments, 0,
               C_Operators.Token (API_Operation.Kind));
         else
            Handler := First (Activation.Native_Results);
            Return_Native (Handler);
         end if;
      elsif Name = "@argument.error" then
         if Activation.Argument_Error_Origin = null then
            raise Program_Error with "argument lookup lost its origin";
         end if;
         if Activation.Native_Stage = 0 then
            Packet.Append (Value'(Table_Kind, State.Foreign_Registry));
            Packet.Append (New_String (State, "_LOADED"));
            Activation.Native_Stage := 1;
            --  This is the normal deferred table operation, including table
            --  forwarding, Lua/C handlers, real handler origins and errors.
            --  The original C activation remains public and owns the live
            --  getfield key/function/detail slots throughout this lookup.
            Schedule (Self, "@get", Packet, 0);
         else
            declare
               Owner : constant Frame_Access :=
                 Inspection.Logical_Frame (State, State.Current, 0);
               Modules : constant Value := First (Activation.Native_Results);
               Index : Natural;
            begin
               if Owner = null or else not Owner.Is_Native or else
                 State.Current.Stack_Window /= Owner
               then
                  raise Program_Error with "argument lookup lost C window";
               end if;
               --  A completed getfield replaces its original key with the
               --  actual returned table/value before raw name search. Keep
               --  the native packet mirror coherent if this CI has one.
               Index := Owner.Stack_Live_Top - Owner.Stack_Base;
               Stacks.Write
                 (State, State.Current, Owner.Stack_Live_Top, Modules);
               if Index <= Natural (Owner.Native_Arguments.Length) then
                  Replace_Root
                    (State, Owner.Native_Arguments, Positive (Index), Modules);
               end if;
               Diagnostics.Finish_Argument_Error
                 (State, Activation.Argument_Error_Origin, Modules);
               raise Program_Error with "argument diagnostic returned";
            end;
         end if;
      elsif Name = "@api.concat" then
         if Activation.Native_Stage = 0 then
            Activation.Native_Aux := Natural
              (Activation.Native_Captures (1).Integer_Data);
            Activation.Native_Index := Natural
              (Activation.Native_Captures (2).Integer_Data);
            --  This C-dispatched private callable initially owns its real
            --  function slot. Its continuation needs metadata only; remove
            --  that window before any handler observes the original caller.
            Retire_Stack_Window (Activation);
         else
            Handler := First (Activation.Native_Results);
            Stacks.Write
              (State, State.Current, Activation.Native_Aux +
               Activation.Native_Index - 2, Handler);
            Foreign.Set_Concatenation_Top
              (State, Activation.Native_Aux + Activation.Native_Index - 2);
            Activation.Native_Results.Clear;
            Activation.Native_Index := Activation.Native_Index - 1;
         end if;
         declare
            Last : Natural :=
              Activation.Native_Aux + Activation.Native_Index - 1;
         begin
            Concatenate_Primitives (State, Activation.Native_Aux, Last);
            Activation.Native_Index := Last - Activation.Native_Aux + 1;
         end;
         if Activation.Native_Index = 1 then
            Append_Root
              (State, Activation.Native_Results,
               Stacks.Read (State.Current, Activation.Native_Aux));
            Complete (Self, Activation.Native_Results, Independent => True);
         else
            Packet.Append (Stacks.Read
              (State.Current, Activation.Native_Aux +
               Activation.Native_Index - 2));
            Packet.Append (Stacks.Read
              (State.Current, Activation.Native_Aux +
               Activation.Native_Index - 1));
            Activation.Native_Stage := 1;
            Schedule (Self, "@binary", Packet, 0, Concatenate);
         end if;
      elsif Name in "@length" | "@equal" then
         if Activation.Native_Stage = 1 then
            Return_Native (First (Activation.Native_Results));
         else
            Activation.Native_Stage := 1;
            Schedule
              (Self, (if Name = "@length" then "@unary" else "@binary"),
               Activation.Native_Arguments, 0,
               (if Name = "@length" then Length else Equal));
         end if;
      elsif Name in "math.min" | "math.max" then
         if Activation.Native_Stage = 0 then
            if Activation.Native_Arguments.Is_Empty then
               Fail (State, "value expected");
            end if;
            --  Retain the argument index, not a snapshot of its value. A
            --  comparison handler may mutate this real C temporary through
            --  debug.setlocal; both later comparisons and the final result
            --  must observe that changed slot, as lmathlib.c does.
            Activation.Native_Aux := 1;
            Activation.Native_Index := 2;
         elsif Truth (First (Activation.Native_Results)) then
            Activation.Native_Aux := Activation.Native_Index;
            Activation.Native_Index := Activation.Native_Index + 1;
         else
            Activation.Native_Index := Activation.Native_Index + 1;
         end if;
         if Activation.Native_Index >
           Natural (Activation.Native_Arguments.Length)
         then
            Return_Native (Arg (Activation.Native_Aux));
         else
            Left := Arg (Activation.Native_Aux);
            Right := Arg (Activation.Native_Index);
            Packet.Append ((if Name = "math.max" then Left else Right));
            Packet.Append ((if Name = "math.max" then Right else Left));
            Activation.Native_Stage := 1;
            Schedule (Self, "@binary", Packet, 0, Less);
         end if;
      elsif Name = "base.xpcall" then
         --  The native activation itself is the protected holder. A failing
         --  target keeps every original frame alive while Recover invokes
         --  its message handler, including recursively raised handler errors.
         if Activation.Native_Stage = 0 then
            if Natural (Activation.Native_Arguments.Length) < 2 then
               Fail (State, "xpcall needs a function and error handler");
            end if;
            if Arg (2).Kind not in Closure_Kind | Native_Closure_Kind |
              Native_Kind_Value | Foreign_Function_Kind
            then
               Fail (State, "error handler must be a function");
            end if;
            for Index in 3 ..
              Natural (Activation.Native_Arguments.Length)
            loop
               Packet.Append (Arg (Index));
            end loop;
            Activation.Error_Packet.Reserve_Capacity (2);
            Activation.Protection := Activation.Protection + 1;
            Activation.Message_Handler := Arg (2);
            Root_Barrier (State, Activation.Message_Handler);
            Activation.Native_Stage := 1;
            Stacks.Write
              (State, State.Current, Activation.Stack_Base + 3,
               (Boolean_Kind, True));
            Dispatch (Self, Arg (1), Packet, 0,
                      Call_Base => Activation.Stack_Base + 4,
                      Has_Call_Window => True);
            Activation.Native_Arguments.Clear;
         else
            Finish_Protected_Return;
         end if;
      elsif Name = "base.tostring" then
         if Activation.Native_Arguments.Is_Empty then
            Diagnostics.Argument_Error (State, 1, "value expected");
         end if;
         if Activation.Native_Stage = 1 then
            Handler := First (Activation.Native_Results);
            if Handler.Kind not in String_Kind | Integer_Kind | Real_Kind
            then
               Fail (State, "'__tostring' must return a string");
            end if;
            if Handler.Kind = String_Kind then
               --  The handler's existing string is the result, including a
               --  long string's identity. Only numbers need a conversion.
               Return_Native (Handler);
            else
               Return_Native
                 (New_String (State, Image (State.Current.Memory, Handler)));
            end if;
         else
            Handler := Metafield (State, Left, "__tostring");
            if Handler.Kind /= Nil_Kind then
               Packet.Append (Left);
               Invoke (Handler, Packet);
            elsif Left.Kind = String_Kind then
               Return_Native (Left);
            else
               Describe_Value (State, Left, Activation.Native_Buffer);
               Return_Native
                 (New_String (State, Activation.Native_Buffer));
            end if;
         end if;
      elsif Name = "base.print" then
         if Activation.Native_Stage = 1 then
            Handler := First (Activation.Native_Results);
            --  Publish each completed conversion before requesting another
            --  __tostring callback. A later callback can observe the output
            --  or fail, and neither event may erase the earlier argument.
            if Activation.Native_Index > 1 then
               Emit_Output (State, [Ada.Characters.Latin_1.HT]);
            end if;
            Emit_Output (State, Image (State.Current.Memory, Handler));
            Activation.Native_Index := Activation.Native_Index + 1;
            Activation.Native_Stage := 0;
         elsif Activation.Native_Index = 0 then
            Activation.Native_Index := 1;
         end if;
         if Activation.Native_Index >
           Natural (Activation.Native_Arguments.Length)
         then
            Emit_Output (State, [Ada.Characters.Latin_1.LF]);
            Flush_Output (State);
            Complete (Self, Values.Empty_Vector);
         else
            Packet.Append (Arg (Activation.Native_Index));
            Activation.Native_Stage := 1;
            Schedule (Self, "base.tostring", Packet, 0);
         end if;
      elsif Name = "base.pairs" then
         --  Presence is checked before metamethod lookup: an installed nil
         --  type metatable cannot turn pairs() into pairs(nil).
         if Activation.Native_Arguments.Is_Empty then
            Fail (State, "value expected");
         end if;
         if Activation.Native_Stage = 1 then
            Packet := Activation.Native_Results;
         else
            Handler := Metafield (State, Left, "__pairs");
            if Handler.Kind /= Nil_Kind then
               Packet.Append (Left);
               Invoke (Handler, Packet);
               return;
            end if;
            Packet := Native
              (Self, Pairs_Function, Activation.Native_Arguments);
         end if;
         Packet.Set_Length (4);
         Complete (Self, Packet);
      elsif Name = "base.ipairs" then
         if Activation.Native_Arguments.Is_Empty then
            Fail (State, "value expected");
         end if;
         Packet.Append (New_Native (State, "ipairs.iterator"));
         Packet.Append (Left);
         Packet.Append (Value'(Integer_Kind, 0));
         Complete (Self, Packet);
      elsif Name = "ipairs.iterator" then
         if Activation.Native_Stage = 0 then
            Right := (Integer_Kind,
              Lua.Integers.Add (Integral (State, Right), 1));
            Copy_Roots
              (State, Activation.Native_Captures,
               One_Value (State, Right, 1));
            Packet.Append (Left);
            Packet.Append (Right);
            Activation.Native_Stage := 1;
            Schedule (Self, "@get", Packet, 0);
         else
            Handler := First (Activation.Native_Results);
            if Handler.Kind /= Nil_Kind then
               Packet.Append (First (Activation.Native_Captures));
            end if;
            Packet.Append (Handler);
            Complete (Self, Packet);
         end if;
      elsif Name in "@get" | "@set" then
         loop
            if Name = "@get" then
               if Left.Kind = Table_Kind then
                  Handler := Get (Left, Right);
                  if Handler.Kind /= Nil_Kind then
                     Return_Native (Handler);
                     return;
                  end if;
               end if;
               Handler := Metafield (State, Left, "__index");
            else
               if Left.Kind = Table_Kind and then
                 Get (Left, Right).Kind /= Nil_Kind
               then
                  Set (State, Left, Right, Arg (3));
                  Complete (Self, Values.Empty_Vector);
                  return;
               end if;
               Handler := Metafield (State, Left, "__newindex");
            end if;
            if Handler.Kind = Nil_Kind then
               if Left.Kind /= Table_Kind then
                  --  Initial lookup still names its real register/upvalue.
                  --  A noncallable __index/__newindex redirects lookup to a
                  --  different object outside that operand slot, so pinned
                  --  varinfo cannot attribute the later object to the first.
                  Operand_Error
                    (State, Left, "index",
                     (if Activation.Native_Aux = 0 then 1 else 0));
               elsif Name = "@get" then
                  Return_Native (Nil_Value);
               else
                  Set (State, Left, Right, Arg (3));
                  Complete (Self, Values.Empty_Vector);
               end if;
               return;
            elsif Handler.Kind in Closure_Kind | Native_Closure_Kind |
              Native_Kind_Value | Foreign_Function_Kind
            then
               Replace_Root
                 (State, Activation.Native_Arguments,
                  1, Left);
               Invoke (Handler, Activation.Native_Arguments);
               return;
            end if;
            Activation.Native_Aux := Activation.Native_Aux + 1;
            if State.Steps >= State.Bounds.Instructions then
               Fail (State, "instruction limit exceeded", Resource => True);
            end if;
            if State.Policy = Bounded then
               State.Steps := State.Steps + 1;
            end if;
            if Activation.Native_Aux >= 2000 then
               Fail (State, "metatable index chain too long");
            end if;
            Left := Handler;
         end loop;
      elsif Name in "@binary" | "@unary" then
         if Name = "@unary" then
            Primitive := Operator = Not_Word or else
              (Operator = Length and then Left.Kind = String_Kind) or else
              (Operator = Minus and then
                 Left.Kind in Integer_Kind | Real_Kind) or else
              (Operator = Bit_Xor and then Primitive_Integer (Left));
            Event := To_Unbounded_String
              ((case Operator is
                   when Minus => "__unm", when Bit_Xor => "__bnot",
                   when Length => "__len", when others => ""));
            Right := Left;  --  Unary handlers receive duplicate operands.
         else
            Primitive :=
              (Left.Kind in Integer_Kind | Real_Kind and then
                 Right.Kind in Integer_Kind | Real_Kind) or else
              (Operator in Concatenate | Less | Less_Equal |
                 Greater | Greater_Equal and then
                 Left.Kind = String_Kind and then Right.Kind = String_Kind);
            if Operator in Bit_And | Bit_Or | Bit_Xor |
              Shift_Left | Shift_Right
            then
               Primitive := Primitive_Integer (Left) and then
                 Primitive_Integer (Right);
            elsif Operator = Concatenate then
               Primitive := Left.Kind in String_Kind | Integer_Kind |
                 Real_Kind and then Right.Kind in String_Kind |
                 Integer_Kind | Real_Kind;
            end if;
            if Operator in Equal | Not_Equal then
               Primitive := Equal (Left, Right) or else
                 Left.Kind /= Right.Kind or else
                 Left.Kind not in Table_Kind | Userdata_Kind;
            end if;
            if Operator in Greater | Greater_Equal then
               Handler := Left;
               Left := Right;
               Right := Handler;
               Operator :=
                 (if Operator = Greater then Less else Less_Equal);
            end if;
            Event := To_Unbounded_String
              ((case Operator is
                   when Plus => "__add", when Minus => "__sub",
                   when Star => "__mul", when Slash => "__div",
                   when Floor_Divide => "__idiv", when Percent => "__mod",
                   when Power => "__pow", when Bit_And => "__band",
                   when Bit_Or => "__bor", when Bit_Xor => "__bxor",
                   when Shift_Left => "__shl", when Shift_Right => "__shr",
                   when Concatenate => "__concat",
                   when Equal | Not_Equal => "__eq",
                   when Less => "__lt", when Less_Equal => "__le",
                   when others => ""));
         end if;
         if not Primitive then
            Handler := Metafield (State, Left, To_String (Event));
            if Handler.Kind = Nil_Kind and then Name = "@binary" then
               Handler := Metafield (State, Right, To_String (Event));
            end if;
            if Handler.Kind /= Nil_Kind then
               Packet.Append (Left);
               Packet.Append (Right);
               Invoke (Handler, Packet);
               return;
            elsif Name = "@binary" and then
              Operator in Equal | Not_Equal
            then
               Return_Native ((Boolean_Kind, Operator = Not_Equal));
               return;
            elsif Operator in Plus | Minus | Star | Slash | Floor_Divide |
              Percent | Power | Bit_And | Bit_Or | Bit_Xor | Shift_Left |
              Shift_Right and then
              (Left.Kind not in Integer_Kind | Real_Kind or else
               Right.Kind not in Integer_Kind | Real_Kind)
            then
               --  Raw arithmetic does not coerce strings. The installed
               --  string-library handler owns that conversion. Once both
               --  handler lookups fail, select the first non-number exactly
               --  as luaG_opinterror does, including a wrong right operand.
               Handler := (if Left.Kind in Integer_Kind | Real_Kind then
                             Right else Left);
               Operand_Error
                 (State, Handler, "perform " &
                  (if Operator in Bit_And | Bit_Or | Bit_Xor | Shift_Left |
                      Shift_Right then "bitwise operation"
                   else "arithmetic") & " on",
                  (if Left.Kind in Integer_Kind | Real_Kind then 2 else 1));
            end if;
         end if;
         Return_Native ((if Name = "@unary"
                  then Unary_Value (State, Operator, Left)
                  else Binary_Value (State, Operator, Left, Right)));
      elsif Name = "base.getmetatable" then
         if Activation.Native_Arguments.Is_Empty then
            Fail (State, "value expected");
         end if;
         Handler := Metafield (State, Left, "__metatable");
         if Handler.Kind /= Nil_Kind then
            Return_Native (Handler);
         else
            declare
               Meta : constant Object_Access := Raw_Metatable (State, Left);
            begin
               Return_Native ((if Meta = null then Nil_Value else
                                  (Table_Kind, Meta)));
            end;
         end if;
      elsif Name = "base.setmetatable" then
         if Left.Kind /= Table_Kind then
            --  Left/Right are already Value copies. A diagnostic may
            --  transfer a failed direct-builtin phase and invoke a registry
            --  callback; no vector indexing borrow may span that transfer.
            Diagnostics.Type_Error
              (State, 1, "table", Left,
               Present => not Activation.Native_Arguments.Is_Empty);
         elsif Activation.Native_Arguments.Length < 2 or else
           Right.Kind not in Nil_Kind | Table_Kind
         then
            --  luaB_setmetatable accepts an explicit nil, but not an absent
            --  second argument. Validate before the protected-metatable
            --  lookup, preserving its actual second-argument/self origin.
            Diagnostics.Type_Error
              (State, 2, "nil or table", Right,
               Present => Activation.Native_Arguments.Length >= 2);
         elsif Metafield (State, Left, "__metatable").Kind /= Nil_Kind then
            Fail (State, "cannot change a protected metatable");
         end if;
         Set_Metatable
           (State, Left, (if Right.Kind = Nil_Kind then null else
                            Right.Reference));
         Return_Native (Left);
      elsif Name'Length > 6 and then Name (1 .. 6) = "arith." then
         Event := To_Unbounded_String (Name (7 .. Name'Last));
         Operator :=
           (if Event = "__add" then Plus
            elsif Event = "__sub" or else Event = "__unm" then Minus
            elsif Event = "__mul" then Star
            elsif Event = "__mod" then Percent
            elsif Event = "__div" then Slash
            elsif Event = "__idiv" then Floor_Divide else Power);
         declare
            function Convert (Item : Value) return Lua.Numbers.Number;
            function Convert (Item : Value) return Lua.Numbers.Number is
            begin
               if Item.Kind = String_Kind then
                  return Read_Number (State, Item.Reference.Bytes);
               elsif Item.Kind = Integer_Kind then
                  return (Lua.Numbers.Integer_Number, Item.Integer_Data);
               elsif Item.Kind = Real_Kind then
                  return (Lua.Numbers.Real_Number, Item.Real_Data);
               else
                  return (Kind => Lua.Numbers.Invalid);
               end if;
            end Convert;
            function Numeric_Value (Item : Lua.Numbers.Number) return Value;
            function Numeric_Value (Item : Lua.Numbers.Number) return Value is
              (case Item.Kind is
                  when Lua.Numbers.Integer_Number =>
                     (Integer_Kind, Item.Integer_Item),
                  when Lua.Numbers.Real_Number => (Real_Kind, Item.Real_Item),
                  when Lua.Numbers.Invalid => Nil_Value);
            L : constant Lua.Numbers.Number := Convert (Left);
            R : Lua.Numbers.Number := (Kind => Lua.Numbers.Invalid);
         begin
            --  tonum(1) && tonum(2) is deliberately short-circuiting. Do not
            --  scan or charge a large rhs when lhs conversion already failed.
            --  C tonum also pushes its converted number: with one original
            --  argument that pushed value becomes index two for the next
            --  conversion. It is observable through direct handler calls.
            if L.Kind /= Lua.Numbers.Invalid then
               if Activation.Native_Arguments.Length = 1 then
                  R := L;
               else
                  R := Convert (Right);
               end if;
            end if;
            if L.Kind /= Lua.Numbers.Invalid and then
              R.Kind /= Lua.Numbers.Invalid
            then
               --  Unary lua_arith uses the top converted operand. Ordinary
               --  VM unary calls supply duplicated arguments; a direct call
               --  with two different operands must retain its second value.
               Return_Native
                 ((if Event = "__unm" then
                       Unary_Value (State, Minus, Numeric_Value (R)) else
                       Binary_Value
                         (State, Operator, Numeric_Value (L),
                          Numeric_Value (R))));
            else
               --  trymt restores exactly two original argument slots before
               --  invoking Lua. Clear extra packet and scalar roots together
               --  so a callback collection sees the same lifetime boundary.
               Set_Native_Top (State, Activation, 2);
               Handler := (if Right.Kind /= String_Kind
                           then Metafield (State, Right, To_String (Event))
                           else Nil_Value);
               if Handler.Kind = Nil_Kind then
                  Fail (State, "attempt to " &
                    Name (9 .. Name'Last) & " a '" &
                    Type_Name (Left) & "' with a '" & Type_Name (Right) & "'");
               end if;
               Packet.Append (Left);
               Packet.Append (Right);
               Invoke (Handler, Packet);
            end if;
         end;
      elsif Name in "math.random" | "math.randomseed" then
         --  Each opened math table owns one shared generator capture. The
         --  activation keeps that userdata rooted through all charged RNG
         --  work and rejection retries; another module cannot mutate it.
         Complete (Self, Mathematics.Run
           (State, Name, Activation.Native_Arguments,
            First (Activation.Native_Captures)));
      elsif Name'Length > 5 and then
        (Name (1 .. 5) = "math." or else Name (1 .. 6) = "table.")
      then
         Complete (Self, Core_Libraries.Run
           (State, Name, Activation.Native_Arguments));
      elsif Name'Length > 7 and then Name (1 .. 7) = "string." then
         if Name in "string.pack" | "string.packsize" | "string.unpack"
         then
            Complete (Self, Packing.Run
              (State, Name (8 .. Name'Last), Activation.Native_Arguments));
         else
            --  Scalar string results reuse the actual activation's owned
            --  arena. A fresh function-result vector would allocate even
            --  for a warmed plain find that only returns two integers.
            Strings.Run
              (State, Name (8 .. Name'Last), Activation.Native_Arguments,
               Activation.Native_Results);
            Complete (Self, Activation.Native_Results, Independent => True);
         end if;
      elsif Name'Length > 5 and then Name (1 .. 5) = "utf8." then
         if Name = "utf8.codes" then
            Packet.Append (New_Native
              (State, (if Truth (Arg (2)) then "utf8.lax_step"
                       else "utf8.step")));
            for Item of Unicode.Run
              (State, "codes", Activation.Native_Arguments)
            loop
               Packet.Append (Item);
            end loop;
            Complete (Self, Packet);
         elsif Name in "utf8.step" | "utf8.lax_step" then
            Packet := Activation.Native_Arguments;
            Packet.Append ((Boolean_Kind, Name = "utf8.lax_step"));
            Complete (Self, Unicode.Run (State, "step", Packet));
         else
            Complete (Self, Unicode.Run
              (State, Name (6 .. Name'Last), Activation.Native_Arguments));
         end if;
      else
         Fail (State, "native continuation not implemented: " & Name);
      end if;
   end Native_Step;

   procedure Execute_Private_Instruction (Self : Driver) is
      State : World renames Self.Universe.all;
      --  Copy the instruction before dispatch: calls may replace the
      --  current activation, and a tail call may free it entirely.
      Activation : constant Frame_Access :=
        State.Current.Stack.Last_Element;
      Code : constant Instruction := Activation.Code.Code (Activation.PC);
      A : constant Natural := Code.A;
      B : constant Natural := Code.B;
      C : constant Natural := Code.C;
      Packet : Values.Vector := Owned_Values (State);
      Left, Right, Item : Value;
      L, R, S : Lua.Numbers.Number;
      Control, Bound, Stride : Integer_Value;
      Real_Control, Real_Bound, Real_Delta : Real_Value;
   begin
      Activation.PC := Activation.PC + 1;
      State.Current.Failure_At := Code.Location;
      case Code.Op is
         when No_Operation => null;
         when Clear_Registers =>
            for Register_Id in A .. B loop
               Put_Packet (State, Activation, Register_Id,
                 Values.Empty_Vector);
            end loop;
         when Load_Value => Put_One (State, Activation, A, Code.Literal);
         when Load_String =>
            Put_One (State, Activation, A,
                     New_String (State, To_String (Code.Text)));
         when Move_First => Put_One (State, Activation, A, Scalar
           (Activation, B));
         when Read_Local =>
            Put_One (State, Activation, A, Read_Local (Activation.Scope,
              B));
         when Write_Local =>
            Write_Local (State, Activation.Scope, B, Scalar (Activation, A));
         when Declare_Local =>
            Declare_Local (State, Activation.Scope, B, Scalar
              (Activation, A));
         when Enter_Scope =>
            Activation.Scope := New_Environment (State, Activation.Scope);
            Root_Barrier (State, Activation.Scope);
            Activation.Scope_Depth := Activation.Scope_Depth + 1;
         when Leave_Scope =>
            Start_Unwind
              (Self, Activation, Scope_Exit,
               Depth => Activation.Scope_Depth - 1);
         when Goto_Label =>
            Start_Unwind
              (Self, Activation, Jump_Exit, Depth => A, PC => Code.Target,
               Live => Code.Inputs);
         when Register_Close =>
            declare
               Cell : constant Object_Access :=
                 Find_Cell (Activation.Scope, B);
               Item : constant Value := Cell.Cell_Value;
            begin
               if Truth (Item) and then
                 Metafield (State, Item, "__close").Kind = Nil_Kind
               then
                  Fail (State, "variable '" & To_String (Code.Text) &
                          "' got a non-closable value");
               end if;
               if Truth (Item) then
                  --  False/nil declarations are never enrolled for closing.
                  --  A later debug upvalue mutation cannot turn an inactive
                  --  declaration into a new close obligation.
                  Activation.Closers.Append
                    (Close_Entry'(Cell => Cell, Symbol => B,
                                  Depth => Activation.Scope_Depth,
                                  others => <>));
               end if;
            end;
         when New_Table => Put_One (State, Activation, A, New_Table
           (State));
         when Get_Item =>
            Packet.Append (Scalar (Activation, B));
            Packet.Append (Scalar (Activation, C));
            Schedule (Self, "@get", Packet, A);
         when Set_Item =>
            Packet.Append (Scalar (Activation, A));
            Packet.Append (Scalar (Activation, B));
            Packet.Append (Scalar (Activation, C));
            Schedule (Self, "@set", Packet, 0);
         when Set_Sequence =>
            Packet := Flatten (Activation, Code.Inputs, C /= 0);
            for Index in Packet.First_Index .. Packet.Last_Index loop
               Set (State, Scalar (Activation, A),
                    (Integer_Kind, Integer_Value (B + Index - 1)),
                    Packet (Index));
            end loop;
         when Unary =>
            Packet.Append (Scalar (Activation, B));
            Schedule (Self, "@unary", Packet, A, Code.Operator);
         when Binary =>
            Packet.Append (Scalar (Activation, B));
            Packet.Append (Scalar (Activation, C));
            Schedule (Self, "@binary", Packet, A, Code.Operator);
         when Jump => Activation.PC := Code.Target;
         when Jump_False | Jump_True | Jump_Nil =>
            Item := Scalar (Activation, A);
            if (Code.Op = Jump_Nil and then Item.Kind = Nil_Kind) or else
              (Code.Op = Jump_False and then not Truth (Item)) or else
              (Code.Op = Jump_True and then Truth (Item))
            then
               Activation.PC := Code.Target;
            end if;
         when Make_Closure =>
            Put_One (State, Activation, A,
                     New_Closure (State, Code.Nested, Activation.Scope));
         when Read_Varargs =>
            if Activation.Vararg_Table = null then
               Put_Packet (State, Activation, A, Activation.Varargs);
            else
               --  A named Lua 5.5 vararg table is live storage: changes
               --  to indexed values or n affect subsequent ... results.
               Left := (Table_Kind, Activation.Vararg_Table);
               Right := Get (Left, New_String (State, "n"));
               if Right.Kind /= Integer_Kind or else
                 Right.Integer_Data < 0
               then
                  Fail (State, "vararg table has no proper 'n'");
               end if;
               if Right.Integer_Data >
                 Integer_Value (State.Bounds.Table_Entries)
               then
                  Fail (State, "vararg result limit exceeded", True);
               end if;
               for Index in 1 .. Natural (Right.Integer_Data) loop
                  Packet.Append
                    (Get (Left, (Integer_Kind, Integer_Value (Index))));
               end loop;
               Put_Packet (State, Activation, A, Packet);
            end if;
         when Pick_Value =>
            Packet := Flatten (Activation, Code.Inputs);
            Put_One (State, Activation, A,
                     (if B <= Natural (Packet.Length) then Packet (B)
                      else Nil_Value));
         when Return_Values =>
            if Activation.Closers.Is_Empty then
               Complete (Self, Flatten (Activation, Code.Inputs));
            else
               Start_Unwind
                 (Self, Activation, Return_Exit, Flatten (Activation,
                   Code.Inputs));
            end if;
         when Call_Function | Tail_Call =>
            Dispatch (Self, Scalar (Activation, B),
                      Flatten (Activation, Code.Inputs), A,
                      Tail => Code.Op = Tail_Call,
                      Call_Name => Code.Text, Name_Kind => Code.Name_Kind);
         when Check_Global =>
            if Get (Scalar (Activation, A), Scalar (Activation, B)).Kind /=
              Nil_Kind
            then
               Fail (State, "global '" &
                     Image (State.Current.Memory, Scalar (Activation, B)) &
                       "' already defined");
            end if;
         when Check_Iterator =>
            Left := Scalar (Activation, A);
            if Truth (Left) then
               if Metafield (State, Left, "__close").Kind = Nil_Kind then
                  Fail (State, "non-closable iterator value");
               end if;
               declare
                  Cell : constant Object_Access := New_Environment
                    (State, null);
               begin
                  --  A hidden environment cell roots the iterator's fourth
                  --  result for the entire loop, not just one iteration.
                  Declare_Local (State, Cell, 1, Left);
                  Activation.Closers.Append
                    (Close_Entry'(Cell => Find_Cell (Cell, 1), Symbol => 0,
                                  Depth => Activation.Scope_Depth,
                                  others => <>));
               end;
            end if;
         when For_Initialize =>
            Left := Scalar (Activation, Code.D);
            Right := Scalar (Activation, Code.Inputs (2));
            L := Numeric (State, Left);
            R := Numeric (State, Scalar (Activation, Code.Inputs (1)));
            S := Numeric (State, Right);
            if Left.Kind = Integer_Kind and then Right.Kind = Integer_Kind
            then
               Control := L.Integer_Item;
               Stride := S.Integer_Item;
               if Stride = 0 then
                  Fail (State, "for step is zero");
               end if;
               Put_One (State, Activation, A, (Integer_Kind, Control));
               Put_One (State, Activation, C, (Integer_Kind, Stride));
               if R.Kind = Lua.Numbers.Integer_Number then
                  Bound := R.Integer_Item;
               else
                  Real_Bound := R.Real_Item;
                  --  Integer loops round a float bound toward the valid
                  --  side of the interval, saturating finite overflow.
                  --  NaN or an entirely unreachable bound marks an empty
                  --  loop with nil, without an unsafe signed conversion.
                  if Real_Bound /= Real_Bound or else
                    (Stride > 0 and then Real_Bound < -2.0 ** 63) or else
                    (Stride < 0 and then Real_Bound >= 2.0 ** 63)
                  then
                     Put_One (State, Activation, A, Nil_Value);
                     Bound := 0;
                  elsif Real_Bound >= 2.0 ** 63 then
                     Bound := Integer_Value'Last;
                  elsif Real_Bound <= -2.0 ** 63 then
                     Bound := Integer_Value'First;
                  else
                     Bound := Integer_Value
                       (if Stride > 0 then Real_Value'Floor (Real_Bound)
                        else Real_Value'Ceiling (Real_Bound));
                  end if;
               end if;
               Put_One (State, Activation, B, (Integer_Kind, Bound));
            else
               Real_Delta := Lua.Numbers.To_Real (S);
               if Real_Delta = 0.0 then
                  Fail (State, "for step is zero");
               end if;
               Put_One (State, Activation, A,
                        (Real_Kind, Lua.Numbers.To_Real (L)));
               Put_One (State, Activation, B,
                        (Real_Kind, Lua.Numbers.To_Real (R)));
               Put_One (State, Activation, C, (Real_Kind, Real_Delta));
            end if;
         when For_Test =>
            Left := Scalar (Activation, A);
            if Left.Kind = Nil_Kind then
               Activation.PC := Code.Target;
            elsif Left.Kind = Integer_Kind then
               Control := Left.Integer_Data;
               Bound := Scalar (Activation, B).Integer_Data;
               Stride := Scalar (Activation, C).Integer_Data;
               if (Stride > 0 and then Control > Bound) or else
                 (Stride < 0 and then Control < Bound)
               then
                  Activation.PC := Code.Target;
               end if;
            else
               Real_Control := Left.Real_Data;
               Real_Bound := Scalar (Activation, B).Real_Data;
               Real_Delta := Scalar (Activation, C).Real_Data;
               if not (if Real_Delta > 0.0 then Real_Control <= Real_Bound
                       else Real_Control >= Real_Bound)
               then
                  Activation.PC := Code.Target;
               end if;
            end if;
         when For_Advance =>
            Left := Scalar (Activation, A);
            if Left.Kind = Integer_Kind then
               Control := Left.Integer_Data;
               Stride := Scalar (Activation, C).Integer_Data;
               --  The loop counter must stop before signed wraparound,
               --  Ordinary Lua integer arithmetic intentionally wraps;
               --  a numeric-for control variable must instead terminate.
               if (Stride > 0 and then
                 Control > Integer_Value'Last - Stride)
                 or else (Stride < 0 and then
                   Control < Integer_Value'First - Stride)
               then
                  Activation.PC := Code.D;
                  return;
               end if;
               Put_One (State, Activation, A, (Integer_Kind, Control +
                 Stride));
            else
               Put_One (State, Activation, A,
                 (Real_Kind,
                  Left.Real_Data + Scalar (Activation, C).Real_Data));
            end if;
            Activation.PC := Code.Target;
      end case;
   end Execute_Private_Instruction;

   procedure Execute_Instruction (Self : Driver) is
      State : World renames Self.Universe.all;
      Activation : constant Frame_Access :=
        State.Current.Stack.Last_Element;
   begin
      if Activation.Code.Canonical_Node = null then
         Execute_Private_Instruction (Self);
         return;
      end if;
      declare
         Next : constant Canonical.Action :=
           Canonical.Step (State, Activation);
      begin
         --  Canonical.Step returns before any Lua/native callable runs. Its
         --  frame owns every requested argument and outgoing result while
         --  this bridge publishes the next scheduler activation.
         case Next.Kind is
            when Canonical.Advanced => null;
            when Canonical.Invoke_Helper =>
               Schedule (Self, To_String (Next.Helper), Next.Arguments,
                         Next.Destination, Next.Operator);
               --  Schedule published its owned packet before this bridge
               --  retires the request. Original register/upvalue edges stay
               --  authoritative, including debug mutations during handlers.
               Activation.Native_Arguments.Clear;
            when Canonical.Invoke_Function =>
               --  The source frame roots its retained argument packet until
               --  Dispatch publishes the callee. A separate Action copy
               --  would allocate even for a warmed zero-growth C callback.
               Dispatch (Self, Next.Function_Value,
                         Activation.Native_Arguments,
                         Next.Destination,
                         Call_Base => Next.Call_Base,
                         Has_Call_Window => Next.Has_Call_Window);
               Activation.Native_Arguments.Clear;
               Activation.Native_Captures.Clear;
            when Canonical.Tail_Invoke =>
               if not Activation.Closers.Is_Empty then
                  --  The compiler never emits TAILCALL while a TBC slot is
                  --  live. Reject an imported contradictory sequence rather
                  --  than retire that slot without invoking its handler.
                  Fail (State, "canonical tail call has pending close values");
               end if;
               --  Dispatch owns a copy before retiring a tail/metacall
               --  source, while ordinary calls can borrow it synchronously.
               Dispatch (Self, Next.Function_Value,
                         Activation.Native_Arguments,
                         Next.Destination, Tail => True,
                         Call_Base => Next.Call_Base,
                         Has_Call_Window => Next.Has_Call_Window);
            when Canonical.Return_Results =>
               if Activation.Closers.Is_Empty then
                  Complete (Self, Next.Arguments);
               else
                  Start_Unwind
                    (Self, Activation, Return_Exit, Next.Arguments);
               end if;
            when Canonical.Close_From_Register =>
               Start_Unwind (Self, Activation, Scope_Exit,
                             Depth => Next.Close_From);
         end case;
      end;
   end Execute_Instruction;

   function Advance_Process_Exit (Self : in out Driver) return Boolean;
   function Advance_Process_Exit (Self : in out Driver) return Boolean is
      State : World renames Self.Universe.all;
      function Every_Object (Item : Object_Access) return Boolean;
      function Every_Object (Item : Object_Access) return Boolean is
        (Item /= null);

      procedure Finish_Exit;
      procedure Finish_Exit is
      begin
         --  A false close flag abandons execution, not the owned universe.
         --  An Ada host may inspect the typed request and later reuse/reset
         --  its session. No Lua callback may resume this execution chain.
         while State.Current /= null loop
            declare
               Context : constant Context_Access := State.Current;
               Parent : constant Context_Access := Context.Resumer;
            begin
               Clear_Frames (State);
               Context.Resumer := null;
               Context.Status := Dead_Context;
               Context.Phase := Executing;
               Context.Transfer.Kind := No_Transfer;
               Context.Transfer.Target := 0;
               Context.Transfer.Results.Clear;
               exit when Parent = null;
               State.Current := Parent;
            end;
         end loop;
         State.Current := Self.Root_Context;
         Self.Root_Context.Transfer :=
           (Kind => Process_Stopped, others => <>);
         Root_Barrier (State, Self.Root_Context.Transfer.Results);
         State.Exit_Phase := Exit_Complete;
         Self.Done := True;
      end Finish_Exit;
   begin
      if State.Exit_Phase = Exit_Requested then
         if not State.Exit_Close_State then
            Finish_Exit;
            return True;
         end if;
         --  lua_close always closes the main thread, even when os.exit is
         --  called from a coroutine. Retire the active child chain without
         --  running its TBC handlers; suspended Lua-owned threads are later
         --  reclaimed through ordinary world ownership.
         while State.Current /= State.Main_Context loop
            declare
               Child : constant Context_Access := State.Current;
               Parent : constant Context_Access := Child.Resumer;
            begin
               Clear_Frames (State);
               Child.Resumer := null;
               Child.Status := Dead_Context;
               Child.Transfer.Kind := No_Transfer;
               Child.Transfer.Target := 0;
               Child.Transfer.Results.Clear;
               State.Current :=
                 (if Parent = null then State.Main_Context else Parent);
            end;
         end loop;
         State.State_Close_Phase := True;
         State.Current.Status := Running_Context;
         State.Current.Phase := Closing;
         State.Current.Resumer := null;
         State.Current.Failure := Nil_Value;
         Root_Barrier (State, State.Current.Failure);
         State.Current.Has_Failure_Value := False;
         State.Current.Failure_Class := No_Failure;
         State.Current.Transfer.Kind := No_Transfer;
         State.Current.Transfer.Target := 0;
         State.Current.Transfer.Results.Clear;
         --  Repeated os.exit(true) starts a new close walk over the remaining
         --  actual frames. Consumed close entries/finalizer queue nodes have
         --  already been removed, so they cannot run twice.
         State.Exit_Phase := Closing_Main;
         Schedule (Self, "@close.thread", Values.Empty_Vector, 0);
         return True;
      elsif State.Exit_Phase = Closing_Main and then
        State.Current.Transfer.Kind in Completed | Lua_Raised
      then
         State.Current.Transfer.Kind := No_Transfer;
         State.Current.Transfer.Target := 0;
         State.Current.Transfer.Results.Clear;
         State.Current.Failure := Nil_Value;
         Root_Barrier (State, State.Current.Failure);
         State.Current.Has_Failure_Value := False;
         State.Current.Failure_Class := No_Failure;
         State.Exit_Phase := Draining_Exit_Finalizers;
         Finalizers.Queue_Unreachable
           (State, Every_Object'Access, All_Objects => True);
         if not Try_Push_Finalizers (Self) then Finish_Exit; end if;
         return True;
      elsif State.Exit_Phase = Draining_Exit_Finalizers and then
        State.Current.Transfer.Kind in Completed | Lua_Raised
      then
         --  Errors in individual finalizers were protected and warned by
         --  their controller. They never replace the process status code.
         Finish_Exit;
         return True;
      end if;
      return False;
   end Advance_Process_Exit;

   procedure Scheduler_Step (Self : in out Driver) is
      State : World renames Self.Universe.all;
   begin
      if Advance_Process_Exit (Self) then return; end if;
      --  All cross-context movement occurs here. A suspended native
      --  activation owns its resume destination; no Ada frame survives a
      --  yield and no nested scheduler restarts an execution budget.
      if State.Current.Transfer.Kind in Resume_Requested |
        Close_Requested
      then
         declare
            Caller : constant Context_Access := State.Current;
            Request : constant Control_Transfer := Caller.Transfer;
            Target : constant Context_Access :=
              State.Contexts (Request.Target);
            Fresh : constant Boolean := Target.Status = New_Context;
         begin
            Pin (State, Request.Results);
            Caller.Transfer.Kind := No_Transfer;
            Caller.Transfer.Target := 0;
            Caller.Transfer.Results.Clear;
            if State.Native_Depth + Target.Native_Depth >=
              Lua.Runtime_Configuration.Maximum_C_Calls
            then
               Fail (State, "C stack overflow");
            end if;
            Caller.Status := Normal_Context;
            Target.Resumer := Caller;
            State.Current := Target;
            State.Native_Depth := State.Native_Depth +
              Target.Native_Depth;
            Target.Status := Running_Context;
            Target.Hook_Suspended := False;
            if Target.Detached_Resume_Window then
               --  A thread last driven by lua_resume exposes its delivery
               --  in a detached public window. Lua resume/close can also
               --  take over that thread; restore its retained activation
               --  view before supplying arguments or starting cleanup.
               Target.Foreign_Activation := Target.Resume_Foreign_Activation;
               Target.Foreign_View := Target.Resume_Foreign_View;
               Target.Foreign_Base := Target.Resume_Foreign_Base;
               Target.Foreign_Top := Target.Resume_Foreign_Top;
               Target.Stack_Used := Target.Resume_Stack_Used;
               Target.Host_Stack_Top := Target.Resume_Host_Stack_Top;
               Target.Resume_Foreign_Activation := null;
               Target.Resume_Foreign_View := null;
               Target.Detached_Resume_Window := False;
            end if;
            if Request.Kind = Close_Requested then
               Target.Phase := Closing;
               Target.Entry_Function := Nil_Value;
               Root_Barrier (State, Target.Entry_Function);
               Schedule (Self, "@close.thread", Values.Empty_Vector, 0);
            elsif Fresh then
               Dispatch (Self, Target.Entry_Function, Request.Results, 0);
               Target.Entry_Function := Nil_Value;
               Root_Barrier (State, Target.Entry_Function);
            elsif Target.Stack.Last_Element.Is_Native then
               Copy_Roots
                 (State, Target.Stack.Last_Element.Native_Results,
                  Request.Results);
            else
               --  A yielded C hook interrupts a Lua instruction rather than
               --  a call result. Resume arguments are discarded, not retained
               --  as invisible roots on that Lua frame.
               Target.Stack.Last_Element.Native_Results.Clear;
            end if;
         end;
      elsif State.Current.Transfer.Kind in Completed | Yielded |
        Lua_Raised
      then
         declare
            Child : constant Context_Access := State.Current;
            Kind : constant Transfer_Kind := Child.Transfer.Kind;
            Parent : constant Context_Access := Child.Resumer;
            Reset_Error : constant Boolean := Child.C_Reset_Error;
            Receiver : Frame_Access;
            Delivery_Error : Boolean := False;

            function Can_Return_Results return Boolean;
            function Can_Return_Results return Boolean is
               Name : constant String := Native_Operation_Name (Receiver);
               Window : constant Frame_Access :=
                 (if Receiver.Has_Stack_Window then Receiver else
                    Stack_Views.Physical_Owner (Parent));
               Base : constant Natural :=
                 (if Window = null then Parent.Foreign_Base
                  else Window.Stack_Base);
               Extra : constant Positive :=
                 (if Name = "coroutine.resume" then 2 else 1);
               Count : constant Natural :=
                 Natural (Child.Transfer.Results.Length);
               Last : Natural;
            begin
               if Kind = Lua_Raised or else Reset_Error or else
                 Name not in "coroutine.resume" | "coroutine.wrapped"
               then
                  return True;
               end if;
               --  auxresume checks nres+1 above the C function's remaining
               --  prefix before moving any values. resume retains its thread
               --  argument; wrapped has consumed all ordinary arguments.
               --  This is the real recipient reservation, including a direct
               --  builtin call borrowing a C/Lua view, not the child's room.
               if Base > Natural'Last - Extra or else
                 Count > Natural'Last - Base - Extra
               then
                  return False;
               end if;
               Last := Base + Count + Extra;
               if not Ensure_Stack
                 (State, Parent, Last, Raise_Error => False)
               then
                  return False;
               end if;
               if Window /= null then
                  Resize_Stack_Window
                    (State, Window, Natural'Max
                       (Window.Stack_Window_Length, Last - Base));
               else
                  Parent.Stack_Used := Natural'Max
                    (Parent.Stack_Used, Last);
               end if;
               return True;
            end Can_Return_Results;
         begin
            if Parent /= null then
               if Parent.Stack.Is_Empty then
                  raise Program_Error with "coroutine recipient is missing";
               end if;
               Receiver := Parent.Stack.Last_Element;
               Delivery_Error := not Can_Return_Results;
               if State.Policy = Bounded then
                  declare
                     Raw_Count : constant Ada.Containers.Count_Type :=
                       Child.Transfer.Results.Length;
                     Published_Count : constant Ada.Containers.Count_Type :=
                       (if Reset_Error or else Delivery_Error then 2
                        else Raw_Count + 1);
                     Work : constant Ada.Containers.Count_Type :=
                       Raw_Count + 2 * Published_Count;
                  begin
                     --  Meter the real pin/barrier/receiver passes, not the
                     --  eliminated controlled-record snapshot. Keep the
                     --  original transfer intact if this quota rejects it.
                     if Work > Ada.Containers.Count_Type
                       (State.Bounds.Instructions - Natural'Min
                          (State.Steps, State.Bounds.Instructions))
                     then
                        Fail (State, "instruction limit exceeded", True);
                     end if;
                     State.Steps := State.Steps + Natural (Work);
                  end;
               end if;
               if not Delivery_Error then
                  Pin (State, Child.Transfer.Results);
               end if;
               Child.Transfer.Kind := No_Transfer;
               Child.Transfer.Target := 0;
            end if;
            Child.Status :=
              (if Kind = Yielded then Suspended_Context
               else Dead_Context);
            if Kind = Yielded and then Parent /= null then
               --  Lua's resumer consumes the yielded values. Expose an empty
               --  C API window above the retained frames so later public
               --  pushes (or a C takeover of resume) cannot overwrite them.
               Child.Resume_Foreign_Activation := Child.Foreign_Activation;
               Child.Resume_Foreign_View := Child.Foreign_View;
               Child.Resume_Foreign_Base := Child.Foreign_Base;
               Child.Resume_Foreign_Top := Child.Foreign_Top;
               Child.Resume_Stack_Used := Child.Stack_Used;
               Child.Resume_Host_Stack_Top := Child.Host_Stack_Top;
               Child.Resume_Return_Base := 0;
               Child.Resume_Return_Top := Child.Host_Stack_Top;
               Child.Foreign_Activation := null;
               Child.Foreign_View := null;
               Child.Foreign_Base := Child.Stack_Used;
               Child.Foreign_Top := Child.Foreign_Base;
               Child.Host_Stack_Top := Child.Foreign_Top;
               Child.Detached_Resume_Window := True;
            end if;
            if Kind /= Yielded then
               --  Closing is an execution phase, not a permanent dead
               --  thread attribute observed by later boundary queries.
               Child.Phase := Executing;
            end if;
            if Parent = null then
               --  The root already owns its complete packet. Copying the
               --  controlled transfer record here would allocate merely to
               --  report success, even after a permanently refusing C body.
               Self.Done := True;
               return;
            end if;
            State.Native_Depth := State.Native_Depth -
              Child.Native_Depth;
            Child.Resumer := null;
            State.Current := Parent;
            Parent.Status := Running_Context;
            --  Publish directly into the real receiver's retained packet.
            --  The child remains an owner until this publication finishes;
            --  a separate controlled transfer/temporary vector is needless.
            Receiver.Native_Results.Reserve_Capacity
              ((if Reset_Error or else Delivery_Error then 2
                else Child.Transfer.Results.Length + 1));
            Receiver.Native_Results.Clear;
            Append_Root
              (State, Receiver.Native_Results,
               (Boolean_Kind, Kind /= Lua_Raised and then not Delivery_Error));
            if Delivery_Error then
               Child.Transfer.Results.Clear;
               Append_Root
                 (State, Receiver.Native_Results,
                  New_String (State, "too many results to resume"));
            elsif Reset_Error then
               Append_Root (State, Receiver.Native_Results, Child.Failure);
               Child.C_Reset_Error := False;
            else
               Append_Root
                 (State, Receiver.Native_Results, Child.Transfer.Results);
            end if;
            Receiver.Result_Failure_Class :=
              (if not Delivery_Error and then
                   (Kind = Lua_Raised or else Reset_Error)
               then Child.Failure_Class else No_Failure);
            Receiver.Result_Handler_Called :=
              not Delivery_Error and then
              (Kind = Lua_Raised or else Reset_Error) and then
              Child.Failure_Handled;
            --  Preserve the original child packet until the actual receiver
            --  owns every result. Only scalar transfer metadata is snapshotted
            --  above; the ordinary root path needs no duplicate value buffer.
            Child.Transfer.Results.Clear;
         end;
      else
         if not State.State_Close_Phase and then
           not State.Current.Error_Recovery_Pending
         then
            Poll_Collection (State);
         end if;
         if not State.Current.Error_Recovery_Pending and then
           State.Finalizers_Requested and then
           not State.Finalizer_Active and then
           State.Current.Stack.Last_Element.Native_Name /= "@gc.finalize"
           and then Try_Push_Finalizers (Self, Silent => True)
         then
            return;
         end if;
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         if State.Policy = Bounded then
            State.Steps := State.Steps + 1;
         end if;
         begin
            if State.Current.Error_Recovery_Pending then
               --  The C guard has already returned and scopes have been
               --  restored. Use the normal scheduler's error protocol before
               --  any hook, finalizer or old instruction can be considered.
               State.Current.Error_Recovery_Pending := False;
               Recover
                 (Self, Prefix_Floor => State.Current.Error_Recovery_Floor);
            elsif State.Current.Stack.Last_Element.External_Return_Pending then
               State.Current.Stack.Last_Element.External_Return_Pending :=
                 False;
               if State.Current.Stack.Last_Element.
                 External_Return_Independent
               then
                  --  This retained range is already the complete packet;
                  --  a hook reconstruction may include protection prefixes.
                  Complete_Packet
                    (Self, State.Current.Stack.Last_Element.Unwind_Results,
                     State.Current.Stack.Last_Element.Unwind_Results);
               else
                  Complete
                    (Self, State.Current.Stack.Last_Element.Unwind_Results);
               end if;
            elsif State.Current.Stack.Last_Element.Native_Tail_State =
              Ready_Native_Tail
            then
               declare
                  Owner : constant Frame_Access :=
                    State.Current.Stack.Last_Element;
                  Count : constant Natural :=
                    Natural (Owner.Native_Results.Length);
               begin
                  if Owner.Has_Stack_Window then
                     --  A native tail callee has returned into this retained
                     --  Lua frame. Its delivery packet must be published in
                     --  the original CALL A range before a Lua return hook
                     --  can inspect or edit the real cells. The native
                     --  callee's retired window no longer owns those slots.
                     --  Keep the packet rooted until reservation succeeds.
                     if Count > Natural'Last - Owner.Canonical_Base then
                        Fail (State, "stack overflow");
                     elsif State.Policy = Bounded then
                        if Count > State.Bounds.Instructions - Natural'Min
                          (State.Steps, State.Bounds.Instructions)
                        then
                           Fail (State, "instruction limit exceeded", True);
                        end if;
                        State.Steps := State.Steps + Count;
                     end if;
                     Resize_Stack_Window
                       (State, Owner, Natural'Max
                          (Owner.Stack_Window_Length,
                           Owner.Canonical_Base + Count));
                     for Index in 1 .. Count loop
                        Stacks.Write
                          (State, State.Current,
                           Owner.Stack_Base + Owner.Canonical_Base + Index,
                           Owner.Native_Results.Element (Index));
                     end loop;
                     Owner.Canonical_GC_Top := Owner.Canonical_Base + Count;
                     Owner.Transfer_First := Owner.Canonical_Base + 1;
                     Owner.Transfer_Count := Count;
                     Owner.Return_Window_Published := True;
                  end if;
               end;
               Complete
                 (Self, State.Current.Stack.Last_Element.Native_Results);
            elsif Before_Step (Self) then
               null;
            elsif State.Current.Hook_Yield_Pending and then
              not State.Current.Hook_Active
            then
               --  Native traceexec delivers a due count and line event for
               --  one instruction before acting on a hook's yield request.
               --  The interrupted instruction has still not executed.
               State.Current.Hook_Yield_Pending := False;
               State.Current.Hook_Suspended := True;
               State.Current.Hook_Frame := State.Current.Stack.Last_Element;
               State.Current.Transfer.Kind := Yielded;
               State.Current.Transfer.Results.Clear;
            elsif State.Current.Stack.Last_Element.Is_Native then
               Native_Step (Self);
            else
               State.Current.Stack.Last_Element.Hook_PC := 0;
               State.Current.Stack.Last_Element.Line_Hook_Checked :=
                 False;
               State.Current.Stack.Last_Element.Last_Executed_PC :=
                 State.Current.Stack.Last_Element.PC;
               Execute_Instruction (Self);
            end if;
         exception
            when Diagnostics.Deferred_Argument_Error =>
               declare
                  Origin : constant Frame_Access :=
                    State.Current.Stack.Last_Element;
               begin
                  if Origin.Argument_Error_Index = 0 then
                     raise Program_Error with "unowned argument lookup";
                  end if;
                  Schedule (Self, "@argument.error", Values.Empty_Vector, 0);
                  State.Current.Stack.Last_Element.Argument_Error_Origin :=
                    Origin;
                  --  luaL_argerror is a synchronous C operation. Its lookup
                  --  can reenter Lua but cannot yield across that actual
                  --  operation; this continuation owns and retires the
                  --  precise barrier even on callback error/host abort.
                  State.Current.Stack.Last_Element.Blocks_Yield := True;
                  State.Current.Non_Yieldable :=
                    State.Current.Non_Yieldable + 1;
               end;
            when Error : Language_Error |
              Lua.Storage.Allocation_Error | Program_Error =>
               if Lua.Storage.Refusal_Pending (State.Memory) or else
                 Ada.Exceptions.Exception_Identity (Error) =
                   Lua.Storage.Allocation_Error'Identity
               then
                  Record_Memory_Error (State);
               elsif Ada.Exceptions.Exception_Identity (Error) =
                 Program_Error'Identity
               then
                  raise;
               end if;
               begin
                  Recover (Self);
               exception
                  when Language_Error =>
                     if State.Current.Failure_Class = Host_Abort or else
                       State.Current = Self.Root_Context
                     then
                        raise;
                     end if;
                     if not State.Current.Has_Failure_Value then
                        State.Current.Failure :=
                          Ensure_Error_Object (State, State.Current);
                        Root_Barrier (State, State.Current.Failure);
                        State.Current.Has_Failure_Value := True;
                     end if;
                     State.Current.Transfer :=
                       (Kind => Lua_Raised,
                        Results => One_Value
                          (State.Current.Memory, State.Current.Failure, 1),
                        Target => 0);
                     Root_Barrier (State, State.Current.Transfer.Results);
               end;
         end;
      end if;
   exception
      when Error : Language_Error | Lua.Storage.Allocation_Error |
        Program_Error =>
         if Lua.Storage.Refusal_Pending (State.Memory) or else
           Ada.Exceptions.Exception_Identity (Error) =
             Lua.Storage.Allocation_Error'Identity
         then
            Record_Memory_Error (State);
         elsif Ada.Exceptions.Exception_Identity (Error) =
           Program_Error'Identity
         then
            raise;
         end if;
         begin
            Recover (Self);
         exception
            when Language_Error =>
               if State.Current.Failure_Class = Host_Abort or else
                 State.Current = Self.Root_Context
               then
                  raise;
               end if;
               if not State.Current.Has_Failure_Value then
                  State.Current.Failure :=
                    Ensure_Error_Object (State, State.Current);
                  Root_Barrier (State, State.Current.Failure);
                  State.Current.Has_Failure_Value := True;
               end if;
               State.Current.Transfer :=
                 (Kind => Lua_Raised,
                  Results => One_Value
                    (State.Current.Memory, State.Current.Failure, 1),
                  Target => 0);
               Root_Barrier (State, State.Current.Transfer.Results);
         end;
   end Scheduler_Step;

   procedure Abandon (Self : Driver) is
      State : World renames Self.Universe.all;
   begin
      --  A host abort invalidates this active resume chain as a unit.
      --  Abandoned continuations cannot be resumed to evade the quota.
      if State.Current /= Self.Root_Context then
         Self.Root_Context.Failure := State.Current.Failure;
         Root_Barrier (State, Self.Root_Context.Failure);
         Self.Root_Context.Has_Failure_Value :=
           State.Current.Has_Failure_Value;
         Self.Root_Context.Failure_Text := State.Current.Failure_Text;
         Self.Root_Context.Failure_Class := State.Current.Failure_Class;
         Self.Root_Context.Failure_At := State.Current.Failure_At;
      end if;
      while State.Current /= Self.Root_Context loop
         declare
            Child : constant Context_Access := State.Current;
            Parent : constant Context_Access := Child.Resumer;
         begin
            Clear_Frames (State);
            Child.Status := Dead_Context;
            Child.Phase := Executing;
            Child.Resumer := null;
            State.Current := Parent;
         end;
      end loop;
   end Abandon;

   procedure Prepare
     (Self : in out Driver; Universe : not null World_View;
      Retained_Depth : Natural := 0)
   is
   begin
      if Self.Universe /= null or else Universe.Current = null or else
        Natural (Universe.Current.Stack.Length) /= Retained_Depth
      then
         raise Program_Error with "invalid VM driver start";
      end if;
      Self.Universe := Universe;
      Self.Root_Context := Universe.Current;
      Self.Entry_Depth := Retained_Depth;
      Self.Done := False;
      Self.Failed := False;
   end Prepare;

   procedure Start_Borrowed
     (Self : in out Driver; Universe : not null World_View;
      Code : Prototype_Access; Function_Value : Value;
      Arguments : Values.Vector)
   is
      State : World renames Universe.all;
      Callee : Value := Function_Value;
      Prepared : Boolean := False;
   begin
      Prepare (Self, Universe);
      Prepared := True;
      Begin_Operation (State);
      State.Current.Transfer.Kind := No_Transfer;
      State.Current.Transfer.Target := 0;
      State.Current.Transfer.Results.Clear;
      if Code /= null then
         Pin (State, Code);
         Callee := New_Closure (State, Code, null);
      end if;
      --  Dispatch publishes the call into owned frames. The operation epoch
      --  protects construction and pins existing arguments before any frame
      --  replacement or allocator-triggered emergency collection can occur.
      Dispatch (Self, Callee, Arguments, 0);
      End_Operation (State);
   exception
      when others =>
         if Prepared then
            End_Operation (State);
            Self.Failed := True;
            Abandon (Self);
         end if;
         raise;
   end Start_Borrowed;

   procedure Start
     (Self : in out Driver; State : not null World_Access;
      Code : Prototype_Access)
   is
   begin
      Start_Borrowed
        (Self, World_View (State), Code, Nil_Value,
         State.Current.Arguments);
   end Start;

   procedure Start
     (Self : in out Driver; State : not null World_Access;
      Function_Value : Value; Arguments : Values.Vector)
   is
   begin
      Start_Borrowed
        (Self, World_View (State), null, Function_Value, Arguments);
   end Start;

   procedure Start_Foreign
     (Self : in out Driver; State : in out World;
      Callee : Value; Arguments : Values.Vector;
      Message_Handler : Value := Nil_Value;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False;
      Retained_Depth : Natural := 0; Direct_Builtin : Boolean := False)
   is
      Packet : Values.Vector := Owned_Values (State);
      Prepared : Boolean := False;
   begin
      Prepare
        (Self, World_View (World_Addresses.To_Pointer (State'Address)),
         Retained_Depth);
      Prepared := True;
      Begin_Operation (State);
      State.Current.Transfer.Kind := No_Transfer;
      State.Current.Transfer.Target := 0;
      State.Current.Transfer.Results.Clear;
      Pin (State, Callee);
      Pin (State, Arguments);
      Pin (State, Message_Handler);
      Packet.Append (Callee);
      for Argument of Arguments loop
         Packet.Append (Argument);
      end loop;
      --  This holder exists before the target is dispatched, so even a call
      --  to a non-callable value has a real protected handler boundary. No
      --  synthetic heap closure or second executor is needed for C entry.
      Schedule (Self, "@foreign.entry", Packet, 0);
      State.Current.Stack.Last_Element.Native_Builtin_Direct :=
        Direct_Builtin;
      State.Current.Stack.Last_Element.Foreign_Previous_Frame :=
        State.Current.Foreign_Activation;
      State.Current.Stack.Last_Element.Native_Index := Call_Base;
      State.Current.Stack.Last_Element.Native_Aux :=
        Boolean'Pos (Has_Call_Window);
      State.Current.Stack.Last_Element.Error_Packet.Reserve_Capacity (2);
      State.Current.Stack.Last_Element.Protection := 1;
      State.Current.Stack.Last_Element.Message_Handler := Message_Handler;
      Root_Barrier
        (State, State.Current.Stack.Last_Element.Message_Handler);
      End_Operation (State);
   exception
      when others =>
         if Prepared then
            End_Operation (State);
            Self.Failed := True;
            Abandon (Self);
         end if;
         raise;
   end Start_Foreign;

   procedure Start_Foreign
     (Self : in out Driver; State : not null World_Access;
      Callee : Value; Arguments : Values.Vector;
      Message_Handler : Value := Nil_Value;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False;
      Retained_Depth : Natural := 0; Direct_Builtin : Boolean := False)
   is
   begin
      Start_Foreign
        (Self, State.all, Callee, Arguments, Message_Handler, Call_Base,
         Has_Call_Window, Retained_Depth, Direct_Builtin);
   end Start_Foreign;

   procedure Start_Resume
     (Self : in out Driver; State : in out World;
      Callee : Value; Arguments : Values.Vector;
      Fresh : Boolean; Call_Base : Natural := 0)
   is
   begin
      if Self.Universe /= null then
         raise Program_Error with "active C resume driver";
      end if;
      Self.Universe := World_View
        (World_Addresses.To_Pointer (State'Address));
      Self.Root_Context := State.Current;
      Self.Done := False;
      Self.Failed := False;
      Begin_Operation (State);
      State.Current.Transfer.Kind := No_Transfer;
      State.Current.Transfer.Results.Clear;
      State.Current.Status := Running_Context;
      State.Current.Hook_Suspended := False;
      State.Current.C_Resuming := True;
      State.Current.C_Reset_Self := False;
      State.Current.Resumer := null;
      if Fresh then
         Dispatch (Self, Callee, Arguments, 0,
                   Call_Base => Call_Base, Has_Call_Window => True);
         State.Current.Entry_Function := Nil_Value;
      elsif State.Current.Stack.Last_Element.Is_Native then
         Copy_Roots
           (State, State.Current.Stack.Last_Element.Native_Results,
            Arguments);
      else
         State.Current.Stack.Last_Element.Native_Results.Clear;
      end if;
      End_Operation (State);
   exception
      when others =>
         End_Operation (State);
         Self.Failed := True;
         raise;
   end Start_Resume;

   function Has_Thread_Closers (Context : not null Context_Access)
                                return Boolean
   is
      function Pending (Item : not null Frame_Access) return Boolean;
      function Pending (Item : not null Frame_Access) return Boolean is
         Child : Frame_Access := Item.Deferred_Error_Head;
      begin
         if Item.C_Closing_Level /= 0 or else not Item.Closers.Is_Empty then
            return True;
         end if;
         while Child /= null loop
            if Pending (Child) then return True; end if;
            Child := Child.Deferred_Error_Next;
         end loop;
         return False;
      end Pending;
   begin
      for Item of Context.Stack loop
         if Pending (Item) then return True; end if;
      end loop;
      return False;
   end Has_Thread_Closers;

   procedure Adopt_Reset_Error_Scopes (State : in out World);
   procedure Adopt_Reset_Error_Scopes (State : in out World) is
      Context : constant Context_Access := State.Current;
      Guard, Higher, Item, Owner : Frame_Access;
      Floor : Natural;
      Traceback : Boolean;

      procedure Restore_Higher;
      procedure Restore_Higher is
      begin
         while Higher /= null loop
            Item := Higher;
            Higher := Item.Deferred_Error_Next;
            Item.Deferred_Error_Next := null;
            Context.Stack.Append (Item);
         end loop;
      end Restore_Higher;
   begin
      loop
         Guard := null;
         for Candidate of reverse Context.Stack loop
            if Candidate.Pending_Error_Transfer then
               Guard := Candidate;
               exit;
            end if;
         end loop;
         exit when Guard = null;
         Owner := Guard.Error_Guard_Owner;
         if Owner = null or else Owner.Foreign_Entered then
            raise Program_Error with "reset found an unacknowledged C body";
         end if;
         --  Reentrant C cleanup can have scheduled genuine Lua scopes above
         --  an older held error view. Every C body has now ACKed. Preserve
         --  these higher scope records in an intrusive temporary chain while
         --  adopting the old view; no allocation/GC/callback can occur here.
         --  Their original stack capacity also covers restoration afterwards.
         Higher := null;
         begin
            while Context.Stack.Last_Element /= Guard loop
               Item := Context.Stack.Last_Element;
               Retire_Frame_Execution (State, Item);
               Context.Stack.Delete_Last;
               Item.Deferred_Error_Next := Higher;
               Higher := Item;
            end loop;
            Adopt_Deferred_Error_Scopes
              (State,
               (Activation => Owner.all'Address,
                Serial => Owner.Foreign_Ticket), Owner, Floor, Traceback);
            Restore_Higher;
         exception
            when others =>
               Restore_Higher;
               raise;
         end;
      end loop;
   end Adopt_Reset_Error_Scopes;

   procedure Prepare_Thread_Reset
     (State : in out World; Native_Base : Natural; Self_Close : Boolean);
   procedure Prepare_Thread_Reset
     (State : in out World; Native_Base : Natural; Self_Close : Boolean)
   is
      Context : constant Context_Access := State.Current;
      Last : Natural := 0;
   begin
      --  A published yield window contains delivery values, not departing
      --  locals. Restore the real retained view before deriving close levels.
      if Context.Detached_Resume_Window then
         Context.Foreign_Activation := Context.Resume_Foreign_Activation;
         Context.Foreign_View := Context.Resume_Foreign_View;
         Context.Foreign_Base := Context.Resume_Foreign_Base;
         Context.Foreign_Top := Context.Resume_Foreign_Top;
         Context.Stack_Used := Context.Resume_Stack_Used;
         Context.Host_Stack_Top := Context.Resume_Host_Stack_Top;
         Context.Resume_Foreign_Activation := null;
         Context.Resume_Foreign_View := null;
         Context.Detached_Resume_Window := False;
      end if;
      --  Only an unhandled failure that stopped the coroutine is its old
      --  status. Protected API/load errors on a still-idle thread are stack
      --  values and cannot become reset's incoming error by accident.
      if Context.Status /= Dead_Context then
         Context.Failure := Nil_Value;
         Context.Has_Failure_Value := False;
         Context.Failure_Class := No_Failure;
         Context.Failure_Handled := False;
      end if;
      Context.C_Reset_Active := True;
      Context.Error_Recovery_Pending := False;
      Context.Error_Recovery_Floor := 0;
      Context.C_Reset_Self := Self_Close;
      Context.C_Reset_Error := False;
      Context.Status := Running_Context;
      Context.Phase := Closing;
      if not Self_Close then Context.Resumer := null; end if;
      Context.Entry_Function := Nil_Value;
      Context.Arguments.Clear;
      Context.Boundary_Results.Clear;
      Context.Transfer.Kind := No_Transfer;
      Context.Transfer.Target := 0;
      Context.Transfer.Results.Clear;
      Context.Host_Stack_Top := 0;
      State.Native_Depth := Native_Base + Context.Native_Depth;
      for Item of Context.Stack loop
         Last := Natural'Max (Last, Pending_Closing_Level (Item));
      end loop;
      Set_Closing_Stack_Prefix (State, Last);
      Adopt_Reset_Error_Scopes (State);
      --  The caller has acknowledged every abandoned C body. Retire actual
      --  windows in physical reverse order while frozen Lua close cells and
      --  the real scalar prefix retain exactly the pending cleanup owners.
      for Item of reverse Context.Stack loop
         Retire_Frame_Execution (State, Item);
      end loop;
      Context.Foreign_Activation := null;
      Context.Foreign_View := null;
      Context.Foreign_Base := 0;
      Context.Hook_Suspended := False;
      Context.Hook_Yield_Pending := False;
      Context.Hook_Active := False;
      Context.Hook_Frame := null;
      Set_Closing_Stack_Prefix (State, Last);
      Context.Resume_Return_Base := 0;
      Context.Resume_Return_Top := 0;
   end Prepare_Thread_Reset;

   procedure Reset_Without_Closers
     (State : in out World; Native_Base : Natural)
   is
      Context : constant Context_Access := State.Current;
   begin
      Prepare_Thread_Reset (State, Native_Base, Self_Close => False);
      Clear_Frames (State);
      Set_Closing_Stack_Prefix (State, 0);
      Stacks.Clear_Range
        (Context, 1, Natural (Context.Foreign_Stack.Length));
      Context.C_Resuming := False;
      Context.C_Reset_Requested := False;
      Context.C_Reset_Active := False;
      Context.Status := Dead_Context;
      Context.Phase := Executing;
   end Reset_Without_Closers;

   procedure Start_Close_Thread
     (Self : in out Driver; State : in out World; Native_Base : Natural;
      Self_Close : Boolean := False)
   is
   begin
      if Self_Close then
         if Self.Universe = null then
            raise Program_Error with "self close has no current driver";
         end if;
      else
         if Self.Universe /= null then
            raise Program_Error with "thread close borrowed an active driver";
         end if;
         Self.Universe := World_View
           (World_Addresses.To_Pointer (State'Address));
         Self.Root_Context := State.Current;
         Self.Entry_Depth := 0;
      end if;
      Self.Done := False;
      Self.Failed := False;
      Prepare_Thread_Reset (State, Native_Base, Self_Close);
      if not Has_Thread_Closers (State.Current) then
         --  In particular a self-closing C callback needs no helper-frame
         --  allocation when no handler exists. The existing scheduler can
         --  deliver this actual terminal transfer after C has unwound.
         Clear_Frames (State);
         Set_Closing_Stack_Prefix (State, 0);
         Stacks.Clear_Range
           (State.Current, 1, Natural (State.Current.Foreign_Stack.Length));
         State.Current.Transfer.Kind := Completed;
         State.Current.C_Reset_Requested := False;
         State.Current.C_Reset_Active := False;
         if Self_Close then
            State.Native_Depth := State.Current.C_Reset_Return_Depth;
         end if;
      else
         Schedule (Self, "@close.thread", Values.Empty_Vector, 0);
      end if;
   exception
      when others =>
         Self.Failed := True;
         raise;
   end Start_Close_Thread;

   procedure Acknowledge_Self_Close
     (Self : Driver; Token : Callback_Identity)
   is
      Context : constant Context_Access := Self.Universe.Current;
      Selected : Frame_Access;
      Adopted : Boolean := False;
   begin
      if Pending_Foreign_Error_Transfer (Self) then
         declare
            Floor : Natural;
            Traceback : Boolean;
         begin
            --  This exact C body has now returned through its guard. Adopt
            --  genuine held scopes before reset scans/retirement; dropping
            --  the view would otherwise discard their still-pending TBCs.
            Adopt_Deferred_Error_Scopes
              (Self.Universe.all, Token, Selected, Floor, Traceback);
            Adopted := True;
         end;
      end if;
      for Item of Context.Stack loop
         if Item.all'Address = Token.Activation then
            Selected := Item;
            exit;
         end if;
      end loop;
      if Selected = null or else Selected.Foreign_Ticket /= Token.Serial or
        else Selected.Foreign_Handler = System.Null_Address or else
        not Selected.Foreign_Entered or else
        Selected.Native_Stage /= (if Adopted then 3 else 1)
      then
         raise Program_Error with "invalid self-close C guard acknowledgment";
      end if;
      if Context.Foreign_Activation = Selected then
         Stack_Views.Restore
           (Self.Universe.all, Selected.Hook_View, Abandon => True);
         Context.Foreign_Top := Selected.Saved_Foreign_Top;
         Context.Foreign_Base := Selected.Foreign_Previous_Base;
         Context.Foreign_Activation := Selected.Foreign_Previous_Frame;
         Context.Foreign_View := Selected.Foreign_Previous_View;
      end if;
      Selected.Foreign_Entered := False;
      Selected.Native_Stage := 6;
   end Acknowledge_Self_Close;

   procedure Deliver_Owned
     (Self : Driver; Activation : Frame_Access; Destination : Natural;
      Packet : in out Values.Vector; Failure : Failure_Kind := No_Failure;
      Handler_Called : Boolean := False)
   is
      State : World renames Self.Universe.all;
      procedure Move_Slot (Slot : in out Values.Vector);
      procedure Move_Slot (Slot : in out Values.Vector) is
      begin
         Move_Roots (State, Slot, Packet);
      end Move_Slot;
   begin
      --  The source holder remains on the activation stack throughout this
      --  operation. No temporary pin vector or controlled packet copy is
      --  needed, including while a canonical result write can still fail.
      if Activation = null then
         Move_Roots (State, State.Current.Transfer.Results, Packet);
         State.Current.Transfer.Kind := Completed;
         State.Current.Transfer.Target := 0;
      elsif Activation.Native_Tail_State = Waiting_Native_Tail then
         Move_Roots (State, Activation.Native_Results, Packet);
         Activation.Native_Tail_State := Ready_Native_Tail;
      elsif Activation.Is_Native then
         declare
            Protected_Error : constant Boolean :=
              Activation.Native_Name = "@foreign.boundary" and then
              not Packet.Is_Empty and then Packet.First_Element.Kind =
                Boolean_Kind and then not Packet.First_Element.Boolean_Data;
         begin
            if Activation.Native_Results.Capacity < Packet.Length and then
              Activation.Native_Arguments.Is_Empty and then
              Activation.Native_Arguments.Capacity >= Packet.Length
            then
               --  A waiting native caller has relinquished its input
               --  request. Reuse that empty arena for its actual returned
               --  packet before considering a transfer of the producer's
               --  warmed workspace. No live input or result is copied here.
               Values.Move (Activation.Native_Results,
                            Activation.Native_Arguments);
               Activation.Native_Arguments.Set_Owner (Activation.Memory);
            end if;
            if Activation.Native_Results.Capacity >= Packet.Length then
               --  The real source remains traced throughout publication.
               --  Copy into existing capacity, then immediately retire its
               --  old value edges while retaining reusable empty storage.
               Copy_Roots (State, Activation.Native_Results, Packet);
               Packet.Clear;
            else
               --  Refusing error/foreign paths may have no receiver arena.
               --  Preserve their existing allocation-free owning transfer.
               Move_Roots (State, Activation.Native_Results, Packet);
            end if;
            Activation.Result_Failure_Class := Failure;
            Activation.Result_Handler_Called := Handler_Called;
            if Protected_Error then
               Activation.Native_Aux :=
                 (if Failure = Memory_Failure then 4
                  elsif Failure = Handling_Failure then 5 else 2);
            end if;
         end;
      elsif Activation.Code.Canonical_Node /= null then
         --  Scalars/cells become authoritative before the source packet is
         --  cleared. A refused open-result growth leaves that source intact
         --  so the still-live protected holder can publish its reserved error.
         Canonical.Deliver (State, Activation, Packet);
         Packet.Clear;
      elsif Destination /= 0 then
         declare
            Old_Extra : constant Natural := Natural'Max
              (1, Natural (Activation.Slots (Destination).Length)) - 1;
            New_Extra : constant Natural :=
              Natural'Max (1, Natural (Packet.Length)) - 1;
            Delta_Slots : constant Integer := New_Extra - Old_Extra;
         begin
            --  Preserve the private backend's existing semantic accounting.
            --  Only the ownership transfer differs from Put_Packet; the
            --  outer register packet array was reserved when its frame began.
            if Delta_Slots > 0 and then Delta_Slots >
              Lua.Runtime_Configuration.Maximum_Stack - Natural'Min
                (Lua.Runtime_Configuration.Maximum_Stack,
                 State.Current.Stack_Slots)
            then
               Fail (State, "stack overflow");
            end if;
            Activation.Slots.Update_Element
              (Destination, Move_Slot'Access);
            Activation.Slot_Cost := Activation.Slot_Cost + Delta_Slots;
            State.Current.Stack_Slots :=
              State.Current.Stack_Slots + Delta_Slots;
         end;
      else
         Packet.Clear;
      end if;
   end Deliver_Owned;

   procedure Take_Results (Self : Driver; Packet : in out Values.Vector) is
   begin
      if Self.Universe = null or else not Self.Done then
         raise Program_Error with "unfinished VM driver results";
      end if;
      Move_Roots
        (Self.Universe.all, Packet, Self.Root_Context.Transfer.Results);
   end Take_Results;

   function New_Driver (State : in out World) return Driver_Access is
   begin
      return new (Lua.Storage.Handle (State.Memory)) Driver;
   end New_Driver;

   procedure Free_Driver (Self : in out Driver_Access) is
      procedure Destroy is new Ada.Unchecked_Deallocation
        (Driver, Driver_Access);
   begin
      if Self /= null and then Self.Universe /= null then
         raise Program_Error with "foreign driver still owns a drive";
      end if;
      Destroy (Self);
   end Free_Driver;

   function Needs_Foreign_Call (Self : Driver) return Boolean is
     (Self.Universe /= null and then not Self.Done and then not Self.Failed
      and then not Self.Universe.Current.Stack.Is_Empty and then
      Self.Universe.Current.Stack.Last_Element.Is_Native and then
      (Self.Universe.Current.Stack.Last_Element.Native_Name =
         "foreign.callback" or else
       Self.Universe.Current.Stack.Last_Element.Load_Reader_Portal) and then
      Self.Universe.Current.Stack.Last_Element.Native_Stage = 1);

   function Foreign_Handler (Self : Driver) return System.Address is
   begin
      if not Needs_Foreign_Call (Self) then
         raise Program_Error with "no pending foreign callback";
      end if;
      return Self.Universe.Current.Stack.Last_Element.Foreign_Handler;
   end Foreign_Handler;

   function Foreign_Token (Self : Driver) return Callback_Identity is
      Activation : Frame_Access;
   begin
      if not Needs_Foreign_Call (Self) then
         raise Program_Error with "no pending foreign callback identity";
      end if;
      Activation := Self.Universe.Current.Stack.Last_Element;
      return (Activation => Activation.all'Address,
              Serial => Activation.Foreign_Ticket);
   end Foreign_Token;

   function Foreign_Context (Self : Driver) return Context_Access is
   begin
      if not Needs_Foreign_Call (Self) then
         raise Program_Error with "no pending foreign context";
      end if;
      return Self.Universe.Current;
   end Foreign_Context;

   function Foreign_Continuation (Self : Driver) return System.Address is
     (Foreign_Context (Self).Stack.Last_Element.Foreign_Continuation);
   function Foreign_KContext (Self : Driver) return Interfaces.C.ptrdiff_t is
     (Foreign_Context (Self).Stack.Last_Element.Foreign_KContext);
   function Foreign_KStatus (Self : Driver) return Interfaces.C.int is
     (Foreign_Context (Self).Stack.Last_Element.Foreign_KStatus);

   procedure Adopt_Deferred_Error_Scopes
     (State : in out World; Token : Callback_Identity;
      Owner : out Frame_Access; Prefix_Floor : out Natural;
      Retained_Traceback : out Boolean)
   is
      Context : constant Context_Access := State.Current;
      Guard, Next, Item : Frame_Access;
   begin
      if Context.Stack.Is_Empty or else
        not Context.Stack.Last_Element.Pending_Error_Transfer
      then
         raise Program_Error with "no current deferred C error view";
      end if;
      Guard := Context.Stack.Last_Element;
      Owner := Guard.Error_Guard_Owner;
      if Owner = null or else Context.Stack.Length < 2 or else
        Context.Stack (Context.Stack.Last_Index - 1) /= Owner or else
        Token.Activation /= Owner.all'Address or else
        Token.Serial /= Owner.Foreign_Ticket or else
        Guard.Warning_Borrow_Depth /= 0
      then
         raise Program_Error with "unacknowledged deferred C scope owner";
      end if;
      Prefix_Floor := Guard.Error_Previous_Prefix;
      Retained_Traceback := Guard.Deferred_Error_Traceback;
      Next := Guard.Deferred_Error_Head;
      Guard.Deferred_Error_Head := null;
      Guard.Deferred_Error_Count := 0;
      Context.Stack.Delete_Last;
      Retire_Stack_Window (Guard);
      Context.Foreign_Activation := Owner;
      Context.Foreign_View := Guard.Foreign_Previous_View;
      Context.Foreign_Base := Owner.Stack_Base;
      Context.Foreign_Top := Owner.Stack_Live_Top;
      Release_Frame (State, Guard);
      --  Stage three records the genuinely completed C transfer. Preserved
      --  failed traceback windows still belong to these records; resetting
      --  them is a later explicit operation, not a side effect of adoption.
      Owner.Native_Stage := 3;
      while Next /= null loop
         Item := Next;
         Next := Item.Deferred_Error_Next;
         Item.Deferred_Error_Next := null;
         Context.Deferred_Error_Depth := Context.Deferred_Error_Depth - 1;
         if Context.Stack.Length = Context.Stack.Capacity then
            raise Program_Error with "unreserved scope restore";
         end if;
         Context.Stack.Append (Item);
      end loop;
   end Adopt_Deferred_Error_Scopes;

   procedure Complete_Foreign_Call
     (Self : Driver; Result_Count : Natural; Error_Status : Natural := 0;
      Handler_Called : Boolean := False;
      Token : Callback_Identity)
   is
      State : World renames Self.Universe.all;
      Context : constant Context_Access := State.Current;
      Activation : Frame_Access;
      Guard : Frame_Access;
      Count : Natural;
   begin
      if Error_Status not in 0 | 2 | 4 | 5 then
         raise Program_Error with "invalid foreign callback completion";
      end if;
      if Pending_Foreign_Error_Transfer (Self) then
         Guard := Context.Stack.Last_Element;
         Activation := Guard.Error_Guard_Owner;
         if Error_Status = 0 or else Activation = null or else
           Context.Stack.Length < 2 or else
           Context.Stack (Context.Stack.Last_Index - 1) /= Activation
         then
            raise Program_Error with "invalid pending C error transfer";
         end if;
      elsif Needs_Foreign_Call (Self) then
         Activation := Context.Stack.Last_Element;
      else
         raise Program_Error with "invalid foreign callback completion";
      end if;
      --  A nested C pump can return through several live guards. Each one
      --  acknowledges its own activation, never whichever frame happens to
      --  be deepest after a child transfer. Serial also rejects cache reuse.
      if Token.Activation /= Activation.all'Address or else
        Token.Serial /= Activation.Foreign_Ticket
      then
         raise Program_Error with "stale foreign callback identity";
      end if;
      Count := Context.Foreign_Top - Context.Foreign_Base;
      if (Error_Status = 0 and then Result_Count > Count) or else
        (Error_Status /= 0 and then Count = 0)
      then
         Fail (State, "invalid number of C callback results");
      end if;
      Count := (if Error_Status = 0 then Result_Count else 1);
      if Error_Status = 0 then
         --  The callback's topmost real C slots supply its return values.
         --  Save their base before restoring that window or copying the
         --  result packet, so return hooks expose the original position.
         Activation.Transfer_First :=
           Context.Foreign_Top - Context.Foreign_Base - Count + 1;
         Activation.Transfer_Count := Count;
         Activation.Return_Window_Published := True;
      end if;
      if Error_Status /= 0 then
         --  Callback failure has one existing C-stack object. Do not allocate
         --  a temporary packet while a permanent provider refusal is active.
         --  The preserved window and explicit context error are both roots.
         Context.Failure := Stacks.Read (Context, Context.Foreign_Top);
         Root_Barrier (State, Context.Failure);
         Context.Has_Failure_Value := True;
         Lua.Diagnostic_Text.Clear (Context.Failure_Text);
         Context.Failure_Class :=
           (if Error_Status = 4 then Memory_Failure
            elsif Error_Status = 5 then Handling_Failure
            else Language_Failure);
         Context.Failure_Handled := Handler_Called;
         Activation.Native_Stage := 3;
         if Guard /= null then
            declare
               Adopted : Frame_Access;
               Floor : Natural;
               Traceback : Boolean;
            begin
               --  The exact C guard has returned. Its real error-view slot
               --  is rooted by Context.Failure before the transport retires.
               --  Restore retained scopes without allocation, then recover
               --  immediately; their abandoned PCs are never scheduled.
               Adopt_Deferred_Error_Scopes
                 (State, Token, Adopted, Floor, Traceback);
               if Adopted /= Activation then
                  raise Program_Error with "changed deferred C error owner";
               end if;
               Stack_Views.Restore
                 (State, Activation.Hook_View, Abandon => True);
               if not Traceback then
                  Retire_Frame_Execution (State, Activation);
               end if;
               Context.Error_Recovery_Floor := Floor;
               Context.Error_Recovery_Pending := True;
            end;
         end if;
         Stack_Views.Restore
           (State, Activation.Hook_View, Abandon => True);
         return;
      end if;
      Activation.Native_Results.Clear;
      if Activation.Completion = Deliver_Results then
         Activation.Native_Results.Reserve_Capacity
           (Ada.Containers.Count_Type (Count));
         for Index in Context.Foreign_Top - Count + 1 .. Context.Foreign_Top
         loop
            Append_Root
              (State, Activation.Native_Results,
               Stacks.Read (Context, Index));
         end loop;
      end if;
      --  The live activation owns every result before the C window is
      --  truncated. No extra temporary pin or controlled copy is required.
      if Activation.Load_Reader_Portal then
         --  A direct saved builtin borrowed its actual C caller's window.
         --  Its completed results now have an independent rooted packet;
         --  restore the lease only after the real portal guard acknowledged
         --  that return, before restoring the preceding public C view.
         Stack_Views.Restore (State, Activation.Hook_View);
      end if;
      Context.Foreign_Top := Activation.Saved_Foreign_Top;
      Context.Foreign_Base := Activation.Foreign_Previous_Base;
      Context.Foreign_Activation := Activation.Foreign_Previous_Frame;
      Context.Foreign_View := Activation.Foreign_Previous_View;
      Activation.Foreign_Entered := False;
      Context.Failure := Nil_Value;
      Root_Barrier (State, Context.Failure);
      Context.Has_Failure_Value := False;
      Context.Failure_Class := No_Failure;
      Context.Failure_Handled := False;
      Activation.Native_Stage := 2;
      if Context.Hook_Active and then Activation.Foreign_Suspended then
         --  A line/count C hook resumes the interrupted Lua instruction,
         --  without retaining artificial hook/C frames in debug inspection.
         Context.Stack.Delete_Last;
         Release_Frame (State, Activation);
         Activation := Context.Stack.Last_Element;
         Context.Stack.Delete_Last;
         Release_Frame (State, Activation);
         Context.Hook_Active := False;
         --  A yielded hook interrupted the next instruction before its PC
         --  advanced. Public suspended-frame inspection must keep observing
         --  that instruction until a real resumer continues execution.
         Context.Hook_Suspended := True;
         Context.Hook_Frame := Context.Stack.Last_Element;
         if not Context.Hook_Frame.Line_Hook_Checked then
            --  Count comes before line. Delay only publication of the yield;
            --  the original C callback is already abandoned and retired.
            Context.Hook_Yield_Pending := True;
            Context.Hook_Suspended := False;
            Context.Transfer.Kind := No_Transfer;
            Context.Transfer.Results.Clear;
         else
            Context.Hook_Yield_Pending := False;
         end if;
      end if;
   end Complete_Foreign_Call;

   procedure Start_Foreign_Boundary
     (Self : Driver; Callee : Value; Arguments : Values.Vector;
      Message_Handler : Value := Nil_Value;
      Call_Base : Natural := 0; Has_Call_Window : Boolean := False;
      Yieldable : Boolean := False; Wanted : Integer := 0;
      Protected_Call : Boolean := False; Direct_Builtin : Boolean := False;
      Error_Token : Callback_Identity := (others => <>))
   is
      State : World renames Self.Universe.all;
      Original_Depth : constant Natural :=
        Natural (State.Current.Stack.Length);
      Hook_Origin : constant Boolean :=
        State.Current.Foreign_Activation /= null and then
        State.Current.Foreign_Activation.Is_C_Hook_Transport;
      --  A C hook that calls Lua borrows the interrupted CIST_HOOKED caller,
      --  even after removing its own installation. Transfer that actual
      --  activation origin across the C-owned boundary; a nested ordinary C
      --  activation has no marker and cannot inherit the hook's name.
   begin
      if not Needs_Foreign_Call (Self) and then
        State.External_Release_Active = null and then
        (State.Warning_Head = null or else
         State.Warning_Head.Warning_Phase /= Warning_Callback_Active)
      then
         raise Program_Error with "foreign boundary has no C caller";
      end if;
      Pin (State, Callee);
      Pin (State, Arguments);
      Pin (State, Message_Handler);
      Schedule (Self, "@foreign.boundary", Values.Empty_Vector, 0);
      State.Current.Stack.Last_Element.Error_Packet.Reserve_Capacity (2);
      --  lua_call without a continuation cannot suspend its C activation.
      --  A future continuation-aware boundary must make that choice explicit,
      --  rather than treating every scheduler continuation as yieldable.
      State.Current.Stack.Last_Element.Blocks_Yield := not Yieldable;
      State.Current.Stack.Last_Element.Foreign_Suspended := False;
      State.Current.Stack.Last_Element.Foreign_Wanted := Wanted;
      State.Current.Stack.Last_Element.Foreign_Protected := Protected_Call;
      State.Current.Stack.Last_Element.Foreign_Previous_Frame :=
        State.Current.Foreign_Activation;
      if not Protected_Call and then
        State.Current.Foreign_Activation /= null and then
        Error_Token.Activation =
          State.Current.Foreign_Activation.all'Address and then
        Error_Token.Serial =
          State.Current.Foreign_Activation.Foreign_Ticket and then
        State.Current.Foreign_Activation.Foreign_Entered and then
        State.Current.Foreign_Activation.Native_Stage = 1
      then
         --  Tokens are copied from the actual current C guard, including
         --  zero for ownerless reader/probe/parser guards. A nearby callback
         --  frame alone cannot authorize abandoning somebody else's body.
         State.Current.Stack.Last_Element.Error_Guard_Owner :=
           State.Current.Foreign_Activation;
      end if;
      State.Current.Stack.Last_Element.Native_Index := Call_Base - 1;
      State.Current.Stack.Last_Element.Protection := 1;
      State.Current.Stack.Last_Element.Message_Handler := Message_Handler;
      Root_Barrier
        (State, State.Current.Stack.Last_Element.Message_Handler);
      State.Current.Stack.Last_Element.Retain_On_Failure := True;
      if not Yieldable then
         State.Current.Non_Yieldable := State.Current.Non_Yieldable + 1;
      end if;
      begin
         if Direct_Builtin then
            Schedule_Builtin
              (Self, Callee.Native_Data, Arguments, 0,
               State.Current.Foreign_Activation);
         else
            Dispatch (Self, Callee, Arguments, 0,
                   Call_Name => (if Hook_Origin then
                     To_Unbounded_String ("?") else Null_Unbounded_String),
                   Name_Kind => (if Hook_Origin then
                     To_Unbounded_String ("hook") else Null_Unbounded_String),
                   Call_Base => Call_Base,
                      Has_Call_Window => Has_Call_Window);
         end if;
      exception
         when Language_Error => Recover (Self);
         when Lua.Storage.Allocation_Error =>
            Record_Memory_Error (State);
            Recover (Self);
      end;
   exception
      when others =>
         --  A setup failure precedes execution of the protected child. Remove
         --  only this boundary's partial activations; the outer C callback
         --  and its live C guard still own the interrupted driver.
         while Natural (State.Current.Stack.Length) > Original_Depth loop
            declare
               Item : Frame_Access := State.Current.Stack.Last_Element;
            begin
               State.Current.Stack.Delete_Last;
               Release_Frame (State, Item);
            end;
         end loop;
         raise;
   end Start_Foreign_Boundary;

   function Has_Foreign_Result (Self : Driver) return Boolean is
     (Self.Universe /= null and then not Self.Done and then not Self.Failed
      and then not Self.Universe.Current.Stack.Is_Empty and then
      Self.Universe.Current.Stack.Last_Element.Is_Native and then
      Self.Universe.Current.Stack.Last_Element.Native_Name =
        "@foreign.boundary" and then
      not Self.Universe.Current.Stack.Last_Element.Foreign_Suspended and then
      Self.Universe.Current.Stack.Last_Element.Native_Stage = 1);

   function Pending_Foreign_Error_Transfer (Self : Driver) return Boolean is
     (Self.Universe /= null and then not Self.Universe.Current.Stack.Is_Empty
      and then Self.Universe.Current.Stack.Last_Element
        .Pending_Error_Transfer);

   procedure Take_Foreign_Result
     (Self : Driver; Packet : in out Values.Vector; Error_Status : out Natural;
      Handler_Called : out Boolean)
   is
      State : World renames Self.Universe.all;
      Activation : Frame_Access;
   begin
      if not Has_Foreign_Result (Self) then
         raise Program_Error with "no completed foreign boundary";
      end if;
      Activation := State.Current.Stack.Last_Element;
      if Activation.Native_Results.Is_Empty or else
        Activation.Native_Results.First_Element.Kind /= Boolean_Kind
      then
         raise Program_Error with "foreign boundary lost protection packet";
      end if;
      Error_Status :=
        (if Activation.Native_Results.First_Element.Boolean_Data then 0
         else Natural'Max (2, Activation.Native_Aux));
      Handler_Called := Activation.Result_Handler_Called;
      Move_Roots (State, Packet, Activation.Native_Results);
      Packet.Delete_First;
      if Error_Status /= 0 and then Activation.Error_Guard_Owner /= null then
         declare
            Context : constant Context_Access := State.Current;
            Base : constant Natural := Natural'Max
              (Context.Foreign_Top, Context.Closing_Stack_Prefix);
         begin
            if Base >= Natural (Context.Foreign_Stack.Length) then
               raise Program_Error with "missing reserved C error slot";
            end if;
            --  Reusing the old caller's outgoing slot here would overwrite
            --  a pending TBC prefix before C acknowledges abandonment. This
            --  real one-value C transport view sits above that prefix, using
            --  already initialized extra stack storage; it invents no call
            --  frame or minimum C-stack reservation. Reentrant release APIs
            --  see this same physical error slot while the C guard returns.
            Activation.Stack_Base := Base;
            Activation.Call_Base := Base + 1;
            Activation.Stack_Window_Length := 1;
            Activation.Stack_Live_Top := Base + 1;
            Activation.Saved_Stack_Used := Context.Stack_Used;
            Activation.Previous_Stack_Window := Context.Stack_Window;
            Activation.Has_Stack_Window := True;
            Activation.Native_Stage := 2;
            Activation.Pending_Error_Transfer := True;
            Activation.Foreign_Previous_View := Context.Foreign_View;
            Context.Stack_Window := Activation;
            Context.Stack_Used := Natural'Max (Context.Stack_Used, Base + 1);
            Context.Foreign_Base := Base;
            Context.Foreign_Top := Base + 1;
            Context.Foreign_Activation := Activation;
            Context.Foreign_View := null;
            Stacks.Write (State, Context, Base + 1, Packet.First_Element);
            Packet.Clear;
            return;
         end;
      end if;
      State.Current.Stack.Delete_Last;
      Release_Frame (State, Activation);
   end Take_Foreign_Result;

   function Current_Message_Handler (Self : Driver) return Value is
     (Active_Handler (Self));

   procedure Step (Self : in out Driver) is
      Validated : Boolean := False;
   begin
      if Self.Universe = null or else Self.Done or else Self.Failed then
         raise Program_Error with "inactive VM driver step";
      end if;
      if Needs_Foreign_Call (Self) or else Has_Foreign_Result (Self) then
         raise Program_Error with "foreign drive requires its C-owned pump";
      end if;
      Validated := True;
      Begin_Operation (Self.Universe.all);
      --  Exactly one transfer or instruction/native/hook phase runs here.
      --  All continuations are frame data; returning drops every helper's
      --  Ada activation while retaining the same world, roots and budget.
      Scheduler_Step (Self);
      End_Operation (Self.Universe.all);
   exception
      when others =>
         if Validated then
            End_Operation (Self.Universe.all);
            Self.Failed := True;
            Abandon (Self);
         end if;
         raise;
   end Step;

   function Is_Complete (Self : Driver) return Boolean is (Self.Done);

   function Outcome (Self : Driver) return Transfer_Kind is
   begin
      if Self.Universe = null or else not Self.Done then
         raise Program_Error with "unfinished VM driver outcome";
      end if;
      return Self.Root_Context.Transfer.Kind;
   end Outcome;

   function Results (Self : Driver) return Values.Vector is
   begin
      if Self.Universe = null or else not Self.Done then
         raise Program_Error with "unfinished VM driver results";
      end if;
      return Self.Root_Context.Transfer.Results;
   end Results;

   procedure Finish (Self : in out Driver) is
   begin
      if Self.Universe /= null and then not Self.Done and then
        not Self.Failed
      then
         raise Program_Error with "unfinished VM driver borrow";
      end if;
      if Self.Done and then Self.Root_Context /= null then
         Self.Root_Context.Transfer.Kind := No_Transfer;
         Self.Root_Context.Transfer.Target := 0;
         Self.Root_Context.Transfer.Results.Clear;
      end if;
      Self.Universe := null;
      Self.Root_Context := null;
      Self.Entry_Depth := 0;
      Self.Done := False;
      Self.Failed := False;
   end Finish;

   procedure Cancel (Self : in out Driver) is
   begin
      if Self.Universe /= null then
         Self.Failed := True;
         Abandon (Self);
         Finish (Self);
      end if;
   end Cancel;

   procedure Run (State : in out World; Code : Prototype_Access) is
      Self : Driver;
   begin
      --  The legacy synchronous entry borrows an in-out formal, whose stable
      --  address belongs to its caller. This isolated standard Ada address
      --  view cannot escape: Finish clears the local driver's access before
      --  Run returns or propagates failure. Foreign callers instead pass an
      --  actual owned World_Access through Start, without this adaptation.
      Start_Borrowed
        (Self, World_View (World_Addresses.To_Pointer (State'Address)),
         Code, Nil_Value, State.Current.Arguments);
      while not Is_Complete (Self) or else External_Releases.Pending (State)
      loop
         if External_Releases.Pending (State) or else
           Needs_Foreign_Call (Self) or else Warnings.Pending (State)
         then
            --  The helper installs its C guard above this waiting host
            --  activation. No internal Ada step spans the foreign callback;
            --  nested C API work continues on this same explicit driver.
            Lua.Engine.Foreign.Invoke_Borrowed (State, Self);
         else
            Step (Self);
         end if;
      end loop;
      Finish (Self);
   exception
      when others =>
         Self.Failed := True;
         Finish (Self);
         raise;
   end Run;

   procedure Drive_To_Completion (State : in out World; Self : in out Driver);
   procedure Drive_To_Completion (State : in out World; Self : in out Driver)
   is
   begin
      --  Same iterative loop as Run: one scheduler step per iteration, and
      --  foreign/warning callbacks are serviced above this waiting host
      --  activation. No executor entry is ever nested.
      while not Is_Complete (Self) or else External_Releases.Pending (State)
      loop
         if External_Releases.Pending (State) or else
           Needs_Foreign_Call (Self) or else Warnings.Pending (State)
         then
            Lua.Engine.Foreign.Invoke_Borrowed (State, Self);
         else
            Step (Self);
         end if;
      end loop;
   end Drive_To_Completion;

   procedure Run_Retaining (State : in out World; Code : Prototype_Access) is
      Self : Driver;
   begin
      Start_Borrowed
        (Self, World_View (World_Addresses.To_Pointer (State'Address)),
         Code, Nil_Value, State.Current.Arguments);
      Drive_To_Completion (State, Self);
      if State.Exit_Phase /= Exit_Complete and then
        Outcome (Self) = Completed
      then
         --  Ownership transition: the packet moves from the driver's root
         --  context into the context's traced Arguments vector without any
         --  allocation, so there is no safe point at which it is unowned.
         --  Arguments held the chunk's (empty for the REPL) input only; the
         --  drive is complete, so clearing it cannot disturb a live frame.
         State.Current.Arguments.Clear;
         Take_Results (Self, State.Current.Arguments);
      end if;
      Finish (Self);
   exception
      when others =>
         Self.Failed := True;
         Finish (Self);
         raise;
   end Run_Retaining;

   procedure Run_Display (State : in out World) is
      Self : Driver;
   begin
      Prepare
        (Self, World_View (World_Addresses.To_Pointer (State'Address)));
      Schedule (Self, "@host.display", State.Current.Arguments, 0);
      Drive_To_Completion (State, Self);
      Finish (Self);
   exception
      when others =>
         Self.Failed := True;
         Finish (Self);
         raise;
   end Run_Display;
   procedure Run_Warning_Control
     (State : in out World; Enabled : Boolean)
   is
      Self : Driver;
   begin
      Prepare
        (Self, World_View (World_Addresses.To_Pointer (State'Address)));
      Schedule
        (Self, (if Enabled then "@host.warning.on" else "@host.warning.off"),
         Values.Empty_Vector, 0);
      Drive_To_Completion (State, Self);
      Finish (Self);
   exception
      when others =>
         Self.Failed := True;
         Finish (Self);
         raise;
   end Run_Warning_Control;

   procedure Run_Package_Environment
     (State : in out World; Ignore_Environment : Boolean)
   is
      Self : Driver;
   begin
      Prepare
        (Self, World_View (World_Addresses.To_Pointer (State'Address)));
      Schedule
        (Self, (if Ignore_Environment then "@host.package.noenv"
                else "@host.package.env"), Values.Empty_Vector, 0);
      Drive_To_Completion (State, Self);
      Finish (Self);
   exception
      when others =>
         Self.Failed := True;
         Finish (Self);
         raise;
   end Run_Package_Environment;
   procedure Close_Lua_State (State : in out World) is
      Self : Driver;
   begin
      --  This public-boundary operation borrows an idle universe. The same
      --  scheduler handles its close callbacks and C warnings; no executor
      --  is entered recursively and no physical storage is freed here.
      State.Current := State.Main_Context;
      Prepare
        (Self, World_View (World_Addresses.To_Pointer (State'Address)),
         Retained_Depth => Natural (State.Current.Stack.Length));
      --  The idle API base owns genuine C closing slots, but must itself be
      --  consumed by state close. Ordinary root calls retain that activation;
      --  this teardown driver deliberately includes it in its close walk.
      Self.Entry_Depth := 0;
      Request_Process_Exit (State, 0, Close_State => True);
      while not Is_Complete (Self) or else External_Releases.Pending (State)
      loop
         if External_Releases.Pending (State) or else
           Needs_Foreign_Call (Self) or else Warnings.Pending (State)
         then
            Lua.Engine.Foreign.Invoke_Borrowed (State, Self);
         else
            Step (Self);
         end if;
      end loop;
      Finish (Self);
   exception
      when others =>
         Self.Failed := True;
         Finish (Self);
         raise;
   end Close_Lua_State;

   procedure Drain_External_Releases (State : in out World) is
      Self : Driver;
   begin
      --  Teardown calls this before deleting contexts or code. Reentrant
      --  lua_call schedules an ordinary foreign boundary on this same idle
      --  borrow; the original executor is not recursively entered.
      Prepare
        (Self, World_View (World_Addresses.To_Pointer (State'Address)),
         Retained_Depth => Natural (State.Current.Stack.Length));
      while External_Releases.Pending (State) loop
         Lua.Engine.Foreign.Invoke_Borrowed (State, Self);
      end loop;
      Self.Failed := True;
      Finish (Self);
   exception
      when others =>
         Self.Failed := True;
         Finish (Self);
         raise;
   end Drain_External_Releases;
end Lua.Engine.Machine;
