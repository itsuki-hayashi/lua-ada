with Ada.Strings.Fixed;
with Ada.Unchecked_Conversion;
with Interfaces;
with Lua.Big_Naturals;
with Lua.Engine.Strings;

package body Lua.Engine.Formats is
   package Managed renames Lua.Storage.Buffers;
   use type Integer_Value;
   use type Real_Value;
   use type Interfaces.Unsigned_64;
   package Big renames Lua.Big_Naturals;
   use type Big.Ordering;
   function Bits is new Ada.Unchecked_Conversion
     (Real_Value, Interfaces.Unsigned_64);
   function Unsigned_Bits is new Ada.Unchecked_Conversion
     (Integer_Value, Interfaces.Unsigned_64);
   --  Lua's unsigned conversions reinterpret the 64-bit integer pattern.
   --  A checked numeric conversion would reject negative source values.
   Hex : constant String := "0123456789abcdef";
   function Windows_Host
     (Host : String := Lua_Ada_Config.Alire_Host_OS) return Boolean is
     (Host = "windows");
   function Unsigned_NaN
     (Host : String := Lua_Ada_Config.Alire_Host_OS) return Boolean is
     (Host in "windows" | "macos");

   function Trim (Text : String) return String is
     (Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both));

   procedure Work (State : in out World; Count : Natural := 1);
   procedure Work (State : in out World; Count : Natural := 1) is
   begin
      if Count > State.Bounds.Instructions - Natural'Min
        (State.Steps, State.Bounds.Instructions)
      then
         Fail (State, "instruction limit exceeded", Resource => True);
      end if;
      if State.Policy = Bounded then
         State.Steps := State.Steps + Count;
      end if;
   end Work;

   function Unsigned_Image
     (Item : Interfaces.Unsigned_64; Base : Positive) return String;
   function Unsigned_Image
     (Item : Interfaces.Unsigned_64; Base : Positive) return String
   is
      Buffer : String (1 .. 64);
      First : Positive := Buffer'Last;
      Remaining : Interfaces.Unsigned_64 := Item;
   begin
      loop
         Buffer (First) := Hex (Natural (Remaining mod
           Interfaces.Unsigned_64 (Base)) + 1);
         Remaining := Remaining / Interfaces.Unsigned_64 (Base);
         exit when Remaining = 0;
         First := First - 1;
      end loop;
      return Buffer (First .. Buffer'Last);
   end Unsigned_Image;

   type Rational is record
      Numerator, Denominator : Big.Number;
   end record;
   function Exact
     (Memory : not null Lua.Storage.Owner_Access;
      Value : Real_Value) return Rational;
   function Exact
     (Memory : not null Lua.Storage.Owner_Access;
      Value : Real_Value) return Rational
   is
      Raw : constant Interfaces.Unsigned_64 := Bits (Value);
      Exponent : constant Natural := Natural
        (Interfaces.Shift_Right (Raw, 52) and 16#7FF#);
      Mantissa : Interfaces.Unsigned_64 := Raw and 16#F_FFFF_FFFF_FFFF#;
      Power : Integer;
      Result : Rational;
   begin
      if Exponent = 0 then
         Power := -1074;
      else
         Mantissa := Mantissa + 2 ** 52;
         Power := Integer (Exponent) - 1075;
      end if;
      --  Decode the finite binary64 magnitude exactly. Both sides carry the
      --  calling world's allocator, including every limb grown by a shift.
      --  No host big-integer runtime or decimal parsing scratch is involved.
      Big.Set_Owner (Result.Numerator, Memory);
      Big.Set_Owner (Result.Denominator, Memory);
      Big.Set_Value (Result.Numerator, Mantissa);
      Big.Set_Value (Result.Denominator, 1);
      if Mantissa = 0 then
         --  Zero needs no enormous subnormal denominator. Its sign is kept
         --  separately by the caller, so the exact magnitude is simply 0/1.
         return Result;
      elsif Power >= 0 then
         Big.Shift_Left (Result.Numerator, Natural (Power));
      else
         Big.Shift_Left (Result.Denominator, Natural (-Power));
      end if;
      return Result;
   end Exact;

   procedure Rounded
     (Value : Rational; Scale : Integer; Output : in out Managed.Buffer);
   procedure Rounded
     (Value : Rational; Scale : Integer; Output : in out Managed.Buffer)
   is
      Numerator : Big.Number := Value.Numerator;
      Denominator : Big.Number := Value.Denominator;
      Quotient, Remainder : Big.Number;
      Comparison : Big.Ordering;
   begin
      --  Formatting uses exact rational rounding, independently of the host
      --  locale and Ada real I/O conventions. This avoids double rounding
      --  when a short requested precision lies near a decimal halfway case.
      if Scale >= 0 then
         Big.Multiply_Power (Numerator, 10, Natural (Scale));
      else
         Big.Multiply_Power (Denominator, 10, Natural (-Scale));
      end if;
      --  Divide publishes both owned results together. Comparing twice the
      --  exact remainder implements round-to-nearest, ties-to-even; a host
      --  floating-point rounding mode cannot change this decision.
      Big.Divide (Numerator, Denominator, Quotient, Remainder);
      Big.Multiply (Remainder, 2);
      Comparison := Big.Compare (Remainder, Denominator);
      if Comparison = Big.Greater_Than or else
        (Comparison = Big.Equal_To and then Big.Is_Odd (Quotient))
      then
         Big.Add (Quotient, 1);
      end if;
      Big.Decimal (Quotient, Output);
   end Rounded;

   function Decimal_Exponent (Value : Rational) return Integer;
   function Decimal_Exponent (Value : Rational) return Integer is
      Result : Integer;
      Scaled : Big.Number;
      Lower : Boolean;
   begin
      if Big.Is_Zero (Value.Numerator) then
         return 0;
      end if;
      Result := Big.Decimal_Digits (Value.Numerator) -
        Big.Decimal_Digits (Value.Denominator);
      if Result >= 0 then
         Scaled := Value.Denominator;
         Big.Multiply_Power (Scaled, 10, Natural (Result));
         Lower := Big.Compare (Value.Numerator, Scaled) = Big.Less_Than;
      else
         Scaled := Value.Numerator;
         Big.Multiply_Power (Scaled, 10, Natural (-Result));
         Lower := Big.Compare (Scaled, Value.Denominator) = Big.Less_Than;
      end if;
      return (if Lower then Result - 1 else Result);
   end Decimal_Exponent;

   procedure Float_Image
     (State : in out World; Item : Real_Value; Code : Character;
      Precision : Integer; Alternate : Boolean;
      Output : in out Managed.Buffer);
   procedure Float_Image
     (State : in out World; Item : Real_Value; Code : Character;
      Precision : Integer; Alternate : Boolean;
      Output : in out Managed.Buffer)
   is
      Value : constant Rational :=
        Exact (Lua.Storage.Reference (State.Memory), Item);
      Exponent : Integer := Decimal_Exponent (Value);
      Significant : Natural := (if Precision < 0 then 6 else Precision);
      Rounded_Digits : Managed.Buffer;
      Count, Leading_Zeroes : Natural := 0;
      Scientific : Boolean;
      Point : Integer;

      function Digit (Index : Positive) return Character;
      function Digit (Index : Positive) return Character is
        (if Index <= Leading_Zeroes then '0'
         else Rounded_Digits.Element (Index - Leading_Zeroes));

      procedure Append_Digits (First : Positive; Last : Natural);
      procedure Append_Digits (First : Positive; Last : Natural) is
      begin
         for Index in First .. Last loop
            Output.Append (Digit (Index));
         end loop;
      end Append_Digits;
   begin
      Rounded_Digits.Set_Owner (Lua.Storage.Reference (State.Memory));
      Output.Set_Owner (Lua.Storage.Reference (State.Memory));
      Output.Clear;
      if Code in 'f' | 'F' then
         Rounded (Value, Significant, Rounded_Digits);
         --  Treat left padding as virtual digits. Building the final managed
         --  buffer in order avoids repeated front insertions and host String
         --  snapshots, even when a tiny fraction needs many leading zeroes.
         Leading_Zeroes :=
           (if Rounded_Digits.Length <= Significant
            then Significant + 1 - Rounded_Digits.Length else 0);
         Count := Leading_Zeroes + Rounded_Digits.Length;
         Output.Reserve_Capacity (Count + 1);
         for Index in 1 .. Count loop
            if Significant > 0 and then Index = Count - Significant + 1 then
               Output.Append ('.');
            end if;
            Output.Append (Digit (Index));
         end loop;
         if Significant = 0 and then Alternate then
            Output.Append ('.');
         end if;
         return;
      end if;

      if Code in 'e' | 'E' then
         Significant := Significant + 1;
      elsif Significant = 0 then
         Significant := 1;
      end if;
      Rounded (Value, Integer (Significant) - 1 - Exponent, Rounded_Digits);
      Count := Rounded_Digits.Length;
      if Count > Significant then
         --  Carry at a decimal boundary changes the exponent. The final
         --  rounded zero is omitted by reducing the view, not by reallocating.
         Count := Count - 1;
         Exponent := Exponent + 1;
      end if;
      Leading_Zeroes :=
        (if Count < Significant then Significant - Count else 0);
      Count := Count + Leading_Zeroes;
      Scientific := Code in 'e' | 'E' or else
        Exponent < -4 or else Exponent >= Integer (Significant);
      if Code in 'g' | 'G' and then not Alternate then
         while Count > 1 and then Digit (Count) = '0' loop
            Count := Count - 1;
         end loop;
      end if;

      --  Binary64 exponents and Lua's at-most-two-digit requested precision
      --  bound this reservation. All variable-width bytes still belong to the
      --  calling owner; refusal unwinds its exact rational and digit buffers.
      Output.Reserve_Capacity (Count + abs Exponent + 8);
      if Scientific then
         Output.Append (Digit (1));
         if Count > 1 or else Alternate then
            Output.Append ('.');
         end if;
         Append_Digits (2, Count);
         Output.Append ((if Code in 'E' | 'G' then 'E' else 'e'));
         Output.Append ((if Exponent < 0 then '-' else '+'));
         declare
            --  Exponent'Image is bounded scalar scratch, not an input-sized
            --  temporary or allocator-bypassing decimal representation.
            Power : constant String := Trim (Integer'Image (abs Exponent));
         begin
            if Power'Length < 2 then
               Output.Append ('0');
            end if;
            Output.Append (Power);
         end;
      else
         Point := Exponent + 1;
         if Point <= 0 then
            Output.Append ("0.");
            for Index in 1 .. -Point loop
               Output.Append ('0');
            end loop;
            Append_Digits (1, Count);
         elsif Point >= Count then
            Append_Digits (1, Count);
            for Index in Count + 1 .. Point loop
               Output.Append ('0');
            end loop;
            if Alternate then
               Output.Append ('.');
            end if;
         else
            Append_Digits (1, Point);
            Output.Append ('.');
            Append_Digits (Point + 1, Count);
         end if;
      end if;
   end Float_Image;

   procedure Hex_Float
     (State : in out World; Item : Real_Value; Precision : Integer;
      Alternate : Boolean; Host : String; Output : in out Managed.Buffer);
   procedure Hex_Float
     (State : in out World; Item : Real_Value; Precision : Integer;
      Alternate : Boolean; Host : String; Output : in out Managed.Buffer)
   is
      Raw : constant Interfaces.Unsigned_64 := Bits (Item);
      Field : constant Natural := Natural
        (Interfaces.Shift_Right (Raw, 52) and 16#7FF#);
      Exponent : Integer :=
        (if Field = 0 then -1022 else Integer (Field) - 1023);
      Mantissa : Interfaces.Unsigned_64 := Raw and 16#F_FFFF_FFFF_FFFF#;
      --  Binary64 has exactly thirteen hexadecimal fraction digits. Keep
      --  those fixed-width scalar bytes on the Ada stack; arbitrary requested
      --  trailing zeroes are emitted directly into the owner's final buffer.
      Fraction : String (1 .. 13);
      Fraction_Length : Natural := 13;
      Leading : Natural := Boolean'Pos (Field /= 0);
      Remainder, Half : Interfaces.Unsigned_64;
   begin
      if Field = 0 and then Mantissa = 0 then
         Exponent := 0;
      elsif Field = 0 and then Host in "windows" | "macos" then
         --  Lua's Windows C89 formatter and macOS libc both normalize
         --  subnormals; Linux libc retains the minimum normal exponent.
         --  This spelling policy is independent of whether format modifiers
         --  are available. Shift the exact significand, losing no bits.
         while Mantissa < 2 ** 52 loop
            Mantissa := Mantissa * 2;
            Exponent := Exponent - 1;
         end loop;
         Mantissa := Mantissa - 2 ** 52;
         Leading := 1;
      end if;
      if Precision >= 0 and then Precision < 13 then
         Half := 2 ** (51 - 4 * Precision);
         Remainder := Mantissa mod (Half * 2);
         Mantissa := Mantissa / (Half * 2);
         if Remainder > Half or else
           (Remainder = Half and then
              (if Precision = 0 then Leading mod 2 = 1
               else Mantissa mod 2 = 1))
         then
            Mantissa := Mantissa + 1;
         end if;
         Leading := Leading + Natural (Mantissa / 16 ** Precision);
         Mantissa := Mantissa mod 16 ** Precision;
         Fraction_Length := Precision;
         for Index in reverse 1 .. Precision loop
            Fraction (Index) := Hex (Natural (Mantissa mod 16) + 1);
            Mantissa := Mantissa / 16;
         end loop;
      else
         for Index in reverse Fraction'Range loop
            Fraction (Index) := Hex (Natural (Mantissa mod 16) + 1);
            Mantissa := Mantissa / 16;
         end loop;
         if Precision < 0 then
            while Fraction_Length > 0 and then
              Fraction (Fraction_Length) = '0'
            loop
               Fraction_Length := Fraction_Length - 1;
            end loop;
         end if;
      end if;
      Output.Set_Owner (Lua.Storage.Reference (State.Memory));
      Output.Clear;
      Output.Reserve_Capacity
        (Natural'Max (Fraction_Length, Integer'Max (Precision, 0)) + 24);
      Output.Append ("0x");
      Output.Append (Hex (Leading + 1));
      if Fraction_Length > 0 or else Alternate then
         Output.Append ('.');
      end if;
      Output.Append (Fraction (1 .. Fraction_Length));
      for Index in 14 .. Precision loop
         Output.Append ('0');
      end loop;
      Output.Append ('p');
      Output.Append ((if Exponent < 0 then '-' else '+'));
      Output.Append (Trim (Integer'Image (abs Exponent)));
   end Hex_Float;

   procedure Render_Into
     (State : in out World; Specification : String; Item : Value;
      Output : in out Managed.Buffer;
      Host : String := Lua_Ada_Config.Alire_Host_OS)
   is
      Form : constant String (1 .. Specification'Length) := Specification;
      Cursor : Positive := 2;
      Left, Plus, Space, Alternate, Zero : Boolean := False;
      Width : Natural := 0;
      Precision : Integer := -1;
      Precision_Digits : Natural := 0;
      Code : Character;
      Text, Prefix : Managed.Buffer;
      Number : Integer_Value;
      Real : Real_Value;
      Value : Lua.Numbers.Number;
      Padding : Natural;
      Negative : Boolean := False;
      Numeric : Boolean := False;
      use type Lua.Numbers.Number_Kind;
   begin
      Text.Set_Owner (Lua.Storage.Reference (State.Memory));
      Prefix.Set_Owner (Lua.Storage.Reference (State.Memory));
      Output.Set_Owner (Lua.Storage.Reference (State.Memory));
      if Form'Length < 2 or else Form (1) /= '%' then
         Fail (State, "invalid conversion specification");
      elsif Form'Length >= 23 then
         --  The pinned library reserves ten bytes of its 32-byte format
         --  scratch buffer for modifiers, the percent sign, and terminator.
         Fail (State, "invalid format (too long)");
      end if;
      while Cursor < Form'Last and then
        Form (Cursor) in '-' | '+' | ' ' | '#' | '0'
      loop
         Work (State);
         case Form (Cursor) is
            when '-' => Left := True;
            when '+' => Plus := True;
            when ' ' => Space := True;
            when '#' => Alternate := True;
            when others => Zero := True;
         end case;
         Cursor := Cursor + 1;
      end loop;
      while Cursor < Form'Last and then Form (Cursor) in '0' .. '9' loop
         Work (State);
         Width := Width * 10 + Character'Pos (Form (Cursor)) - 48;
         if Width > 99 then
            Fail (State, "invalid conversion specification");
         end if;
         Cursor := Cursor + 1;
      end loop;
      if Cursor < Form'Last and then Form (Cursor) = '.' then
         Cursor := Cursor + 1;
         Precision := 0;
         while Cursor < Form'Last and then Form (Cursor) in '0' .. '9' loop
            Work (State);
            Precision_Digits := Precision_Digits + 1;
            if Precision_Digits > 2 then
               Fail (State, "invalid conversion specification");
            end if;
            Precision := Precision * 10 + Character'Pos (Form (Cursor)) - 48;
            if Precision > 99 then
               Fail (State, "invalid conversion specification");
            end if;
            Cursor := Cursor + 1;
         end loop;
      end if;
      if Cursor /= Form'Last then
         Fail (State, "invalid conversion specification");
      end if;
      Code := Form (Cursor);
      --  Flags are conversion-specific in Lua, even when a host printf
      --  would quietly accept them. Keep validation ahead of conversion so
      --  malformed specifications do not obtain an implementation extension.
      if (Code in 'c' | 'p' | 's' and then
            (Plus or Space or Alternate or Zero)) or else
        (Code = 'u' and then (Plus or Space or Alternate)) or else
        (Code in 'd' | 'i' and then Alternate) or else
        (Code in 'o' | 'x' | 'X' and then (Plus or Space)) or else
        (Code = 'p' and then Precision >= 0)
      then
         Fail (State, "invalid conversion specification");
      end if;
      case Code is
         when 'd' | 'i' | 'u' | 'o' | 'x' | 'X' =>
            Numeric := True;
            Number := Strings.Integer_Argument (State, Item);
            if Code in 'd' | 'i' then
               Text.Set_Value (Trim (Number'Image));
               if Number < 0 then
                  Text.Delete (1, 1);
                  Negative := True;
               end if;
            else
               Text.Set_Value (Unsigned_Image
                 (Unsigned_Bits (Number),
                  (if Code = 'o' then 8 elsif Code = 'u' then 10 else 16)));
            end if;
            if Precision = 0 and then Number = 0 then
               Text.Clear;
            end if;
            while Length (Text) < Precision loop
               Work (State);
               Text.Insert (1, "0");
            end loop;
            if Alternate and then Code = 'o' and then
              (Length (Text) = 0 or else Text.Element (1) /= '0')
            then
               Text.Insert (1, "0");
            elsif Alternate and then Number /= 0 and then Code in 'x' | 'X'
            then
               Prefix.Set_Value ("0x");
            end if;
            if Code in 'u' | 'o' | 'x' | 'X' then
               Plus := False;
               Space := False;
            end if;
            if Precision >= 0 then
               Zero := False;
            end if;
         when 'a' | 'A' | 'e' | 'E' | 'f' | 'g' | 'G' =>
            Numeric := True;
            if Code in 'a' | 'A' and then Windows_Host (Host) and then
              Form not in "%a" | "%A"
            then
               Fail (State,
                     "modifiers for format '%a'/'%A' not implemented");
            end if;
            if Item.Kind = Real_Kind then
               Real := Item.Real_Data;
            elsif Item.Kind = Integer_Kind then
               Real := Real_Value (Item.Integer_Data);
            elsif Item.Kind = String_Kind then
               --  Numeric values need no text roundtrip. A string conversion
               --  borrows its immutable bytes and allocates parser scratch
               --  through this same world, never through a default owner.
               Value := Read_Number (State, Item.Reference.Bytes);
               if Value.Kind = Lua.Numbers.Invalid then
                  Fail (State, "number expected");
               end if;
               Real := Lua.Numbers.To_Real (Value);
            else
               Fail (State, "number expected");
            end if;
            Negative := (Bits (Real) and 2 ** 63) /= 0;
            if Real /= Real or else abs Real > Real_Value'Last then
               Text.Set_Value ((if Real /= Real then "nan" else "inf"));
               if Real /= Real and then Unsigned_NaN (Host) then
                  Negative := False;
               end if;
               Zero := False;
            elsif Code in 'a' | 'A' then
               Hex_Float (State, Real, Precision, Alternate, Host, Text);
            else
               Float_Image (State, Real, Code, Precision, Alternate, Text);
            end if;
         when 's' =>
            if Item.Kind = String_Kind then
               Work (State, Length (Item.Reference.Bytes));
            end if;
            if Item.Kind = String_Kind then
               declare
                  Source : constant String
                    (1 .. Length (Item.Reference.Bytes))
                    with Import, Address => Item.Reference.Bytes.Address;
               begin
                  Text.Set_Value (Source);
               end;
            else
               Text.Set_Value
                 (Image (Lua.Storage.Reference (State.Memory), Item));
            end if;
            if Form /= "%s" then
               for Index in 1 .. Text.Length loop
                  Work (State);
                  if Text.Element (Index) = Character'Val (0) then
                     Fail (State, "string contains zeros");
                  end if;
               end loop;
            end if;
            if Precision >= 0 and then Length (Text) > Precision then
               Text.Delete (Precision + 1, Length (Text));
            end if;
            Zero := False;
         when 'c' =>
            if Precision >= 0 then
               Fail (State, "invalid conversion specification");
            end if;
            Number := Strings.Integer_Argument (State, Item);
            Text.Set_Value (String'(1 => Character'Val (Number mod 256)));
            Zero := False;
         when 'q' =>
            if Form /= "%q" then
               Fail (State, "specifier '%q' cannot have modifiers");
            end if;
            if Item.Kind = String_Kind then
               --  Borrow source bytes and emit escapes into managed storage.
               --  Retain the existing source/assembly work charge even though
               --  the old full-source Ada String snapshot is now unnecessary.
               Work (State, Length (Item.Reference.Bytes));
               Append (Text, '"');
               declare
                  Source : constant Byte_String := Item.Reference.Bytes;
               begin
                  for Index in 1 .. Length (Source) loop
                     Work (State);
                     if Element (Source, Index) in
                       '"' | '\' | Character'Val (10)
                     then
                        Append (Text, '\');
                        Append (Text, Element (Source, Index));
                     elsif Character'Pos (Element (Source, Index)) < 32 or else
                       Character'Pos (Element (Source, Index)) = 127
                     then
                        declare
                           Decimal : constant String := Trim
                             (Natural'Image (Character'Pos
                                (Element (Source, Index))));
                        begin
                           Append (Text, '\');
                           if Index < Length (Source) and then
                             Element (Source, Index + 1) in '0' .. '9'
                           then
                              for Pad in Decimal'Length + 1 .. 3 loop
                                 Work (State);
                                 Append (Text, '0');
                              end loop;
                           end if;
                           Append (Text, Decimal);
                        end;
                     else
                        Append (Text, Element (Source, Index));
                     end if;
                  end loop;
               end;
               Append (Text, '"');
            elsif Item.Kind = Real_Kind then
               Real := Item.Real_Data;
               if Real /= Real then
                  Text.Set_Value ("(0/0)");
               elsif abs Real > Real_Value'Last then
                  Text.Set_Value
                    ((if Real < 0.0 then "-1e9999" else "1e9999"));
               else
                  Hex_Float (State, Real, -1, False, Host, Text);
                  if (Bits (Real) and 2 ** 63) /= 0 then
                     Text.Insert (1, "-");
                  end if;
               end if;
            elsif Item.Kind = Integer_Kind and then
              Item.Integer_Data = Integer_Value'First
            then
               Text.Set_Value ("0x8000000000000000");
            elsif Item.Kind in Integer_Kind | Nil_Kind | Boolean_Kind then
               Text.Set_Value
                 (Image (Lua.Storage.Reference (State.Memory), Item));
            else
               Fail (State, "value has no literal form");
            end if;
         when 'p' =>
            if Item.Kind in String_Kind | Table_Kind | Closure_Kind |
              Native_Closure_Kind
            then
               Text.Set_Value ("0x" & Unsigned_Image
                 (Interfaces.Unsigned_64 (Item.Reference.Serial), 16));
            else
               Text.Set_Value ("(null)");
            end if;
            Zero := False;
         when others => Fail (State, "invalid conversion specification");
      end case;
      if Code in 'A' | 'E' | 'F' | 'G' | 'X' then
         for Index in 1 .. Length (Text) loop
            Work (State);
            if Text.Element (Index) in 'a' .. 'z' then
               Text.Replace_Element (Index, Character'Val
                 (Character'Pos (Text.Element (Index)) - 32));
            end if;
         end loop;
         if Code = 'X' then
            Prefix.Set_Value ((if Length (Prefix) > 0 then "0X" else ""));
         end if;
      end if;
      if Numeric then
         if Negative then
            Prefix.Insert (1, "-");
         elsif Plus then
            Prefix.Insert (1, "+");
         elsif Space then
            Prefix.Insert (1, " ");
         end if;
      end if;
      Padding := (if Width > Length (Text) + Length (Prefix) then
                    Width - Length (Text) - Length (Prefix) else 0);
      --  Assembly is also native work, particularly for an unmodified %s
      --  whose output may be much larger than the format specification.
      Work (State, Padding);
      Work (State, Length (Text));
      Work (State, Length (Prefix));
      declare
         Remaining : Natural := State.Bounds.String_Bytes;
         procedure Charge_Size (Count : Natural);
         procedure Charge_Size (Count : Natural) is
         begin
            if Count > Remaining then
               Fail (State, "string byte limit exceeded", Resource => True);
            end if;
            Remaining := Remaining - Count;
         end Charge_Size;
      begin
         --  Validate combined size before growing the retained output. Borrow
         --  each managed part only while copying it into its final position;
         --  no input-sized Ada String or concatenation temporary is created.
         Charge_Size (Output.Length);
         Charge_Size (Text.Length);
         Charge_Size (Prefix.Length);
         Charge_Size (Padding);
         Output.Reserve_Capacity
           (State.Bounds.String_Bytes - Remaining);
         if Left then
            Output.Append (Prefix);
            Output.Append (Text);
            for Index in 1 .. Padding loop
               Output.Append (' ');
            end loop;
         elsif Zero then
            Output.Append (Prefix);
            for Index in 1 .. Padding loop
               Output.Append ('0');
            end loop;
            Output.Append (Text);
         else
            for Index in 1 .. Padding loop
               Output.Append (' ');
            end loop;
            Output.Append (Prefix);
            Output.Append (Text);
         end if;
      end;
   end Render_Into;

   function Render
     (State : in out World; Specification : String; Item : Value;
      Host : String := Lua_Ada_Config.Alire_Host_OS) return String
   is
      Output : Managed.Buffer;
   begin
      --  Compatibility wrapper for Ada-side inspection/tests. Runtime format
      --  continuations call Render_Into to keep their complete output managed.
      Render_Into (State, Specification, Item, Output, Host);
      return To_String (Output);
   end Render;

   function Run
     (State : in out World; Arguments : Values.Vector) return Values.Vector
   is
      Result : Values.Vector := Owned_Values (State);
      Output : Managed.Buffer;
      Cursor : Positive := 1;
      First : Positive;
      Argument : Positive := 1;
   begin
      Output.Set_Owner (Lua.Storage.Reference (State.Memory));
      if Arguments.Is_Empty then
         Fail (State, "string expected");
      end if;
      declare
         procedure Apply_Format (Form : String);
         procedure Apply_Format (Form : String) is
         begin
            while Cursor <= Form'Last loop
               if State.Steps >= State.Bounds.Instructions then
                  Fail (State, "instruction limit exceeded", Resource => True);
               end if;
               if State.Policy = Bounded then
                  State.Steps := State.Steps + 1;
               end if;
               if Form (Cursor) /= '%' then
                  Append (Output, Form (Cursor));
                  Cursor := Cursor + 1;
               elsif Cursor < Form'Last and then Form (Cursor + 1) = '%' then
                  Append (Output, '%');
                  Cursor := Cursor + 2;
               else
                  First := Cursor;
                  Cursor := Cursor + 1;
                  while Cursor <= Form'Last and then
                    Form (Cursor) in '-' | '+' | ' ' | '#' | '0' .. '9' | '.'
                  loop
                     Work (State);
                     Cursor := Cursor + 1;
                  end loop;
                  if Cursor > Form'Last then
                     Fail (State, "invalid conversion specification");
                  end if;
                  Argument := Argument + 1;
                  if Argument > Natural (Arguments.Length) then
                     Fail (State, "no value");
                  end if;
                  Render_Into
                    (State, Form (First .. Cursor),
                     Arguments (Argument), Output);
                  Cursor := Cursor + 1;
               end if;
               if Length (Output) > State.Bounds.String_Bytes then
                  Fail (State, "string byte limit exceeded", Resource => True);
               end if;
            end loop;
         end Apply_Format;
      begin
         Strings.Query_Argument (State, Arguments (1), Apply_Format'Access);
      end;
      Result.Append (New_String (State, Output));
      return Result;
   end Run;
end Lua.Engine.Formats;
