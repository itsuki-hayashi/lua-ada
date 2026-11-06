with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Formats;
with Lua.Storage;
with Lua.Storage.Buffers;
with Test_Support;

package body Lua.Managed_Format_Tests is
   package Managed renames Lua.Storage.Buffers;
   use type Lua.Storage.Byte_Count;
   use type Real_Value;
   function Real_From is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, Real_Value);

   generic
      with procedure Action (State : in out World);
   procedure Fixture;

   procedure Fixture is
      State : World;
   begin
      Initialize (State, (others => <>));
      begin
         Action (State);
      exception
         when others => Finalize (State); raise;
      end;
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "formatted scratch survived world finalization");
   end Fixture;

   procedure Expect
     (State : in out World; Specification : String;
      Number : Real_Value; Expected : String);
   procedure Expect
     (State : in out World; Specification : String;
      Number : Real_Value; Expected : String)
   is
      Output : Managed.Buffer;
   begin
      Formats.Render_Into (State, Specification, (Real_Kind, Number), Output);
      Assert (Output.To_String = Expected,
              "unexpected bytes for " & Specification);
   end Expect;

   procedure Nearest_Even (State : in out World);
   procedure Decimal_Carry (State : in out World);
   procedure General_Threshold (State : in out World);
   procedure Alternate_Zeroes (State : in out World);
   procedure Smallest_Subnormal (State : in out World);
   procedure Maximum_Magnitude (State : in out World);
   procedure Negative_Zero (State : in out World);
   procedure Wide_Fixed_Precision (State : in out World);
   procedure Hexadecimal_Trailing_Zeroes (State : in out World);
   procedure Numeric_String (State : in out World);
   procedure Invalid_Numeric_String (State : in out World);
   procedure Managed_Output (State : in out World);
   procedure Scratch_Balance (State : in out World);
   procedure First_Growth_Refusal (State : in out World);
   procedure Partial_Growth_Refusal (State : in out World);
   procedure Recovery_After_Refusal (State : in out World);

   procedure Nearest_Even (State : in out World) is
   begin
      --  Exact binary halves straddle odd/even decimal integers. Neither the
      --  host rounding mode nor the limb migration may round every tie up.
      Expect (State, "%.0f", 2.5, "2");
      Expect (State, "%.0f", 3.5, "4");
      Expect (State, "%.0f", -2.5, "-2");
   end Nearest_Even;

   procedure Decimal_Carry (State : in out World) is
   begin
      --  Carry crosses the exponent boundary after exact rational rounding.
      --  The retained view omits only the extra zero, preserving precision.
      Expect (State, "%.2e", 9.999, "1.00e+01");
      Expect (State, "%#.3g", 9.999, "10.0");
   end Decimal_Carry;

   procedure General_Threshold (State : in out World) is
   begin
      --  General formatting chooses notation using the rounded exponent,
      --  including the boundary at -4 and the significant-digit threshold.
      Expect (State, "%.4g", 0.0001, "0.0001");
      Expect (State, "%.4g", 0.00001, "1e-05");
      Expect (State, "%.3g", 999.9, "1e+03");
   end General_Threshold;

   procedure Alternate_Zeroes (State : in out World) is
   begin
      --  Alternate form retains the point/significant zeroes; ordinary g
      --  strips only its virtual digit view rather than changing the source.
      Expect (State, "%#.4g", 12.0, "12.00");
      Expect (State, "%.4g", 12.0, "12");
      Expect (State, "%#.0f", 12.0, "12.");
   end Alternate_Zeroes;

   procedure Smallest_Subnormal (State : in out World) is
   begin
      --  The minimum positive binary64 requires the full 2**1074 denominator.
      --  Decimal formatting must preserve its exact nearest representation.
      Expect (State, "%.17g", Real_From (1), "4.9406564584124654e-324");
   end Smallest_Subnormal;

   procedure Maximum_Magnitude (State : in out World) is
   begin
      --  The opposite exponent boundary exercises a large owned numerator
      --  without constructing an unmanaged decimal big-integer snapshot.
      Expect (State, "%.17g", Real_From (16#7FEF_FFFF_FFFF_FFFF#),
              "1.7976931348623157e+308");
   end Maximum_Magnitude;

   procedure Negative_Zero (State : in out World) is
   begin
      --  Exact magnitude is zero, while the caller's original sign bit must
      --  still supply the minus prefix in every decimal notation.
      Expect (State, "%.2f", Real_From (16#8000_0000_0000_0000#), "-0.00");
      Expect (State, "%g", Real_From (16#8000_0000_0000_0000#), "-0");
   end Negative_Zero;

   procedure Wide_Fixed_Precision (State : in out World) is
      Output : Managed.Buffer;
   begin
      --  Precision 99 used to build a string by repeatedly prepending zeroes.
      --  Check every byte of the direct managed assembly, including its point.
      Formats.Render_Into (State, "%.99f", (Real_Kind, 0.5), Output);
      Assert (Output.Length = 101 and then Output.Element (1) = '0' and then
              Output.Element (2) = '.' and then Output.Element (3) = '5',
              "wide fixed prefix or length");
      for Index in 4 .. Output.Length loop
         Assert (Output.Element (Index) = '0', "wide fixed trailing digit");
      end loop;
   end Wide_Fixed_Precision;

   procedure Hexadecimal_Trailing_Zeroes (State : in out World) is
      Output : Managed.Buffer;
   begin
      --  Inject the Linux spelling policy so every host can exercise a long
      --  hexadecimal precision, independent of Windows C89 modifier limits.
      Formats.Render_Into
        (State, "%.20a", (Real_Kind, 1.0), Output, Host => "linux");
      Assert (Output.To_String = "0x1.00000000000000000000p+0",
              "hexadecimal managed padding");
   end Hexadecimal_Trailing_Zeroes;

   procedure Numeric_String (State : in out World) is
      Text : constant Value := New_String (State, "  0x1.8p+2  ");
      Output : Managed.Buffer;
   begin
      --  A numeric string uses the world-owned parser directly over its byte
      --  payload; integers/reals follow separate exact paths without parsing.
      Formats.Render_Into (State, "%.2f", Text, Output);
      Assert (Output.To_String = "6.00", "borrowed numeric-string conversion");
   end Numeric_String;

   procedure Invalid_Numeric_String (State : in out World) is
      Text : constant Value := New_String (State, "1.5x");
      Output : Managed.Buffer;
      Rejected : Boolean := False;
   begin
      --  Trailing source bytes must not become an accepted numeric prefix.
      --  Failure remains a language error rather than a host parse exception.
      begin
         Formats.Render_Into (State, "%g", Text, Output);
      exception
         when Language_Error => Rejected := True;
      end;
      Assert (Rejected, "malformed numeric string was formatted");
   end Invalid_Numeric_String;

   procedure Managed_Output (State : in out World) is
      Output : Managed.Buffer;
   begin
      --  Inspect the actual returned payload rather than an accounting-only
      --  estimate: the caller's owner must own every byte retained by output.
      Formats.Render_Into (State, "%.99g", (Real_Kind, 0.1), Output);
      Assert (Lua.Storage.Owns (State.Memory, Output.Address),
              "formatted result bypassed the owner");
   end Managed_Output;

   procedure Scratch_Balance (State : in out World) is
      Before : constant Lua.Storage.Allocation_Statistics :=
        Lua.Storage.Statistics (State.Memory);
   begin
      --  Successful rendering destroys all exact numerator/divisor/digit
      --  scratch at scope exit. The retained world itself is unchanged.
      declare
         Output : Managed.Buffer;
      begin
         Formats.Render_Into
           (State, "%.99g", (Real_Kind, Real_From (1)), Output);
         Assert (Lua.Storage.Statistics (State.Memory).Growth_Attempts >
                   Before.Growth_Attempts, "format scratch did not allocate");
      end;
      Assert (Lua.Storage.Statistics (State.Memory).Raw_Bytes =
                Before.Raw_Bytes, "successful rational scratch leaked");
   end Scratch_Balance;

   procedure Refuse
     (State : in out World; Successful_Growths : Lua.Storage.Byte_Count);
   procedure Refuse
     (State : in out World; Successful_Growths : Lua.Storage.Byte_Count)
   is
      Before : constant Lua.Storage.Allocation_Statistics :=
        Lua.Storage.Statistics (State.Memory);
      Rejected : Boolean := False;
   begin
      Lua.Storage.Set_Failure_Countdown (State.Memory, Successful_Growths);
      begin
         declare
            Output : Managed.Buffer;
         begin
            Formats.Render_Into
              (State, "%.99g", (Real_Kind, Real_From (1)), Output);
         end;
      exception
         when Lua.Storage.Allocation_Error => Rejected := True;
         when Program_Error =>
            --  Ada may wrap controlled Adjust failure. Only the provider's
            --  real refusal witness justifies classifying that as memory.
            Rejected := Lua.Storage.Refusal_Pending (State.Memory);
            if not Rejected then
               raise;
            end if;
      end;
      Lua.Storage.Clear_Failures (State.Memory);
      Lua.Storage.Acknowledge_Refusal (State.Memory);
      Assert (Rejected, "allocator-refused formatting unexpectedly succeeded");
      Assert (Lua.Storage.Statistics (State.Memory).Raw_Bytes =
                Before.Raw_Bytes,
              "partially constructed format scratch leaked");
   end Refuse;

   procedure First_Growth_Refusal (State : in out World) is
   begin
      --  Refuse the initial exact-value limb growth. No output or scratch may
      --  survive the failed declaration initializer or controlled unwinding.
      Refuse (State, 0);
   end First_Growth_Refusal;

   procedure Partial_Growth_Refusal (State : in out World) is
      Before : constant Lua.Storage.Byte_Count :=
        Lua.Storage.Statistics (State.Memory).Growth_Attempts;
      Growths : Lua.Storage.Byte_Count;
   begin
      --  Measure a complete operation, then refuse midway through its actual
      --  growth sequence. This protects ownership after several copied limbs,
      --  rather than only the trivial first-allocation failure path.
      declare
         Output : Managed.Buffer;
      begin
         Formats.Render_Into
           (State, "%.99g", (Real_Kind, Real_From (1)), Output);
      end;
      Growths :=
        Lua.Storage.Statistics (State.Memory).Growth_Attempts - Before;
      Assert (Growths >= 4, "rational setup did not exercise partial growth");
      Refuse (State, Growths / 2);
   end Partial_Growth_Refusal;

   procedure Recovery_After_Refusal (State : in out World) is
   begin
      --  A direct owner refusal leaves no hidden default-owner state. Restore
      --  growth and immediately render a new value in the same world.
      Refuse (State, 0);
      Expect (State, "%.2f", 12.5, "12.50");
   end Recovery_After_Refusal;

   procedure Even_Case is new Fixture (Nearest_Even);
   procedure Carry_Case is new Fixture (Decimal_Carry);
   procedure Threshold_Case is new Fixture (General_Threshold);
   procedure Alternate_Case is new Fixture (Alternate_Zeroes);
   procedure Subnormal_Case is new Fixture (Smallest_Subnormal);
   procedure Maximum_Case is new Fixture (Maximum_Magnitude);
   procedure Sign_Case is new Fixture (Negative_Zero);
   procedure Precision_Case is new Fixture (Wide_Fixed_Precision);
   procedure Hex_Case is new Fixture (Hexadecimal_Trailing_Zeroes);
   procedure String_Case is new Fixture (Numeric_String);
   procedure Invalid_Case is new Fixture (Invalid_Numeric_String);
   procedure Owner_Case is new Fixture (Managed_Output);
   procedure Balance_Case is new Fixture (Scratch_Balance);
   procedure First_Case is new Fixture (First_Growth_Refusal);
   procedure Partial_Case is new Fixture (Partial_Growth_Refusal);
   procedure Recovery_Case is new Fixture (Recovery_After_Refusal);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "managed format: nearest-even ties",
                        Even_Case'Access);
      Test_Support.Add (Suite, "managed format: decimal carry",
                        Carry_Case'Access);
      Test_Support.Add (Suite, "managed format: general threshold",
                        Threshold_Case'Access);
      Test_Support.Add (Suite, "managed format: alternate zeroes",
                        Alternate_Case'Access);
      Test_Support.Add (Suite, "managed format: minimum subnormal",
                        Subnormal_Case'Access);
      Test_Support.Add (Suite, "managed format: maximum magnitude",
                        Maximum_Case'Access);
      Test_Support.Add (Suite, "managed format: signed zero",
                        Sign_Case'Access);
      Test_Support.Add (Suite, "managed format: wide fixed precision",
                        Precision_Case'Access);
      Test_Support.Add (Suite, "managed format: hexadecimal padding",
                        Hex_Case'Access);
      Test_Support.Add (Suite, "managed format: numeric string",
                        String_Case'Access);
      Test_Support.Add (Suite, "managed format: malformed numeric string",
                        Invalid_Case'Access);
      Test_Support.Add (Suite, "managed format: actual output owner",
                        Owner_Case'Access);
      Test_Support.Add (Suite, "managed format: scratch balance",
                        Balance_Case'Access);
      Test_Support.Add (Suite, "managed format: first growth refusal",
                        First_Case'Access);
      Test_Support.Add (Suite, "managed format: partial growth refusal",
                        Partial_Case'Access);
      Test_Support.Add (Suite, "managed format: refusal recovery",
                        Recovery_Case'Access);
   end Register;
end Lua.Managed_Format_Tests;
