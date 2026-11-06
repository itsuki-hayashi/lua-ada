with System;

package body Lua.Big_Naturals is
   use type Small;
   use type Wide;
   use type System.Address;
   use type Lua.Storage.Owner_Access;
   Radix : constant Wide := 2 ** 32;

   function Count (Self : Number) return Natural;
   function Limb (Self : Number; Index : Positive) return Small;
   procedure Normalize (Self : in out Number);
   function Divide_Small
     (Self : in out Number; Denominator : Small) return Small;

   function Count (Self : Number) return Natural is
     (Natural (Self.Limbs.Length));
   function Limb (Self : Number; Index : Positive) return Small is
     (Self.Limbs.Element (Index));

   procedure Normalize (Self : in out Number) is
   begin
      while not Self.Limbs.Is_Empty and then Self.Limbs.Last_Element = 0 loop
         Self.Limbs.Delete_Last;
      end loop;
   end Normalize;

   procedure Set_Owner
     (Self : in out Number; Memory : not null Lua.Storage.Owner_Access) is
   begin
      Self.Limbs.Set_Owner (Memory);
   end Set_Owner;

   function Owner_Of (Self : Number) return Lua.Storage.Owner_Access is
     (Self.Limbs.Owner_Of);
   function Is_Zero (Self : Number) return Boolean is (Self.Limbs.Is_Empty);
   function Is_Odd (Self : Number) return Boolean is
     (not Is_Zero (Self) and then (Self.Limbs.First_Element and 1) /= 0);

   procedure Set_Value (Self : in out Number; Value : Wide) is
      Needed : constant Natural :=
        (if Value = 0 then 0 elsif Value < Radix then 1 else 2);
   begin
      --  Reserve before clearing the previous value. Refused growth therefore
      --  leaves both its mathematical value and allocation policy untouched.
      Self.Limbs.Reserve_Capacity (Limb_Lists.Count_Type (Needed));
      Self.Limbs.Clear;
      if Needed /= 0 then
         Self.Limbs.Append (Small (Value and (Radix - 1)));
         if Needed = 2 then
            Self.Limbs.Append (Small (Interfaces.Shift_Right (Value, 32)));
         end if;
      end if;
   end Set_Value;

   function From_Unsigned
     (Memory : not null Lua.Storage.Owner_Access; Value : Wide) return Number
   is
   begin
      return Result : Number do
         Set_Owner (Result, Memory);
         Set_Value (Result, Value);
      end return;
   end From_Unsigned;

   function Bit_Length (Self : Number) return Natural is
      High : Small;
      Bits : Natural := 0;
   begin
      if Is_Zero (Self) then
         return 0;
      end if;
      High := Self.Limbs.Last_Element;
      while High /= 0 loop
         Bits := Bits + 1;
         High := Interfaces.Shift_Right (High, 1);
      end loop;
      if Count (Self) - 1 > (Natural'Last - Bits) / 32 then
         raise Lua.Storage.Allocation_Error;
      end if;
      return (Count (Self) - 1) * 32 + Bits;
   end Bit_Length;

   function Compare (Left, Right : Number) return Ordering is
   begin
      if Count (Left) < Count (Right) then
         return Less_Than;
      elsif Count (Left) > Count (Right) then
         return Greater_Than;
      end if;
      for Index in reverse 1 .. Count (Left) loop
         if Limb (Left, Index) < Limb (Right, Index) then
            return Less_Than;
         elsif Limb (Left, Index) > Limb (Right, Index) then
            return Greater_Than;
         end if;
      end loop;
      return Equal_To;
   end Compare;

   procedure Add (Self : in out Number; Value : Small) is
      Carry : Wide := Wide (Value);
      Length : constant Natural := Count (Self);
   begin
      if Value = 0 then
         return;
      end if;
      --  Predict the carry before writing. Spare capacity is requested only
      --  when the mathematical result really needs another limb, avoiding an
      --  artificial allocator failure for an addition that already fits.
      for Index in 1 .. Length loop
         Carry := Interfaces.Shift_Right
           (Wide (Limb (Self, Index)) + Carry, 32);
         exit when Carry = 0;
      end loop;
      if Carry /= 0 then
         if Length = Natural'Last then
            raise Lua.Storage.Allocation_Error;
         end if;
         Self.Limbs.Reserve_Capacity (Limb_Lists.Count_Type (Length + 1));
      end if;
      Carry := Wide (Value);
      for Index in 1 .. Length loop
         declare
            Sum : constant Wide := Wide (Limb (Self, Index)) + Carry;
         begin
            Self.Limbs.Replace_Element (Index, Small (Sum and (Radix - 1)));
            Carry := Interfaces.Shift_Right (Sum, 32);
         end;
         exit when Carry = 0;
      end loop;
      if Carry /= 0 then
         Self.Limbs.Append (Small (Carry));
      end if;
   end Add;

   procedure Multiply (Self : in out Number; Factor : Small) is
      Carry : Wide := 0;
      Length : constant Natural := Count (Self);
   begin
      if Factor = 0 then
         Self.Limbs.Clear;
         return;
      elsif Factor = 1 or else Length = 0 then
         return;
      end if;
      --  A 32-by-32 product plus carry fits exactly in an unsigned 64-bit
      --  intermediate. The first pass determines growth, the second commits;
      --  no allocation can interrupt the arithmetic after its first write.
      for Index in 1 .. Length loop
         Carry := Interfaces.Shift_Right
           (Wide (Limb (Self, Index)) * Wide (Factor) + Carry, 32);
      end loop;
      if Carry /= 0 then
         if Length = Natural'Last then
            raise Lua.Storage.Allocation_Error;
         end if;
         Self.Limbs.Reserve_Capacity (Limb_Lists.Count_Type (Length + 1));
      end if;
      Carry := 0;
      for Index in 1 .. Length loop
         declare
            Product : constant Wide :=
              Wide (Limb (Self, Index)) * Wide (Factor) + Carry;
         begin
            Self.Limbs.Replace_Element
              (Index, Small (Product and (Radix - 1)));
            Carry := Interfaces.Shift_Right (Product, 32);
         end;
      end loop;
      if Carry /= 0 then
         Self.Limbs.Append (Small (Carry));
      end if;
   end Multiply;

   procedure Shift_Left (Self : in out Number; Count : Natural) is
      Words : constant Natural := Count / 32;
      Bits : constant Natural := Count mod 32;
      Length : constant Natural := Natural (Self.Limbs.Length);
      Extra : Natural := 0;
      Carry : Wide := 0;
   begin
      if Length = 0 or else Count = 0 then
         return;
      elsif Bits /= 0 and then Interfaces.Shift_Right
        (Self.Limbs.Last_Element, 32 - Bits) /= 0
      then
         Extra := 1;
      end if;
      if Words > Natural'Last - Length or else
        Extra > Natural'Last - Length - Words
      then
         raise Lua.Storage.Allocation_Error;
      end if;
      Self.Limbs.Reserve_Capacity
        (Limb_Lists.Count_Type (Length + Words + Extra));
      Self.Limbs.Set_Length
        (Limb_Lists.Count_Type (Length + Words + Extra));
      --  First move complete words backwards, then shift their bits forwards.
      --  Reversing only the word move prevents overwriting unread input when
      --  a shift introduces one or more zero low limbs.
      for Index in reverse 1 .. Length loop
         Self.Limbs.Replace_Element (Index + Words, Limb (Self, Index));
      end loop;
      for Index in 1 .. Words loop
         Self.Limbs.Replace_Element (Index, 0);
      end loop;
      if Bits /= 0 then
         for Index in Words + 1 .. Words + Length loop
            declare
               Value : constant Wide := Interfaces.Shift_Left
                 (Wide (Limb (Self, Index)), Bits) or Carry;
            begin
               Self.Limbs.Replace_Element
                 (Index, Small (Value and (Radix - 1)));
               Carry := Interfaces.Shift_Right (Value, 32);
            end;
         end loop;
         if Extra /= 0 then
            Self.Limbs.Replace_Element (Length + Words + 1, Small (Carry));
         end if;
      end if;
   end Shift_Left;

   procedure Shift_Right (Self : in out Number; Count : Natural) is
      Words : constant Natural := Count / 32;
      Bits : constant Natural := Count mod 32;
      Length : constant Natural := Natural (Self.Limbs.Length);
      Carry : Small := 0;
   begin
      if Words >= Length then
         Self.Limbs.Clear;
         return;
      elsif Count = 0 then
         return;
      end if;
      for Index in 1 .. Length - Words loop
         Self.Limbs.Replace_Element (Index, Limb (Self, Index + Words));
      end loop;
      Self.Limbs.Delete_Last (Limb_Lists.Count_Type (Words));
      if Bits /= 0 then
         for Index in reverse 1 .. Length - Words loop
            declare
               Value : constant Small := Limb (Self, Index);
            begin
               Self.Limbs.Replace_Element
                 (Index, Interfaces.Shift_Right (Value, Bits) or Carry);
               Carry := Interfaces.Shift_Left (Value, 32 - Bits);
            end;
         end loop;
      end if;
      Normalize (Self);
   end Shift_Right;

   procedure Multiply_Power
     (Self : in out Number; Base : Power_Base; Exponent : Natural)
   is
      Factor : Wide := 1;
      Chunk : Natural := 0;
      Remaining : Natural := Exponent;
      Scratch : Number;
   begin
      if Base = 1 or else Exponent = 0 or else Is_Zero (Self) then
         return;
      elsif Base = 2 then
         Shift_Left (Self, Exponent);
         return;
      end if;
      --  Multiplying decimal powers in blocks of nine digits avoids one
      --  complete limb scan per decimal digit. The same bounded construction
      --  supports other small radices without allocating a separate power.
      while Factor <= Wide (Small'Last) / Wide (Base) loop
         Factor := Factor * Wide (Base);
         Chunk := Chunk + 1;
      end loop;
      --  A power can require several separate growth operations. Work on a
      --  private owner-carrying copy and publish once, so a late refusal does
      --  not leave the caller with only an initial prefix of the power.
      Scratch := Self;
      while Remaining >= Chunk loop
         Multiply (Scratch, Small (Factor));
         Remaining := Remaining - Chunk;
      end loop;
      for Index in 1 .. Remaining loop
         Multiply (Scratch, Small (Base));
      end loop;
      Limb_Lists.Move (Self.Limbs, Scratch.Limbs);
   end Multiply_Power;

   procedure Subtract (Self : in out Number; Value : Number) is
      Borrow : Wide := 0;
      Order : constant Ordering := Compare (Self, Value);
   begin
      if Order = Less_Than then
         raise Constraint_Error with "negative exact natural subtraction";
      elsif Order = Equal_To then
         Self.Limbs.Clear;
         return;
      end if;
      for Index in 1 .. Count (Self) loop
         declare
            Current : constant Wide := Wide (Limb (Self, Index));
            Remove : constant Wide := Borrow +
              (if Index <= Count (Value) then Wide (Limb (Value, Index))
               else 0);
         begin
            if Current >= Remove then
               Self.Limbs.Replace_Element (Index, Small (Current - Remove));
               Borrow := 0;
            else
               Self.Limbs.Replace_Element
                 (Index, Small (Radix + Current - Remove));
               Borrow := 1;
            end if;
         end;
      end loop;
      Normalize (Self);
   end Subtract;

   procedure Divide
     (Numerator, Denominator : Number;
      Quotient, Remainder : in out Number)
   is
      Fresh_Quotient, Fresh_Remainder, Shifted : Number;
      Memory : constant Lua.Storage.Owner_Access := Owner_Of (Numerator);
      Difference : Natural;
   begin
      if Is_Zero (Denominator) then
         raise Constraint_Error with "zero exact natural divisor";
      elsif Quotient'Address = Remainder'Address then
         raise Program_Error with "division outputs must be distinct";
      elsif Memory = null then
         raise Program_Error with "exact division requires an owner";
      end if;
      Set_Owner (Fresh_Quotient, Memory);
      Fresh_Remainder := Numerator;
      if Compare (Numerator, Denominator) /= Less_Than then
         Difference := Bit_Length (Numerator) - Bit_Length (Denominator);
         Set_Owner (Shifted, Memory);
         Shifted.Limbs.Append (Denominator.Limbs);
         Shift_Left (Shifted, Difference);
         Fresh_Quotient.Limbs.Set_Length
           (Limb_Lists.Count_Type (Difference / 32 + 1));
         for Index in 1 .. Count (Fresh_Quotient) loop
            Fresh_Quotient.Limbs.Replace_Element (Index, 0);
         end loop;
         --  Long division needs at most one comparison/subtraction per output
         --  bit. It retains an exact remainder, which decides binary/decimal
         --  halfway rounding without double rounding through host floats.
         for Bit in reverse 0 .. Difference loop
            if Compare (Fresh_Remainder, Shifted) /= Less_Than then
               Subtract (Fresh_Remainder, Shifted);
               declare
                  Index : constant Positive := Bit / 32 + 1;
               begin
                  Fresh_Quotient.Limbs.Replace_Element
                    (Index, Limb (Fresh_Quotient, Index) or
                     Interfaces.Shift_Left (Small'(1), Bit mod 32));
               end;
            end if;
            if Bit /= 0 then
               Shift_Right (Shifted, 1);
            end if;
         end loop;
         Normalize (Fresh_Quotient);
      end if;
      --  Publication is an allocation-free move only after both results are
      --  complete. Aliasing an input is safe because no input is read again.
      Limb_Lists.Move (Quotient.Limbs, Fresh_Quotient.Limbs);
      Limb_Lists.Move (Remainder.Limbs, Fresh_Remainder.Limbs);
   end Divide;

   function To_Unsigned (Self : Number) return Wide is
   begin
      if Count (Self) > 2 then
         raise Constraint_Error with "exact natural exceeds 64 bits";
      elsif Is_Zero (Self) then
         return 0;
      elsif Count (Self) = 1 then
         return Wide (Limb (Self, 1));
      end if;
      return Wide (Limb (Self, 1)) or
        Interfaces.Shift_Left (Wide (Limb (Self, 2)), 32);
   end To_Unsigned;

   function Divide_Small
     (Self : in out Number; Denominator : Small) return Small
   is
      Remainder : Wide := 0;
   begin
      for Index in reverse 1 .. Count (Self) loop
         declare
            Current : constant Wide := Interfaces.Shift_Left
              (Remainder, 32) or Wide (Limb (Self, Index));
         begin
            Self.Limbs.Replace_Element
              (Index, Small (Current / Wide (Denominator)));
            Remainder := Current mod Wide (Denominator);
         end;
      end loop;
      Normalize (Self);
      return Small (Remainder);
   end Divide_Small;

   function Decimal_Digits (Self : Number) return Positive is
      Scratch : Number := Self;
      Chunk : Small;
      Result : Positive := 1;
   begin
      if Is_Zero (Self) then
         return 1;
      end if;
      loop
         Chunk := Divide_Small (Scratch, 1_000_000_000);
         exit when Is_Zero (Scratch);
         if Result > Positive'Last - 9 then
            raise Lua.Storage.Allocation_Error;
         end if;
         Result := Result + 9;
      end loop;
      while Chunk >= 10 loop
         Chunk := Chunk / 10;
         Result := Result + 1;
      end loop;
      return Result;
   end Decimal_Digits;

   procedure Decimal
     (Self : Number; Output : in out Lua.Storage.Buffers.Buffer)
   is
      Scratch : Number := Self;
      Chunks : Limb_Lists.Vector;
      Digit_Count : Natural := 1;
   begin
      Chunks.Set_Owner (Owner_Of (Self));
      if not Is_Zero (Self) then
         while not Is_Zero (Scratch) loop
            Chunks.Append (Divide_Small (Scratch, 1_000_000_000));
         end loop;
         declare
            High : Small := Chunks.Last_Element;
         begin
            Digit_Count := (Natural (Chunks.Length) - 1) * 9 + 1;
            while High >= 10 loop
               High := High / 10;
               Digit_Count := Digit_Count + 1;
            end loop;
         end;
      end if;
      --  Reserve the exact mathematical output size before destroying old
      --  output. All subsequent writes use fixed nine-byte stack scratch and
      --  cannot require a managed allocation or an input-sized host String.
      Output.Set_Owner (Owner_Of (Self));
      Output.Reserve_Capacity (Digit_Count);
      Output.Clear;
      if Chunks.Is_Empty then
         Output.Append ('0');
         return;
      end if;
      for Index in reverse Chunks.First_Index .. Chunks.Last_Index loop
         declare
            Chunk : Small := Chunks.Element (Index);
            Bytes : String (1 .. 9) := [others => '0'];
            First : Positive := Bytes'Last;
         begin
            loop
               Bytes (First) := Character'Val
                 (Character'Pos ('0') + Natural (Chunk mod 10));
               Chunk := Chunk / 10;
               exit when Chunk = 0;
               First := First - 1;
            end loop;
            Output.Append
              ((if Index = Chunks.Last_Index then Bytes (First .. Bytes'Last)
                else Bytes));
         end;
      end loop;
   end Decimal;
end Lua.Big_Naturals;
