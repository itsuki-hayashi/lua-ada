with Ada.Characters.Latin_1;
with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Interfaces;
with Interfaces.C;
with Lua.Integers;
with Lua.Lexers; use Lua.Lexers;
with Lua.Platform_Numerics;
with Lua.Engine.Strings;
with Lua.Engine.Packing;
with Lua.Engine.Unicode;
with Lua.Engine.Core_Libraries;
with Lua.Engine.Pattern_Drivers;
with Lua.Engine.Loaders;
with Lua.Engine.Format_Drivers;
with Lua.Engine.Table_Drivers;

package body Lua.Engine.Machine is
   --  The VM is the only executor of compiled chunks. Registers hold result
   --  packets rather than plain values; every primitive explicitly chooses
   --  scalar or expanding consumption. Lua calls use the owned frame vector,
   --  leaving the Ada call stack independent of user recursion depth.
   use type Ada.Containers.Count_Type;
   use type Integer_Value;
   use type Real_Value;
   use type Interfaces.Unsigned_64;
   use type Lua.Numbers.Number_Kind;

   procedure Free_Frame is new Ada.Unchecked_Deallocation
     (Frame, Frame_Access);
   function From_Bits is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, Real_Value);
   function To_Bits is new Ada.Unchecked_Conversion
     (Real_Value, Interfaces.Unsigned_64);
   --  These bit operations are isolated to IEEE signs/special values. They
   --  never reinterpret heap pointers or turn off arithmetic runtime checks.

   function First (Packet : Values.Vector) return Value is
     (if Packet.Is_Empty then Nil_Value else Packet.First_Element);

   function Scalar (Activation : Frame_Access; Register_Id : Natural)
                    return Value is
     (if Register_Id = 0 then Nil_Value
      else First (Activation.Slots (Register_Id)));

   procedure Put_Packet
     (Activation : Frame_Access; Register_Id : Positive;
      Packet : Values.Vector);
   procedure Put_One
     (Activation : Frame_Access; Register_Id : Positive; Item : Value);
   function Flatten
     (Activation : Frame_Access; Inputs : Registers.Vector;
      Expand_Last : Boolean := True) return Values.Vector;
   function Numeric (State : in out World; Item : Value)
                     return Lua.Numbers.Number;
   function Diagnostic_Type (State : in out World; Item : Value)
                            return String;
   function Integral (State : in out World; Item : Value) return Integer_Value;
   function Binary_Value
     (State : in out World; Operator : Token_Kind; Left, Right : Value)
      return Value;
   function Unary_Value
     (State : in out World; Operator : Token_Kind; Item : Value) return Value;

   procedure Put_Packet
     (Activation : Frame_Access; Register_Id : Positive;
      Packet : Values.Vector)
   is
      --  Coercion belongs at the primitive operation boundary, not in the
      --  stored value. A numeric string remains a string for type/identity.
   begin
      Activation.Slots.Replace_Element (Register_Id, Packet);
   end Put_Packet;

   procedure Put_One
     (Activation : Frame_Access; Register_Id : Positive; Item : Value)
   is
      Packet : Values.Vector;
   begin
      Packet.Append (Item);
      Put_Packet (Activation, Register_Id, Packet);
   end Put_One;

   function Flatten
     (Activation : Frame_Access; Inputs : Registers.Vector;
      Expand_Last : Boolean := True) return Values.Vector
   is
      Result : Values.Vector;
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

   function Diagnostic_Type (State : in out World; Item : Value)
                            return String
   is
      Name : constant Value := Metafield (State, Item, "__name");
   begin
      --  type() remains the language's primitive category. Error wording
      --  alone honors a raw string __name supplied by the object's owner.
      return (if Name.Kind = String_Kind then Image (Name)
              else Type_Name (Item));
   end Diagnostic_Type;

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
            Result := Lua.Numbers.Read (To_String (Item.Reference.Bytes));
            if Result.Kind /= Lua.Numbers.Invalid then
               return Result;
            end if;
         when others => null;
      end case;
      Fail (State, "attempt to perform arithmetic on a " &
              Diagnostic_Type (State, Item) & " value");
      return (Kind => Lua.Numbers.Invalid);
   end Numeric;

   function Integral (State : in out World; Item : Value) return Integer_Value
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
         Fail (State, "number has no integer representation");
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
         Fail (State, "attempt to compare " & Diagnostic_Type (State, A) &
                 " with " & Diagnostic_Type (State, B));
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
            Fail (State, "attempt to concatenate a non-string value");
         end if;
         if Image (Left)'Length > State.Bounds.String_Bytes -
           Natural'Min (Image (Right)'Length, State.Bounds.String_Bytes)
         then
            Fail (State, "string byte limit exceeded", Resource => True);
         end if;
         return New_String (State, Image (Left) & Image (Right));
      elsif Operator in Bit_And | Bit_Or | Bit_Xor | Shift_Left | Shift_Right
      then
         --  Base argument conversion may accept numeric strings, but Lua's
         --  primitive bitwise operators do not. Keep that policy separate
         --  from Integral, which also serves tonumber/select/error arguments.
         if Left.Kind = String_Kind or else Right.Kind = String_Kind then
            Fail (State, "attempt to perform bitwise operation on a string");
         end if;
         IL := Integral (State, Left);
         IR := Integral (State, Right);
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
               --  Quotient-based x-floor(x/y)*y loses signed zero and fails
               --  when the quotient overflows. Ada's IEEE remainder gives
               --  a bounded residue; adjusting its sign yields Lua modulo.
               if FR = 0.0 or else FL /= FL or else FR /= FR or else
                 abs FL > Real_Value'Last
               then
                  Result := From_Bits (16#FFF8_0000_0000_0000#);
               elsif abs FR > Real_Value'Last then
                  Result := FL;
               else
                  Result := Real_Value'Remainder (FL, FR);
               end if;
               if (Result > 0.0 and then FR < 0.0) or else
                 (Result < 0.0 and then FR > 0.0)
               then
                  Result := Result + FR;
               end if;
            elsif FR = 0.0 then
               if FL = 0.0 then
                  Result := From_Bits (16#FFF8_0000_0000_0000#);
               else
                  Result := From_Bits
                    (16#7FF0_0000_0000_0000# or
                     ((To_Bits (FL) xor To_Bits (FR)) and 2 ** 63));
               end if;
            else
               Result := FL / FR;
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
         Fail (State, "attempt to divide or perform modulo by zero");
         return Nil_Value;
   end Binary_Value;

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
                       Integer_Value (Ada.Strings.Unbounded.Length
                         (Item.Reference.Bytes)));
            elsif Item.Kind = Table_Kind then
               return (Integer_Kind, Integer_Value (Table_Length (Item)));
            end if;
            Fail (State, "attempt to get length of a " & Type_Name (Item));
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
                    Lua.Integers.Subtract (-1, Integral (State, Item)));
         when others => raise Program_Error with "invalid unary opcode";
      end case;
      return Nil_Value;
   end Unary_Value;

   procedure Clear_Frames (State : in out World) is
   begin
      for Activation of State.Stack loop
         declare
            Item : Frame_Access := Activation;
         begin
            Free_Frame (Item);
         end;
      end loop;
      State.Stack.Clear;
   end Clear_Frames;

   procedure Run (State : in out World; Code : Prototype_Access) is
      procedure Dispatch
        (Function_Value : Value; Arguments : Values.Vector;
         Destination : Natural; Tail : Boolean := False);
      procedure Complete (Result : Values.Vector);
      procedure Recover;
      procedure Step;
      procedure Native_Step;
      procedure Schedule
        (Name : String; Arguments : Values.Vector; Destination : Natural;
         Operator : Token_Kind := End_Of_Input);
      function Native
        (Function_Id : Native_Kind; Arguments : Values.Vector)
         return Values.Vector;
      function Wrap (Result : Values.Vector; Count : Natural;
                     Success : Boolean := True) return Values.Vector;
      procedure Raise_Value (Item : Value; Level : Natural := 1);
      procedure Push_Frame
        (Function_Value : Value; Arguments : Values.Vector;
         Destination, Protection : Natural);
      procedure Deliver
        (Activation : Frame_Access; Destination : Natural;
         Packet : Values.Vector);

      procedure Deliver
        (Activation : Frame_Access; Destination : Natural;
         Packet : Values.Vector)
      is
      begin
         --  A callback resumes its owning native activation instead of
         --  writing a Lua register. This is the single return-channel bridge.
         if Activation.Is_Native then
            Activation.Native_Results := Packet;
         elsif Destination /= 0 then
            Put_Packet (Activation, Destination, Packet);
         end if;
      end Deliver;

      procedure Schedule
        (Name : String; Arguments : Values.Vector; Destination : Natural;
         Operator : Token_Kind := End_Of_Input)
      is
         Activation : Frame_Access;
      begin
         if Natural (State.Stack.Length) >= State.Bounds.Call_Depth then
            Fail (State, "call depth limit exceeded", Resource => True);
         end if;
         State.Stack.Reserve_Capacity (State.Stack.Length + 1);
         Activation := new Frame;
         Activation.Is_Native := True;
         Activation.Native_Name := To_Unbounded_String (Name);
         Activation.Native_Arguments := Arguments;
         Activation.Native_Operator := Operator;
         Activation.Call_Site := State.Failure_At;
         Activation.Return_To := Destination;
         State.Stack.Append (Activation);
      end Schedule;

      function Wrap (Result : Values.Vector; Count : Natural;
                     Success : Boolean := True) return Values.Vector
      is
         Packet : Values.Vector;
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

      procedure Raise_Value (Item : Value; Level : Natural := 1) is
         Error_Value : Value := Item;
      begin
         --  Lua 5.5 normalizes nil errors before protected-call delivery.
         --  Preserve other arbitrary values, including false and tables.
         if Error_Value.Kind = Nil_Kind then
            Error_Value := New_String (State, "<no error object>");
         end if;
         if Item.Kind = String_Kind and then Level in 1 ..
           Natural (State.Stack.Length)
         then
            declare
               Activation : constant Frame_Access := State.Stack
                 (State.Stack.Last_Index - Level + 1);
               Line : constant Positive :=
                 (if Activation.Is_Native then Activation.Call_Site.Line
                  else Activation.Code.Code
                    (Positive'Max (1, Activation.PC - 1)).Location.Line);
            begin
               Error_Value := New_String
                 (State, (if Activation.Is_Native then "(native)"
                          else To_String (Activation.Code.Name)) & ":" &
                  Ada.Strings.Fixed.Trim (Line'Image, Ada.Strings.Both) &
                  ": " & Image (Item));
            end;
         end if;
         State.Failure := Error_Value;
         State.Has_Failure_Value := True;
         State.Failure_Text := To_Unbounded_String (Image (Error_Value));
         State.Is_Resource := False;
         raise Language_Error;
      end Raise_Value;

      function Native
        (Function_Id : Native_Kind; Arguments : Values.Vector)
         return Values.Vector
      is
         Result : Values.Vector;
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
               --  Capture output inside the universe first. The host sink
               --  runs only after execution, so it cannot reenter live frames
               --  or invalidate roots while this operation is in progress.
               for Position in Arguments.First_Index .. Arguments.Last_Index
               loop
                  if Position > 1 then
                     Append (State.Output, Ada.Characters.Latin_1.HT);
                  end if;
                  if Ada.Strings.Unbounded.Length (State.Output) +
                    Image (Arg (Position))'Length
                    >= State.Bounds.Output_Bytes
                  then
                     Fail (State, "output byte limit exceeded", True);
                  end if;
                  Append (State.Output, Image (Arg (Position)));
               end loop;
               if Ada.Strings.Unbounded.Length (State.Output) >=
                 State.Bounds.Output_Bytes
               then
                  Fail (State, "output byte limit exceeded", True);
               end if;
               Append (State.Output, Ada.Characters.Latin_1.LF);
            when Assert_Function =>
               Require (1);
               if not Truth (Arg (1)) then
                  if Arguments.Length >= 2 then
                     Raise_Value (Arg (2));
                  else
                     Raise_Value (New_String (State, "assertion failed!"));
                  end if;
               end if;
               return Arguments;
            when Error_Function =>
               Index := (if Arguments.Length >= 2 and then
                           Arg (2).Kind /= Nil_Kind then
                           Integral (State, Arg (2)) else 1);
               Raise_Value
                 (Arg (1), (if Index > 0 and then
                   Index <= Integer_Value (State.Stack.Length)
                   then Natural (Index) else 0));
            when Type_Function =>
               Require (1);
               Result.Append (New_String (State, Type_Name (Arg (1))));
            when Tostring_Function =>
               Require (1);
               Result.Append (New_String (State, Image (Arg (1))));
            when Tonumber_Function =>
               Require (1);
               if Arguments.Length >= 2 and then Arg (2).Kind /= Nil_Kind then
                  Index := Integral (State, Arg (2));
                  if Index not in 2 .. 36 or else
                    Arg (1).Kind /= String_Kind
                  then
                     Fail (State, "base 2..36 and string expected");
                  end if;
                  Number := Lua.Numbers.Read
                    (Image (Arg (1)), Base => Natural (Index));
               elsif Arg (1).Kind in Integer_Kind | Real_Kind then
                  Result.Append (Arg (1));
                  return Result;
               elsif Arg (1).Kind = String_Kind then
                  Number := Lua.Numbers.Read (Image (Arg (1)));
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
                 Ada.Strings.Unbounded.Length (Arg (1).Reference.Bytes) > 0
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
               --  ipairs validates its state lazily when its iterator is
               --  called; pairs validates the table immediately.
               if Function_Id = Pairs_Function then
                  Require_Table;
               else
                  Require (1);
               end if;
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
                  Index := Integer_Value (Ada.Strings.Unbounded.Length
                    (Arg (1).Reference.Bytes));
               elsif Arg (1).Kind = Table_Kind then
                  Index := Integer_Value (Table_Length (Arg (1)));
               else
                  Fail (State, "table or string expected");
               end if;
               Result.Append (Value'(Integer_Kind, Index));
            when Pcall_Function =>
               raise Program_Error with "pcall must use frame dispatch";
         end case;
         return Result;
      end Native;

      procedure Push_Frame
        (Function_Value : Value; Arguments : Values.Vector;
         Destination, Protection : Natural)
      is
         Item : Frame_Access;
         Prototype : constant Prototype_Access :=
           Function_Value.Reference.Code;
      begin
         --  A frame owns its fresh lexical scope and register packets.
         --  Publish it before parameter/vararg setup so the central cleanup
         --  path also owns partially initialized activations after failure.
         if Natural (State.Stack.Length) >= State.Bounds.Call_Depth then
            Fail (State, "call depth limit exceeded", Resource => True);
         end if;
         --  Reserve before allocating the frame: even a host allocation
         --  failure must leave either no frame or one owned by the stack.
         State.Stack.Reserve_Capacity (State.Stack.Length + 1);
         Item := new Frame;
         Item.Code := Prototype;
         Item.Return_To := Destination;
         Item.Protection := Protection;
         State.Stack.Append (Item);
         Item.Scope := New_Environment
           (State, Function_Value.Reference.Capture);
         Item.Slots.Set_Length
           (Ada.Containers.Count_Type (Prototype.Register_Count));
         if Prototype.Is_Main then
            Declare_Local (Item.Scope, Prototype.Environment_Symbol,
              (if Function_Value.Reference.Capture = null
               then (Table_Kind, State.Globals)
               else Read_Local (Function_Value.Reference.Capture,
                                Prototype.Environment_Symbol)));
         end if;
         for Position in Prototype.Parameters.First_Index ..
           Prototype.Parameters.Last_Index
         loop
            Declare_Local
              (Item.Scope, Prototype.Parameters (Position),
               (if Position <= Natural (Arguments.Length) then
                  Arguments (Position) else Nil_Value));
         end loop;
         if Prototype.Vararg then
            for Position in Natural (Prototype.Parameters.Length) + 1 ..
              Natural (Arguments.Length)
            loop
               Item.Varargs.Append (Arguments (Position));
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
               Declare_Local (Item.Scope, Prototype.Vararg_Name, Table);
               Item.Vararg_Table := Table.Reference;
               Item.Varargs.Clear;
            end;
         end if;
      end Push_Frame;

      procedure Complete (Result : Values.Vector) is
         Activation : Frame_Access := State.Stack.Last_Element;
         Destination : constant Natural := Activation.Return_To;
         Packet : constant Values.Vector :=
           Wrap (Result, Activation.Protection);
      begin
         --  Copy the outgoing packet before releasing its activation. No
         --  collection occurs until the caller's destination owns it again.
         --  The outermost chunk has no consumer and intentionally discards it.
         State.Stack.Delete_Last;
         Free_Frame (Activation);
         if not State.Stack.Is_Empty then
            Deliver (State.Stack.Last_Element, Destination, Packet);
         end if;
      end Complete;

      procedure Dispatch
        (Function_Value : Value; Arguments : Values.Vector;
         Destination : Natural; Tail : Boolean := False)
      is
         Function_Item : Value := Function_Value;
         Args : Values.Vector := Arguments;
         Protection : Natural := 0;
         Return_To : Natural := Destination;
         Packet : Values.Vector;
      begin
         --  pcall is a frame boundary, not a recursive invocation of Run.
         --  Tail calls replace the current frame while retaining the outer
         --  protected-return contract and the caller's destination register.
         declare
            Hops : Natural := 0;
            Handler : Value;
         begin
            loop
               if Function_Item.Kind = Native_Kind_Value and then
                 Function_Item.Native_Data = Pcall_Function
               then
                  Protection := Protection + 1;
                  if Protection > State.Bounds.Call_Depth then
                     Fail (State, "protected call limit exceeded", True);
                  end if;
                  Function_Item := First (Args);
                  if not Args.Is_Empty then
                     Args.Delete_First;
                  end if;
               elsif Function_Item.Kind in Closure_Kind |
                 Native_Closure_Kind | Native_Kind_Value
               then
                  exit;
               else
                  Handler := Metafield (State, Function_Item, "__call");
                  if Handler.Kind = Nil_Kind then
                     Fail (State, "attempt to call a " &
                             Diagnostic_Type (State, Function_Item) &
                             " value");
                  end if;
                  Hops := Hops + 1;
                  if Hops > 15 then
                     Fail (State, "call metamethod chain too long");
                  end if;
                  Args.Prepend (Function_Item);
                  Function_Item := Handler;
               end if;
            end loop;
         end;
         if Function_Item.Kind in Closure_Kind | Native_Closure_Kind then
            if Tail then
               declare
                  Old : Frame_Access := State.Stack.Last_Element;
               begin
                  Return_To := Old.Return_To;
                  Protection := Protection + Old.Protection;
                  State.Stack.Delete_Last;
                  Free_Frame (Old);
               end;
            end if;
            if Function_Item.Kind = Closure_Kind then
               Push_Frame (Function_Item, Args, Return_To, Protection);
            else
               Schedule (To_String (Function_Item.Reference.Native_Name),
                         Args, Return_To);
               State.Stack.Last_Element.Protection := Protection;
               State.Stack.Last_Element.Native_Captures :=
                 Function_Item.Reference.Captures;
               State.Stack.Last_Element.Native_Self := Function_Item.Reference;
            end if;
         else
            if Function_Item.Kind /= Native_Kind_Value then
               Fail (State, "attempt to call a " &
                       Type_Name (Function_Item) & " value");
            end if;
            Packet := Wrap
              (Native (Function_Item.Native_Data, Args), Protection);
            if Tail then
               Complete (Packet);
            else
               Deliver (State.Stack.Last_Element, Destination, Packet);
            end if;
         end if;
      exception
         when Language_Error =>
            if Protection = 0 or else State.Is_Resource then
               raise;
            end if;
            if not State.Has_Failure_Value then
               State.Failure := New_String
                 (State, To_String (State.Failure_Text));
            end if;
            Packet.Clear;
            Packet.Append (State.Failure);
            Packet := Wrap (Packet, Protection, Success => False);
            if Tail then
               Complete (Packet);
            else
               Deliver (State.Stack.Last_Element, Destination, Packet);
            end if;
            State.Failure := Nil_Value;
            State.Has_Failure_Value := False;
      end Dispatch;

      procedure Recover is
         Protected_Index : Natural := 0;
         Destination : Natural;
         Protection : Natural;
         Packet : Values.Vector;
      begin
         --  Resource exhaustion is a host execution boundary: allowing Lua
         --  pcall to catch it could restart an exhausted instruction budget.
         --  Ordinary errors unwind only to the nearest protected VM frame.
         if State.Is_Resource then
            raise Language_Error;
         end if;
         for Index in reverse State.Stack.First_Index ..
           State.Stack.Last_Index
         loop
            if State.Stack (Index).Protection > 0 then
               Protected_Index := Index;
               exit;
            end if;
         end loop;
         if Protected_Index = 0 then
            raise Language_Error;
         end if;
         Destination := State.Stack (Protected_Index).Return_To;
         Protection := State.Stack (Protected_Index).Protection;
         if not State.Has_Failure_Value then
            State.Failure := New_String
              (State, To_String (State.Failure_Text));
         end if;
         Packet.Append (State.Failure);
         Packet := Wrap (Packet, Protection, Success => False);
         while Natural (State.Stack.Length) >= Protected_Index loop
            declare
               Old : Frame_Access := State.Stack.Last_Element;
            begin
               State.Stack.Delete_Last;
               Free_Frame (Old);
            end;
         end loop;
         --  A protected tail call may have replaced the outermost chunk.
         --  Its caught failure completes that chunk successfully; there is
         --  no caller packet to receive the intentionally discarded results.
         if not State.Stack.Is_Empty then
            Deliver (State.Stack.Last_Element, Destination, Packet);
         end if;
         State.Failure := Nil_Value;
         State.Has_Failure_Value := False;
      end Recover;

      procedure Native_Step is
         Activation : constant Frame_Access := State.Stack.Last_Element;
         Name : constant String := To_String (Activation.Native_Name);
         function Arg (Index : Positive) return Value is
           (if Index <= Natural (Activation.Native_Arguments.Length)
            then Activation.Native_Arguments (Index) else Nil_Value);
         Packet : Values.Vector;
         Left : Value := Arg (1);
         Right : Value := Arg (2);
         Handler : Value;
         Event : Unbounded_String;
         Operator : Token_Kind := Activation.Native_Operator;
         Primitive : Boolean := False;
         Action : Native_Action;
         Library_Step : Boolean := True;
         procedure Finish (Item : Value);
         procedure Invoke (Function_Value : Value; Args : Values.Vector);
         procedure Finish (Item : Value) is
            Result : Values.Vector;
         begin
            Result.Append (Item);
            Complete (Result);
         end Finish;
         procedure Invoke (Function_Value : Value; Args : Values.Vector) is
         begin
            --  Publish the resume phase before dispatch: immediate builtins
            --  may return immediately; Lua closures suspend this frame.
            Activation.Native_Stage := 1;
            Dispatch (Function_Value, Args, 0);
         end Invoke;
      begin
         State.Failure_At := Activation.Call_Site;
         --  Stateful libraries own their continuation phase. Dispatch their
         --  requested callback through this same activation stack, so neither
         --  Lua nesting nor a protected error creates a second VM or budget.
         if Name in "string.gmatch" | "gmatch.iterator" | "string.gsub" then
            Action := Pattern_Drivers.Advance (State, Activation);
         elsif Name = "string.format" then
            Action := Format_Drivers.Advance (State, Activation);
         elsif Name in "table.concat" | "table.insert" | "table.remove" |
           "table.move" | "table.unpack"
         then
            Action := Table_Drivers.Advance (State, Activation);
         elsif Name in "base.load" | "base.loadfile" | "base.dofile" |
           "base.require" | "package.searchpath" |
           "package.preload_searcher" | "package.lua_searcher"
         then
            Action := Loaders.Advance (State, Activation);
         else
            Library_Step := False;
            Action.Kind := Continue_Step;
         end if;
         if Action.Kind = Finished then
            Complete (Action.Results);
            return;
         elsif Action.Kind = Invoke then
            Dispatch (Action.Function_Value, Action.Arguments, 0);
            return;
         elsif Library_Step then
            return;
         end if;
         if Activation.Native_Stage = 1 and then
           (Name in "@set" | "@invoke" | "@get" | "@binary" | "@unary" or else
            (Name'Length > 6 and then Name (1 .. 6) = "arith."))
         then
            if Name = "@set" then
               Complete (Values.Empty_Vector);
            elsif Name = "@invoke" then
               Complete (Activation.Native_Results);
            elsif Name = "@binary" and then
              Activation.Native_Operator in Equal | Not_Equal |
                Less | Less_Equal | Greater | Greater_Equal
            then
               Finish ((Boolean_Kind,
                        Truth (First (Activation.Native_Results)) xor
                        (Activation.Native_Operator = Not_Equal)));
            else
               Finish (First (Activation.Native_Results));
            end if;
            return;
         end if;
         if Name = "@invoke" then
            Handler := First (Activation.Native_Captures);
            Invoke (Handler, Activation.Native_Arguments);
         elsif Name in "@length" | "@equal" then
            if Activation.Native_Stage = 1 then
               Finish (First (Activation.Native_Results));
            else
               Activation.Native_Stage := 1;
               Schedule
                 ((if Name = "@length" then "@unary" else "@binary"),
                  Activation.Native_Arguments, 0,
                  (if Name = "@length" then Length else Equal));
            end if;
         elsif Name in "math.min" | "math.max" then
            if Activation.Native_Stage = 0 then
               if Activation.Native_Arguments.Is_Empty then
                  Fail (State, "value expected");
               end if;
               Activation.Native_Captures := Values.To_Vector (Left, 1);
               Activation.Native_Index := 2;
            elsif Truth (First (Activation.Native_Results)) then
               Activation.Native_Captures.Replace_Element
                 (1, Arg (Activation.Native_Index));
               Activation.Native_Index := Activation.Native_Index + 1;
            else
               Activation.Native_Index := Activation.Native_Index + 1;
            end if;
            if Activation.Native_Index >
              Natural (Activation.Native_Arguments.Length)
            then
               Finish (First (Activation.Native_Captures));
            else
               Left := First (Activation.Native_Captures);
               Right := Arg (Activation.Native_Index);
               Packet.Append ((if Name = "math.max" then Left else Right));
               Packet.Append ((if Name = "math.max" then Right else Left));
               Activation.Native_Stage := 1;
               Schedule ("@binary", Packet, 0, Less);
            end if;
         elsif Name = "base.xpcall" then
            --  The protected target is an ordinary dispatched call. Its
            --  packet returns to this rooted continuation before the error
            --  handler is requested, retaining arbitrary error objects.
            if Activation.Native_Stage = 0 then
               if Natural (Activation.Native_Arguments.Length) < 2 then
                  Fail (State, "xpcall needs a function and error handler");
               end if;
               if Arg (2).Kind not in Closure_Kind | Native_Closure_Kind |
                 Native_Kind_Value
               then
                  Fail (State, "error handler must be a function");
               end if;
               Packet.Append (Arg (1));
               for Index in 3 ..
                 Natural (Activation.Native_Arguments.Length)
               loop
                  Packet.Append (Arg (Index));
               end loop;
               Activation.Native_Stage := 1;
               Dispatch ((Native_Kind_Value, Pcall_Function), Packet, 0);
            elsif Activation.Native_Stage = 1 then
               if Truth (First (Activation.Native_Results)) then
                  Complete (Activation.Native_Results);
               else
                  Packet.Append (Arg (2));
                  Packet.Append (Activation.Native_Results (2));
                  Activation.Native_Stage := 2;
                  Dispatch ((Native_Kind_Value, Pcall_Function), Packet, 0);
               end if;
            else
               Packet.Append (Value'(Boolean_Kind, False));
               Packet.Append
                 ((if Truth (First (Activation.Native_Results)) then
                     (if Activation.Native_Results.Length >= 2 then
                         Activation.Native_Results (2) else Nil_Value)
                   else New_String (State, "error in error handling")));
               Complete (Packet);
            end if;
         elsif Name = "base.tostring" then
            if Activation.Native_Arguments.Is_Empty then
               Fail (State, "value expected");
            end if;
            if Activation.Native_Stage = 1 then
               Handler := First (Activation.Native_Results);
               if Handler.Kind not in String_Kind | Integer_Kind | Real_Kind
               then
                  Fail (State, "__tostring must return a string");
               end if;
               Finish (New_String (State, Image (Handler)));
            else
               Handler := Metafield (State, Left, "__tostring");
               if Handler.Kind /= Nil_Kind then
                  Packet.Append (Left);
                  Invoke (Handler, Packet);
               else
                  Finish (New_String (State, Image (Left)));
               end if;
            end if;
         elsif Name = "base.print" then
            if Activation.Native_Stage = 1 then
               Handler := First (Activation.Native_Results);
               if Image (Handler)'Length +
                 Boolean'Pos (Activation.Native_Index > 1) >
                 State.Bounds.Output_Bytes - Length (State.Output)
               then
                  Fail (State, "output byte limit exceeded", Resource => True);
               end if;
               if Activation.Native_Index > 1 then
                  Append (State.Output, Ada.Characters.Latin_1.HT);
               end if;
               Append (State.Output, Image (Handler));
               Activation.Native_Index := Activation.Native_Index + 1;
               Activation.Native_Stage := 0;
            elsif Activation.Native_Index = 0 then
               Activation.Native_Index := 1;
            end if;
            if Activation.Native_Index >
              Natural (Activation.Native_Arguments.Length)
            then
               if Length (State.Output) >= State.Bounds.Output_Bytes then
                  Fail (State, "output byte limit exceeded", Resource => True);
               end if;
               Append (State.Output, Ada.Characters.Latin_1.LF);
               Complete (Values.Empty_Vector);
            else
               Packet.Append (Arg (Activation.Native_Index));
               Activation.Native_Stage := 1;
               Schedule ("base.tostring", Packet, 0);
            end if;
         elsif Name = "base.pairs" then
            if Activation.Native_Stage = 1 then
               Packet := Activation.Native_Results;
            else
               Handler := Metafield (State, Left, "__pairs");
               if Handler.Kind /= Nil_Kind then
                  Packet.Append (Left);
                  Invoke (Handler, Packet);
                  return;
               end if;
               Packet := Native (Pairs_Function, Activation.Native_Arguments);
            end if;
            Packet.Set_Length (4);
            Complete (Packet);
         elsif Name = "base.ipairs" then
            if Activation.Native_Arguments.Is_Empty then
               Fail (State, "value expected");
            end if;
            Packet.Append (New_Native (State, "@ipairs.step"));
            Packet.Append (Left);
            Packet.Append (Value'(Integer_Kind, 0));
            Complete (Packet);
         elsif Name = "@ipairs.step" then
            if Activation.Native_Stage = 0 then
               Right := (Integer_Kind,
                 Lua.Integers.Add (Integral (State, Right), 1));
               Activation.Native_Captures := Values.To_Vector (Right, 1);
               Packet.Append (Left);
               Packet.Append (Right);
               Activation.Native_Stage := 1;
               Schedule ("@get", Packet, 0);
            else
               Handler := First (Activation.Native_Results);
               if Handler.Kind /= Nil_Kind then
                  Packet.Append (First (Activation.Native_Captures));
               end if;
               Packet.Append (Handler);
               Complete (Packet);
            end if;
         elsif Name in "@get" | "@set" then
            loop
               if Name = "@get" then
                  if Left.Kind = Table_Kind then
                     Handler := Get (Left, Right);
                     if Handler.Kind /= Nil_Kind then
                        Finish (Handler);
                        return;
                     end if;
                  end if;
                  Handler := Metafield (State, Left, "__index");
               else
                  if Left.Kind = Table_Kind and then
                    Get (Left, Right).Kind /= Nil_Kind
                  then
                     Set (State, Left, Right, Arg (3));
                     Complete (Values.Empty_Vector);
                     return;
                  end if;
                  Handler := Metafield (State, Left, "__newindex");
               end if;
               if Handler.Kind = Nil_Kind then
                  if Left.Kind /= Table_Kind then
                     Fail (State, "attempt to index a " & Type_Name (Left));
                  elsif Name = "@get" then
                     Finish (Nil_Value);
                  else
                     Set (State, Left, Right, Arg (3));
                     Complete (Values.Empty_Vector);
                  end if;
                  return;
               elsif Handler.Kind in Closure_Kind | Native_Closure_Kind |
                 Native_Kind_Value
               then
                  Activation.Native_Arguments.Replace_Element (1, Left);
                  Invoke (Handler, Activation.Native_Arguments);
                  return;
               end if;
               Activation.Native_Aux := Activation.Native_Aux + 1;
               if State.Steps >= State.Bounds.Instructions then
                  Fail (State, "instruction limit exceeded", Resource => True);
               end if;
               State.Steps := State.Steps + 1;
               if Activation.Native_Aux >= 2000 then
                  Fail (State, "metatable index chain too long");
               end if;
               Left := Handler;
            end loop;
         elsif Name in "@binary" | "@unary" then
            if Name = "@unary" then
               Primitive := Operator = Not_Word or else
                 (Operator = Length and then Left.Kind = String_Kind) or else
                 (Operator in Minus | Bit_Xor and then
                    Left.Kind in Integer_Kind | Real_Kind);
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
               if Operator = Concatenate then
                  Primitive := Left.Kind in String_Kind | Integer_Kind |
                    Real_Kind and then Right.Kind in String_Kind |
                    Integer_Kind | Real_Kind;
               end if;
               if Operator in Equal | Not_Equal then
                  Primitive := Equal (Left, Right) or else
                    Left.Kind /= Table_Kind or else Right.Kind /= Table_Kind;
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
                  Finish ((Boolean_Kind, Operator = Not_Equal));
                  return;
               elsif Left.Kind = String_Kind and then
                 Operator not in Concatenate | Equal | Not_Equal |
                   Less | Less_Equal | Greater | Greater_Equal
               then
                  Fail (State, "no arithmetic metamethod for string");
               end if;
            end if;
            Finish ((if Name = "@unary"
                     then Unary_Value (State, Operator, Left)
                     else Binary_Value (State, Operator, Left, Right)));
         elsif Name = "base.getmetatable" then
            if Activation.Native_Arguments.Is_Empty then
               Fail (State, "value expected");
            end if;
            Handler := Metafield (State, Left, "__metatable");
            if Handler.Kind /= Nil_Kind then
               Finish (Handler);
            elsif Left.Kind = Table_Kind and then
              Left.Reference.Metatable /= null
            then
               Finish ((Table_Kind, Left.Reference.Metatable));
            elsif Left.Kind = String_Kind and then
              State.String_Metatable /= null
            then
               Finish ((Table_Kind, State.String_Metatable));
            else
               Finish (Nil_Value);
            end if;
         elsif Name = "base.setmetatable" then
            if Left.Kind /= Table_Kind then
               Fail (State, "table expected");
            elsif Right.Kind not in Nil_Kind | Table_Kind then
               Fail (State, "nil or table expected");
            elsif Metafield (State, Left, "__metatable").Kind /= Nil_Kind then
               Fail (State, "cannot change a protected metatable");
            end if;
            Left.Reference.Metatable :=
              (if Right.Kind = Nil_Kind then null else Right.Reference);
            Finish (Left);
         elsif Name'Length > 6 and then Name (1 .. 6) = "arith." then
            Event := To_Unbounded_String (Name (7 .. Name'Last));
            Operator :=
              (if Event = "__add" then Plus
               elsif Event = "__sub" or else Event = "__unm" then Minus
               elsif Event = "__mul" then Star
               elsif Event = "__mod" then Percent
               elsif Event = "__div" then Slash
               elsif Event = "__idiv" then Floor_Divide else Power);
            if Event = "__unm" then
               Right := Left;
            end if;
            declare
               function Convert (Item : Value) return Lua.Numbers.Number;
               function Convert (Item : Value) return Lua.Numbers.Number is
               begin
                  if Item.Kind = String_Kind then
                     return Lua.Numbers.Read
                       (To_String (Item.Reference.Bytes));
                  elsif Item.Kind = Integer_Kind then
                     return (Lua.Numbers.Integer_Number, Item.Integer_Data);
                  elsif Item.Kind = Real_Kind then
                     return (Lua.Numbers.Real_Number, Item.Real_Data);
                  else
                     return (Kind => Lua.Numbers.Invalid);
                  end if;
               end Convert;
               L : constant Lua.Numbers.Number := Convert (Left);
               R : constant Lua.Numbers.Number := Convert (Right);
            begin
               if L.Kind /= Lua.Numbers.Invalid and then
                 R.Kind /= Lua.Numbers.Invalid
               then
                  Finish ((if Event = "__unm"
                           then Unary_Value (State, Minus, Left)
                           else Binary_Value (State, Operator, Left, Right)));
               else
                  Handler := (if Right.Kind /= String_Kind
                              then Metafield (State, Right, To_String (Event))
                              else Nil_Value);
                  if Handler.Kind = Nil_Kind then
                     Fail (State, "attempt to perform arithmetic on a " &
                             Type_Name (Left));
                  end if;
                  Packet.Append (Left);
                  Packet.Append (Right);
                  Invoke (Handler, Packet);
               end if;
            end;
         elsif Name'Length > 5 and then
           (Name (1 .. 5) = "math." or else Name (1 .. 6) = "table.")
         then
            Complete (Core_Libraries.Run
              (State, Name, Activation.Native_Arguments));
         elsif Name'Length > 7 and then Name (1 .. 7) = "string." then
            if Name in "string.pack" | "string.packsize" | "string.unpack"
            then
               Complete (Packing.Run
                 (State, Name (8 .. Name'Last), Activation.Native_Arguments));
            else
               Complete (Strings.Run
                 (State, Name (8 .. Name'Last), Activation.Native_Arguments));
            end if;
         elsif Name'Length > 5 and then Name (1 .. 5) = "utf8." then
            if Name = "utf8.codes" then
               Packet.Append (New_Native
                 (State, "utf8.step", Values.To_Vector (Arg (2), 1)));
               for Item of Unicode.Run
                 (State, "codes", Activation.Native_Arguments)
               loop
                  Packet.Append (Item);
               end loop;
               Complete (Packet);
            elsif Name = "utf8.step" then
               Packet := Activation.Native_Arguments;
               Packet.Append (First (Activation.Native_Captures));
               Complete (Unicode.Run (State, "step", Packet));
            else
               Complete (Unicode.Run
                 (State, Name (6 .. Name'Last), Activation.Native_Arguments));
            end if;
         else
            Fail (State, "native continuation not implemented: " & Name);
         end if;
      end Native_Step;

      procedure Step is
         --  Copy the instruction before dispatch: calls may replace the
         --  current activation, and a tail call may free it entirely.
         Activation : constant Frame_Access := State.Stack.Last_Element;
         Code : constant Instruction := Activation.Code.Code (Activation.PC);
         A : constant Natural := Code.A;
         B : constant Natural := Code.B;
         C : constant Natural := Code.C;
         Packet : Values.Vector;
         Left, Right, Item : Value;
         L, R, S : Lua.Numbers.Number;
         Control, Bound, Stride : Integer_Value;
         Real_Control, Real_Bound, Real_Delta : Real_Value;
      begin
         Activation.PC := Activation.PC + 1;
         State.Failure_At := Code.Location;
         case Code.Op is
            when No_Operation => null;
            when Clear_Registers =>
               for Register_Id in A .. B loop
                  Put_Packet (Activation, Register_Id, Values.Empty_Vector);
               end loop;
            when Load_Value => Put_One (Activation, A, Code.Literal);
            when Load_String =>
               Put_One (Activation, A,
                        New_String (State, To_String (Code.Text)));
            when Move_First => Put_One (Activation, A, Scalar (Activation, B));
            when Read_Local =>
               Put_One (Activation, A, Read_Local (Activation.Scope, B));
            when Write_Local =>
               Write_Local (Activation.Scope, B, Scalar (Activation, A));
            when Declare_Local =>
               Declare_Local (Activation.Scope, B, Scalar (Activation, A));
            when Enter_Scope =>
               Activation.Scope := New_Environment (State, Activation.Scope);
            when Leave_Scope => Activation.Scope := Activation.Scope.Parent;
            when New_Table => Put_One (Activation, A, New_Table (State));
            when Get_Item =>
               Packet.Append (Scalar (Activation, B));
               Packet.Append (Scalar (Activation, C));
               Schedule ("@get", Packet, A);
            when Set_Item =>
               Packet.Append (Scalar (Activation, A));
               Packet.Append (Scalar (Activation, B));
               Packet.Append (Scalar (Activation, C));
               Schedule ("@set", Packet, 0);
            when Set_Sequence =>
               Packet := Flatten (Activation, Code.Inputs, C /= 0);
               for Index in Packet.First_Index .. Packet.Last_Index loop
                  Set (State, Scalar (Activation, A),
                       (Integer_Kind, Integer_Value (B + Index - 1)),
                       Packet (Index));
               end loop;
            when Unary =>
               Packet.Append (Scalar (Activation, B));
               Schedule ("@unary", Packet, A, Code.Operator);
            when Binary =>
               Packet.Append (Scalar (Activation, B));
               Packet.Append (Scalar (Activation, C));
               Schedule ("@binary", Packet, A, Code.Operator);
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
               Put_One (Activation, A,
                        New_Closure (State, Code.Nested, Activation.Scope));
            when Read_Varargs =>
               if Activation.Vararg_Table = null then
                  Put_Packet (Activation, A, Activation.Varargs);
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
                  Put_Packet (Activation, A, Packet);
               end if;
            when Pick_Value =>
               Packet := Flatten (Activation, Code.Inputs);
               Put_One (Activation, A,
                        (if B <= Natural (Packet.Length) then Packet (B)
                         else Nil_Value));
            when Return_Values => Complete (Flatten (Activation, Code.Inputs));
            when Call_Function | Tail_Call =>
               Dispatch (Scalar (Activation, B),
                         Flatten (Activation, Code.Inputs), A,
                         Tail => Code.Op = Tail_Call);
            when Check_Global =>
               if Get (Scalar (Activation, A), Scalar (Activation, B)).Kind /=
                 Nil_Kind
               then
                  Fail (State, "global '" & Image (Scalar (Activation, B)) &
                          "' already defined");
               end if;
            when Check_Iterator =>
               if Truth (Scalar (Activation, A)) then
                  Fail (State, "to-be-closed iterators are outside M1");
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
                  Put_One (Activation, A, (Integer_Kind, Control));
                  Put_One (Activation, C, (Integer_Kind, Stride));
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
                        Put_One (Activation, A, Nil_Value);
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
                  Put_One (Activation, B, (Integer_Kind, Bound));
               else
                  Real_Delta := Lua.Numbers.To_Real (S);
                  if Real_Delta = 0.0 then
                     Fail (State, "for step is zero");
                  end if;
                  Put_One (Activation, A,
                           (Real_Kind, Lua.Numbers.To_Real (L)));
                  Put_One (Activation, B,
                           (Real_Kind, Lua.Numbers.To_Real (R)));
                  Put_One (Activation, C, (Real_Kind, Real_Delta));
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
                  Put_One (Activation, A, (Integer_Kind, Control + Stride));
               else
                  Put_One (Activation, A,
                    (Real_Kind,
                     Left.Real_Data + Scalar (Activation, C).Real_Data));
               end if;
               Activation.PC := Code.Target;
         end case;
      end Step;
   begin
      Dispatch (New_Closure (State, Code, null), State.Arguments, 0);
      while not State.Stack.Is_Empty loop
         --  At this boundary every live value is in a frame packet, lexical
         --  cell, closure capture, globals table, or the explicit error root.
         if Natural (State.Heap.Length) >= State.Next_GC then
            Collect (State);
         end if;
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         State.Steps := State.Steps + 1;
         begin
            if State.Stack.Last_Element.Is_Native then
               Native_Step;
            else
               Step;
            end if;
         exception
            when Language_Error => Recover;
         end;
      end loop;
   end Run;
end Lua.Engine.Machine;
