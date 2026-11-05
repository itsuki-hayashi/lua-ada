with Interfaces;

package Lua.Integers is
   pragma Pure;

   subtype Integer_Value is Interfaces.Integer_64;
   --  Lua's default signed 64-bit integer configuration.

   Arithmetic_Error : exception;
   --  Primitive arithmetic failure; the VM must convert this to Lua errors.

   function Add (Left, Right : Integer_Value) return Integer_Value;
   --  Add modulo 2**64 and interpret the resulting signed bit pattern.

   function Subtract (Left, Right : Integer_Value) return Integer_Value;
   --  Subtract with Lua wrapping semantics and active Ada runtime checks.

   function Multiply (Left, Right : Integer_Value) return Integer_Value;
   --  Multiply with Lua wrapping semantics.

   function Negate (Value : Integer_Value) return Integer_Value;
   --  Negate with wrapping, including the minimum integer.

   function Floor_Divide (Left, Right : Integer_Value) return Integer_Value;
   --  Divide toward minus infinity; minimum / -1 wraps to minimum.
   --  @exception Arithmetic_Error Right is zero.

   function Modulo (Left, Right : Integer_Value) return Integer_Value;
   --  Remainder with the divisor's sign, including minimum mod -1 = 0.
   --  @exception Arithmetic_Error Right is zero.

   function Shift_Left
     (Value, Amount : Integer_Value) return Integer_Value;
   --  Logical shift; negative counts reverse direction; magnitude >=64 = 0.

   function Shift_Right
     (Value, Amount : Integer_Value) return Integer_Value;
   --  Logical right shift, with the same count rules as Shift_Left.
end Lua.Integers;
