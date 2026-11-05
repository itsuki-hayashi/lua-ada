with AUnit.Assertions; use AUnit.Assertions;
with Lua.Integers; use Lua.Integers;
with Test_Support;

package body Integer_Tests is
   use type Integer_Value;
   procedure Addition_Wrap;
   procedure Subtraction_Wrap;
   procedure Multiplication_Wrap;
   procedure Minimum_Negation;
   procedure Mixed_Sign_Addition;
   procedure Negative_Dividend;
   procedure Negative_Divisor;
   procedure Same_Sign_Division;
   procedure Positive_Modulo;
   procedure Negative_Modulo;
   procedure Minimum_Division;
   procedure Minimum_Remainder;
   procedure Logical_Right_Shift;
   procedure Sign_Bit_Shift;
   procedure Negative_Left_Count;
   procedure Negative_Right_Count;
   procedure Word_Size_Shift;
   procedure Minimum_Shift_Count;
   procedure Maximum_Shift_Count;
   procedure Divide_By_Zero;
   procedure Modulo_By_Zero;

   procedure Addition_Wrap is
      --  Adding one to the maximum signed integer must wrap to the minimum.
   begin
      Assert (Add (Integer_Value'Last, 1) = Integer_Value'First,
              "addition wraps at the signed boundary");
   end Addition_Wrap;

   procedure Subtraction_Wrap is
      --  Subtracting one from the minimum must preserve modulo-2**64
      --  behavior.
   begin
      Assert (Subtract (Integer_Value'First, 1) = Integer_Value'Last,
              "subtraction wraps at the signed boundary");
   end Subtraction_Wrap;

   procedure Multiplication_Wrap is
      --  Multiplication keeps low bits rather than raising an Ada overflow
      --  check.
   begin
      Assert (Multiply (Integer_Value'Last, 2) = -2, "low-bit product");
   end Multiplication_Wrap;

   procedure Minimum_Negation is
      --  Negation of the minimum integer is the same signed bit pattern.
   begin
      Assert (Negate (Integer_Value'First) = Integer_Value'First,
              "minimum integer negation");
   end Minimum_Negation;

   procedure Mixed_Sign_Addition is
      --  Ordinary mixed-sign arithmetic must remain exact.
   begin
      Assert (Add (-3, 7) = 4, "mixed signs");
   end Mixed_Sign_Addition;

   procedure Negative_Dividend is
      --  A negative nonintegral quotient rounds down, not toward zero.
   begin
      Assert (Floor_Divide (-7, 3) = -3, "floor negative dividend");
   end Negative_Dividend;

   procedure Negative_Divisor is
      --  A negative divisor also requires floor adjustment.
   begin
      Assert (Floor_Divide (7, -3) = -3, "floor negative divisor");
   end Negative_Divisor;

   procedure Same_Sign_Division is
      --  Two negative operands give an ordinary positive integer quotient.
   begin
      Assert (Floor_Divide (-7, -3) = 2, "same sign division");
   end Same_Sign_Division;

   procedure Positive_Modulo is
      --  Modulo uses the positive divisor's sign.
   begin
      Assert (Modulo (-7, 3) = 2, "positive divisor remainder");
   end Positive_Modulo;

   procedure Negative_Modulo is
      --  Modulo uses the negative divisor's sign.
   begin
      Assert (Modulo (7, -3) = -2, "negative divisor remainder");
   end Negative_Modulo;

   procedure Minimum_Division is
      --  The single overflowing signed quotient wraps under Lua's rules.
   begin
      Assert (Floor_Divide (Integer_Value'First, -1) = Integer_Value'First,
              "minimum divided by minus one");
   end Minimum_Division;

   procedure Minimum_Remainder is
      --  The minimum modulo minus one is zero without a hardware trap.
   begin
      Assert (Modulo (Integer_Value'First, -1) = 0, "minimum remainder");
   end Minimum_Remainder;

   procedure Logical_Right_Shift is
      --  Right-shifting a negative number fills with zero bits.
   begin
      Assert (Shift_Right (-1, 1) = Integer_Value'Last, "logical shift");
   end Logical_Right_Shift;

   procedure Sign_Bit_Shift is
      --  A left shift can set the sign bit without a signed overflow.
   begin
      Assert (Shift_Left (1, 63) = Integer_Value'First, "sign bit");
   end Sign_Bit_Shift;

   procedure Negative_Left_Count is
      --  A negative left-shift count reverses the direction.
   begin
      Assert (Shift_Left (8, -1) = 4, "negative left count");
   end Negative_Left_Count;

   procedure Negative_Right_Count is
      --  A negative right-shift count reverses the direction.
   begin
      Assert (Shift_Right (1, -3) = 8, "negative right count");
   end Negative_Right_Count;

   procedure Word_Size_Shift is
      --  Shifting by the word size returns zero rather than masking the
      --  count.
   begin
      Assert (Shift_Left (1, 64) = 0, "word-size count");
   end Word_Size_Shift;

   procedure Minimum_Shift_Count is
      --  Negating the minimum signed count must not overflow in the
      --  implementation.
   begin
      Assert (Shift_Left (1, Integer_Value'First) = 0, "minimum count");
   end Minimum_Shift_Count;

   procedure Maximum_Shift_Count is
      --  An enormous positive shift has a defined zero result.
   begin
      Assert (Shift_Right (-1, Integer_Value'Last) = 0, "maximum count");
   end Maximum_Shift_Count;

   procedure Divide_By_Zero is
      --  A zero divisor must produce the dedicated primitive error so the
      --  VM can turn it into a catchable Lua failure, not a host exception.
      Result : Integer_Value;
   begin
      Result := Floor_Divide (1, 0);
      Assert (False, "zero divisor returned" & Result'Image);
   exception
      when Arithmetic_Error => null;
   end Divide_By_Zero;

   procedure Modulo_By_Zero is
      --  A zero divisor must produce the dedicated primitive error so the
      --  VM can turn it into a catchable Lua failure, not a host exception.
      Result : Integer_Value;
   begin
      Result := Modulo (1, 0);
      Assert (False, "zero divisor returned" & Result'Image);
   exception
      when Arithmetic_Error => null;
   end Modulo_By_Zero;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "integers: addition wrap",
         Addition_Wrap'Access);
      Test_Support.Add
        (Suite, "integers: subtraction wrap",
         Subtraction_Wrap'Access);
      Test_Support.Add
        (Suite, "integers: multiplication wrap",
         Multiplication_Wrap'Access);
      Test_Support.Add
        (Suite, "integers: minimum negation",
         Minimum_Negation'Access);
      Test_Support.Add
        (Suite, "integers: mixed sign addition",
         Mixed_Sign_Addition'Access);
      Test_Support.Add
        (Suite, "integers: negative dividend",
         Negative_Dividend'Access);
      Test_Support.Add
        (Suite, "integers: negative divisor",
         Negative_Divisor'Access);
      Test_Support.Add
        (Suite, "integers: same sign division",
         Same_Sign_Division'Access);
      Test_Support.Add
        (Suite, "integers: positive modulo",
         Positive_Modulo'Access);
      Test_Support.Add
        (Suite, "integers: negative modulo",
         Negative_Modulo'Access);
      Test_Support.Add
        (Suite, "integers: minimum division",
         Minimum_Division'Access);
      Test_Support.Add
        (Suite, "integers: minimum remainder",
         Minimum_Remainder'Access);
      Test_Support.Add
        (Suite, "integers: logical right shift",
         Logical_Right_Shift'Access);
      Test_Support.Add
        (Suite, "integers: sign bit shift",
         Sign_Bit_Shift'Access);
      Test_Support.Add
        (Suite, "integers: negative left count",
         Negative_Left_Count'Access);
      Test_Support.Add
        (Suite, "integers: negative right count",
         Negative_Right_Count'Access);
      Test_Support.Add
        (Suite, "integers: word size shift",
         Word_Size_Shift'Access);
      Test_Support.Add
        (Suite, "integers: minimum shift count",
         Minimum_Shift_Count'Access);
      Test_Support.Add
        (Suite, "integers: maximum shift count",
         Maximum_Shift_Count'Access);
      Test_Support.Add
        (Suite, "integers: divide by zero",
         Divide_By_Zero'Access);
      Test_Support.Add
        (Suite, "integers: modulo by zero",
         Modulo_By_Zero'Access);
   end Register;
end Integer_Tests;
