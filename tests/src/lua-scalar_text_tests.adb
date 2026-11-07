with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Lua.Engine; use Lua.Engine;
with Lua.Platform_Locales;
with Lua.Storage;
with Test_Support;

package body Lua.Scalar_Text_Tests is
   use type Lua.Storage.Byte_Count;
   function Real is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, Real_Value);
   procedure Check (Bits : Interfaces.Unsigned_64; Expected : String);
   procedure Positive_Even_Tie;
   procedure Negative_Even_Tie;
   procedure Large_Even_Tie;
   procedure Subnormal_Fifteen_Digits;
   procedure Maximum_Finite;
   procedure Negative_Zero;

   procedure Check (Bits : Interfaces.Unsigned_64; Expected : String) is
      Memory : Lua.Storage.Owner;
      Native_Text : String := Expected;
      Point : constant Character :=
        Character'Val (Lua.Platform_Locales.Decimal_Point);
   begin
      --  Each exact expected spelling was observed from the independent
      --  pinned C image. Refuse every selected-provider growth before the
      --  operation: the scalar workspace must not depend on that provider.
      Lua.Storage.Set_Failure_Countdown (Memory, 0);
      for Byte of Native_Text loop
         if Byte = '.' then Byte := Point; end if;
      end loop;
      Assert (Image (Lua.Storage.Reference (Memory),
                     Value'(Real_Kind, Real (Bits))) = Native_Text,
              "exact pinned scalar spelling for " & Expected);
      Assert (Lua.Storage.Statistics (Memory).Growth_Attempts = 0 and then
              Lua.Storage.Statistics (Memory).Live_Blocks = 0,
              "scalar rendering makes no selected-provider request");
   end Check;

   procedure Positive_Even_Tie is
   begin
      --  Exact .625 is halfway at seventeen significant digits. Decimal
      --  quotient/remainder rounding must choose the even final digit.
      Check (16#42E8_ED5B_E419_3CF4#, "219261823928807.62");
   end Positive_Even_Tie;

   procedure Negative_Even_Tie is
   begin
      --  The rounding rule acts on magnitude before restoring the sign;
      --  negative halfway values must not inherit Float_IO's away rounding.
      Check (16#C2F4_AD6F_C23F_3312#, "-363762190381873.12");
   end Negative_Even_Tie;

   procedure Large_Even_Tie is
   begin
      --  A different binary exponent protects the fixed/general boundary
      --  from an accidental correction specific to one mantissa magnitude.
      Check (16#4300_39D2_9E91_EB75#, "570897049206126.62");
   end Large_Even_Tie;

   procedure Subnormal_Fifteen_Digits is
   begin
      --  The fifteen-digit spelling already round-trips to this subnormal.
      --  A less accurate readback incorrectly chooses the longer fallback.
      Check (16#8001_AD5A_972D_9019#, "-2.33238298489396e-309");
   end Subnormal_Fifteen_Digits;

   procedure Maximum_Finite is
   begin
      --  The first spelling rounds outside the finite range; its actual
      --  readback requires a successful seventeen-digit retry, not an abort.
      Check (16#7FEF_FFFF_FFFF_FFFF#, "1.7976931348623157e+308");
   end Maximum_Finite;

   procedure Negative_Zero is
   begin
      --  Preserve both the sign bit and a real-looking suffix even though
      --  the exact rational magnitude has no significant numerator limbs.
      Check (16#8000_0000_0000_0000#, "-0.0");
   end Negative_Zero;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "scalar text: positive even decimal tie",
                        Positive_Even_Tie'Access);
      Test_Support.Add (Suite, "scalar text: negative even decimal tie",
                        Negative_Even_Tie'Access);
      Test_Support.Add (Suite, "scalar text: large even decimal tie",
                        Large_Even_Tie'Access);
      Test_Support.Add (Suite, "scalar text: fifteen digit subnormal",
                        Subnormal_Fifteen_Digits'Access);
      Test_Support.Add (Suite, "scalar text: maximum finite retry",
                        Maximum_Finite'Access);
      Test_Support.Add (Suite, "scalar text: negative real zero",
                        Negative_Zero'Access);
   end Register;
end Lua.Scalar_Text_Tests;
