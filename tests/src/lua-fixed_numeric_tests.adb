with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Lua.Number_Parsing;
with Lua.Numbers;
with Lua.Storage.Fixed_Arenas;
with System;
with Test_Support;

package body Lua.Fixed_Numeric_Tests is
   use Lua.Numbers;
   use Lua.Storage;
   use type Byte_Count;
   use type Integer_Value;
   use type Real_Value;
   use type Interfaces.Unsigned_64;
   use type System.Address;
   function Bits is new Ada.Unchecked_Conversion
     (Real_Value, Interfaces.Unsigned_64);

   procedure Arena_Refusal_Transaction;
   procedure Arena_Copy_And_Release;
   procedure Decimal_Midpoints;
   procedure Decimal_Maximum_Scratch;
   procedure Hexadecimal_Maximum_Scratch;
   procedure Long_Cancellation;
   procedure Syntax_And_Locale;

   procedure Arena_Refusal_Transaction is
      Arena : Fixed_Arenas.Arena (2_048);
      Memory : Owner;
      First, Live : System.Address;
      Taken : Byte_Count;
      Rejected : Boolean := False;
   begin
      --  Freed regions remain in the fixed arena's cumulative cursor. A
      --  later request cannot borrow them or fall back to a heap provider;
      --  refusal must retain both the old block and the exact cursor.
      Fixed_Arenas.Bind (Arena, Memory);
      First := Allocate (Memory, 512);
      Release (Memory, First);
      Live := Allocate (Memory, 1_024);
      Taken := Fixed_Arenas.Used (Arena);
      begin
         Reallocate (Memory, Live, 1_025);
      exception
         when Allocation_Error => Rejected := True;
      end;
      Assert (Rejected and then Fixed_Arenas.Used (Arena) = Taken and then
              Allocation_Size (Live) = 1_024,
              "fixed cumulative refusal preserves live ownership/cursor");
      Release (Memory, Live);
      Assert (Statistics (Memory).Live_Blocks = 0 and then
              Fixed_Arenas.Used (Arena) = Taken,
              "free retires actual owner block without resetting arena");
   end Arena_Refusal_Transaction;

   procedure Arena_Copy_And_Release is
      Arena : Fixed_Arenas.Arena (8_192);
      Memory : Owner;
      Block : System.Address;
   begin
      Fixed_Arenas.Bind (Arena, Memory);
      Block := Allocate (Memory, 128);
      declare
         Bytes : String (1 .. 128) with Import, Address => Block;
      begin
         Bytes := [others => 'x'];
      end;
      Reallocate (Memory, Block, 512);
      declare
         Bytes : constant String (1 .. 128) with Import, Address => Block;
      begin
         Assert (Bytes = String'(1 .. 128 => 'x'),
                 "copy-on-growth preserves actual provider bytes");
      end;
      Release (Memory, Block);
      Assert (Block = System.Null_Address and then
              Statistics (Memory).Raw_Bytes = 0 and then
              Fixed_Arenas.Used (Arena) > 512,
              "all actual records retire before fixed arena leaves scope");
   end Arena_Copy_And_Release;

   procedure Decimal_Midpoints is
      Half : constant String :=
        "1.00000000000000011102230246251565404236316680908203125";
      Below : constant Number := Number_Parsing.Read_Without_Allocation
        (Half & String'(1 .. 3_000 => '0'));
      Above : constant Number := Number_Parsing.Read_Without_Allocation
        (Half & String'(1 .. 3_000 => '0') & "1");
   begin
      --  A nonzero digit far beyond the retained prefix remains sticky.
      --  The exact midpoint rounds to even; that final remote digit selects
      --  the next binary64 value without increasing fixed scratch capacity.
      Assert (Below.Kind = Real_Number and then
              Bits (Below.Real_Item) = 16#3FF0_0000_0000_0000#,
              "arbitrarily long exact decimal tie rounds to even");
      Assert (Above.Kind = Real_Number and then
              Bits (Above.Real_Item) = 16#3FF0_0000_0000_0001#,
              "remote nonzero tail changes the existing exact rounding");
   end Decimal_Midpoints;

   procedure Decimal_Maximum_Scratch is
      Arena : Fixed_Arenas.Arena;
      Memory : Owner;
      Parsed : Number;
   begin
      --  All 1,100 kept significant decimal digits are used. The scale
      --  requires a roughly 4,730-bit denominator and subnormal quotient;
      --  cumulative growth/copies, not merely peak live bytes, fit the arena.
      Fixed_Arenas.Bind (Arena, Memory);
      Parsed := Number_Parsing.Read
        (String'(1 .. 1_100 => '9') & "e-1423", Reference (Memory));
      Assert (Parsed.Kind = Real_Number and then
              Bits (Parsed.Real_Item) = 2,
              "largest retained decimal rational rounds to two subnormals");
      Assert (Statistics (Memory).Live_Blocks = 0 and then
              Fixed_Arenas.Used (Arena) < Fixed_Arenas.Numeric_Scratch_Bytes,
              "all cumulative exact decimal scratch remains fixed");
   end Decimal_Maximum_Scratch;

   procedure Hexadecimal_Maximum_Scratch is
      Arena : Fixed_Arenas.Arena;
      Memory : Owner;
      Parsed : Number;
   begin
      --  1,100 hexadecimal digits dominate the decimal limb bound: the
      --  denominator reaches 5,474 bits before subnormal rounding. A point
      --  prevents the deliberately wrapping arbitrary-length integer path.
      Fixed_Arenas.Bind (Arena, Memory);
      Parsed := Number_Parsing.Read
        ("0x" & String'(1 .. 1_100 => 'f') & ".0p-5473",
         Reference (Memory));
      Assert (Parsed.Kind = Real_Number and then
              Bits (Parsed.Real_Item) = 2,
              "largest retained hexadecimal rational exact rounding");
      Assert (Statistics (Memory).Live_Blocks = 0 and then
              Fixed_Arenas.Used (Arena) < Fixed_Arenas.Numeric_Scratch_Bytes,
              "all cumulative hexadecimal scratch remains fixed");
   end Hexadecimal_Maximum_Scratch;

   procedure Long_Cancellation is
      Decimal : constant Number := Number_Parsing.Read_Without_Allocation
        ("1" & String'(1 .. 10_000 => '0') & ".0e-10000");
      Hex : constant Number := Number_Parsing.Read_Without_Allocation
        ("0x1" & String'(1 .. 10_000 => '0') & ".0p-40000");
   begin
      --  Input length and exponent cancellation grow far beyond the arena.
      --  Both grammar scans retain the original scalar result and bounded
      --  1,100-digit/sticky arithmetic rather than allocating input scratch.
      Assert (Decimal.Kind = Real_Number and then Decimal.Real_Item = 1.0,
              "long decimal exponent/mantissa cancellation");
      Assert (Hex.Kind = Real_Number and then Hex.Real_Item = 1.0,
              "long hexadecimal exponent/mantissa cancellation");
   end Long_Cancellation;

   procedure Syntax_And_Locale is
      Hex : constant Number := Number_Parsing.Read_Without_Allocation
        (" -0xffffffffffffffff ");
      Locale : constant Number := Number_Parsing.Read_Without_Allocation
        ("1,25", Decimal_Point => ',');
      Mixed : constant Number := Number_Parsing.Read_Without_Allocation
        ("1.2,5", Decimal_Point => ',');
      Zero : constant Number := Number_Parsing.Read_Without_Allocation
        ("-0.0");
   begin
      --  The wrapper invokes the original scanner, including signed modular
      --  hexadecimal integers, alternate locale point and malformed input.
      Assert (Hex.Kind = Integer_Number and then Hex.Integer_Item = 1,
              "same hexadecimal integer distinction and wrapping");
      Assert (Locale.Kind = Real_Number and then Locale.Real_Item = 1.25
              and then
              Mixed.Kind = Invalid, "same alternate-point grammar");
      Assert (Zero.Kind = Real_Number and then
              Bits (Zero.Real_Item) = 16#8000_0000_0000_0000#,
              "same negative floating zero representation");
   end Syntax_And_Locale;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "fixed numeric arena: refusal transaction",
                        Arena_Refusal_Transaction'Access);
      Test_Support.Add (Suite, "fixed numeric arena: copy and actual release",
                        Arena_Copy_And_Release'Access);
      Test_Support.Add (Suite, "fixed numeric parsing: remote midpoint tail",
                        Decimal_Midpoints'Access);
      Test_Support.Add (Suite, "fixed numeric parsing: decimal scratch bound",
                        Decimal_Maximum_Scratch'Access);
      Test_Support.Add (Suite, "fixed numeric parsing: hexadecimal bound",
                        Hexadecimal_Maximum_Scratch'Access);
      Test_Support.Add (Suite, "fixed numeric parsing: long cancellation",
                        Long_Cancellation'Access);
      Test_Support.Add (Suite, "fixed numeric parsing: shared locale grammar",
                        Syntax_And_Locale'Access);
   end Register;
end Lua.Fixed_Numeric_Tests;
