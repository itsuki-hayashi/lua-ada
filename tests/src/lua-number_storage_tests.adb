with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Lua.Number_Parsing;
with Lua.Numbers;
with Lua.Sessions;
with Lua.Storage; use Lua.Storage;
with Test_Support;

package body Lua.Number_Storage_Tests is
   use type Interfaces.Unsigned_64;
   use type Lua.Numbers.Number_Kind;
   use type Lua.Numbers.Integer_Value;
   use type Byte_Count;
   use type Lua.Sessions.Execution_Status;
   function Bits is new Ada.Unchecked_Conversion
     (Lua.Numbers.Real_Value, Interfaces.Unsigned_64);

   procedure Shifted_Source;
   procedure Integer_Conversion_Uses_No_Limbs;
   procedure Midpoint_Rounding;
   procedure Subnormal_Rounding;
   procedure Dropped_Digit_Sticky_Bit;
   procedure Balanced_Long_Hex_Exponent;
   procedure Extreme_Classification_Without_Growth;
   procedure Allocator_Refusal_And_Recovery;
   procedure Bounded_String_Work_And_Recovery;

   procedure Check_Real
     (Memory : in out Owner; Source : String;
      Expected : Interfaces.Unsigned_64);
   procedure Check_Real
     (Memory : in out Owner; Source : String;
      Expected : Interfaces.Unsigned_64)
   is
      Value : constant Lua.Numbers.Number :=
        Lua.Number_Parsing.Read (Source, Reference (Memory));
   begin
      Assert (Value.Kind = Lua.Numbers.Real_Number and then
              Bits (Value.Real_Item) = Expected,
              "exact owned conversion bits for " & Source);
      Assert (Statistics (Memory).Live_Blocks = 0,
              "numeric conversion retained temporary limbs");
   end Check_Real;

   procedure Shifted_Source is
      Memory : Owner;
      Source : constant String (Integer'Last - 3 .. Integer'Last) := "1.25";
   begin
      --  Borrow bytes with an extreme Ada lower bound. Normalizing only the
      --  descriptor must preserve numeric semantics and avoid index overflow.
      Check_Real (Memory, Source, 16#3FF4_0000_0000_0000#);
   end Shifted_Source;

   procedure Integer_Conversion_Uses_No_Limbs is
      Memory : Owner;
      Value : Lua.Numbers.Number;
   begin
      --  Native-width integer parsing needs no exact-rational scratch. It
      --  remains usable while growth is refused, including explicit-base wrap.
      Set_Failure_Countdown (Memory, 0);
      Value := Lua.Number_Parsing.Read
        ("0xffffffffffffffff", Reference (Memory));
      Assert (Value.Kind = Lua.Numbers.Integer_Number and then
              Value.Integer_Item = -1, "hex integer wrapped at 64 bits");
      Value := Lua.Number_Parsing.Read ("FF", Reference (Memory), 16);
      Assert (Value.Kind = Lua.Numbers.Integer_Number and then
              Value.Integer_Item = 255, "explicit base stayed integer");
      Assert (Statistics (Memory).Growth_Attempts = 0 and
              not Refusal_Pending (Memory), "integer parsing used no growth");
   end Integer_Conversion_Uses_No_Limbs;

   procedure Midpoint_Rounding is
      Memory : Owner;
   begin
      --  Adjacent hexadecimal halfway cases distinguish even and odd lower
      --  significands. The largest finite midpoint also tests exponent carry.
      Check_Real (Memory, "0x1.00000000000008p0", 16#3FF0_0000_0000_0000#);
      Check_Real (Memory, "0x1.00000000000018p0", 16#3FF0_0000_0000_0002#);
      Check_Real (Memory, "0x1.fffffffffffff8p1023",
                  16#7FF0_0000_0000_0000#);
   end Midpoint_Rounding;

   procedure Subnormal_Rounding is
      Memory : Owner;
   begin
      --  Exactly half the least subnormal rounds to even zero. One retained
      --  nonzero hexadecimal tail rounds upward; a negative exact zero keeps
      --  its sign independently of the unsigned significand calculation.
      Check_Real (Memory, "0x1p-1075", 0);
      Check_Real (Memory, "0x1.0000000000001p-1075", 1);
      Check_Real (Memory, "-0x1p-1075", 16#8000_0000_0000_0000#);
      Check_Real (Memory, "0x1p-1074", 1);
   end Subnormal_Rounding;

   procedure Dropped_Digit_Sticky_Bit is
      Memory : Owner;
      Midpoint : constant String :=
        "1.00000000000000011102230246251565404236316680908203125";
      Zeros : constant String (1 .. 1_100) := [others => '0'];
   begin
      --  The significant-prefix bound must not discard a decisive nonzero
      --  beyond its 1100th digit. Trailing zeros preserve the exact tie;
      --  appending one changes the correctly rounded least significant bit.
      Check_Real (Memory, Midpoint & Zeros, 16#3FF0_0000_0000_0000#);
      Check_Real (Memory, Midpoint & Zeros & "1", 16#3FF0_0000_0000_0001#);
   end Dropped_Digit_Sticky_Bit;

   procedure Balanced_Long_Hex_Exponent is
      Memory : Owner;
      Source : constant String := "0x1" &
        String'(1 .. 250_000 => '0') & "p-1000000";
   begin
      --  A fixed small exponent cap breaks cancellation against a long but
      --  valid mantissa. This 250012-byte numeral is exactly one and remains
      --  inside the ordinary frontend source limit. Scratch must depend on
      --  retained precision, not on all quarter-million source digits.
      Set_Ceiling (Memory, 65_536);
      Check_Real (Memory, Source, 16#3FF0_0000_0000_0000#);
      Assert (Statistics (Memory).Peak_Raw_Bytes <= 65_536,
              "long balanced numeral used bounded managed precision");
   end Balanced_Long_Hex_Exponent;

   procedure Extreme_Classification_Without_Growth is
      Memory : Owner;
   begin
      --  Obvious zero/overflow/underflow needs no rational allocation. Check
      --  before building limbs, even under a permanently refusing provider.
      Set_Failure_Countdown (Memory, 0);
      Check_Real (Memory, "0e999999999999999999999", 0);
      Check_Real (Memory, "1e999999999999999999999",
                  16#7FF0_0000_0000_0000#);
      Check_Real (Memory, "-1e-999999999999999999999",
                  16#8000_0000_0000_0000#);
      Assert (Statistics (Memory).Growth_Attempts = 0 and
              not Refusal_Pending (Memory), "extreme parsing used no growth");
   end Extreme_Classification_Without_Growth;

   procedure Allocator_Refusal_And_Recovery is
      Memory : Owner;
      Failed : Boolean := False;
   begin
      --  A normal finite conversion needs exact scratch. Its refusal must
      --  escape as managed memory failure, release partial limbs, and leave
      --  the owner reusable after the caller lifts that allocator policy.
      Set_Failure_Countdown (Memory, 0);
      begin
         declare
            Value : constant Lua.Numbers.Number :=
              Lua.Number_Parsing.Read ("1.25", Reference (Memory));
         begin
            Assert (Value.Kind = Lua.Numbers.Real_Number,
                    "unexpected finite conversion result");
         end;
      exception
         when Allocation_Error | Program_Error => Failed := True;
      end;
      Assert (Failed and Refusal_Pending (Memory),
              "owned numeric parser preserved refusal classification");
      Assert (Statistics (Memory).Live_Blocks = 0,
              "refused conversion released partial limb storage");
      Clear_Failures (Memory);
      Acknowledge_Refusal (Memory);
      Check_Real (Memory, "1.25", 16#3FF4_0000_0000_0000#);
   end Allocator_Refusal_And_Recovery;

   procedure Bounded_String_Work_And_Recovery is
      Universe : Lua.Sessions.Session;
      Bounds : Lua.Sessions.Execution_Limits;
      Result : Lua.Sessions.Execution_Result;
   begin
      --  Many long conversions must not hide linear scans behind a handful
      --  of VM calls. Protection cannot catch/restart a host quota; the next
      --  public execution receives a fresh budget and keeps a usable session.
      Bounds.Instructions := 10_000;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute
        ("local text=string.rep('0',300)..'1.25'; " &
         "pcall(function() for i=1,100 do tonumber(text) end end)");
      Assert (Result.Status = Lua.Sessions.Resource_Error,
              "numeric source scans charged the existing bounded budget");
      Result := Universe.Execute ("assert(tonumber('1.25')==1.25)");
      Assert (Result.Status = Lua.Sessions.Succeeded,
              "numeric work exhaustion allowed subsequent execution");
   end Bounded_String_Work_And_Recovery;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "owned numbers: shifted source bounds",
                        Shifted_Source'Access);
      Test_Support.Add (Suite, "owned numbers: allocation-free integers",
                        Integer_Conversion_Uses_No_Limbs'Access);
      Test_Support.Add (Suite, "owned numbers: midpoint rounding",
                        Midpoint_Rounding'Access);
      Test_Support.Add (Suite, "owned numbers: subnormal rounding",
                        Subnormal_Rounding'Access);
      Test_Support.Add (Suite, "owned numbers: dropped-digit sticky bit",
                        Dropped_Digit_Sticky_Bit'Access);
      Test_Support.Add (Suite, "owned numbers: balanced long exponent",
                        Balanced_Long_Hex_Exponent'Access);
      Test_Support.Add (Suite, "owned numbers: allocation-free extremes",
                        Extreme_Classification_Without_Growth'Access);
      Test_Support.Add (Suite, "owned numbers: allocator refusal recovery",
                        Allocator_Refusal_And_Recovery'Access);
      Test_Support.Add (Suite, "owned numbers: bounded scan work recovery",
                        Bounded_String_Work_And_Recovery'Access);
   end Register;
end Lua.Number_Storage_Tests;
