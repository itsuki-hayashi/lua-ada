with Ada.Numerics.Big_Numbers.Big_Integers;
with Ada.Strings.Fixed;
with Ada.Unchecked_Conversion;
with Interfaces;
with Lua.Engine.Strings;

package body Lua.Engine.Formats is
   package Managed renames Lua.Storage.Buffers;
   use type Integer_Value;
   use type Real_Value;
   use type Interfaces.Unsigned_64;
   package Big renames Ada.Numerics.Big_Numbers.Big_Integers;
   use type Big.Big_Integer;
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
      Numerator, Denominator : Big.Big_Integer;
   end record;
   function Exact (Value : Real_Value) return Rational;
   function Exact (Value : Real_Value) return Rational is
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
      Result.Numerator := Big.From_String (Trim (Mantissa'Image));
      Result.Denominator := Big.To_Big_Integer (1);
      if Power >= 0 then
         Result.Numerator := Result.Numerator *
           Big.To_Big_Integer (2) ** Natural (Power);
      else
         Result.Denominator := Big.To_Big_Integer (2) ** Natural (-Power);
      end if;
      return Result;
   end Exact;

   function Rounded (Value : Rational; Scale : Integer) return String;
   function Rounded (Value : Rational; Scale : Integer) return String is
      Numerator : Big.Big_Integer := Value.Numerator;
      Denominator : Big.Big_Integer := Value.Denominator;
      Quotient, Remainder : Big.Big_Integer;
      Two : constant Big.Big_Integer := Big.To_Big_Integer (2);
   begin
      --  Formatting uses exact rational rounding, independently of the host
      --  locale and Ada real I/O conventions. This avoids double rounding
      --  when a short requested precision lies near a decimal halfway case.
      if Scale >= 0 then
         Numerator := Numerator * Big.To_Big_Integer (10) ** Natural (Scale);
      else
         Denominator := Denominator *
           Big.To_Big_Integer (10) ** Natural (-Scale);
      end if;
      Quotient := Numerator / Denominator;
      Remainder := Numerator rem Denominator;
      if Remainder * Two > Denominator or else
        (Remainder * Two = Denominator and then Quotient rem Two /= 0)
      then
         Quotient := Quotient + 1;
      end if;
      return Trim (Big.To_String (Quotient));
   end Rounded;

   function Decimal_Exponent (Value : Rational) return Integer;
   function Decimal_Exponent (Value : Rational) return Integer is
      N : constant String := Trim (Big.To_String (Value.Numerator));
      D : constant String := Trim (Big.To_String (Value.Denominator));
      Result : constant Integer := N'Length - D'Length;
      Lower : Boolean;
   begin
      if Value.Numerator = 0 then
         return 0;
      end if;
      if Result >= 0 then
         Lower := Value.Numerator < Value.Denominator *
           Big.To_Big_Integer (10) ** Natural (Result);
      else
         Lower := Value.Numerator * Big.To_Big_Integer (10) **
           Natural (-Result) < Value.Denominator;
      end if;
      return (if Lower then Result - 1 else Result);
   end Decimal_Exponent;

   function Float_Image
     (Item : Real_Value; Code : Character; Precision : Integer;
      Alternate : Boolean) return String;
   function Float_Image
     (Item : Real_Value; Code : Character; Precision : Integer;
      Alternate : Boolean) return String
   is
      Value : constant Rational := Exact (Item);
      Exponent : Integer := Decimal_Exponent (Value);
      Significant : Natural := (if Precision < 0 then 6 else Precision);
      Text : Unbounded_String;
      Result : Unbounded_String;
      Scientific : Boolean;
      Point : Integer;
   begin
      if Code in 'f' | 'F' then
         Text := To_Unbounded_String (Rounded (Value, Significant));
         while Length (Text) <= Significant loop
            Insert (Text, 1, "0");
         end loop;
         if Significant > 0 then
            Insert (Text, Length (Text) - Significant + 1, ".");
         elsif Alternate then
            Append (Text, '.');
         end if;
         return To_String (Text);
      end if;
      if Code in 'e' | 'E' then
         Significant := Significant + 1;
      elsif Significant = 0 then
         Significant := 1;
      end if;
      Text := To_Unbounded_String
        (Rounded (Value, Integer (Significant) - 1 - Exponent));
      if Length (Text) > Significant then
         Delete (Text, Length (Text), Length (Text));
         Exponent := Exponent + 1;
      end if;
      while Length (Text) < Significant loop
         Insert (Text, 1, "0");
      end loop;
      Scientific := Code in 'e' | 'E' or else
        Exponent < -4 or else Exponent >= Integer (Significant);
      if Code in 'g' | 'G' and then not Alternate then
         while Length (Text) > 1 and then
           Element (Text, Length (Text)) = '0'
         loop
            Delete (Text, Length (Text), Length (Text));
         end loop;
      end if;
      if Scientific then
         Append (Result, Element (Text, 1));
         if Length (Text) > 1 or else Alternate then
            Append (Result, '.');
         end if;
         Append (Result, Slice (Text, 2, Length (Text)));
         Append (Result, (if Code in 'E' | 'G' then 'E' else 'e'));
         Append (Result, (if Exponent < 0 then '-' else '+'));
         declare
            Power : constant String := Trim (Integer'Image (abs Exponent));
         begin
            if Power'Length < 2 then
               Append (Result, '0');
            end if;
            Append (Result, Power);
         end;
      else
         Point := Exponent + 1;
         if Point <= 0 then
            Append (Result, "0.");
            for Index in 1 .. -Point loop
               Append (Result, '0');
            end loop;
            Append (Result, Text);
         elsif Point >= Length (Text) then
            Append (Result, Text);
            for Index in Length (Text) + 1 .. Point loop
               Append (Result, '0');
            end loop;
            if Alternate then
               Append (Result, '.');
            end if;
         else
            Append (Result, Slice (Text, 1, Point));
            Append (Result, '.');
            Append (Result, Slice (Text, Point + 1, Length (Text)));
         end if;
      end if;
      return To_String (Result);
   end Float_Image;

   function Hex_Float
     (Item : Real_Value; Precision : Integer; Alternate : Boolean;
      Host : String)
      return String;
   function Hex_Float
     (Item : Real_Value; Precision : Integer; Alternate : Boolean;
      Host : String)
      return String
   is
      Raw : constant Interfaces.Unsigned_64 := Bits (Item);
      Field : constant Natural := Natural
        (Interfaces.Shift_Right (Raw, 52) and 16#7FF#);
      Exponent : Integer :=
        (if Field = 0 then -1022 else Integer (Field) - 1023);
      Mantissa : Interfaces.Unsigned_64 := Raw and 16#F_FFFF_FFFF_FFFF#;
      Fraction : Unbounded_String;
      Leading : Natural := Boolean'Pos (Field /= 0);
      Result : Unbounded_String;
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
         for Index in reverse 1 .. Precision loop
            Insert (Fraction, 1, String'(1 => Hex
              (Natural (Mantissa mod 16) + 1)));
            Mantissa := Mantissa / 16;
         end loop;
      else
         for Index in 1 .. 13 loop
            Insert (Fraction, 1, String'(1 => Hex
              (Natural (Mantissa mod 16) + 1)));
            Mantissa := Mantissa / 16;
         end loop;
         if Precision < 0 then
            while Length (Fraction) > 0 and then
              Element (Fraction, Length (Fraction)) = '0'
            loop
               Delete (Fraction, Length (Fraction), Length (Fraction));
            end loop;
         else
            for Index in 14 .. Precision loop
               Append (Fraction, '0');
            end loop;
         end if;
      end if;
      Append (Result, "0x" & Hex (Leading + 1));
      if Length (Fraction) > 0 or else Alternate then
         Append (Result, '.');
      end if;
      Append (Result, Fraction);
      Append (Result, 'p');
      Append (Result, (if Exponent < 0 then '-' else '+'));
      Append (Result, Trim (Integer'Image (abs Exponent)));
      return To_String (Result);
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
            Value := Lua.Numbers.Read (Strings.String_Argument (State, Item));
            if Item.Kind = Real_Kind then
               Real := Item.Real_Data;
            elsif Item.Kind = Integer_Kind then
               Real := Real_Value (Item.Integer_Data);
            elsif Value.Kind /= Lua.Numbers.Invalid then
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
               Text.Set_Value (Hex_Float (Real, Precision, Alternate, Host));
            else
               Text.Set_Value (Float_Image (Real, Code, Precision, Alternate));
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
               Text.Set_Value (Image (Item));
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
                  Text.Set_Value
                    ((if (Bits (Real) and 2 ** 63) /= 0 then "-" else "") &
                     Hex_Float (Real, -1, False, Host));
               end if;
            elsif Item.Kind = Integer_Kind and then
              Item.Integer_Data = Integer_Value'First
            then
               Text.Set_Value ("0x8000000000000000");
            elsif Item.Kind in Integer_Kind | Nil_Kind | Boolean_Kind then
               Text.Set_Value (Image (Item));
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
