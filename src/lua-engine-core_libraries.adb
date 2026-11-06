with Ada.Containers;
with Ada.Unchecked_Conversion;
with Interfaces;
with Lua.Integers;

package body Lua.Engine.Core_Libraries is
   use type Ada.Containers.Count_Type;
   use type Integer_Value;
   use type Real_Value;
   use type Interfaces.Unsigned_64;
   use type Lua.Numbers.Number_Kind;
   subtype Bits is Interfaces.Unsigned_64;
   function To_Bits is new Ada.Unchecked_Conversion (Real_Value, Bits);
   function From_Bits is new Ada.Unchecked_Conversion (Bits, Real_Value);
   function Integer_Bits is new Ada.Unchecked_Conversion (Integer_Value, Bits);
   Sign : constant Bits := 2 ** 63;
   Fraction : constant Bits := 2 ** 52 - 1;
   Hidden : constant Bits := 2 ** 52;
   Exponent : constant Bits := 16#7FF0_0000_0000_0000#;

   function As_Integer (Item : Lua.Numbers.Number; Valid : out Boolean)
                        return Integer_Value;
   function As_Integer (Item : Lua.Numbers.Number; Valid : out Boolean)
                        return Integer_Value
   is
      Number : Real_Value;
   begin
      Valid := True;
      if Item.Kind = Lua.Numbers.Integer_Number then
         return Item.Integer_Item;
      elsif Item.Kind = Lua.Numbers.Real_Number then
         Number := Item.Real_Item;
         --  The upper test is strict: binary64 rounds int64'Last to 2**63.
         --  Guard NaN/infinity before integer conversion or floor evaluation.
         if Number = Number and then Number >= -(2.0 ** 63) and then
           Number < 2.0 ** 63 and then Real_Value'Floor (Number) = Number
         then
            return Integer_Value (Number);
         end if;
      end if;
      Valid := False;
      return 0;
   end As_Integer;

   function Number_Value (Item : Real_Value) return Value;
   function Number_Value (Item : Real_Value) return Value is
      Valid : Boolean;
      Integral : constant Integer_Value := As_Integer
        ((Lua.Numbers.Real_Number, Item), Valid);
   begin
      return (if Valid then (Integer_Kind, Integral)
              else (Real_Kind, Item));
   end Number_Value;

   function Remainder
     (State : in out World; Left, Right : Real_Value) return Real_Value;
   function Remainder
     (State : in out World; Left, Right : Real_Value) return Real_Value
   is
      X : constant Bits := To_Bits (Left);
      Y : constant Bits := To_Bits (Right);
      AX : constant Bits := X and not Sign;
      AY : constant Bits := Y and not Sign;
      MX, MY : Bits;
      EX, EY, Encoded : Integer;
      procedure Charge;
      procedure Charge is
      begin
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         if State.Policy = Bounded then
            State.Steps := State.Steps + 1;
         end if;
      end Charge;
   begin
      --  Reduce the exact dyadic significands, never a rounded X/Y quotient.
      --  This remains exact when quotient magnitude exceeds binary64's range.
      if AX > Exponent or else AY > Exponent then
         return Left + Right;
      elsif AX = Exponent then
         return Left - Left;
      elsif AY = 0 then
         return Right / Right;
      elsif AX < AY or else AY = Exponent then
         return Left;
      elsif AX = AY then
         return From_Bits (X and Sign);
      end if;
      EX := Integer (Interfaces.Shift_Right (AX, 52)) - 1075;
      EY := Integer (Interfaces.Shift_Right (AY, 52)) - 1075;
      MX := AX and Fraction;
      MY := AY and Fraction;
      if EX = -1075 then
         EX := -1074;
      else
         MX := MX or Hidden;
      end if;
      if EY = -1075 then
         EY := -1074;
      else
         MY := MY or Hidden;
      end if;
      --  Normalize subnormal operands with integer shifts. At most 52 shifts
      --  are required; every subsequent reduction iteration removes one bit
      --  of exponent distance, giving a fixed bound for IEEE binary64.
      while MX < Hidden loop
         Charge;
         MX := MX * 2;
         EX := EX - 1;
      end loop;
      while MY < Hidden loop
         Charge;
         MY := MY * 2;
         EY := EY - 1;
      end loop;
      while EX > EY loop
         Charge;
         if MX >= MY then
            MX := MX - MY;
         end if;
         MX := MX * 2;
         EX := EX - 1;
      end loop;
      if MX >= MY then
         MX := MX - MY;
      end if;
      if MX = 0 then
         return From_Bits (X and Sign);
      end if;
      while MX < Hidden loop
         Charge;
         MX := MX * 2;
         EX := EX - 1;
      end loop;
      Encoded := EX + 1075;
      if Encoded > 0 then
         MX := Interfaces.Shift_Left (Bits (Encoded), 52) or
           (MX and Fraction);
      else
         MX := Interfaces.Shift_Right (MX, Natural (1 - Encoded));
      end if;
      return From_Bits (MX or (X and Sign));
   end Remainder;

   function Run
     (State : in out World; Name : String; Arguments : Values.Vector)
      return Values.Vector
   is
      Result : Values.Vector;
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Arguments.Length) then Arguments (Index)
         else Nil_Value);
      procedure Charge;
      procedure Require (Count : Positive);
      function Numeric (Index : Positive) return Lua.Numbers.Number;
      function Integral (Index : Positive) return Integer_Value;
      function Text (Item : Value) return String;
      procedure Require_Table (Item : Value);
      function Less (Left, Right : Value) return Boolean;
      function Key (Index : Integer_Value) return Value is
        ((Integer_Kind, Index));
      Item, Other, Destination : Value;
      Number : Lua.Numbers.Number;
      R, Whole : Real_Value;
      A, B, First, Last, Position, Count : Integer_Value;
      Valid : Boolean;
      Buffer, Separator : Unbounded_String;

      procedure Charge is
      begin
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         if State.Policy = Bounded then
            State.Steps := State.Steps + 1;
         end if;
      end Charge;

      procedure Require (Count : Positive) is
      begin
         if Natural (Arguments.Length) < Count then
            Fail (State, "bad argument to " & Name & " (value expected)");
         end if;
      end Require;

      function Numeric (Index : Positive) return Lua.Numbers.Number is
         Item : constant Value := Arg (Index);
         Parsed : Lua.Numbers.Number;
      begin
         case Item.Kind is
            when Integer_Kind =>
               return (Lua.Numbers.Integer_Number, Item.Integer_Data);
            when Real_Kind =>
               return (Lua.Numbers.Real_Number, Item.Real_Data);
            when String_Kind =>
               Parsed := Lua.Numbers.Read (To_String (Item.Reference.Bytes));
               if Parsed.Kind /= Lua.Numbers.Invalid then
                  return Parsed;
               end if;
            when others => null;
         end case;
         Fail (State, "bad argument to " & Name & " (number expected)");
         return (Kind => Lua.Numbers.Invalid);
      end Numeric;

      function Integral (Index : Positive) return Integer_Value is
         Valid : Boolean;
         Value : constant Integer_Value := As_Integer (Numeric (Index), Valid);
      begin
         if not Valid then
            Fail (State, "number has no integer representation");
         end if;
         return Value;
      end Integral;

      function Text (Item : Value) return String is
      begin
         if Item.Kind = String_Kind then
            return To_String (Item.Reference.Bytes);
         elsif Item.Kind in Integer_Kind | Real_Kind then
            return Image (Item);
         end if;
         Fail (State, "invalid value (" & Type_Name (Item) &
               ") in table for 'concat'");
         return "";
      end Text;

      procedure Require_Table (Item : Value) is
      begin
         if Item.Kind /= Table_Kind then
            Fail (State, "bad argument to " & Name & " (table expected)");
         end if;
      end Require_Table;

      function Less (Left, Right : Value) return Boolean is
         function Number (Item : Value) return Lua.Numbers.Number is
           (if Item.Kind = Integer_Kind then
              (Lua.Numbers.Integer_Number, Item.Integer_Data)
            else (Lua.Numbers.Real_Number, Item.Real_Data));
      begin
         if Left.Kind in Integer_Kind | Real_Kind and then
           Right.Kind in Integer_Kind | Real_Kind
         then
            return Lua.Numbers.Less (Number (Left), Number (Right));
         elsif Left.Kind = String_Kind and then Right.Kind = String_Kind then
            return To_String (Left.Reference.Bytes) <
              To_String (Right.Reference.Bytes);
         end if;
         Fail (State, "attempt to compare " & Type_Name (Left) & " with " &
               Type_Name (Right));
         return False;
      end Less;
   begin
      Charge;
      if Name = "table.pack" then
         Item := New_Table (State);
         for Index in Arguments.First_Index .. Arguments.Last_Index loop
            Charge;
            Set (State, Item, Key (Integer_Value (Index)), Arguments (Index));
         end loop;
         Set (State, Item, New_String (State, "n"),
              Key (Integer_Value (Arguments.Length)));
         Result.Append (Item);
         return Result;
      end if;
      Require (1);
      Item := Arg (1);
      if Name = "math.type" then
         Result.Append
           ((if Item.Kind = Integer_Kind then New_String (State, "integer")
             elsif Item.Kind = Real_Kind then New_String (State, "float")
             else Nil_Value));
      elsif Name = "math.tointeger" then
         if Item.Kind not in Integer_Kind | Real_Kind | String_Kind then
            Result.Append (Nil_Value);
         else
            Number := (if Item.Kind = String_Kind then
                         Lua.Numbers.Read (To_String (Item.Reference.Bytes))
                       else Numeric (1));
            A := As_Integer (Number, Valid);
            Result.Append ((if Valid then Key (A) else Nil_Value));
         end if;
      elsif Name = "math.max" or else Name = "math.min" then
         for Index in 2 .. Natural (Arguments.Length) loop
            Charge;
            if (if Name = "math.max" then Less (Item, Arguments (Index))
                else Less (Arguments (Index), Item))
            then
               Item := Arguments (Index);
            end if;
         end loop;
         Result.Append (Item);
      elsif Name = "math.ult" then
         Require (2);
         A := Integral (1);
         B := Integral (2);
         Result.Append
           (Value'(Boolean_Kind, Integer_Bits (A) < Integer_Bits (B)));
      elsif Name = "math.fmod" then
         Require (2);
         if Item.Kind = Integer_Kind and then Arg (2).Kind = Integer_Kind then
            A := Item.Integer_Data;
            B := Arg (2).Integer_Data;
            if B = 0 then
               Fail (State, "bad argument #2 to fmod (zero)");
            end if;
            Result.Append (Key ((if B = -1 then 0 else A rem B)));
         else
            Result.Append (Value'(Real_Kind, Remainder
              (State, Lua.Numbers.To_Real (Numeric (1)),
               Lua.Numbers.To_Real (Numeric (2)))));
         end if;
      elsif Name in "math.abs" | "math.ceil" | "math.floor" | "math.modf"
      then
         if Item.Kind = Integer_Kind then
            A := Item.Integer_Data;
            if Name = "math.abs" and then A < 0 then
               A := Lua.Integers.Negate (A);
            end if;
            Result.Append (Key (A));
            if Name = "math.modf" then
               Result.Append (Value'(Real_Kind, 0.0));
            end if;
         else
            R := Lua.Numbers.To_Real (Numeric (1));
            if Name = "math.abs" then
               Result.Append
                 (Value'(Real_Kind, From_Bits (To_Bits (R) and not Sign)));
            else
               if (To_Bits (R) and Exponent) = Exponent then
                  Whole := R;
               elsif Name = "math.ceil" or else
                 (Name = "math.modf" and then R < 0.0)
               then
                  Whole := Real_Value'Ceiling (R);
               else
                  Whole := Real_Value'Floor (R);
               end if;
               Result.Append (Number_Value (Whole));
               if Name = "math.modf" then
                  Result.Append
                    (Value'(Real_Kind,
                            (if R = Whole then 0.0 else R - Whole)));
               end if;
            end if;
         end if;
      elsif Name = "table.unpack" then
         Require_Table (Item);
         First := (if Arg (2).Kind = Nil_Kind then 1 else Integral (2));
         Last := (if Arg (3).Kind = Nil_Kind then
                    Integer_Value (Table_Length (Item)) else Integral (3));
         if Last >= First then
            if First <= 0 and then Last >= Integer_Value'Last + First then
               Fail (State, "too many results to unpack");
            end if;
            Count := Last - First + 1;
            if Name = "table.unpack" and then Count > Integer_Value
              (1_000_000 - Natural'Min
                 (1_000_000, State.Current.Stack_Slots))
            then
               Fail (State, "too many results to unpack (stack overflow)");
            end if;
            if Count > Integer_Value (State.Bounds.Table_Entries) then
               Fail (State, "result count limit exceeded", Resource => True);
            end if;
            for Index in Integer_Value range 0 .. Count - 1 loop
               Charge;
               Result.Append (Get (Item, Key (First + Index)));
            end loop;
         end if;
      elsif Name = "table.concat" then
         Require_Table (Item);
         Separator := (if Arg (2).Kind = Nil_Kind then Null_Unbounded_String
                       else To_Unbounded_String (Text (Arg (2))));
         First := (if Arg (3).Kind = Nil_Kind then 1 else Integral (3));
         Last := (if Arg (4).Kind = Nil_Kind then
                    Integer_Value (Table_Length (Item)) else Integral (4));
         A := First;
         while First <= Last loop
            Charge;
            declare
               Part : constant String := Text (Get (Item, Key (First)));
               Added : constant Natural := Part'Length +
                 (if First = A then 0 else Length (Separator));
            begin
               if Added > State.Bounds.String_Bytes - Length (Buffer) then
                  Fail (State, "string byte limit exceeded", Resource => True);
               end if;
               if First /= A then
                  Append (Buffer, Separator);
               end if;
               Append (Buffer, Part);
            end;
            exit when First = Last;
            First := First + 1;
         end loop;
         Result.Append (New_String (State, To_String (Buffer)));
      elsif Name = "table.insert" then
         Require_Table (Item);
         Last := Integer_Value (Table_Length (Item));
         if Arguments.Length = 2 then
            Position := Last + 1;
            Other := Arg (2);
         elsif Arguments.Length = 3 then
            Position := Integral (2);
            Other := Arg (3);
         else
            Fail (State, "wrong number of arguments to insert");
         end if;
         if Position < 1 or else Position > Last + 1 then
            Fail (State, "position out of bounds");
         end if;
         for Index in reverse Position .. Last loop
            Charge;
            Set (State, Item, Key (Index + 1), Get (Item, Key (Index)));
         end loop;
         Set (State, Item, Key (Position), Other);
      elsif Name = "table.remove" then
         Require_Table (Item);
         Last := Integer_Value (Table_Length (Item));
         Position := (if Arg (2).Kind = Nil_Kind then Last else Integral (2));
         if Position /= Last and then
           (Position < 1 or else Position > Last + 1)
         then
            Fail (State, "position out of bounds");
         end if;
         Result.Append (Get (Item, Key (Position)));
         while Position < Last loop
            Charge;
            Set (State, Item, Key (Position), Get (Item, Key (Position + 1)));
            Position := Position + 1;
         end loop;
         Set (State, Item, Key (Position), Nil_Value);
      elsif Name = "table.move" then
         Require (4);
         Require_Table (Item);
         Destination := (if Arg (5).Kind = Nil_Kind then Item else Arg (5));
         Require_Table (Destination);
         First := Integral (2);
         Last := Integral (3);
         Position := Integral (4);
         if Last >= First then
            --  Check semantic arithmetic before iteration/allocation limits.
            if First <= 0 and then Last >= Integer_Value'Last + First then
               Fail (State, "too many elements to move");
            end if;
            Count := Last - First + 1;
            if Position > Integer_Value'Last - Count + 1 then
               Fail (State, "destination wrap around");
            end if;
            if Count > Integer_Value (State.Bounds.Table_Entries) then
               Fail (State, "table move work limit exceeded",
                     Resource => True);
            end if;
            --  Preserve overlapping ranges by copying the trailing element
            --  first only when both ranges belong to the same raw table.
            if Equal (Item, Destination) and then
              Position > First and then Position <= Last
            then
               for Offset in reverse Integer_Value range 0 .. Count - 1 loop
                  Charge;
                  Set (State, Destination, Key (Position + Offset),
                       Get (Item, Key (First + Offset)));
               end loop;
            else
               for Offset in Integer_Value range 0 .. Count - 1 loop
                  Charge;
                  Set (State, Destination, Key (Position + Offset),
                       Get (Item, Key (First + Offset)));
               end loop;
            end if;
         end if;
         Result.Append (Destination);
      else
         Fail (State, "unknown core library function: " & Name);
      end if;
      return Result;
   end Run;
end Lua.Engine.Core_Libraries;
