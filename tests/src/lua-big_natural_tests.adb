with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Lua.Big_Naturals;
with Lua.Storage; use Lua.Storage;
with Lua.Storage.Buffers;
with Test_Support;

package body Lua.Big_Natural_Tests is
   package Big renames Lua.Big_Naturals;
   use type Big.Wide;
   use type Big.Ordering;
   use type Byte_Count;

   procedure Explicit_Owner;
   procedure Unsigned_Boundaries;
   procedure Carry_And_Borrow;
   procedure Small_Product_Boundary;
   procedure Word_And_Bit_Shifts;
   procedure Block_Powers;
   procedure Wide_Division_Campaign;
   procedure Large_Exact_Division;
   procedure Division_Input_Aliasing;
   procedure Division_Refusal_Is_Atomic;
   procedure Invalid_Arithmetic;
   procedure Decimal_Output;
   procedure Growth_Refusal_Preserves;
   procedure Copy_Owner_And_Lifetime;

   procedure Explicit_Owner is
      Value : Big.Number;
      Rejected : Boolean := False;
   begin
      --  Zero can be inspected without storage, but constructing a nonzero
      --  value cannot invent a standard/global allocator behind the caller.
      Assert (Big.Is_Zero (Value) and Big.Bit_Length (Value) = 0,
              "default exact natural is zero");
      begin
         Big.Set_Value (Value, 1);
      exception
         when Program_Error => Rejected := True;
      end;
      Assert (Rejected and Big.Is_Zero (Value),
              "nonzero construction requires explicit owner");
   end Explicit_Owner;

   procedure Unsigned_Boundaries is
      Memory : Owner;
      Value : Big.Number;
      type Cases is array (Positive range <>) of Big.Wide;
      Inputs : constant Cases :=
        [0, 1, 2 ** 32 - 1, 2 ** 32, 2 ** 63, Big.Wide'Last];
   begin
      --  Exercise empty, one-limb and two-limb representations through the
      --  external unsigned interface, including its highest representable bit.
      Big.Set_Owner (Value, Reference (Memory));
      for Input of Inputs loop
         Big.Set_Value (Value, Input);
         Assert (Big.To_Unsigned (Value) = Input,
                 "unsigned exact natural round trip");
         Assert (Big.Is_Odd (Value) = (Input mod 2 /= 0),
                 "unsigned low-bit classification");
      end loop;
      Assert (Big.Bit_Length (Value) = 64, "highest unsigned bit length");
   end Unsigned_Boundaries;

   procedure Carry_And_Borrow is
      Memory : Owner;
      Value : Big.Number := Big.From_Unsigned
        (Reference (Memory), Big.Wide'Last);
      One : constant Big.Number := Big.From_Unsigned (Reference (Memory), 1);
   begin
      --  Carry through two full limbs into a third, then borrow back across
      --  both zeros. Normalization must remove the newly empty highest limb.
      Big.Add (Value, 1);
      Assert (Big.Bit_Length (Value) = 65 and not Big.Is_Odd (Value),
              "carry propagated across full limbs");
      Big.Subtract (Value, One);
      Assert (Big.To_Unsigned (Value) = Big.Wide'Last,
              "borrow restored full unsigned value");
      Big.Subtract (Value, Value);
      Assert (Big.Is_Zero (Value), "self subtraction normalized zero");
   end Carry_And_Borrow;

   procedure Small_Product_Boundary is
      Memory : Owner;
      Value : Big.Number := Big.From_Unsigned
        (Reference (Memory), Big.Wide (Big.Small'Last));
   begin
      --  The largest limb product checks the full 64-bit intermediate. This
      --  cannot be approximated by floating arithmetic without losing bits.
      Big.Multiply (Value, Big.Small'Last);
      Assert (Big.To_Unsigned (Value) =
                Big.Wide (Big.Small'Last) * Big.Wide (Big.Small'Last),
              "maximal small-factor product");
      Big.Multiply (Value, 0);
      Assert (Big.Is_Zero (Value), "zero factor normalized all limbs");
   end Small_Product_Boundary;

   procedure Word_And_Bit_Shifts is
      Memory : Owner;
      Original : constant Big.Number := Big.From_Unsigned
        (Reference (Memory), 16#FEDC_BA98_7654_3210#);
   begin
      --  Cover both whole-word moves and cross-word carries. Right shifting
      --  the inserted zero suffix must recover the original exact magnitude.
      for Shift in 0 .. 129 loop
         declare
            Value : Big.Number := Original;
         begin
            Big.Shift_Left (Value, Shift);
            Assert (Big.Bit_Length (Value) = 64 + Shift,
                    "left shift exact bit length");
            Big.Shift_Right (Value, Shift);
            Assert (Big.Compare (Value, Original) = Big.Equal_To,
                    "cross-word shift round trip");
            Big.Shift_Right (Value, 64);
            Assert (Big.Is_Zero (Value), "complete right shift cleared value");
         end;
      end loop;
   end Word_And_Bit_Shifts;

   procedure Block_Powers is
      Memory : Owner;
      Value : Big.Number := Big.From_Unsigned (Reference (Memory), 1);
   begin
      --  Powers use multi-digit factors while preserving the final partial
      --  block. The expected result is independent native unsigned arithmetic.
      Big.Multiply_Power (Value, 10, 19);
      Assert (Big.To_Unsigned (Value) = 10 ** 19,
              "decimal block power included partial block");
      Big.Set_Value (Value, 1);
      Big.Multiply_Power (Value, 2, 63);
      Assert (Big.To_Unsigned (Value) = 2 ** 63,
              "binary power used exact shift");
   end Block_Powers;

   procedure Wide_Division_Campaign is
      Memory : Owner;
      Seed : Big.Wide := 16#551_2026#;
   begin
      --  A fixed seed compares 4096 exact divisions with the native 64-bit
      --  quotient/remainder operators. Zero numerators and odd divisors cover
      --  normalization and short/long quotient paths without assumed output.
      for Trial in 1 .. 4_096 loop
         Seed := Seed * 6_364_136_223_846_793_005 + 1;
         declare
            N : constant Big.Wide := (if Trial mod 17 = 0 then 0 else Seed);
            D : constant Big.Wide :=
              Interfaces.Shift_Right (Seed xor 16#FEDC_BA98_7654_3210#, 11)
                or 1;
            Numerator : constant Big.Number :=
              Big.From_Unsigned (Reference (Memory), N);
            Denominator : constant Big.Number :=
              Big.From_Unsigned (Reference (Memory), D);
            Quotient, Remainder : Big.Number;
         begin
            Big.Divide (Numerator, Denominator, Quotient, Remainder);
            Assert (Big.To_Unsigned (Quotient) = N / D and
                    Big.To_Unsigned (Remainder) = N rem D,
                    "seeded exact quotient and remainder");
         end;
      end loop;
      Assert (Statistics (Memory).Live_Blocks = 0,
              "division campaign released all temporary limbs");
   end Wide_Division_Campaign;

   procedure Large_Exact_Division is
      Memory : Owner;
      Numerator : Big.Number := Big.From_Unsigned (Reference (Memory), 1);
      Denominator : Big.Number := Big.From_Unsigned (Reference (Memory), 1);
      Expected : Big.Number := Big.From_Unsigned (Reference (Memory), 1);
      Three : constant Big.Number :=
        Big.From_Unsigned (Reference (Memory), 3);
      Quotient, Remainder : Big.Number;
   begin
      --  (2^1024+3)*(2^1024-3)=2^2048-9. This independently derived identity
      --  verifies a quotient far beyond machine width and a small remainder.
      Big.Shift_Left (Numerator, 2_048);
      Big.Add (Numerator, 123_456_789);
      Big.Shift_Left (Denominator, 1_024);
      Big.Add (Denominator, 3);
      Big.Shift_Left (Expected, 1_024);
      Big.Subtract (Expected, Three);
      Big.Divide (Numerator, Denominator, Quotient, Remainder);
      Assert (Big.Compare (Quotient, Expected) = Big.Equal_To and
              Big.To_Unsigned (Remainder) = 123_456_798,
              "large exact division identity");
   end Large_Exact_Division;

   procedure Division_Input_Aliasing is
      Memory : Owner;
      Numerator : Big.Number := Big.From_Unsigned (Reference (Memory), 100);
      Denominator : Big.Number := Big.From_Unsigned (Reference (Memory), 7);
   begin
      --  Inputs may become outputs only after the complete calculation. A
      --  move must not destroy a divisor still needed by the division loop.
      Big.Divide (Numerator, Denominator, Numerator, Denominator);
      Assert (Big.To_Unsigned (Numerator) = 14 and
              Big.To_Unsigned (Denominator) = 2,
              "division published aliased outputs after computation");
   end Division_Input_Aliasing;

   procedure Division_Refusal_Is_Atomic is
      Memory : Owner;
      Numerator : constant Big.Number :=
        Big.From_Unsigned (Reference (Memory), 100);
      Denominator : constant Big.Number :=
        Big.From_Unsigned (Reference (Memory), 7);
      Quotient : Big.Number := Big.From_Unsigned (Reference (Memory), 19);
      Remainder : Big.Number := Big.From_Unsigned (Reference (Memory), 23);
      Failed : Boolean := False;
   begin
      --  Both output values already exist. Refuse intermediate storage and
      --  require neither output nor either input to be partially published.
      Set_Failure_Countdown (Memory, 0);
      begin
         Big.Divide (Numerator, Denominator, Quotient, Remainder);
      exception
         when Allocation_Error | Program_Error => Failed := True;
      end;
      Assert (Failed and Refusal_Pending (Memory), "division refusal witness");
      Assert (Big.To_Unsigned (Quotient) = 19 and
              Big.To_Unsigned (Remainder) = 23 and
              Big.To_Unsigned (Numerator) = 100,
              "refused division preserved inputs and both outputs");
      Assert (Statistics (Memory).Live_Blocks = 4,
              "refused division leaked no partial scratch");
   end Division_Refusal_Is_Atomic;

   procedure Invalid_Arithmetic is
      Memory : Owner;
      Zero : constant Big.Number := Big.From_Unsigned (Reference (Memory), 0);
      Value : Big.Number := Big.From_Unsigned (Reference (Memory), 1);
      Quotient, Remainder : Big.Number;
      Rejections : Natural := 0;
   begin
      --  Invalid private operations must fail before publishing output. This
      --  protects representation checks from becoming corrupt limb arithmetic.
      begin
         Big.Divide (Value, Zero, Quotient, Remainder);
      exception
         when Constraint_Error => Rejections := Rejections + 1;
      end;
      begin
         Big.Subtract (Quotient, Value);
      exception
         when Constraint_Error => Rejections := Rejections + 1;
      end;
      Big.Shift_Left (Value, 64);
      begin
         declare
            Too_Wide : constant Big.Wide := Big.To_Unsigned (Value);
         begin
            Assert (Too_Wide = 0, "unexpected wide conversion");
         end;
      exception
         when Constraint_Error => Rejections := Rejections + 1;
      end;
      Assert (Rejections = 3, "invalid exact operations rejected");
   end Invalid_Arithmetic;

   procedure Decimal_Output is
      Memory : Owner;
      Value : Big.Number := Big.From_Unsigned (Reference (Memory), 1);
      Output : Buffers.Buffer;
   begin
      --  Produce a decimal well beyond binary64 formatting size, with zeros
      --  crossing every nine-digit output block and a nonzero final digit.
      Big.Multiply_Power (Value, 10, 1_100);
      Big.Add (Value, 1);
      Big.Decimal (Value, Output);
      Assert (Big.Decimal_Digits (Value) = 1_101 and Output.Length = 1_101,
              "large exact decimal digit count");
      Assert (Output.Element (1) = '1' and Output.Element (1_101) = '1',
              "large decimal boundary digits");
      for Index in 2 .. 1_100 loop
         Assert (Output.Element (Index) = '0', "decimal block zero padding");
      end loop;
      Assert (Output.Owner_Of = Reference (Memory), "decimal output owner");
   end Decimal_Output;

   procedure Growth_Refusal_Preserves is
      Memory : Owner;
      Value : Big.Number := Big.From_Unsigned
        (Reference (Memory), Big.Wide'Last);
      Failed : Boolean := False;
   begin
      --  Force a larger buffer than its initial capacity. A refused shift
      --  must leave the original exact value intact and usable for recovery.
      Set_Failure_Countdown (Memory, 0);
      begin
         Big.Shift_Left (Value, 128);
      exception
         when Allocation_Error => Failed := True;
      end;
      Assert (Failed and Big.To_Unsigned (Value) = Big.Wide'Last,
              "refused shift preserved exact value");
      Clear_Failures (Memory);
      Acknowledge_Refusal (Memory);
      Big.Add (Value, 1);
      Assert (Big.Bit_Length (Value) = 65, "exact value recovered after OOM");
   end Growth_Refusal_Preserves;

   procedure Copy_Owner_And_Lifetime is
      Memory : Owner;
      Value : Big.Number := Big.From_Unsigned (Reference (Memory), 17);
   begin
      --  Controlled component copying inherits the provider and independent
      --  limb storage. Finalizing a copy cannot consume the source's buffer.
      declare
         Duplicate : Big.Number := Value;
      begin
         Big.Add (Duplicate, 1);
         Assert (Big.Owner_Of (Duplicate) = Reference (Memory) and
                 Big.To_Unsigned (Duplicate) = 18 and
                 Big.To_Unsigned (Value) = 17,
                 "exact copy retained owner and independent limbs");
      end;
      Assert (Statistics (Memory).Live_Blocks = 1,
              "exact copy finalized independently");
      Big.Set_Value (Value, 0);
      Assert (Big.Is_Zero (Value), "source remained mutable after copy");
   end Copy_Owner_And_Lifetime;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "exact limbs: explicit owner",
                        Explicit_Owner'Access);
      Test_Support.Add (Suite, "exact limbs: unsigned boundaries",
                        Unsigned_Boundaries'Access);
      Test_Support.Add (Suite, "exact limbs: carry and borrow",
                        Carry_And_Borrow'Access);
      Test_Support.Add (Suite, "exact limbs: small product boundary",
                        Small_Product_Boundary'Access);
      Test_Support.Add (Suite, "exact limbs: word and bit shifts",
                        Word_And_Bit_Shifts'Access);
      Test_Support.Add (Suite, "exact limbs: block powers",
                        Block_Powers'Access);
      Test_Support.Add (Suite, "exact limbs: seeded 64-bit divisions",
                        Wide_Division_Campaign'Access);
      Test_Support.Add (Suite, "exact limbs: large division identity",
                        Large_Exact_Division'Access);
      Test_Support.Add (Suite, "exact limbs: aliased division outputs",
                        Division_Input_Aliasing'Access);
      Test_Support.Add (Suite, "exact limbs: atomic division refusal",
                        Division_Refusal_Is_Atomic'Access);
      Test_Support.Add (Suite, "exact limbs: invalid operations",
                        Invalid_Arithmetic'Access);
      Test_Support.Add (Suite, "exact limbs: decimal output",
                        Decimal_Output'Access);
      Test_Support.Add (Suite, "exact limbs: shift refusal recovery",
                        Growth_Refusal_Preserves'Access);
      Test_Support.Add (Suite, "exact limbs: copy ownership lifetime",
                        Copy_Owner_And_Lifetime'Access);
   end Register;
end Lua.Big_Natural_Tests;
