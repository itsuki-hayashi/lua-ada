with AUnit.Assertions; use AUnit.Assertions;
with Lua.Integers; use Lua.Integers;

package body Integer_Tests is
   use type Integer_Value;

   procedure Wrapping (Self : in out Fixture) is
      pragma Unreferenced (Self);
   begin
      Assert (Add (Integer_Value'Last, 1) = Integer_Value'First,
              "maximum plus one wraps");
      Assert (Subtract (Integer_Value'First, 1) = Integer_Value'Last,
              "minimum minus one wraps");
      Assert (Multiply (Integer_Value'Last, 2) = -2, "multiply wraps");
      Assert (Negate (Integer_Value'First) = Integer_Value'First,
              "minimum negation wraps");
      Assert (Add (-3, 7) = 4, "mixed signs");
   end Wrapping;

   procedure Division_And_Shifts (Self : in out Fixture) is
      pragma Unreferenced (Self);
      Result : Integer_Value;
   begin
      Assert (Floor_Divide (-7, 3) = -3, "negative dividend floors");
      Assert (Floor_Divide (7, -3) = -3, "negative divisor floors");
      Assert (Floor_Divide (-7, -3) = 2, "same signs");
      Assert (Modulo (-7, 3) = 2 and then Modulo (7, -3) = -2,
              "modulo follows divisor sign");
      Assert (Floor_Divide (Integer_Value'First, -1) = Integer_Value'First,
              "minimum divided by minus one");
      Assert (Modulo (Integer_Value'First, -1) = 0, "minimum remainder");
      Assert (Shift_Right (-1, 1) = Integer_Value'Last, "logical shift");
      Assert (Shift_Left (1, 63) = Integer_Value'First, "sign bit shift");
      Assert (Shift_Left (8, -1) = 4, "negative shift reverses");
      Assert (Shift_Right (1, -3) = 8, "negative right shift");
      Assert (Shift_Left (1, Integer_Value'First) = 0 and then
              Shift_Right (-1, Integer_Value'Last) = 0, "extreme counts");
      Assert (Shift_Left (1, 64) = 0, "shift by word size");
      begin
         Result := Floor_Divide (1, 0);
         Assert (False, "zero division returned" & Result'Image);
      exception
         when Arithmetic_Error => null;
      end;
      begin
         Result := Modulo (1, 0);
         Assert (False, "zero modulo returned" & Result'Image);
      exception
         when Arithmetic_Error => null;
      end;
   end Division_And_Shifts;
end Integer_Tests;
