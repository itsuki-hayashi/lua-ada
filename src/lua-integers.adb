package body Lua.Integers is
   use type Interfaces.Integer_64;
   use type Interfaces.Unsigned_64;

   function Signed (Bits : Interfaces.Unsigned_64) return Integer_Value;
   --  Avoid out-of-range signed conversions; no unchecked conversion needed.

   function Unsigned (Value : Integer_Value) return Interfaces.Unsigned_64;
   --  Ordinary conversions reject negatives when validity checks are active.

   function Unsigned (Value : Integer_Value) return Interfaces.Unsigned_64 is
   begin
      if Value >= 0 then
         return Interfaces.Unsigned_64 (Value);
      end if;
      return Interfaces.Unsigned_64 (Value - Integer_Value'First) + 2 ** 63;
   end Unsigned;

   function Signed (Bits : Interfaces.Unsigned_64) return Integer_Value is
      Sign_Bit : constant Interfaces.Unsigned_64 := 2 ** 63;
   begin
      if Bits < Sign_Bit then
         return Integer_Value (Bits);
      end if;
      return Integer_Value'First + Integer_Value (Bits - Sign_Bit);
   end Signed;

   function Add (Left, Right : Integer_Value) return Integer_Value is
     (Signed (Unsigned (Left) + Unsigned (Right)));

   function Subtract (Left, Right : Integer_Value) return Integer_Value is
     (Signed (Unsigned (Left) - Unsigned (Right)));

   function Multiply (Left, Right : Integer_Value) return Integer_Value is
     (Signed (Unsigned (Left) * Unsigned (Right)));

   function Negate (Value : Integer_Value) return Integer_Value is
     (Signed (0 - Unsigned (Value)));

   function Floor_Divide (Left, Right : Integer_Value) return Integer_Value is
      Quotient : Integer_Value;
   begin
      --  Ada integer division truncates toward zero. Lua rounds toward
      --  negative infinity, requiring one correction for unlike signs and
      --  a nonzero residue. The minimum/-1 case wraps before Ada division.
      if Right = 0 then
         raise Arithmetic_Error with "attempt to divide by zero";
      elsif Left = Integer_Value'First and then Right = -1 then
         return Left;
      end if;
      Quotient := Left / Right;
      if (Left < 0) /= (Right < 0) and then Left rem Right /= 0 then
         Quotient := Quotient - 1;
      end if;
      return Quotient;
   end Floor_Divide;

   function Modulo (Left, Right : Integer_Value) return Integer_Value is
   begin
      --  Ada mod already follows the divisor's sign. Handle -1 separately
      --  so the signed minimum never reaches a host division overflow.
      if Right = 0 then
         raise Arithmetic_Error with "attempt to perform modulo by zero";
      elsif Right = -1 then
         return 0;
      end if;
      return Left mod Right;
   end Modulo;

   function Shift_Left
     (Value, Amount : Integer_Value) return Integer_Value
   is
   begin
      --  Check the full signed count before negating it: Integer'First has
      --  no positive signed counterpart. Out-of-word shifts are zero.
      if Amount <= -64 or else Amount >= 64 then
         return 0;
      elsif Amount < 0 then
         return Shift_Right (Value, -Amount);
      end if;
      return Signed
        (Interfaces.Shift_Left
           (Unsigned (Value), Natural (Amount)));
   end Shift_Left;

   function Shift_Right
     (Value, Amount : Integer_Value) return Integer_Value
   is
   begin
      if Amount <= -64 or else Amount >= 64 then
         return 0;
      elsif Amount < 0 then
         return Shift_Left (Value, -Amount);
      end if;
      return Signed
        (Interfaces.Shift_Right
           (Unsigned (Value), Natural (Amount)));
   end Shift_Right;
end Lua.Integers;
