with Ada.Calendar;
with Ada.Strings.Fixed;
with Ada.Unchecked_Conversion;
with Interfaces.C;
with Lua.Platform_Mathematics;
with Lua.Platform_Numerics;
with Lua_Ada_Config;
with System.Storage_Elements;

package body Lua.Engine.Mathematics is
   use type Interfaces.Unsigned_64;
   use type Interfaces.Unsigned_32;
   use type Integer_Value;
   use type Real_Value;
   use type Lua.Numbers.Number_Kind;
   subtype Word is Interfaces.Unsigned_64;
   subtype Half is Interfaces.Unsigned_32;
   subtype C_Real is Interfaces.C.double;
   package Host renames Lua.Platform_Mathematics;

   function To_Word is new Ada.Unchecked_Conversion (Integer_Value, Word);
   function To_Integer is new Ada.Unchecked_Conversion (Word, Integer_Value);
   function Signed_C_Int is new Ada.Unchecked_Conversion
     (Interfaces.C.unsigned, Interfaces.C.int);

   Pi : constant Real_Value := 3.141592653589793238462643383279502884;
   Half_Mask : constant Word := 16#FFFF_FFFF#;

   function C99_Logarithms (Host_Name : String) return Boolean is
     (Host_Name /= "windows");
   --  luaconf enables LUA_USE_C89 with its ordinary Windows configuration.
   --  Keep host selection in a function so both strict source branches remain
   --  meaningful while compiling either native target.

   procedure Charge (State : in out World);
   procedure Charge (State : in out World) is
   begin
      --  Rejection sampling is normally short, but its retries are native
      --  work and cannot bypass a bounded session's shared instruction budget.
      if State.Policy = Bounded then
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         State.Steps := State.Steps + 1;
      end if;
   end Charge;

   type Split_Word is record
      High, Low : Half;
   end record;

   function Split (Item : Word) return Split_Word is
     ((Half (Interfaces.Shift_Right (Item, 32)), Half (Item and Half_Mask)));
   function Join (Item : Split_Word) return Word is
     (Interfaces.Shift_Left (Word (Item.High), 32) or Word (Item.Low));
   function Exclusive (Left, Right : Split_Word) return Split_Word is
     ((Left.High xor Right.High, Left.Low xor Right.Low));
   function Left_Shift (Item : Split_Word; Count : Positive)
                        return Split_Word is
     ((Interfaces.Shift_Left (Item.High, Count) or
       Interfaces.Shift_Right (Item.Low, 32 - Count),
       Interfaces.Shift_Left (Item.Low, Count)));
   --  Callers use only the fixed counts 2, 3 and 17, all smaller than 32.

   function Rotate (Item : Split_Word; Count : Positive)
                    return Split_Word;
   function Rotate (Item : Split_Word; Count : Positive)
                    return Split_Word
   is
      Shift : constant Natural := Count mod 32;
      Source : constant Split_Word :=
        (if Count >= 32 then (Item.Low, Item.High) else Item);
   begin
      --  Both paths perform 32-bit operations. Swapping the halves accounts
      --  for the extra 32 bits of xoshiro's 45-bit state rotation.
      if Shift = 0 then
         return Source;
      end if;
      return
        (Interfaces.Shift_Left (Source.High, Shift) or
         Interfaces.Shift_Right (Source.Low, 32 - Shift),
         Interfaces.Shift_Left (Source.Low, Shift) or
         Interfaces.Shift_Right (Source.High, 32 - Shift));
   end Rotate;

   function Add (Left, Right : Split_Word) return Split_Word;
   function Add (Left, Right : Split_Word) return Split_Word is
      Low : constant Half := Left.Low + Right.Low;
      Carry : constant Half := (if Low < Left.Low then 1 else 0);
   begin
      return (Left.High + Right.High + Carry, Low);
   end Add;

   function Next_Word
     (State : in out World; Charge_Work : Boolean := True) return Word;
   function Next_Word
     (State : in out World; Charge_Work : Boolean := True) return Word
   is
      Result : Word;
   begin
      if Charge_Work then
         Charge (State);
      end if;
      if State.Random_Use_32_Bits then
         declare
            A : constant Split_Word := Split (State.Random_Words (0));
            B : constant Split_Word := Split (State.Random_Words (1));
            C : constant Split_Word :=
              Exclusive (Split (State.Random_Words (2)), A);
            D : constant Split_Word :=
              Exclusive (Split (State.Random_Words (3)), B);
            Times_Five : constant Split_Word := Add (Left_Shift (B, 2), B);
            Rotated : constant Split_Word := Rotate (Times_Five, 7);
         begin
            Result := Join (Add (Left_Shift (Rotated, 3), Rotated));
            State.Random_Words (0) := Join (Exclusive (A, D));
            State.Random_Words (1) := Join (Exclusive (B, C));
            State.Random_Words (2) := Join (Exclusive (C, Left_Shift (B, 17)));
            State.Random_Words (3) := Join (Rotate (D, 45));
         end;
      else
         declare
            A : constant Word := State.Random_Words (0);
            B : constant Word := State.Random_Words (1);
            C : constant Word := State.Random_Words (2) xor A;
            D : constant Word := State.Random_Words (3) xor B;
         begin
            --  The old second word must survive every assignment: it feeds
            --  both the output scrambler and the 17-bit transition term.
            --  Modular types express xoshiro's intentional wraparound.
            Result := Interfaces.Rotate_Left (B * 5, 7) * 9;
            State.Random_Words (0) := A xor D;
            State.Random_Words (1) := B xor C;
            State.Random_Words (2) := C xor Interfaces.Shift_Left (B, 17);
            State.Random_Words (3) := Interfaces.Rotate_Left (D, 45);
         end;
      end if;
      return Result;
   end Next_Word;

   procedure Seed
     (State : in out World; First, Second : Word;
      Charge_Work : Boolean := True);
   procedure Seed
     (State : in out World; First, Second : Word;
      Charge_Work : Boolean := True)
   is
      Discarded : Word;
      pragma Unreferenced (Discarded);
   begin
      State.Random_Seeded := False;
      State.Random_Words := [First, 16#FF#, Second, 0];
      --  Sixteen transitions diffuse both seed words. This exact warmup and
      --  the nonzero second state word are part of pinned Lua reproducibility.
      for Index in 1 .. 16 loop
         Discarded := Next_Word (State, Charge_Work);
      end loop;
      State.Random_Seeded := True;
   end Seed;

   function Entropy (State : World) return Word;
   function Entropy (State : World) return Word is
      Year : Ada.Calendar.Year_Number;
      Month : Ada.Calendar.Month_Number;
      Day : Ada.Calendar.Day_Number;
      Seconds : Ada.Calendar.Day_Duration;
      Tick : Word;
   begin
      Ada.Calendar.Split (Ada.Calendar.Clock, Year, Month, Day, Seconds);
      Tick := Word (Long_Long_Integer (Real_Value (Seconds) * 1.0E9));
      Tick := Tick xor Interfaces.Shift_Left (Word (Year), 24) xor
        Interfaces.Shift_Left (Word (Month), 16) xor Word (Day);
      Tick := Tick xor Word
        (System.Storage_Elements.To_Integer (State'Address));
      --  Lua's unspecified automatic seed is an unsigned C seed. Mixing a
      --  clock and the universe's address requires no shared global state and
      --  makes no cryptographic promise. Explicit seeds remain fully portable.
      return Tick and Half_Mask;
   end Entropy;

   procedure Reset (State : in out World) is
   begin
      --  Creating/resetting a standard environment precedes public execution;
      --  it must remain possible even with a one-instruction host allowance.
      Seed (State, Entropy (State), 0, Charge_Work => False);
   end Reset;

   function Quotient (Numerator, Denominator : Real_Value) return Real_Value;
   function Quotient (Numerator, Denominator : Real_Value) return Real_Value is
   begin
      --  Domain NaNs are observable through string.pack. Use the same host
      --  quotient as ordinary Lua division, including architecture-specific
      --  zero/zero signs, rather than synthesizing an x86 bit pattern.
      return Real_Value (Lua.Platform_Numerics.Divide
        (C_Real (Numerator), C_Real (Denominator)));
   end Quotient;

   function Run
     (State : in out World; Name : String; Arguments : Values.Vector)
      return Values.Vector
   is
      Result : Values.Vector := Owned_Values (State);
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Arguments.Length) then Arguments (Index)
         else Nil_Value);
      function Numeric (Index : Positive) return Real_Value;
      function Integral (Index : Positive) return Integer_Value;
      procedure Push (Item : Real_Value);
      function Project (Random, Upper : Word) return Word;
      Short_Name : constant String :=
        (if Name'Length > 5 and then
           Name (Name'First .. Name'First + 4) = "math."
         then Name (Name'First + 5 .. Name'Last) else Name);

      function Numeric (Index : Positive) return Real_Value is
         Item : constant Value := Arg (Index);
         Parsed : Lua.Numbers.Number;
      begin
         case Item.Kind is
            when Integer_Kind => return Real_Value (Item.Integer_Data);
            when Real_Kind => return Item.Real_Data;
            when String_Kind =>
               Parsed := Read_Number (State, Item.Reference.Bytes);
               if Parsed.Kind /= Lua.Numbers.Invalid then
                  return Lua.Numbers.To_Real (Parsed);
               end if;
            when others => null;
         end case;
         Fail (State, "bad argument #" &
               Ada.Strings.Fixed.Trim (Positive'Image (Index),
                                       Ada.Strings.Both) &
               " to '" & Short_Name & "' (number expected, got " &
               (if Index > Natural (Arguments.Length) then "no value"
                else Type_Name (Item)) & ")");
         return 0.0;
      end Numeric;

      function Integral (Index : Positive) return Integer_Value is
         Item : constant Value := Arg (Index);
         Parsed : Lua.Numbers.Number;
         Number : Real_Value;
      begin
         if Item.Kind = Integer_Kind then
            return Item.Integer_Data;
         elsif Item.Kind = String_Kind then
            Parsed := Read_Number (State, Item.Reference.Bytes);
            if Parsed.Kind = Lua.Numbers.Integer_Number then
               return Parsed.Integer_Item;
            end if;
         end if;
         Number := Numeric (Index);
         --  The upper endpoint is strict: int64'Last rounds upward to 2**63
         --  in binary64. Test finiteness and integrality before conversion.
         if Number = Number and then Number >= -(2.0 ** 63) and then
           Number < 2.0 ** 63 and then Real_Value'Floor (Number) = Number
         then
            return Integer_Value (Number);
         end if;
         Fail (State, "number has no integer representation");
         return 0;
      end Integral;

      procedure Push (Item : Real_Value) is
      begin
         Result.Append (Value'(Real_Kind, Item));
      end Push;

      function Project (Random, Upper : Word) return Word is
         type Shift_Array is array (Positive range <>) of Natural;
         Mask : Word := Upper;
         Candidate : Word := Random;
      begin
         --  Mask to the smallest 2**k-1 covering Upper. A modulo operation
         --  would bias non-power-of-two ranges and consume a different stream.
         for Shift of Shift_Array'[1, 2, 4, 8, 16, 32] loop
            Mask := Mask or Interfaces.Shift_Right (Mask, Shift);
         end loop;
         loop
            Candidate := Candidate and Mask;
            exit when Candidate <= Upper;
            Candidate := Next_Word (State);
         end loop;
         return Candidate;
      end Project;

      X, Y : Real_Value;
      Exponent : aliased Interfaces.C.int := 0;
      Low, High : Integer_Value := 0;
      First, Second, Random : Word;
   begin
      if Name = "math.randomseed" then
         if not State.Random_Seeded then
            Reset (State);
         end if;
         if Arguments.Is_Empty then
            First := Entropy (State);
            Second := Next_Word (State);
         else
            First := To_Word (Integral (1));
            Second := (if Arg (2).Kind = Nil_Kind then 0
                       else To_Word (Integral (2)));
         end if;
         Seed (State, First, Second);
         Result.Append (Value'(Integer_Kind, To_Integer (First)));
         Result.Append (Value'(Integer_Kind, To_Integer (Second)));
      elsif Name = "math.random" then
         if not State.Random_Seeded then
            Reset (State);
         end if;
         --  Pinned Lua draws before validating argument count or types. Even
         --  a protected invalid call therefore advances this universe's RNG.
         Random := Next_Word (State);
         case Natural (Arguments.Length) is
            when 0 =>
               Push (Real_Value (Interfaces.Shift_Right (Random, 11)) *
                     2.0 ** (-53));
               return Result;
            when 1 =>
               Low := 1;
               High := Integral (1);
               if High = 0 then
                  Result.Append (Value'(Integer_Kind, To_Integer (Random)));
                  return Result;
               end if;
            when 2 =>
               Low := Integral (1);
               High := Integral (2);
            when others =>
               Fail (State, "wrong number of arguments");
         end case;
         if Low > High then
            Fail (State, "bad argument #1 to 'random' (interval is empty)");
         end if;
         Random := Project (Random, To_Word (High) - To_Word (Low));
         Result.Append (Value'
           (Integer_Kind, To_Integer (Random + To_Word (Low))));
      else
         X := Numeric (1);
         if Name = "math.sin" then
            Push (Real_Value (Host.Sine (C_Real (X))));
         elsif Name = "math.cos" then
            Push (Real_Value (Host.Cosine (C_Real (X))));
         elsif Name = "math.tan" then
            Push (Real_Value (Host.Tangent (C_Real (X))));
         elsif Name = "math.asin" then
            Push (Real_Value (Host.Arc_Sine (C_Real (X))));
         elsif Name = "math.acos" then
            Push (Real_Value (Host.Arc_Cosine (C_Real (X))));
         elsif Name in "math.atan" | "math.atan2" then
            Y := (if Arg (2).Kind = Nil_Kind then 1.0 else Numeric (2));
            Push (Real_Value (Host.Arc_Tangent (C_Real (X), C_Real (Y))));
         elsif Name = "math.exp" then
            Push (Real_Value (Host.Exponential (C_Real (X))));
         elsif Name = "math.sqrt" then
            Push (Real_Value (Host.Square_Root (C_Real (X))));
         elsif Name = "math.deg" then
            Push (X * (180.0 / Pi));
         elsif Name = "math.rad" then
            Push (X * (Pi / 180.0));
         elsif Name = "math.log" then
            if Arg (2).Kind = Nil_Kind then
               Push (Real_Value (Host.Logarithm (C_Real (X))));
            else
               Y := Numeric (2);
               --  Pinned luaconf enables LUA_USE_C89 on Windows, so its
               --  math.log uses log(x)/log(2), not the host log2 function.
               --  This affects rounding and exceptional-value bit patterns.
               if Y = 2.0 and then
                 C99_Logarithms (Lua_Ada_Config.Alire_Host_OS)
               then
                  Push (Real_Value (Host.Logarithm_2 (C_Real (X))));
               elsif Y = 10.0 then
                  Push (Real_Value (Host.Logarithm_10 (C_Real (X))));
               else
                  Push (Quotient
                    (Real_Value (Host.Logarithm (C_Real (X))),
                     Real_Value (Host.Logarithm (C_Real (Y)))));
               end if;
            end if;
         elsif Name = "math.frexp" then
            Push (Real_Value (Host.Fraction (C_Real (X), Exponent'Access)));
            Result.Append (Value'(Integer_Kind, Integer_Value (Exponent)));
         elsif Name = "math.ldexp" then
            --  The reference explicitly casts lua_Integer to C int. Preserve
            --  the supported two's-complement ABI's low bits, rather than
            --  raising an Ada range error for a large but valid Lua integer.
            Exponent := Signed_C_Int (Interfaces.C.unsigned
              (To_Word (Integral (2)) and
               Word (Interfaces.C.unsigned'Last)));
            Push (Real_Value (Host.Scale (C_Real (X), Exponent)));
         elsif Name = "math.cosh" then
            Push (Real_Value (Host.Hyperbolic_Cosine (C_Real (X))));
         elsif Name = "math.sinh" then
            Push (Real_Value (Host.Hyperbolic_Sine (C_Real (X))));
         elsif Name = "math.tanh" then
            Push (Real_Value (Host.Hyperbolic_Tangent (C_Real (X))));
         elsif Name = "math.pow" then
            Y := Numeric (2);
            Push (Real_Value (Host.Power (C_Real (X), C_Real (Y))));
         elsif Name = "math.log10" then
            Push (Real_Value (Host.Logarithm_10 (C_Real (X))));
         else
            raise Program_Error with "unknown mathematical export";
         end if;
      end if;
      return Result;
   end Run;
end Lua.Engine.Mathematics;
