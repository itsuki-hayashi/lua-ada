with Ada.Characters.Latin_1;
with Ada.Unchecked_Conversion;
with Interfaces;
with Lua.Big_Naturals;

package body Lua.Number_Parsing is
   use Lua.Numbers;
   use type Interfaces.Unsigned_64;
   use type Real_Value;
   use type Integer_Value;
   package Big renames Lua.Big_Naturals;
   use type Big.Ordering;

   function From_Bits is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, Real_Value);
   --  Only the final rounded IEEE representation is reinterpreted. No host
   --  strtod, locale state, external numeric object or pointer alias is used.

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
     (Mantissa : String; Radix : Positive; Exponent : Long_Long_Integer;
      Memory : not null Lua.Storage.Owner_Access) return Real_Value;

   function Exact_Real
     (Mantissa : String; Radix : Positive; Exponent : Long_Long_Integer;
      Memory : not null Lua.Storage.Owner_Access) return Real_Value
   is
      Numerator, Denominator, Quotient, Residue, Shifted : Big.Number;
      Prefix : String (1 .. 1_100) := [others => '0'];
      Kept, Dropped, Fraction : Natural := 0;
      After_Point, Significant, Sticky : Boolean := False;
      Wide_Scale : Long_Long_Integer;
      Scale, Binary_Exponent, Shift : Integer;
      Comparison : Big.Ordering;
      Raw_Quotient : Interfaces.Unsigned_64;
   begin
      --  Scan arbitrarily long mantissas in linear time, retaining only a
      --  bounded significant prefix and a nonzero-tail witness. Binary64
      --  midpoints have terminating decimal expansions within 1075 places;
      --  1100 significant digits therefore decide every tie. Fixed stack
      --  prefix storage is independent of input length and needs no allocator.
      for Character_Value of Mantissa loop
         if Character_Value = '.' then
            After_Point := True;
         else
            if After_Point then
               Fraction := Fraction + 1;
            end if;
            Significant := Significant or else Digit (Character_Value) /= 0;
            if Significant then
               if Kept < Prefix'Length then
                  Kept := Kept + 1;
                  Prefix (Kept) := Character_Value;
               else
                  Dropped := Dropped + 1;
                  Sticky := Sticky or else Digit (Character_Value) /= 0;
               end if;
            end if;
         end if;
      end loop;
      if not Significant then
         return 0.0;
      end if;
      --  Scale cancellation can involve millions of digits even though the
      --  final double is ordinary. Widen before subtracting/multiplying and
      --  classify extremes before converting the bounded scale back to Ada
      --  Integer or allocating any limb scratch.
      Wide_Scale := Exponent +
        (Long_Long_Integer (Dropped) - Long_Long_Integer (Fraction)) *
        (if Radix = 16 then 4 else 1);
      if (Radix = 10 and then Long_Long_Integer (Kept) + Wide_Scale > 310)
        or else (Radix = 16 and then
          Long_Long_Integer (Kept) * 4 + Wide_Scale > 1_030)
      then
         return From_Bits (16#7FF0_0000_0000_0000#);
      elsif (Radix = 10 and then
          Long_Long_Integer (Kept) + Wide_Scale < -330) or else
        (Radix = 16 and then
          Long_Long_Integer (Kept) * 4 + Wide_Scale < -1_080)
      then
         return 0.0;
      end if;
      Scale := Integer (Wide_Scale);
      Big.Set_Owner (Numerator, Memory);
      Big.Set_Owner (Denominator, Memory);
      Big.Set_Owner (Quotient, Memory);
      Big.Set_Owner (Residue, Memory);
      Big.Set_Owner (Shifted, Memory);
      for Index in 1 .. Kept loop
         Big.Multiply (Numerator, Big.Small (Radix));
         Big.Add (Numerator, Big.Small (Digit (Prefix (Index))));
      end loop;
      Big.Set_Value (Denominator, 1);
      if Scale >= 0 then
         Big.Multiply_Power
           (Numerator, (if Radix = 16 then 2 else 10), Natural (Scale));
      else
         Big.Multiply_Power
           (Denominator, (if Radix = 16 then 2 else 10), Natural (-Scale));
      end if;

      --  Locate the binade from limb lengths, then correct one estimate.
      --  This avoids temporary base-two strings or repeated big doublings for
      --  very small values. All copies retain this explicit universe owner.
      Binary_Exponent := Big.Bit_Length (Numerator) -
        Big.Bit_Length (Denominator);
      if Binary_Exponent >= 0 then
         Shifted := Denominator;
         Big.Shift_Left (Shifted, Natural (Binary_Exponent));
         Comparison := Big.Compare (Numerator, Shifted);
      else
         Shifted := Numerator;
         Big.Shift_Left (Shifted, Natural (-Binary_Exponent));
         Comparison := Big.Compare (Shifted, Denominator);
      end if;
      if Comparison = Big.Less_Than then
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
         Big.Shift_Left (Numerator, Natural (Shift));
      else
         Big.Shift_Left (Denominator, Natural (-Shift));
      end if;
      Big.Divide (Numerator, Denominator, Quotient, Residue);
      Big.Multiply (Residue, 2);
      Comparison := Big.Compare (Residue, Denominator);
      if Comparison = Big.Greater_Than or else
        (Comparison = Big.Equal_To and then
         (Sticky or else Big.Is_Odd (Quotient)))
      then
         Big.Add (Quotient, 1);
      end if;

      --  Subnormal significands use exponent -1074 and may round up to the
      --  smallest normal value. Normal carry advances the binade. Encoding
      --  uses exact 64-bit words, with no second host-floating conversion.
      if Binary_Exponent < -1_022 then
         return From_Bits (Big.To_Unsigned (Quotient));
      end if;
      if Big.Bit_Length (Quotient) > 53 then
         Big.Shift_Right (Quotient, 1);
         Binary_Exponent := Binary_Exponent + 1;
      end if;
      if Binary_Exponent > 1_023 then
         return From_Bits (16#7FF0_0000_0000_0000#);
      end if;
      Raw_Quotient := Big.To_Unsigned (Quotient);
      return From_Bits
        (Interfaces.Unsigned_64 (Binary_Exponent + 1_023) * 2 ** 52 +
         (Raw_Quotient - 2 ** 52));
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

   function Read
     (Text : String; Memory : not null Lua.Storage.Owner_Access;
      Base : Natural := 0) return Number
   is
      Source : constant String (1 .. Text'Length)
        with Import, Address => Text'Address;
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
      Exponent : Long_Long_Integer := 0;
      Exponent_Limit : constant Long_Long_Integer :=
        Long_Long_Integer (Source'Length) * 4 + 2_000;
      Exp_Negative : Boolean := False;
   begin
      if Source'Length = Positive'Last then
         raise Lua.Storage.Allocation_Error;
      end if;
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
            --  A fixed small exponent cap loses valid cancellation against
            --  long mantissas. Bound it relative to the complete source;
            --  larger exponents cannot cancel even all hexadecimal digits.
            if Exponent >
              (Exponent_Limit - Long_Long_Integer (Digit (Source (First)))) /
                10
            then
               Exponent := Exponent_Limit;
            else
               Exponent := Exponent * 10 +
                 Long_Long_Integer (Digit (Source (First)));
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
         Mantissa : String renames Source (Start .. Mantissa_Last);
      begin
         Value := Exact_Real (Mantissa, Radix, Exponent, Memory);
      end;
      if Negative then
         Value := -Value;
      end if;
      return (Real_Number, Value);
   end Read;

end Lua.Number_Parsing;
