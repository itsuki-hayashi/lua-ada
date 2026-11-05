with Ada.Characters.Latin_1;
with Ada.Unchecked_Conversion;
with Ada.Strings.Fixed;
with Ada.Numerics.Big_Numbers.Big_Integers;

package body Lua.Numbers is
   use type Interfaces.Unsigned_64;
   use type Real_Value;
   use type Integer_Value;
   package Big renames Ada.Numerics.Big_Numbers.Big_Integers;
   package Big_Unsigned is new Big.Unsigned_Conversions
     (Interfaces.Unsigned_64);
   use type Big.Big_Integer;

   function From_Bits is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, Real_Value);
   --  This isolated conversion constructs rounded IEEE representations.
   --  No foreign addresses or pointer reinterpretations enter the parser.

   function Digit (Item : Character) return Integer is
     (case Item is
         when '0' .. '9' => Character'Pos (Item) - Character'Pos ('0'),
         when 'a' .. 'z' => Character'Pos (Item) - Character'Pos ('a') + 10,
         when 'A' .. 'Z' => Character'Pos (Item) - Character'Pos ('A') + 10,
         when others => -1);

   function Space (Item : Character) return Boolean is
     (Item in ' ' | Ada.Characters.Latin_1.HT ..
        Ada.Characters.Latin_1.CR);

   function Signed
     (Bits : Interfaces.Unsigned_64; Negative : Boolean) return Integer_Value;
   function Exact_Real
     (Mantissa : String; Radix : Positive; Exponent : Integer)
      return Real_Value;

   function Exact_Real
     (Mantissa : String; Radix : Positive; Exponent : Integer)
      return Real_Value
   is
      Numerator : Big.Big_Integer := 0;
      Denominator : Big.Big_Integer := 1;
      Quotient, Residue : Big.Big_Integer := 0;
      Kept, Dropped, Fraction : Natural := 0;
      After_Point, Significant, Sticky : Boolean := False;
      Scale, Binary_Exponent, Shift : Integer;
      Bits : Interfaces.Unsigned_64;
      function Bit_Length (Item : Big.Big_Integer) return Positive;

      function Bit_Length (Item : Big.Big_Integer) return Positive is
         Text : constant String := Big.To_String (Item, Base => 2);
         Opening : constant Natural := Ada.Strings.Fixed.Index (Text, "#");
         Closing : constant Natural := Ada.Strings.Fixed.Index
           (Text, "#", Going => Ada.Strings.Backward);
      begin
         return (if Opening /= 0 then Closing - Opening - 1
                 else Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both)'Length);
      end Bit_Length;
   begin
      --  Build an exact rational rather than relying on host strtod/Value
      --  rounding at the subnormal boundary. Leading zeros need no storage.
      --  Binary64 midpoints have terminating decimal expansions within 1075
      --  fractional places. Keeping 1100 significant digits plus a sticky bit
      --  therefore suffices to decide every binary64 halfway case.
      for Character_Value of Mantissa loop
         if Character_Value = '.' then
            After_Point := True;
         else
            if After_Point then
               Fraction := Fraction + 1;
            end if;
            Significant := Significant or else Digit (Character_Value) /= 0;
            if Significant then
               if Kept < 1_100 then
                  Numerator := Numerator * Big.To_Big_Integer (Radix) +
                    Big.To_Big_Integer (Digit (Character_Value));
                  Kept := Kept + 1;
               else
                  Dropped := Dropped + 1;
                  Sticky := Sticky or else Digit (Character_Value) /= 0;
               end if;
            end if;
         end if;
      end loop;
      if Numerator = 0 then
         return 0.0;
      end if;
      Scale := Exponent + (Integer (Dropped) - Integer (Fraction)) *
        (if Radix = 16 then 4 else 1);
      if (Radix = 10 and then Integer (Kept) + Scale > 310) or else
        (Radix = 16 and then Integer (Kept) * 4 + Scale > 1_030)
      then
         return From_Bits (16#7FF0_0000_0000_0000#);
      elsif (Radix = 10 and then Integer (Kept) + Scale < -330) or else
        (Radix = 16 and then Integer (Kept) * 4 + Scale < -1_080)
      then
         return 0.0;
      end if;
      declare
         Base : constant Big.Big_Integer :=
           Big.To_Big_Integer (if Radix = 16 then 2 else 10);
      begin
         if Scale >= 0 then
            Numerator := Numerator * Base ** Scale;
         else
            Denominator := Base ** (-Scale);
         end if;
      end;

      --  Bit lengths locate the binade in constant-many big operations.
      --  One comparison corrects the estimate without repeatedly doubling a
      --  large denominator for deeply subnormal inputs.
      Binary_Exponent := Bit_Length (Numerator) - Bit_Length (Denominator);
      if Binary_Exponent >= 0 then
         if Numerator < Denominator * Big.Big_Integer'(2) ** Binary_Exponent
         then
            Binary_Exponent := Binary_Exponent - 1;
         end if;
      elsif Numerator * Big.Big_Integer'(2) ** (-Binary_Exponent) < Denominator
      then
         Binary_Exponent := Binary_Exponent - 1;
      end if;
      if Binary_Exponent > 1_023 then
         return From_Bits (16#7FF0_0000_0000_0000#);
      elsif Binary_Exponent < -1_075 then
         return 0.0;
      end if;
      Shift := (if Binary_Exponent < -1_022 then 1_074
                else 52 - Binary_Exponent);
      if Shift >= 0 then
         Numerator := Numerator * Big.Big_Integer'(2) ** Shift;
      else
         Denominator := Denominator * Big.Big_Integer'(2) ** (-Shift);
      end if;
      Quotient := Numerator / Denominator;
      Residue := Numerator rem Denominator;
      if Residue * 2 > Denominator or else
        (Residue * 2 = Denominator and then
         (Sticky or else Quotient mod 2 /= 0))
      then
         Quotient := Quotient + 1;
      end if;

      --  Encode the rounded significand directly. Subnormal significands
      --  use an implicit exponent of -1074; rounding can promote one to the
      --  smallest normal double. Normal carries advance the binade instead.
      if Binary_Exponent < -1_022 then
         return From_Bits (Big_Unsigned.From_Big_Integer (Quotient));
      end if;
      if Quotient >= Big.Big_Integer'(2) ** 53 then
         Quotient := Quotient / 2;
         Binary_Exponent := Binary_Exponent + 1;
      end if;
      if Binary_Exponent > 1_023 then
         return From_Bits (16#7FF0_0000_0000_0000#);
      end if;
      Bits := Interfaces.Unsigned_64 (Binary_Exponent + 1_023) * 2 ** 52 +
        Big_Unsigned.From_Big_Integer (Quotient - Big.Big_Integer'(2) ** 52);
      return From_Bits (Bits);
   end Exact_Real;

   function Signed
     (Bits : Interfaces.Unsigned_64; Negative : Boolean) return Integer_Value
   is
      Magnitude : constant Interfaces.Unsigned_64 :=
        (if Negative then 0 - Bits else Bits);
   begin
      --  Directly converting a high-bit-set modular value is out of range
      --  for Ada's signed type. Construct its signed interpretation safely.
      if Magnitude < 2 ** 63 then
         return Integer_Value (Magnitude);
      end if;
      return Integer_Value'First + Integer_Value (Magnitude - 2 ** 63);
   end Signed;

   function Read (Text : String; Base : Natural := 0) return Number is
      Source : constant String (1 .. Text'Length) := Text;
      First  : Positive := 1;
      Last   : Natural := Source'Last;
      Start  : Positive;
      Exp_At : Natural := 0;
      Digits_Seen : Natural := 0;
      Radix       : Natural := Base;
      Negative    : Boolean := False;
      Hexadecimal : Boolean := False;
      Bits        : Interfaces.Unsigned_64 := 0;
      Too_Large   : Boolean := False;
      Limit       : Interfaces.Unsigned_64;
      Value       : Real_Value;
      Exponent    : Integer := 0;
      Exp_Negative : Boolean := False;
   begin
      --  tonumber accepts surrounding whitespace, but embedded whitespace
      --  is never part of a numeric token. Empty and sign-only inputs fail.
      while First <= Last and then Space (Source (First)) loop
         First := First + 1;
      end loop;
      while Last >= First and then Space (Source (Last)) loop
         Last := Last - 1;
      end loop;
      if First > Last then
         return (Kind => Invalid);
      end if;
      if Source (First) in '+' | '-' then
         Negative := Source (First) = '-';
         First := First + 1;
      end if;
      if First > Last or else (Base /= 0 and then Base not in 2 .. 36) then
         return (Kind => Invalid);
      end if;
      if Base = 0 then
         Hexadecimal := Last - First >= 1 and then Source (First) = '0'
           and then Source (First + 1) in 'x' | 'X';
         Radix := (if Hexadecimal then 16 else 10);
         if Hexadecimal then
            First := First + 2;
         end if;
      end if;
      Start := First;
      Limit := (if Negative then 2 ** 63 else 2 ** 63 - 1);

      --  Accumulate integer bits modulo 2**64. Decimal automatic syntax
      --  also tracks signed overflow, which changes the result to a float.
      while First <= Last loop
         declare
            D : constant Integer := Digit (Source (First));
         begin
            exit when D < 0 or else D >= Radix;
            if Bits > (Limit - Interfaces.Unsigned_64 (D)) /
              Interfaces.Unsigned_64 (Radix)
            then
               Too_Large := True;
            end if;
            Bits := Bits * Interfaces.Unsigned_64 (Radix) +
              Interfaces.Unsigned_64 (D);
            Digits_Seen := Digits_Seen + 1;
            First := First + 1;
         end;
      end loop;
      if First > Last and then Digits_Seen > 0 and then
        (Base /= 0 or else Hexadecimal or else not Too_Large)
      then
         return (Integer_Number, Signed (Bits, Negative));
      elsif Base /= 0 then
         return (Kind => Invalid);
      end if;

      --  Validate the fractional/exponent grammar independently of Ada's
      --  converter. A second dot, missing digits, underscores, and trailing
      --  garbage are rejected rather than accepted as Ada literal syntax.
      if First <= Last and then Source (First) = '.' then
         First := First + 1;
         while First <= Last and then Digit (Source (First)) >= 0 and then
           Digit (Source (First)) < Radix
         loop
            Digits_Seen := Digits_Seen + 1;
            First := First + 1;
         end loop;
      end if;
      if Digits_Seen = 0 then
         return (Kind => Invalid);
      end if;
      if First <= Last and then
        ((Hexadecimal and then Source (First) in 'p' | 'P') or else
         (not Hexadecimal and then Source (First) in 'e' | 'E'))
      then
         Exp_At := First;
         First := First + 1;
         if First <= Last and then Source (First) in '+' | '-' then
            Exp_Negative := Source (First) = '-';
            First := First + 1;
         end if;
         if First > Last or else Source (First) not in '0' .. '9' then
            return (Kind => Invalid);
         end if;
         while First <= Last and then Source (First) in '0' .. '9' loop
            --  Saturation only bounds parsing work for an enormous exponent.
            --  Its mathematical overflow/underflow result is unchanged.
            if Exponent < 100_000 then
               Exponent := Exponent * 10 + Digit (Source (First));
            end if;
            First := First + 1;
         end loop;
      end if;
      if First <= Last then
         return (Kind => Invalid);
      end if;
      if Exp_Negative then
         Exponent := -Exponent;
      end if;
      declare
         Mantissa_Last : constant Natural :=
           (if Exp_At = 0 then Last else Exp_At - 1);
         Mantissa : constant String := Source (Start .. Mantissa_Last);
      begin
         Value := Exact_Real (Mantissa, Radix, Exponent);
      end;
      if Negative then
         Value := -Value;
      end if;
      return (Real_Number, Value);
   end Read;

   function To_Real (Item : Number) return Real_Value is
     (if Item.Kind = Integer_Number then Real_Value (Item.Integer_Item)
      else Item.Real_Item);

   function Equal (Left, Right : Number) return Boolean is
      I : Integer_Value;
      F : Real_Value;
   begin
      if Left.Kind = Integer_Number and then Right.Kind = Integer_Number then
         return Left.Integer_Item = Right.Integer_Item;
      elsif Left.Kind = Real_Number and then Right.Kind = Real_Number then
         return Left.Real_Item = Right.Real_Item;
      end if;
      I := (if Left.Kind = Integer_Number then Left.Integer_Item else
              Right.Integer_Item);
      F := (if Left.Kind = Real_Number then Left.Real_Item
            else Right.Real_Item);
      --  Above 2**53 integer-to-float conversion loses information. Compare
      --  only after checking that the float denotes an in-range exact int.
      if F /= F or else F < -2.0 ** 63 or else F >= 2.0 ** 63 or else
        Real_Value'Truncation (F) /= F
      then
         return False;
      end if;
      return I = Integer_Value (F);
   end Equal;

   function Less (Left, Right : Number) return Boolean is
      I : Integer_Value;
      F : Real_Value;
      Integer_First : constant Boolean := Left.Kind = Integer_Number;
   begin
      if Left.Kind = Integer_Number and then Right.Kind = Integer_Number then
         return Left.Integer_Item < Right.Integer_Item;
      elsif Left.Kind = Real_Number and then Right.Kind = Real_Number then
         return Left.Real_Item < Right.Real_Item;
      end if;
      I := (if Integer_First then Left.Integer_Item else Right.Integer_Item);
      F := (if Integer_First then Right.Real_Item else Left.Real_Item);
      if F /= F then
         return False;
      elsif F >= 2.0 ** 63 then
         return Integer_First;
      elsif F < -2.0 ** 63 then
         return not Integer_First;
      end if;
      if Integer_First then
         return I < Integer_Value (Real_Value'Ceiling (F));
      else
         return Integer_Value (Real_Value'Floor (F)) < I;
      end if;
   end Less;
end Lua.Numbers;
