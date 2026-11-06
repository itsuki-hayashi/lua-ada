with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Mathematics;
with Test_Support;

package body Lua.Mathematics_Tests is
   use type Interfaces.Unsigned_64;
   use type Integer_Value;
   use type Real_Value;
   subtype Word is Interfaces.Unsigned_64;
   function Bits is new Ada.Unchecked_Conversion (Real_Value, Word);
   function Real_From is new Ada.Unchecked_Conversion (Word, Real_Value);
   function Integer_Bits is new Ada.Unchecked_Conversion (Integer_Value, Word);
   package Math renames Lua.Engine.Mathematics;

   function Args (First : Value) return Values.Vector;
   function Args (First : Value) return Values.Vector is
      Result : Values.Vector;
   begin
      Result.Append (First);
      return Result;
   end Args;
   function Args (First, Second : Value) return Values.Vector;
   function Args (First, Second : Value) return Values.Vector is
      Result : Values.Vector := Args (First);
   begin
      Result.Append (Second);
      return Result;
   end Args;
   function Int (Item : Integer_Value) return Value is ((Integer_Kind, Item));
   function Real (Item : Real_Value) return Value is ((Real_Kind, Item));

   procedure Seed
     (State : in out World; First : Integer_Value := 0;
      Second : Integer_Value := 0);
   procedure Seed
     (State : in out World; First : Integer_Value := 0;
      Second : Integer_Value := 0)
   is
      Result : constant Values.Vector :=
        Math.Run (State, "math.randomseed", Args (Int (First), Int (Second)));
   begin
      Assert (Natural (Result.Length) = 2 and then
              Result (1).Integer_Data = First and then
              Result (2).Integer_Data = Second, "seed setup/result packet");
   end Seed;

   function Fails
     (State : in out World; Name : String; Arguments : Values.Vector)
      return Boolean;
   function Fails
     (State : in out World; Name : String; Arguments : Values.Vector)
      return Boolean
   is
      Result : Values.Vector;
      pragma Unreferenced (Result);
   begin
      --  Execute inside the handled sequence. A declaration initializer can
      --  fail while elaborating the body, before this expected-error handler.
      Result := Math.Run (State, Name, Arguments);
      return False;
   exception
      when Language_Error => return True;
   end Fails;

   generic
      with procedure Action (State : in out World);
   procedure Fixture;
   procedure Fixture is
      State : World;
   begin
      --  Heap and RNG state belong to this case alone. Cleanup after failures
      --  is essential: a failed RNG check must not contaminate its successor.
      Initialize (State, (others => <>));
      begin
         Action (State);
      exception
         when others => Finalize (State); raise;
      end;
      Finalize (State);
   end Fixture;

   procedure Sine_Signed_Zero (State : in out World);
   procedure Cosine_Origin (State : in out World);
   procedure Tangent_Signed_Zero (State : in out World);
   procedure Arc_Sine_Domain (State : in out World);
   procedure Arc_Cosine_Domain (State : in out World);
   procedure Atan_Quadrants (State : in out World);
   procedure Exponential_Limits (State : in out World);
   procedure Square_Root_Domain (State : in out World);
   procedure Square_Root_Zero (State : in out World);
   procedure Logarithm_Bases (State : in out World);
   procedure Logarithm_Unit_Base (State : in out World);
   procedure Angular_Conversions (State : in out World);
   procedure Frexp_Subnormal (State : in out World);
   procedure Frexp_Signed_Zero (State : in out World);
   procedure Ldexp_C_Int_Cast (State : in out World);
   procedure Numeric_Strings (State : in out World);
   procedure Missing_Argument (State : in out World);
   procedure Invalid_Argument (State : in out World);
   procedure Known_Integer_Stream (State : in out World);
   procedure Known_Float_Stream (State : in out World);
   procedure Rejection_Sequence (State : in out World);
   procedure Full_Integer_Interval (State : in out World);
   procedure Power_Of_Two_Projection (State : in out World);
   procedure Invalid_Call_Advances (State : in out World);
   procedure Invalid_Count_Advances (State : in out World);
   procedure Seed_Optional_Argument (State : in out World);
   procedure Seed_Nil_Rejected (State : in out World);
   procedure Independent_Generators (State : in out World);
   procedure Split_Generator (State : in out World);
   procedure Reset_Precedes_Budget (State : in out World);
   procedure Rejection_Budget (State : in out World);
   procedure Automatic_Seed_Reproduction (State : in out World);
   procedure Compatibility_Cosh (State : in out World);
   procedure Compatibility_Sinh (State : in out World);
   procedure Compatibility_Tanh (State : in out World);
   procedure Compatibility_Power (State : in out World);
   procedure Compatibility_Log10 (State : in out World);
   procedure Compatibility_Atan2 (State : in out World);

   procedure Sine_Signed_Zero (State : in out World) is
      Result : constant Values.Vector := Math.Run
        (State, "math.sin", Args (Real (Real_From (2 ** 63))));
   begin
      --  A numeric zero comparison hides its sign. Check the binary64 result
      --  of the host primitive, protecting Lua's signed-zero contract.
      Assert (Bits (Result (1).Real_Data) = 2 ** 63, "sin(-0) sign");
   end Sine_Signed_Zero;

   procedure Cosine_Origin (State : in out World) is
      Result : constant Values.Vector :=
        Math.Run (State, "math.cos", Args (Int (0)));
   begin
      --  Integer inputs must still produce a floating result, even when the
      --  mathematical answer is an exactly representable integer.
      Assert (Result (1).Kind = Real_Kind and then
              Result (1).Real_Data = 1.0, "cos(0) float result");
   end Cosine_Origin;

   procedure Tangent_Signed_Zero (State : in out World) is
      Result : constant Values.Vector := Math.Run
        (State, "math.tan", Args (Real (Real_From (2 ** 63))));
   begin
      --  Tangent has its own imported primitive; verify it does not lose the
      --  sign through an integer conversion or a sine/cosine quotient.
      Assert (Bits (Result (1).Real_Data) = 2 ** 63, "tan(-0) sign");
   end Tangent_Signed_Zero;

   procedure Arc_Sine_Domain (State : in out World) is
      Result : constant Values.Vector :=
        Math.Run (State, "math.asin", Args (Int (2)));
      X : constant Real_Value := Result (1).Real_Data;
   begin
      --  Lua exposes a NaN outside asin's real domain. An Ada elementary
      --  Argument_Error must not escape from this language-level operation.
      Assert (X /= X, "asin domain yields NaN");
   end Arc_Sine_Domain;

   procedure Arc_Cosine_Domain (State : in out World) is
      Result : constant Values.Vector :=
        Math.Run (State, "math.acos", Args (Int (-2)));
      X : constant Real_Value := Result (1).Real_Data;
   begin
      --  Check acos separately: its domain and endpoint implementation are
      --  independent from asin in the host library.
      Assert (X /= X, "acos domain yields NaN");
   end Arc_Cosine_Domain;

   procedure Atan_Quadrants (State : in out World) is
      One : constant Values.Vector :=
        Math.Run (State, "math.atan", Args (Int (1)));
      Explicit_One : constant Values.Vector :=
        Math.Run (State, "math.atan", Args (Int (1), Int (1)));
      Negative_Zero : constant Values.Vector := Math.Run
        (State, "math.atan", Args (Real (Real_From (2 ** 63)), Int (-1)));
   begin
      --  Lua's atan is atan2 with an optional x=1. The negative-zero case
      --  protects quadrant selection, which atan(y/x) would get wrong.
      Assert (Bits (One (1).Real_Data) = Bits (Explicit_One (1).Real_Data),
              "atan optional x");
      Assert (Negative_Zero (1).Real_Data < -3.14, "atan negative quadrant");
   end Atan_Quadrants;

   procedure Exponential_Limits (State : in out World) is
      Large : constant Values.Vector :=
        Math.Run (State, "math.exp", Args (Int (1000)));
      Small : constant Values.Vector :=
        Math.Run (State, "math.exp", Args (Int (-1000)));
   begin
      --  Host overflow/underflow are ordinary IEEE results in Lua. Preserve
      --  infinity and zero rather than turning either into a runtime error.
      Assert (Bits (Large (1).Real_Data) = 16#7FF0_0000_0000_0000#,
              "exp overflow infinity");
      Assert (Bits (Small (1).Real_Data) = 0, "exp underflow zero");
   end Exponential_Limits;

   procedure Square_Root_Domain (State : in out World) is
      Result : constant Values.Vector :=
        Math.Run (State, "math.sqrt", Args (Int (-1)));
      X : constant Real_Value := Result (1).Real_Data;
   begin
      --  A negative argument is a NaN result, not an Ada exception or a
      --  fabricated nil result.
      Assert (X /= X, "sqrt negative argument");
   end Square_Root_Domain;

   procedure Square_Root_Zero (State : in out World) is
      Result : constant Values.Vector := Math.Run
        (State, "math.sqrt", Args (Real (Real_From (2 ** 63))));
   begin
      --  IEEE sqrt preserves the sign of negative zero, independently from
      --  the negative-domain NaN case above.
      Assert (Bits (Result (1).Real_Data) = 2 ** 63, "sqrt(-0) sign");
   end Square_Root_Zero;

   procedure Logarithm_Bases (State : in out World) is
      Binary : constant Values.Vector :=
        Math.Run (State, "math.log", Args (Int (8), Int (2)));
      Decimal : constant Values.Vector :=
        Math.Run (State, "math.log", Args (Int (100), Int (10)));
   begin
      --  Lua selects host log2/log10 for these bases. A quotient of rounded
      --  natural logarithms can differ even at these exact powers.
      Assert (Binary (1).Real_Data = 3.0, "binary logarithm branch");
      Assert (Decimal (1).Real_Data = 2.0, "decimal logarithm branch");
   end Logarithm_Bases;

   procedure Logarithm_Unit_Base (State : in out World) is
      Infinite : constant Values.Vector :=
        Math.Run (State, "math.log", Args (Int (2), Int (1)));
      Invalid : constant Values.Vector :=
        Math.Run (State, "math.log", Args (Int (1), Int (1)));
      X : constant Real_Value := Invalid (1).Real_Data;
   begin
      --  Division by log(1)=0 must use IEEE semantics, not Ada's checked
      --  zero-divisor exception. Distinguish nonzero/zero and zero/zero.
      Assert (Bits (Infinite (1).Real_Data) = 16#7FF0_0000_0000_0000#,
              "unit-base infinity");
      Assert (X /= X, "unit-base indeterminate result");
   end Logarithm_Unit_Base;

   procedure Angular_Conversions (State : in out World) is
      Radians : constant Values.Vector :=
        Math.Run (State, "math.rad", Args (Int (180)));
      Degrees : constant Values.Vector :=
        Math.Run (State, "math.deg", Args (Real (Radians (1).Real_Data)));
   begin
      --  Keep the pinned multiplication order and binary64 pi constant.
      --  Reassociating the conversion can change endpoint rounding.
      Assert (Radians (1).Real_Data > 3.14 and then
              Radians (1).Real_Data < 3.15, "radian conversion");
      Assert (Degrees (1).Real_Data = 180.0, "degree conversion");
   end Angular_Conversions;

   procedure Frexp_Subnormal (State : in out World) is
      Result : constant Values.Vector :=
        Math.Run (State, "math.frexp", Args (Real (Real_From (1))));
   begin
      --  The smallest binary64 subnormal is 0.5 * 2**(-1073). Check both
      --  return positions and their Lua number kinds.
      Assert (Natural (Result.Length) = 2 and then
              Result (1).Real_Data = 0.5 and then
              Result (2).Integer_Data = -1073, "frexp subnormal pair");
   end Frexp_Subnormal;

   procedure Frexp_Signed_Zero (State : in out World) is
      Result : constant Values.Vector :=
        Math.Run (State, "math.frexp", Args (Real (Real_From (2 ** 63))));
   begin
      --  Decomposition preserves a zero's sign and writes the exponent through
      --  a real borrowed C int, not a fabricated second Lua result.
      Assert (Bits (Result (1).Real_Data) = 2 ** 63 and then
              Result (2).Integer_Data = 0, "frexp negative zero");
   end Frexp_Signed_Zero;

   procedure Ldexp_C_Int_Cast (State : in out World) is
      Result : constant Values.Vector := Math.Run
        (State, "math.ldexp", Args (Real (0.75), Int (2 ** 32 + 1)));
   begin
      --  Pinned Lua casts the integer exponent to the host C int. On the
      --  supported ABIs its low 32 bits select exponent one; no Ada range
      --  failure is permitted for this valid Lua integer argument.
      Assert (Result (1).Real_Data = 1.5, "ldexp C exponent conversion");
   end Ldexp_C_Int_Cast;

   procedure Numeric_Strings (State : in out World) is
      Result : constant Values.Vector := Math.Run
        (State, "math.cos", Args (New_String (State, " 0x0p0 ")));
   begin
      --  Auxiliary math argument checks accept numeric byte strings. Keep
      --  this conversion separate from primitive bitwise coercion policy.
      Assert (Result (1).Real_Data = 1.0, "math numeric string");
   end Numeric_Strings;

   procedure Missing_Argument (State : in out World) is
   begin
      --  No argument is distinct from a supplied nil in the diagnostic; the
      --  failure uses the language transfer, never a vector index error.
      Assert (Fails (State, "math.sin", Values.Empty_Vector),
              "missing mathematical argument");
      Assert (State.Current.Failure_Class = Language_Failure,
              "missing argument language classification");
   end Missing_Argument;

   procedure Invalid_Argument (State : in out World) is
   begin
      --  A boolean cannot become a numeric zero. Reject it through the same
      --  controlled Lua path used by the public native dispatcher.
      Assert (Fails (State, "math.exp", Args ((Boolean_Kind, True))),
              "boolean mathematical argument");
   end Invalid_Argument;

   procedure Known_Integer_Stream (State : in out World) is
      type Word_Array is array (Positive range <>) of Word;
      Expected : constant Word_Array :=
        [16#3F35_9D4E_37B4_33C1#, 16#3C1D_C586_F35D_E208#,
         16#11BC_1166_AD55_F7AB#, 16#9622_8121_1A7B_2F15#,
         16#7963_8F04_6E82_6CAF#, 16#43ED_AB18_30E0_D8EC#,
         16#5D18_BBBA_E04D_2457#, 16#6E8C_388E_0E9F_5838#];
   begin
      --  These fixed seed(0,0) words were measured from pinned C Lua. The
      --  case protects seeding, 16 warmup transitions and full integer output.
      Seed (State);
      for Expected_Word of Expected loop
         declare
            Result : constant Values.Vector :=
              Math.Run (State, "math.random", Args (Int (0)));
         begin
            Assert (Integer_Bits (Result (1).Integer_Data) = Expected_Word,
                    "pinned full-width random word");
         end;
      end loop;
   end Known_Integer_Stream;

   procedure Known_Float_Stream (State : in out World) is
      type Word_Array is array (Positive range <>) of Word;
      Expected : constant Word_Array :=
        [16#3FEF_09B0_3A44_FC52#, 16#3FA2_E257_BF7B_58A0#,
         16#3F9B_6C2D_3CA1_EBC0#, 16#3FD1_240F_6F33_59FE#,
         16#3FEB_B857_8576_155D#, 16#3FE5_5F51_5EEE_3FB4#];
   begin
      --  Preserve the high 53 random bits and exact power-of-two scaling.
      --  Low-bit or decimal-normalized output can conceal a wrong RNG path.
      Seed (State, 17, -9);
      for Expected_Word of Expected loop
         declare
            Result : constant Values.Vector :=
              Math.Run (State, "math.random", Values.Empty_Vector);
         begin
            Assert (Bits (Result (1).Real_Data) = Expected_Word,
                    "pinned binary64 random fraction");
         end;
      end loop;
   end Known_Float_Stream;

   procedure Rejection_Sequence (State : in out World) is
      type Integers is array (Positive range <>) of Integer_Value;
      Expected : constant Integers := [-16, -9, 4, 6, 5, -2, 25, 17];
   begin
      --  A 43-value interval requires rejection sampling. These pinned
      --  outputs also verify how many generator words each retry consumes.
      Seed (State);
      for Item of Expected loop
         declare
            Result : constant Values.Vector :=
              Math.Run (State, "math.random", Args (Int (-17), Int (25)));
         begin
            Assert (Result (1).Integer_Data = Item, "rejection sequence");
         end;
      end loop;
   end Rejection_Sequence;

   procedure Full_Integer_Interval (State : in out World) is
      Result : Values.Vector;
   begin
      --  The signed interval spans 2**64 possibilities. Its width and offset
      --  use modular arithmetic instead of overflowing signed subtraction.
      Seed (State);
      Result := Math.Run (State, "math.random",
        Args (Int (Integer_Value'First), Int (Integer_Value'Last)));
      Assert (Integer_Bits (Result (1).Integer_Data) =
              16#BF35_9D4E_37B4_33C1#, "full signed interval");
   end Full_Integer_Interval;

   procedure Power_Of_Two_Projection (State : in out World) is
      Result : Values.Vector;
   begin
      --  A 256-value interval needs no retries. Its low eight bits must match
      --  the full-width generator and leave the second word ready next.
      Seed (State);
      Result := Math.Run (State, "math.random", Args (Int (0), Int (255)));
      Assert (Result (1).Integer_Data = 16#C1#, "power-of-two projection");
      Result := Math.Run (State, "math.random", Args (Int (0)));
      Assert (Integer_Bits (Result (1).Integer_Data) =
              16#3C1D_C586_F35D_E208#, "projection consumes one word");
   end Power_Of_Two_Projection;

   procedure Invalid_Call_Advances (State : in out World) is
      Result : Values.Vector;
   begin
      --  Pinned Lua draws before type validation. Catching a bad argument
      --  must not roll back the RNG stream to the first word.
      Seed (State);
      Assert (Fails (State, "math.random", Args (Nil_Value)),
              "nil random limit rejected");
      Result := Math.Run (State, "math.random", Args (Int (0)));
      Assert (Integer_Bits (Result (1).Integer_Data) =
              16#3C1D_C586_F35D_E208#, "invalid call consumes one word");
   end Invalid_Call_Advances;

   procedure Invalid_Count_Advances (State : in out World) is
      Arguments : Values.Vector := Args (Int (1), Int (2));
      Result : Values.Vector;
   begin
      --  Wrong arity has the same advance-before-validation behavior as bad
      --  types. Extra arguments to random are errors, not silently ignored.
      Seed (State);
      Arguments.Append (Int (3));
      Assert (Fails (State, "math.random", Arguments), "random arity");
      Result := Math.Run (State, "math.random", Args (Int (0)));
      Assert (Integer_Bits (Result (1).Integer_Data) =
              16#3C1D_C586_F35D_E208#, "invalid arity consumes one word");
   end Invalid_Count_Advances;

   procedure Seed_Optional_Argument (State : in out World) is
      Result : constant Values.Vector := Math.Run
        (State, "math.randomseed", Args (Int (-17), Nil_Value));
   begin
      --  A missing or nil second seed means integer zero. Signed seed bits
      --  and the two-result packet must survive without float conversion.
      Assert (Natural (Result.Length) = 2 and then
              Result (1).Integer_Data = -17 and then
              Result (2).Integer_Data = 0, "optional second seed");
   end Seed_Optional_Argument;

   procedure Seed_Nil_Rejected (State : in out World) is
   begin
      --  An omitted first seed requests automatic entropy; an explicit nil
      --  is a type error. They cannot be collapsed by an Arg helper.
      Assert (Fails (State, "math.randomseed", Args (Nil_Value)),
              "explicit nil first seed");
   end Seed_Nil_Rejected;

   procedure Independent_Generators (State : in out World) is
      Other : World;
      Result : Values.Vector;
   begin
      --  Seed and advance another universe between this universe's draws.
      --  Global libc RNG state would make the pinned second word disappear.
      Initialize (Other, (others => <>));
      begin
         Seed (State);
         Result := Math.Run (State, "math.random", Args (Int (0)));
         Seed (Other, 99, 101);
         Result := Math.Run (Other, "math.random", Args (Int (0)));
         Result := Math.Run (State, "math.random", Args (Int (0)));
         Assert (Integer_Bits (Result (1).Integer_Data) =
                 16#3C1D_C586_F35D_E208#, "independent RNG ownership");
      exception
         when others => Finalize (Other); raise;
      end;
      Finalize (Other);
   end Independent_Generators;

   procedure Split_Generator (State : in out World) is
      Other : World;
      Left, Right : Values.Vector;
   begin
      --  The instrumented configuration performs real 32-bit carry/rotation
      --  arithmetic. It must emit the same words as the native 64-bit path.
      Initialize (Other, (others => <>));
      begin
         Other.Random_Use_32_Bits := True;
         State.Random_Use_32_Bits := False;
         Seed (State, -1, Integer_Value'Last);
         Seed (Other, -1, Integer_Value'Last);
         for Index in 1 .. 1_024 loop
            Left := Math.Run (State, "math.random", Args (Int (0)));
            Right := Math.Run (Other, "math.random", Args (Int (0)));
            Assert (Left (1).Integer_Data = Right (1).Integer_Data,
                    "32/64-bit generator equivalence");
         end loop;
      exception
         when others => Finalize (Other); raise;
      end;
      Finalize (Other);
   end Split_Generator;

   procedure Reset_Precedes_Budget (State : in out World) is
      Result : Values.Vector;
   begin
      --  Standard-library initialization precedes execution. A one-instruction
      --  session must still seed successfully and retain that instruction.
      State.Bounds.Instructions := 1;
      State.Steps := 0;
      Math.Reset (State);
      Assert (State.Steps = 0, "reset does not spend execution allowance");
      Result := Math.Run (State, "math.random", Values.Empty_Vector);
      Assert (Result (1).Real_Data >= 0.0 and then
              Result (1).Real_Data < 1.0, "seeded bounded result");
   end Reset_Precedes_Budget;

   procedure Rejection_Budget (State : in out World) is
   begin
      --  With seed(0,0), the first byte is 193, outside [0,128]. Allow the
      --  first draw only; its retry must trigger an uncatchable host abort.
      Seed (State);
      State.Bounds.Instructions := 1;
      State.Steps := 0;
      Assert (Fails (State, "math.random", Args (Int (0), Int (128))),
              "rejection retry charged");
      Assert (State.Current.Failure_Class = Host_Abort,
              "native retry preserves host abort classification");
   end Rejection_Budget;

   procedure Automatic_Seed_Reproduction (State : in out World) is
      Seeds : constant Values.Vector :=
        Math.Run (State, "math.randomseed", Values.Empty_Vector);
      First : constant Values.Vector :=
        Math.Run (State, "math.random", Args (Int (0)));
      Reseed : constant Values.Vector :=
        Math.Run (State, "math.randomseed", Seeds);
      Again : constant Values.Vector :=
        Math.Run (State, "math.random", Args (Int (0)));
   begin
      --  Automatic seeding is unspecified entropy, but its two returned seeds
      --  are a reproducible description of the resulting generator state.
      Assert (Natural (Reseed.Length) = 2 and then
              First (1).Integer_Data = Again (1).Integer_Data,
              "automatic seed reproduction");
   end Automatic_Seed_Reproduction;

   procedure Compatibility_Cosh (State : in out World) is
      Result : constant Values.Vector :=
        Math.Run (State, "math.cosh", Args (Int (0)));
   begin
      --  Compatibility registration is a profile decision. The actual
      --  hyperbolic cosine primitive still has a distinct floating result.
      Assert (Result (1).Real_Data = 1.0, "compat hyperbolic cosine");
   end Compatibility_Cosh;

   procedure Compatibility_Sinh (State : in out World) is
      Result : constant Values.Vector := Math.Run
        (State, "math.sinh", Args (Real (Real_From (2 ** 63))));
   begin
      --  Hyperbolic sine preserves negative zero. Check its bits directly;
      --  comparing it with integer zero would hide a wrong host adapter.
      Assert (Bits (Result (1).Real_Data) = 2 ** 63, "compat sinh sign");
   end Compatibility_Sinh;

   procedure Compatibility_Tanh (State : in out World) is
      Result : constant Values.Vector := Math.Run
        (State, "math.tanh", Args (Real (Real_From (2 ** 63))));
   begin
      --  Hyperbolic tangent uses its own libm operation and must also retain
      --  the sign of negative zero independently from sinh.
      Assert (Bits (Result (1).Real_Data) = 2 ** 63, "compat tanh sign");
   end Compatibility_Tanh;

   procedure Compatibility_Power (State : in out World) is
      Result : constant Values.Vector :=
        Math.Run (State, "math.pow", Args (Int (-2), Int (3)));
   begin
      --  A negative base with an integral exponent is valid in Lua's host
      --  power operation, despite Ada elementary logarithm-domain rules.
      Assert (Result (1).Real_Data = -8.0, "compat signed integral power");
   end Compatibility_Power;

   procedure Compatibility_Log10 (State : in out World) is
      Result : constant Values.Vector :=
        Math.Run (State, "math.log10", Args (Int (100)));
   begin
      --  This compatibility export calls the host decimal logarithm directly.
      --  Preserve its exact result at an integral power of ten.
      Assert (Result (1).Real_Data = 2.0, "compat decimal logarithm");
   end Compatibility_Log10;

   procedure Compatibility_Atan2 (State : in out World) is
      Result : constant Values.Vector :=
        Math.Run (State, "math.atan2", Args (Int (0), Int (-1)));
   begin
      --  The compatibility name shares atan's two-argument quadrant behavior.
      --  A positive zero ordinate over negative x must select positive pi.
      Assert (Result (1).Real_Data > 3.14, "compat atan2 quadrant");
   end Compatibility_Atan2;

   procedure Script_Random_No_Arguments (State : in out World);
   procedure Script_Seed_No_Arguments (State : in out World);

   procedure Script_Random_No_Arguments (State : in out World) is
   begin
      --  Exercise the installed Lua export through normal native dispatch.
      --  A zero-argument draw is valid and reproducible after the same seed;
      --  the generic core-library arity check must not intercept it.
      Assert (Execute (State,
        "math.randomseed(17,-9);local a=math.random();" &
        "math.randomseed(17,-9);assert(a==math.random() and a>=0 and a<1)",
        "random-no-args"), "script random() was rejected");
   end Script_Random_No_Arguments;

   procedure Script_Seed_No_Arguments (State : in out World) is
   begin
      --  Automatic seeding returns the actual two words. Replaying them must
      --  reconstruct the next draw through the public Lua-facing functions.
      Assert (Execute (State,
        "local a,b=math.randomseed();local r=math.random(0);" &
        "math.randomseed(a,b);assert(math.random(0)==r)", "seed-no-args"),
        "script randomseed() was rejected");
   end Script_Seed_No_Arguments;

   procedure Script_Random_Case is new Fixture (Script_Random_No_Arguments);
   procedure Script_Seed_Case is new Fixture (Script_Seed_No_Arguments);
   procedure Sine_Case is new Fixture (Sine_Signed_Zero);
   procedure Cosine_Case is new Fixture (Cosine_Origin);
   procedure Tangent_Case is new Fixture (Tangent_Signed_Zero);
   procedure Asin_Case is new Fixture (Arc_Sine_Domain);
   procedure Acos_Case is new Fixture (Arc_Cosine_Domain);
   procedure Atan_Case is new Fixture (Atan_Quadrants);
   procedure Exp_Case is new Fixture (Exponential_Limits);
   procedure Sqrt_Domain_Case is new Fixture (Square_Root_Domain);
   procedure Sqrt_Zero_Case is new Fixture (Square_Root_Zero);
   procedure Log_Base_Case is new Fixture (Logarithm_Bases);
   procedure Log_Unit_Case is new Fixture (Logarithm_Unit_Base);
   procedure Angle_Case is new Fixture (Angular_Conversions);
   procedure Frexp_Subnormal_Case is new Fixture (Frexp_Subnormal);
   procedure Frexp_Zero_Case is new Fixture (Frexp_Signed_Zero);
   procedure Ldexp_Case is new Fixture (Ldexp_C_Int_Cast);
   procedure Numeric_String_Case is new Fixture (Numeric_Strings);
   procedure Missing_Case is new Fixture (Missing_Argument);
   procedure Invalid_Case is new Fixture (Invalid_Argument);
   procedure Integer_Stream_Case is new Fixture (Known_Integer_Stream);
   procedure Float_Stream_Case is new Fixture (Known_Float_Stream);
   procedure Rejection_Case is new Fixture (Rejection_Sequence);
   procedure Full_Range_Case is new Fixture (Full_Integer_Interval);
   procedure Power_Two_Case is new Fixture (Power_Of_Two_Projection);
   procedure Invalid_Advance_Case is new Fixture (Invalid_Call_Advances);
   procedure Arity_Advance_Case is new Fixture (Invalid_Count_Advances);
   procedure Optional_Seed_Case is new Fixture (Seed_Optional_Argument);
   procedure Nil_Seed_Case is new Fixture (Seed_Nil_Rejected);
   procedure Independent_Case is new Fixture (Independent_Generators);
   procedure Split_Case is new Fixture (Split_Generator);
   procedure Reset_Case is new Fixture (Reset_Precedes_Budget);
   procedure Budget_Case is new Fixture (Rejection_Budget);
   procedure Automatic_Case is new Fixture (Automatic_Seed_Reproduction);
   procedure Cosh_Case is new Fixture (Compatibility_Cosh);
   procedure Sinh_Case is new Fixture (Compatibility_Sinh);
   procedure Tanh_Case is new Fixture (Compatibility_Tanh);
   procedure Power_Case is new Fixture (Compatibility_Power);
   procedure Log10_Case is new Fixture (Compatibility_Log10);
   procedure Atan2_Case is new Fixture (Compatibility_Atan2);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "math: script zero-argument random",
                        Script_Random_Case'Access);
      Test_Support.Add (Suite, "math: script automatic randomseed",
                        Script_Seed_Case'Access);
      Test_Support.Add (Suite, "math: sine signed zero", Sine_Case'Access);
      Test_Support.Add (Suite, "math: cosine origin", Cosine_Case'Access);
      Test_Support.Add
        (Suite, "math: tangent signed zero", Tangent_Case'Access);
      Test_Support.Add (Suite, "math: asin domain", Asin_Case'Access);
      Test_Support.Add (Suite, "math: acos domain", Acos_Case'Access);
      Test_Support.Add (Suite, "math: atan quadrants", Atan_Case'Access);
      Test_Support.Add (Suite, "math: exponential limits", Exp_Case'Access);
      Test_Support.Add
        (Suite, "math: sqrt domain", Sqrt_Domain_Case'Access);
      Test_Support.Add
        (Suite, "math: sqrt signed zero", Sqrt_Zero_Case'Access);
      Test_Support.Add (Suite, "math: logarithm bases", Log_Base_Case'Access);
      Test_Support.Add
        (Suite, "math: logarithm unit base", Log_Unit_Case'Access);
      Test_Support.Add (Suite, "math: angle conversions", Angle_Case'Access);
      Test_Support.Add
        (Suite, "math: frexp subnormal", Frexp_Subnormal_Case'Access);
      Test_Support.Add
        (Suite, "math: frexp signed zero", Frexp_Zero_Case'Access);
      Test_Support.Add (Suite, "math: ldexp C int cast", Ldexp_Case'Access);
      Test_Support.Add
        (Suite, "math: numeric string", Numeric_String_Case'Access);
      Test_Support.Add (Suite, "math: missing argument", Missing_Case'Access);
      Test_Support.Add (Suite, "math: invalid argument", Invalid_Case'Access);
      Test_Support.Add
        (Suite, "math: pinned integer stream", Integer_Stream_Case'Access);
      Test_Support.Add
        (Suite, "math: pinned float stream", Float_Stream_Case'Access);
      Test_Support.Add
        (Suite, "math: rejection sequence", Rejection_Case'Access);
      Test_Support.Add
        (Suite, "math: full signed interval", Full_Range_Case'Access);
      Test_Support.Add
        (Suite, "math: power-of-two range", Power_Two_Case'Access);
      Test_Support.Add
        (Suite, "math: invalid call advances", Invalid_Advance_Case'Access);
      Test_Support.Add
        (Suite, "math: invalid arity advances", Arity_Advance_Case'Access);
      Test_Support.Add
        (Suite, "math: optional seed", Optional_Seed_Case'Access);
      Test_Support.Add (Suite, "math: nil seed", Nil_Seed_Case'Access);
      Test_Support.Add
        (Suite, "math: independent generators", Independent_Case'Access);
      Test_Support.Add (Suite, "math: split generator", Split_Case'Access);
      Test_Support.Add (Suite, "math: reset before budget", Reset_Case'Access);
      Test_Support.Add (Suite, "math: rejection budget", Budget_Case'Access);
      Test_Support.Add
        (Suite, "math: automatic seed replay", Automatic_Case'Access);
      Test_Support.Add (Suite, "math: compat cosh", Cosh_Case'Access);
      Test_Support.Add (Suite, "math: compat sinh sign", Sinh_Case'Access);
      Test_Support.Add (Suite, "math: compat tanh sign", Tanh_Case'Access);
      Test_Support.Add (Suite, "math: compat power", Power_Case'Access);
      Test_Support.Add (Suite, "math: compat log10", Log10_Case'Access);
      Test_Support.Add (Suite, "math: compat atan2", Atan2_Case'Access);
   end Register;
end Lua.Mathematics_Tests;
