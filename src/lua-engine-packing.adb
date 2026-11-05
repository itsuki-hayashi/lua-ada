with Ada.Strings.Fixed;
with Ada.Unchecked_Conversion;
with Interfaces;

package body Lua.Engine.Packing is
   use type Integer_Value;
   use type Real_Value;
   use type Interfaces.Unsigned_64;
   use type Interfaces.Unsigned_32;
   use type Lua.Numbers.Number_Kind;
   subtype U64 is Interfaces.Unsigned_64;
   subtype U32 is Interfaces.Unsigned_32;
   type Eight_Bytes is array (1 .. 8) of Character;
   function Bytes is new Ada.Unchecked_Conversion (U64, Eight_Bytes);
   function Integer_Bits is new Ada.Unchecked_Conversion (Integer_Value, U64);
   function Signed_Bits is new Ada.Unchecked_Conversion (U64, Integer_Value);
   function Real_Bits is new Ada.Unchecked_Conversion (Real_Value, U64);
   function From_Real_Bits is new Ada.Unchecked_Conversion (U64, Real_Value);
   Max_Size : constant U64 := U64 (Integer_Value'Last);
   --  Lua lengths are size_t quantities capped to the signed Lua index range.
   --  Keeping them in U64 is essential: packsize can describe virtual strings
   --  much larger than either Ada Natural or the configured allocation quota.

   function Round_Shift (Value : U64; Count : Natural) return U64;
   function To_Single (Value : Real_Value) return U32;
   function From_Single (Value : U32) return Real_Value;

   function Round_Shift (Value : U64; Count : Natural) return U64 is
      Quotient, Remainder, Half : U64;
   begin
      if Count = 0 then
         return Value;
      elsif Count >= 64 then
         return 0;
      end if;
      Quotient := Interfaces.Shift_Right (Value, Count);
      Half := Interfaces.Shift_Left (1, Count - 1);
      Remainder := Value and (2 * Half - 1);
      if Remainder > Half or else
        (Remainder = Half and then (Quotient and 1) /= 0)
      then
         Quotient := Quotient + 1;
      end if;
      return Quotient;
   end Round_Shift;

   function To_Single (Value : Real_Value) return U32 is
      Raw : constant U64 := Real_Bits (Value);
      Sign : constant U32 := U32 (Interfaces.Shift_Right (Raw, 32)) and
        16#8000_0000#;
      Exponent : Integer := Integer
        (Interfaces.Shift_Right (Raw, 52) and 16#7FF#);
      Fraction : U64 := Raw and 16#F_FFFF_FFFF_FFFF#;
      Rounded : U64;
   begin
      --  Convert with explicit IEEE nearest/even rounding rather than asking
      --  an Ada constrained float conversion to accept C's infinity overflow.
      if Exponent = 2047 then
         if Fraction = 0 then
            return Sign or 16#7F80_0000#;
         else
            return Sign or 16#7FC0_0000# or
              U32 (Interfaces.Shift_Right (Fraction, 29));
         end if;
      elsif Exponent = 0 and then Fraction = 0 then
         return Sign;
      elsif Exponent = 0 then
         return Sign;  --  Every binary64 subnormal underflows binary32.
      end if;
      Exponent := Exponent - 1023 + 127;
      Fraction := Fraction or 16#10_0000_0000_0000#;
      if Exponent <= 0 then
         Rounded := Round_Shift (Fraction, Natural (30 - Exponent));
         return Sign or U32 (Rounded);
      end if;
      Rounded := Round_Shift (Fraction, 29);
      if Rounded = 16#100_0000# then
         Rounded := Interfaces.Shift_Right (Rounded, 1);
         Exponent := Exponent + 1;
      end if;
      if Exponent >= 255 then
         return Sign or 16#7F80_0000#;
      end if;
      return Sign or Interfaces.Shift_Left (U32 (Exponent), 23) or
        (U32 (Rounded) and 16#7F_FFFF#);
   end To_Single;

   function From_Single (Value : U32) return Real_Value is
      Sign : constant U64 := Interfaces.Shift_Left
        (U64 (Value and 16#8000_0000#), 32);
      Exponent : Integer := Integer
        (Interfaces.Shift_Right (Value, 23) and 255);
      Fraction : U64 := U64 (Value and 16#7F_FFFF#);
   begin
      --  Expansion is exact; preserve infinities, NaNs, and signed zero as
      --  representations rather than passing exceptional values through Ada
      --  floating-point range conversions.
      if Exponent = 255 then
         return From_Real_Bits (Sign or 16#7FF0_0000_0000_0000# or
           Interfaces.Shift_Left (Fraction, 29));
      elsif Exponent = 0 and then Fraction = 0 then
         return From_Real_Bits (Sign);
      elsif Exponent = 0 then
         Exponent := -126;
         while Fraction < 16#80_0000# loop
            Fraction := Interfaces.Shift_Left (Fraction, 1);
            Exponent := Exponent - 1;
         end loop;
         Fraction := Fraction and 16#7F_FFFF#;
      else
         Exponent := Exponent - 127;
      end if;
      return From_Real_Bits (Sign or
        Interfaces.Shift_Left (U64 (Exponent + 1023), 52) or
        Interfaces.Shift_Left (Fraction, 29));
   end From_Single;

   function Run
     (State : in out World; Name : String; Arguments : Values.Vector)
      return Values.Vector
   is
      type Option_Kind is
        (Signed_Integer, Unsigned_Integer, Single_Real, Double_Real,
         Fixed_String, Length_String, Zero_String, Padding, Align_Only, Noop);
      type Option is record
         Kind : Option_Kind := Noop;
         Size : U64 := 0;
         Alignment : U64 := 0;
      end record;
      Result : Values.Vector;
      Buffer : Unbounded_String;
      Format_Position : Positive := 1;
      Little : Boolean := Character'Pos (Bytes (1) (1)) = 1;
      Max_Alignment : U64 := 1;
      Total : U64 := 0;
      Argument : Positive := 2;
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Arguments.Length) then Arguments (Index)
         else Nil_Value);
      function Text (Index : Positive) return String;
      function Number (Index : Positive) return Lua.Numbers.Number;
      function Integer_Arg (Index : Positive) return Integer_Value;
      procedure Charge (Amount : Natural := 1);
      procedure Grow (Amount : U64);
      procedure Put_Bytes (Raw : U64; Size : Positive; Negative : Boolean);
      function Get_Bytes
        (Data : String; Position : Natural; Size : Positive;
         Signed : Boolean) return U64;
      function Parse_Option (Format : String) return Option;
      function Details (Format : String; Position : U64) return Option;

      function Text (Index : Positive) return String is
         Item : constant Value := Arg (Index);
      begin
         if Item.Kind = String_Kind then
            return To_String (Item.Reference.Bytes);
         elsif Item.Kind in Integer_Kind | Real_Kind then
            return Image (Item);
         end if;
         Fail (State, "string expected");
         return "";
      end Text;

      function Number (Index : Positive) return Lua.Numbers.Number is
         Item : constant Value := Arg (Index);
         Parsed : Lua.Numbers.Number;
      begin
         case Item.Kind is
            when Integer_Kind =>
               return (Lua.Numbers.Integer_Number, Item.Integer_Data);
            when Real_Kind =>
               return (Lua.Numbers.Real_Number, Item.Real_Data);
            when String_Kind =>
               Charge (Length (Item.Reference.Bytes));
               Parsed := Lua.Numbers.Read (To_String (Item.Reference.Bytes));
            when others => Parsed := (Kind => Lua.Numbers.Invalid);
         end case;
         if Parsed.Kind = Lua.Numbers.Invalid then
            Fail (State, "number expected");
         end if;
         return Parsed;
      end Number;

      function Integer_Arg (Index : Positive) return Integer_Value is
         Parsed : constant Lua.Numbers.Number := Number (Index);
         Real : Real_Value;
      begin
         if Parsed.Kind = Lua.Numbers.Integer_Number then
            return Parsed.Integer_Item;
         end if;
         Real := Parsed.Real_Item;
         if Real = Real and then Real_Value'Floor (Real) = Real and then
           not Lua.Numbers.Less
             (Parsed, (Lua.Numbers.Integer_Number, Integer_Value'First))
           and then not Lua.Numbers.Less
             ((Lua.Numbers.Integer_Number, Integer_Value'Last), Parsed)
         then
            return Integer_Value (Real);
         end if;
         Fail (State, "number has no integer representation");
         return 0;
      end Integer_Arg;

      procedure Charge (Amount : Natural := 1) is
      begin
         if State.Steps > State.Bounds.Instructions or else
           Amount > State.Bounds.Instructions - State.Steps
         then
            Fail (State, "instruction budget exceeded", True);
         end if;
         State.Steps := State.Steps + Amount;
      end Charge;

      procedure Grow (Amount : U64) is
      begin
         --  A virtual size is checked independently of output allocation.
         --  Semantic overflow stays catchable Lua failure; quota exhaustion
         --  remains the interpreter's nonrecoverable execution resource error.
         if Amount > Max_Size - Total then
            Fail (State, (if Name = "packsize" then "format result too large"
                          else "result too long"));
         end if;
         Total := Total + Amount;
      end Grow;

      procedure Put_Bytes (Raw : U64; Size : Positive; Negative : Boolean) is
         Data : String (1 .. Size);
         Remaining : U64 := Raw;
         Byte : Natural;
      begin
         for Index in 0 .. Size - 1 loop
            Charge;
            Byte := (if Index >= 8 and then Negative then 255
                     else Natural (Remaining and 255));
            Data ((if Little then Index + 1 else Size - Index)) :=
              Character'Val (Byte);
            Remaining := Interfaces.Shift_Right (Remaining, 8);
         end loop;
         Append (Buffer, Data);
      end Put_Bytes;

      function Get_Bytes
        (Data : String; Position : Natural; Size : Positive;
         Signed : Boolean) return U64
      is
         Raw : U64 := 0;
         Byte, Expected : Natural;
      begin
         for Index in reverse 0 .. Natural'Min (Size, 8) - 1 loop
            Charge;
            Byte := Character'Pos (Data
              (Position + (if Little then Index + 1 else Size - Index)));
            Raw := Interfaces.Shift_Left (Raw, 8) or U64 (Byte);
         end loop;
         if Size < 8 and then Signed then
            if (Raw and Interfaces.Shift_Left (1, Size * 8 - 1)) /= 0 then
               Raw := Raw or not (Interfaces.Shift_Left (1, Size * 8) - 1);
            end if;
         elsif Size > 8 then
            Expected := (if Signed and then Signed_Bits (Raw) < 0
                         then 255 else 0);
            for Index in 8 .. Size - 1 loop
               Charge;
               Byte := Character'Pos (Data
                 (Position + (if Little then Index + 1 else Size - Index)));
               if Byte /= Expected then
                  Fail (State, Ada.Strings.Fixed.Trim
                    (Size'Image, Ada.Strings.Both) &
                      "-byte integer does not fit into Lua Integer");
               end if;
            end loop;
         end if;
         return Raw;
      end Get_Bytes;

      function Parse_Option (Format : String) return Option is
         Item : Option;
         Code : Character;
         function Read_Size (Default : U64) return U64;
         function Integral_Size (Default : U64) return U64;

         function Read_Size (Default : U64) return U64 is
            Value : U64 := 0;
            Found : Boolean := False;
            Digit : U64;
         begin
            while Format_Position <= Format'Last and then
              Format (Format_Position) in '0' .. '9'
            loop
               Charge;
               Found := True;
               Digit := U64 (Character'Pos (Format (Format_Position)) - 48);
               if Value > (Max_Size - Digit) / 10 then
                  Fail (State, "invalid format option size");
               end if;
               Value := Value * 10 + Digit;
               Format_Position := Format_Position + 1;
            end loop;
            return (if Found then Value else Default);
         end Read_Size;

         function Integral_Size (Default : U64) return U64 is
            Size : constant U64 := Read_Size (Default);
         begin
            if Size < 1 or else Size > 16 then
               Fail (State, "integral size (" & Ada.Strings.Fixed.Trim
                 (Size'Image, Ada.Strings.Both) & ") out of limits [1,16]");
            end if;
            return Size;
         end Integral_Size;
      begin
         Charge;
         Code := Format (Format_Position);
         Format_Position := Format_Position + 1;
         case Code is
            when 'b' | 'B' =>
               Item.Size := 1;
               Item.Kind := (if Code = 'b' then Signed_Integer
                             else Unsigned_Integer);
            when 'h' | 'H' =>
               Item.Size := Short_Bytes;
               Item.Kind := (if Code = 'h' then Signed_Integer
                             else Unsigned_Integer);
            when 'l' | 'L' =>
               Item.Size := Long_Bytes;
               Item.Kind := (if Code = 'l' then Signed_Integer
                             else Unsigned_Integer);
            when 'j' | 'J' | 'T' =>
               Item.Size := (if Code = 'T' then Size_Bytes else 8);
               Item.Kind := (if Code = 'j' then Signed_Integer
                             else Unsigned_Integer);
            when 'i' | 'I' | 's' =>
               Item.Size := Integral_Size
                 ((if Code = 's' then Size_Bytes else Int_Bytes));
               Item.Kind := (if Code = 'i' then Signed_Integer
                             elsif Code = 'I' then Unsigned_Integer
                             else Length_String);
            when 'f' => Item := (Single_Real, Float_Bytes, 0);
            when 'd' => Item := (Double_Real, Double_Bytes, 0);
            when 'n' => Item := (Double_Real, 8, 0);
            when 'c' =>
               Item.Kind := Fixed_String;
               Item.Size := Read_Size (U64'Last);
               if Item.Size = U64'Last then
                  Fail (State, "missing size for format option 'c'");
               end if;
            when 'z' => Item.Kind := Zero_String;
            when 'x' => Item := (Padding, 1, 0);
            when 'X' => Item.Kind := Align_Only;
            when '<' => Little := True;
            when '>' => Little := False;
            when '=' => Little := Character'Pos (Bytes (1) (1)) = 1;
            when '!' =>
               Max_Alignment := Integral_Size (U64 (Maximum_Alignment));
            when ' ' => null;
            when others =>
               Fail (State, "invalid format option '" & Code & "'");
         end case;
         return Item;
      end Parse_Option;

      function Details (Format : String; Position : U64) return Option is
         Item : Option := Parse_Option (Format);
         Alignment : U64 := Item.Size;
         Following : Option;
      begin
         if Item.Kind = Align_Only then
            if Format_Position > Format'Last then
               Fail (State, "invalid next option for option 'X'");
            end if;
            Following := Parse_Option (Format);
            Alignment := Following.Size;
            if Following.Kind = Fixed_String or else Alignment = 0 then
               Fail (State, "invalid next option for option 'X'");
            end if;
         end if;
         if Alignment > 1 and then Item.Kind /= Fixed_String then
            Alignment := U64'Min (Alignment, Max_Alignment);
            if (Alignment and (Alignment - 1)) /= 0 then
               Fail (State, "format asks for alignment not power of 2");
            end if;
            Item.Alignment := (Alignment - Position mod Alignment) mod
              Alignment;
         end if;
         return Item;
      end Details;
   begin
      declare
         Raw_Format : constant String := Text (1);
         End_Position : Natural := Raw_Format'Last;
      begin
         --  Format options are C-string syntax even though payload strings
         --  remain binary. Embedded NUL terminates the format, as upstream.
         for Index in Raw_Format'Range loop
            if Raw_Format (Index) = Character'Val (0) then
               End_Position := Index - 1;
               exit;
            end if;
         end loop;
         declare
            Format : constant String := Raw_Format (1 .. End_Position);
            Data : constant String := (if Name = "unpack" then Text (2)
                                       else "");
            Position : U64 := 0;
            Item : Option;
            Raw : U64;
            Number_Value : Integer_Value;
            Count : U64;
         begin
            if Name = "unpack" then
               Number_Value := (if Arg (3).Kind = Nil_Kind then 1
                                else Integer_Arg (3));
               if Number_Value < 0 then
                  Number_Value := (if Number_Value < -Integer_Value
                    (Data'Length) then 1
                    else Integer_Value (Data'Length) + Number_Value + 1);
               elsif Number_Value = 0 then
                  Number_Value := 1;
               end if;
               Position := U64 (Number_Value - 1);
               if Position > U64 (Data'Length) then
                  Fail (State, "initial position out of string");
               end if;
            end if;
            while Format_Position <= Format'Last loop
               Item := Details (Format,
                 (if Name = "unpack" then Position else Total));
               if Name = "packsize" then
                  if Item.Kind in Length_String | Zero_String then
                     Fail (State, "variable-length format");
                  end if;
                  Grow (Item.Size + Item.Alignment);
               elsif Name = "pack" then
                  Grow (Item.Size + Item.Alignment);
                  if Total > U64 (State.Bounds.String_Bytes) then
                     Fail (State, "string byte limit exceeded", True);
                  end if;
                  Append (Buffer, String'
                    (1 .. Natural (Item.Alignment) => Character'Val (0)));
                  case Item.Kind is
                     when Signed_Integer | Unsigned_Integer =>
                        Number_Value := Integer_Arg (Argument);
                        Raw := Integer_Bits (Number_Value);
                        if Item.Size < 8 then
                           if Item.Kind = Signed_Integer then
                              declare
                                 Limit : constant Integer_Value :=
                                   2 ** (Natural (Item.Size) * 8 - 1);
                              begin
                                 if Number_Value < -Limit or else
                                   Number_Value >= Limit
                                 then
                                    Fail (State, "integer overflow");
                                 end if;
                              end;
                           elsif Raw >= 2 ** (Natural (Item.Size) * 8) then
                              Fail (State, "unsigned overflow");
                           end if;
                        end if;
                        Put_Bytes (Raw, Positive (Item.Size),
                          Item.Kind = Signed_Integer and Number_Value < 0);
                     when Single_Real | Double_Real =>
                        declare
                           Real : constant Real_Value :=
                             Lua.Numbers.To_Real (Number (Argument));
                        begin
                           Raw := (if Item.Kind = Single_Real
                                   then U64 (To_Single (Real))
                                   else Real_Bits (Real));
                           Put_Bytes (Raw, Positive (Item.Size), False);
                        end;
                     when Fixed_String | Length_String | Zero_String =>
                        declare
                           Payload : constant String := Text (Argument);
                        begin
                           Count := U64 (Payload'Length);
                           if Item.Kind = Fixed_String then
                              if Count > Item.Size then
                                 Fail (State, "string longer than given size");
                              end if;
                              Charge (Natural (Item.Size));
                              Append (Buffer, Payload);
                              Append (Buffer, String'
                                (1 .. Natural (Item.Size - Count) =>
                                   Character'Val (0)));
                           elsif Item.Kind = Length_String then
                              if Item.Size < 8 and then
                                Count >= 2 ** (Natural (Item.Size) * 8)
                              then
                                 Fail (State, "string length does not fit");
                              end if;
                              Grow (Count);
                              if Total > U64 (State.Bounds.String_Bytes) then
                                 Fail
                                   (State, "string byte limit exceeded", True);
                              end if;
                              Put_Bytes (Count, Positive (Item.Size), False);
                              Charge (Natural (Count));
                              Append (Buffer, Payload);
                           else
                              for Byte of Payload loop
                                 Charge;
                                 if Byte = Character'Val (0) then
                                    Fail (State, "string contains zeros");
                                 end if;
                              end loop;
                              Grow (Count + 1);
                              if Total > U64 (State.Bounds.String_Bytes) then
                                 Fail
                                   (State, "string byte limit exceeded", True);
                              end if;
                              Append (Buffer, Payload & Character'Val (0));
                           end if;
                        end;
                     when Padding => Append (Buffer, Character'Val (0));
                     when Align_Only | Noop => null;
                  end case;
                  if Item.Kind not in Padding | Align_Only | Noop then
                     Argument := Argument + 1;
                  end if;
               elsif Name = "unpack" then
                  if Item.Alignment + Item.Size > U64 (Data'Length) -
                    Position
                  then
                     Fail (State, "data string too short");
                  end if;
                  Position := Position + Item.Alignment;
                  case Item.Kind is
                     when Signed_Integer | Unsigned_Integer =>
                        Raw := Get_Bytes (Data, Natural (Position),
                          Positive (Item.Size), Item.Kind = Signed_Integer);
                        Result.Append
                          (Value'(Integer_Kind, Signed_Bits (Raw)));
                     when Single_Real | Double_Real =>
                        Raw := Get_Bytes (Data, Natural (Position),
                                          Positive (Item.Size), False);
                        Result.Append (Value'
                          (Real_Kind, (if Item.Kind = Single_Real
                                       then From_Single (U32 (Raw))
                                       else From_Real_Bits (Raw))));
                     when Fixed_String =>
                        Charge (Natural (Item.Size));
                        Result.Append (New_String (State, Data
                          (Natural (Position) + 1 ..
                           Natural (Position + Item.Size))));
                     when Length_String =>
                        Count := Get_Bytes (Data, Natural (Position),
                                           Positive (Item.Size), False);
                        Position := Position + Item.Size;
                        if Count > U64 (Data'Length) - Position then
                           Fail (State, "data string too short");
                        end if;
                        Charge (Natural (Count));
                        Result.Append (New_String (State, Data
                          (Natural (Position) + 1 ..
                           Natural (Position + Count))));
                        Position := Position + Count;
                        Item.Size := 0;
                     when Zero_String =>
                        Count := Position;
                        while Position < U64 (Data'Length) and then
                          Data (Natural (Position) + 1) /= Character'Val (0)
                        loop
                           Charge;
                           Position := Position + 1;
                        end loop;
                        if Position = U64 (Data'Length) then
                           Fail (State, "unfinished string for format 'z'");
                        end if;
                        Result.Append (New_String (State, Data
                          (Natural (Count) + 1 .. Natural (Position))));
                        Position := Position + 1;
                     when Padding | Align_Only | Noop => null;
                  end case;
                  Position := Position + Item.Size;
               else
                  raise Program_Error with "unknown packing action";
               end if;
            end loop;
            if Name = "packsize" then
               Result.Append (Value'(Integer_Kind, Integer_Value (Total)));
            elsif Name = "pack" then
               Result.Append (New_String (State, To_String (Buffer)));
            else
               Result.Append
                 (Value'(Integer_Kind, Integer_Value (Position) + 1));
            end if;
         end;
      end;
      return Result;
   end Run;
end Lua.Engine.Packing;
