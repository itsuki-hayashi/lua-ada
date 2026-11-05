with AUnit.Assertions; use AUnit.Assertions;
with Lua.Numbers; use Lua.Numbers;
with Test_Support;
with Ada.Unchecked_Conversion;
with Interfaces;

package body Number_Tests is
   use type Integer_Value;
   use type Real_Value;
   use type Interfaces.Unsigned_64;
   function Bits is new Ada.Unchecked_Conversion
     (Real_Value, Interfaces.Unsigned_64);

   procedure Check_Integer (Text : String; Expected : Integer_Value);
   procedure Check_Real (Text : String; Expected : Real_Value);
   procedure Decimal_Integer;
   procedure Negative_Minimum;
   procedure Positive_Overflow;
   procedure Leading_Fraction;
   procedure Trailing_Point;
   procedure Decimal_Exponent;
   procedure Hex_Integer;
   procedure Hex_Wrapping;
   procedure Hex_Fraction;
   procedure Hex_Leading_Fraction;
   procedure Surrounding_Whitespace;
   procedure Explicit_Base;
   procedure Explicit_Base_Wrap;
   procedure Empty_Is_Invalid;
   procedure Sign_Only_Is_Invalid;
   procedure Missing_Exponent_Is_Invalid;
   procedure Ada_Underscores_Are_Invalid;
   procedure Concatenation_Needs_Spacing;
   procedure Embedded_Space_Is_Invalid;
   procedure Base_Fraction_Is_Invalid;
   procedure Overflow_Is_Infinity;
   procedure Underflow_Is_Zero;
   procedure Mixed_Equality_Is_Exact;
   procedure Mixed_Order_Is_Exact;
   procedure Upper_Boundary_Order;
   procedure Fractional_Mixed_Order;
   procedure Smallest_Subnormal;
   procedure Halfway_Rounds_Even;
   procedure Above_Halfway_Rounds_Up;
   procedure Normal_Boundary;

   procedure Check_Integer (Text : String; Expected : Integer_Value) is
      Actual : constant Number := Read (Text);
   begin
      Assert (Actual.Kind = Integer_Number, "integer kind: " & Text);
      Assert (Actual.Integer_Item = Expected, "integer value: " & Text);
   end Check_Integer;

   procedure Check_Real (Text : String; Expected : Real_Value) is
      Actual : constant Number := Read (Text);
   begin
      Assert (Actual.Kind = Real_Number, "float kind: " & Text);
      Assert (Actual.Real_Item = Expected, "float value: " & Text);
   end Check_Real;

   procedure Decimal_Integer is
      --  An ordinary decimal keeps its integer subtype, not merely its value.
   begin
      Check_Integer ("42", 42);
   end Decimal_Integer;

   procedure Negative_Minimum is
      --  The signed lower endpoint has one greater magnitude than the upper.
   begin
      Check_Integer ("-9223372036854775808", Integer_Value'First);
   end Negative_Minimum;

   procedure Positive_Overflow is
      --  One beyond the signed maximum is a float in automatic decimal syntax.
      R : constant Number := Read ("9223372036854775808");
   begin
      Assert (R.Kind = Real_Number,
              "overflow must select floating arithmetic");
      Assert (R.Real_Item = 2.0 ** 63, "overflow magnitude");
   end Positive_Overflow;

   procedure Leading_Fraction is
      --  A leading dot is valid Lua even though Ada requires an integer part.
   begin
      Check_Real (".5", 0.5);
   end Leading_Fraction;

   procedure Trailing_Point is
      --  A trailing point forces a float and need not have fractional digits.
   begin
      Check_Real ("12.", 12.0);
   end Trailing_Point;

   procedure Decimal_Exponent is
      --  Signed decimal exponents are interpreted as powers of ten.
   begin
      Check_Real ("1.25e-2", 0.0125);
   end Decimal_Exponent;

   procedure Hex_Integer is
      --  Hexadecimal source syntax selects an integer when no point/exponent
      --  occurs.
   begin
      Check_Integer ("0xff", 255);
   end Hex_Integer;

   procedure Hex_Wrapping is
      --  Hexadecimal integers preserve all 64 bits instead of promoting on
      --  overflow.
   begin
      Check_Integer ("0xffffffffffffffff", -1);
   end Hex_Wrapping;

   procedure Hex_Fraction is
      --  The hexadecimal mantissa and binary exponent have different radices.
   begin
      Check_Real ("0x1.fp+2", 7.75);
   end Hex_Fraction;

   procedure Hex_Leading_Fraction is
      --  Lua permits a fractional hexadecimal mantissa without a leading
      --  digit.
   begin
      Check_Real ("0x.8p1", 1.0);
   end Hex_Leading_Fraction;

   procedure Surrounding_Whitespace is
      --  tonumber permits surrounding whitespace and a sign, not embedded
      --  spaces.
   begin
      Check_Integer ("  +42  ", 42);
   end Surrounding_Whitespace;

   procedure Explicit_Base is
      --  Explicit-base conversion is integer-only and supports alphabetic
      --  digits.
      R : constant Number := Read (" -zz ", Base => 36);
   begin
      Assert (R.Kind = Integer_Number, "base-36 integer kind");
      Assert (R.Integer_Item = -1295, "base-36 signed magnitude");
   end Explicit_Base;

   procedure Explicit_Base_Wrap is
      --  Explicit-base conversion follows Lua's modular accumulation rule.
      R : constant Number := Read ("ffffffffffffffff", Base => 16);
   begin
      Assert (R.Kind = Integer_Number, "explicit-base integer kind");
      Assert (R.Integer_Item = -1, "explicit-base wrap");
   end Explicit_Base_Wrap;

   procedure Empty_Is_Invalid is
      --  Empty input cannot stand for zero.
   begin
      Assert (Read ("").Kind = Invalid, "empty text");
   end Empty_Is_Invalid;

   procedure Sign_Only_Is_Invalid is
      --  A sign must be followed by at least one mantissa digit.
   begin
      Assert (Read ("-").Kind = Invalid, "sign-only text");
   end Sign_Only_Is_Invalid;

   procedure Missing_Exponent_Is_Invalid is
      --  A syntactically incomplete exponent must not become infinity.
   begin
      Assert (Read ("1e+").Kind = Invalid, "missing exponent digits");
   end Missing_Exponent_Is_Invalid;

   procedure Ada_Underscores_Are_Invalid is
      --  Do not accidentally accept Ada's numeric underscores through Value.
   begin
      Assert (Read ("1_000").Kind = Invalid, "Ada syntax is not Lua syntax");
   end Ada_Underscores_Are_Invalid;

   procedure Concatenation_Needs_Spacing is
      --  The lexer retains 1..2 as one malformed number, as C Lua does.
   begin
      Assert (Read ("1..2").Kind = Invalid, "second decimal point");
   end Concatenation_Needs_Spacing;

   procedure Embedded_Space_Is_Invalid is
      --  Trimming ends must not make internal whitespace acceptable.
   begin
      Assert (Read ("1 2").Kind = Invalid, "embedded whitespace");
   end Embedded_Space_Is_Invalid;

   procedure Base_Fraction_Is_Invalid is
      --  Explicit-base tonumber does not accept floating point syntax.
   begin
      Assert (Read ("1.5", Base => 10).Kind = Invalid, "base fraction");
   end Base_Fraction_Is_Invalid;

   procedure Overflow_Is_Infinity is
      --  Well-formed enormous positive exponents yield IEEE infinity.
      R : constant Number := Read ("1e9999");
   begin
      Assert (R.Kind = Real_Number, "overflow is a number");
      Assert (R.Real_Item > Real_Value'Last, "positive infinity");
   end Overflow_Is_Infinity;

   procedure Underflow_Is_Zero is
      --  A sufficiently small magnitude underflows without a host exception.
   begin
      Check_Real ("1e-9999", 0.0);
   end Underflow_Is_Zero;

   procedure Mixed_Equality_Is_Exact is
      --  Rounding an integer to double would incorrectly equate these values.
      I : constant Number := Read ("9007199254740993");
      F : constant Number := Read ("9007199254740992.0");
   begin
      Assert (not Equal (I, F), "integer precision must not be discarded");
   end Mixed_Equality_Is_Exact;

   procedure Mixed_Order_Is_Exact is
      --  The first integer beyond consecutive double precision is still
      --  greater.
      I : constant Number := Read ("9007199254740993");
      F : constant Number := Read ("9007199254740992.0");
   begin
      Assert (Less (F, I), "mixed comparison beyond 2**53");
      Assert (not Less (I, F), "reverse mixed ordering");
   end Mixed_Order_Is_Exact;

   procedure Upper_Boundary_Order is
      --  The double 2**63 is above every signed Lua integer.
      I : constant Number := Read ("9223372036854775807");
      F : constant Number := Read ("9223372036854775808.0");
   begin
      Assert (Less (I, F) and then not Equal (I, F),
              "signed upper endpoint and rounded float");
   end Upper_Boundary_Order;

   procedure Fractional_Mixed_Order is
      --  Comparison with an integer must preserve the fractional portion.
      I : constant Number := Read ("-2");
      F : constant Number := Read ("-1.5");
   begin
      Assert (Less (I, F), "negative fractional comparison");
      Assert (not Less (F, I), "reverse negative fractional comparison");
   end Fractional_Mixed_Order;

   procedure Smallest_Subnormal is
      --  Decimal conversion must retain the last representable positive bit;
      --  a host Ada Value conversion previously lost subnormal precision.
      Actual : constant Number := Read ("4.9406564584124654e-324");
   begin
      Assert (Actual.Kind = Real_Number, "subnormal is a float");
      Assert (Bits (Actual.Real_Item) = 1, "least positive binary64");
   end Smallest_Subnormal;

   procedure Halfway_Rounds_Even is
      --  This decimal is exactly halfway between 1 and its next double.
      --  IEEE nearest-even chooses 1, whose significand ends in zero.
      Actual : constant Number := Read
        ("1.00000000000000011102230246251565404236316680908203125");
   begin
      Assert (Actual.Real_Item = 1.0, "exact midpoint rounds to even");
   end Halfway_Rounds_Even;

   procedure Above_Halfway_Rounds_Up is
      --  One extra decimal unit above the midpoint must change the result;
      --  rounding the mantissa before dividing would erase this distinction.
      Actual : constant Number := Read
        ("1.00000000000000011102230246251565404236316680908203126");
   begin
      Assert (Bits (Actual.Real_Item) = 16#3FF0_0000_0000_0001#,
              "above midpoint chooses the next double");
   end Above_Halfway_Rounds_Up;

   procedure Normal_Boundary is
      --  Hex input directly names the smallest normal significand/exponent.
      --  It must not be classified or rounded as zero at the normal boundary.
      Actual : constant Number := Read ("0x1p-1022");
   begin
      Assert (Bits (Actual.Real_Item) = 16#0010_0000_0000_0000#,
              "smallest normal binary64");
   end Normal_Boundary;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "numbers: smallest subnormal",
                        Smallest_Subnormal'Access);
      Test_Support.Add (Suite, "numbers: halfway rounds even",
                        Halfway_Rounds_Even'Access);
      Test_Support.Add (Suite, "numbers: above halfway rounds up",
                        Above_Halfway_Rounds_Up'Access);
      Test_Support.Add (Suite, "numbers: normal boundary",
                        Normal_Boundary'Access);
      Test_Support.Add (Suite, "numbers: decimal integer",
                        Decimal_Integer'Access);
      Test_Support.Add (Suite, "numbers: negative minimum",
                        Negative_Minimum'Access);
      Test_Support.Add (Suite, "numbers: positive overflow",
                        Positive_Overflow'Access);
      Test_Support.Add (Suite, "numbers: leading fraction",
                        Leading_Fraction'Access);
      Test_Support.Add (Suite, "numbers: trailing point",
                        Trailing_Point'Access);
      Test_Support.Add (Suite, "numbers: decimal exponent",
                        Decimal_Exponent'Access);
      Test_Support.Add (Suite, "numbers: hex integer",
                        Hex_Integer'Access);
      Test_Support.Add (Suite, "numbers: hex wrapping",
                        Hex_Wrapping'Access);
      Test_Support.Add (Suite, "numbers: hex fraction",
                        Hex_Fraction'Access);
      Test_Support.Add (Suite, "numbers: hex leading fraction",
                        Hex_Leading_Fraction'Access);
      Test_Support.Add (Suite, "numbers: surrounding whitespace",
                        Surrounding_Whitespace'Access);
      Test_Support.Add (Suite, "numbers: explicit base",
                        Explicit_Base'Access);
      Test_Support.Add (Suite, "numbers: explicit base wrap",
                        Explicit_Base_Wrap'Access);
      Test_Support.Add (Suite, "numbers: empty is invalid",
                        Empty_Is_Invalid'Access);
      Test_Support.Add (Suite, "numbers: sign only is invalid",
                        Sign_Only_Is_Invalid'Access);
      Test_Support.Add (Suite, "numbers: missing exponent is invalid",
                        Missing_Exponent_Is_Invalid'Access);
      Test_Support.Add (Suite, "numbers: ada underscores are invalid",
                        Ada_Underscores_Are_Invalid'Access);
      Test_Support.Add (Suite, "numbers: concatenation needs spacing",
                        Concatenation_Needs_Spacing'Access);
      Test_Support.Add (Suite, "numbers: embedded space is invalid",
                        Embedded_Space_Is_Invalid'Access);
      Test_Support.Add (Suite, "numbers: base fraction is invalid",
                        Base_Fraction_Is_Invalid'Access);
      Test_Support.Add (Suite, "numbers: overflow is infinity",
                        Overflow_Is_Infinity'Access);
      Test_Support.Add (Suite, "numbers: underflow is zero",
                        Underflow_Is_Zero'Access);
      Test_Support.Add (Suite, "numbers: mixed equality is exact",
                        Mixed_Equality_Is_Exact'Access);
      Test_Support.Add (Suite, "numbers: mixed order is exact",
                        Mixed_Order_Is_Exact'Access);
      Test_Support.Add (Suite, "numbers: upper boundary order",
                        Upper_Boundary_Order'Access);
      Test_Support.Add (Suite, "numbers: fractional mixed order",
                        Fractional_Mixed_Order'Access);
   end Register;
end Number_Tests;
