with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Lua.Lexers is
   package Latin renames Ada.Characters.Latin_1;

   function Is_Digit (Item : Character) return Boolean is
     (Item in '0' .. '9');

   function Is_Letter (Item : Character) return Boolean is
     (Item in 'a' .. 'z' | 'A' .. 'Z' | '_');

   function Is_Space (Item : Character) return Boolean is
     (Item in ' ' | Latin.HT | Latin.LF | Latin.CR | Latin.VT | Latin.FF);

   function Hex_Value (Item : Character) return Integer is
     (case Item is
         when '0' .. '9' => Character'Pos (Item) - Character'Pos ('0'),
         when 'a' .. 'f' => Character'Pos (Item) - Character'Pos ('a') + 10,
         when 'A' .. 'F' => Character'Pos (Item) - Character'Pos ('A') + 10,
         when others    => -1);

   function Keyword (Text : String) return Token_Kind;

   function Keyword (Text : String) return Token_Kind is
   begin
      for Kind in And_Word .. While_Word loop
         declare
            Image : constant String := Token_Kind'Image (Kind);
            Name  : String := Image (Image'First .. Image'Last - 5);
         begin
            for Item of Name loop
               Item := Character'Val (Character'Pos (Item) + 32);
            end loop;
            if Text = Name then
               return Kind;
            end if;
         end;
      end loop;
      return Identifier;
   end Keyword;

   function Scan
     (Source         : String;
      Maximum_Tokens : Positive := 100_000) return Scan_Result
   is
      Input  : constant String (1 .. Source'Length) := Source;
      Result : Scan_Result;
      Cursor : Source_Location;
      Failed : exception;

      procedure Advance;
      procedure Fail
        (Message : String; Status : Scan_Status := Syntax_Error);
      procedure Emit
        (Kind : Token_Kind; Start : Source_Location; Text : String);
      function Long_Level return Integer;
      procedure Long_String
        (Level : Natural; Text : out Unbounded_String);
      procedure Append_UTF8
        (Text : in out Unbounded_String; Value : Natural);
      procedure Quoted_String (Text : out Unbounded_String);

      function Peek (Ahead : Natural := 0) return Character is
        (if Ahead < Input'Length and then
            Cursor.Offset <= Input'Last - Ahead
         then Input (Cursor.Offset + Ahead) else Latin.NUL);

      procedure Advance is
         Old : constant Character := Peek;
      begin
         Cursor.Offset := Cursor.Offset + 1;
         if Old in Latin.CR | Latin.LF then
            if Cursor.Offset <= Input'Last and then
              Peek in Latin.CR | Latin.LF and then Peek /= Old
            then
               Cursor.Offset := Cursor.Offset + 1;
            end if;
            Cursor.Line := Cursor.Line + 1;
            Cursor.Column := 1;
         else
            Cursor.Column := Cursor.Column + 1;
         end if;
      end Advance;

      procedure Fail
        (Message : String; Status : Scan_Status := Syntax_Error)
      is
      begin
         Result.Status := Status;
         Result.Location := Cursor;
         Result.Message := To_Unbounded_String (Message);
         raise Failed;
      end Fail;

      procedure Emit
        (Kind : Token_Kind; Start : Source_Location; Text : String)
      is
      begin
         if Natural (Result.Tokens.Length) = Maximum_Tokens then
            Fail ("token limit exceeded", Resource_Error);
         end if;
         Result.Tokens.Append
           (Token'(Kind, Start, To_Unbounded_String (Text)));
      end Emit;

      function Long_Level return Integer is
         Ahead : Natural := 1;
      begin
         if Peek /= '[' then
            return -1;
         end if;
         while Peek (Ahead) = '=' loop
            Ahead := Ahead + 1;
         end loop;
         return (if Peek (Ahead) = '[' then Integer (Ahead - 1) else -1);
      end Long_Level;

      procedure Long_String
        (Level : Natural; Text : out Unbounded_String)
      is
      begin
         Text := Null_Unbounded_String;
         for Index in 1 .. Level + 2 loop
            Advance;
         end loop;
         if Peek in Latin.CR | Latin.LF then
            Advance;
         end if;
         loop
            if Cursor.Offset > Input'Last then
               Fail ("unfinished long string or comment");
            end if;
            if Peek = ']' then
               declare
                  Ahead : Natural := 1;
               begin
                  while Peek (Ahead) = '=' loop
                     Ahead := Ahead + 1;
                  end loop;
                  if Ahead = Level + 1 and then Peek (Ahead) = ']' then
                     for Index in 1 .. Level + 2 loop
                        Advance;
                     end loop;
                     return;
                  end if;
               end;
            end if;
            Append (Text, (if Peek in Latin.CR | Latin.LF
                           then Latin.LF else Peek));
            Advance;
         end loop;
      end Long_String;

      procedure Append_UTF8
        (Text : in out Unbounded_String; Value : Natural)
      is
         Remaining : Natural := Value;
         Bytes     : String (1 .. 6);
         First     : Positive := Bytes'Last;
         Prefix    : Natural := 16#80#;
         Capacity  : Natural := 16#40#;
      begin
         if Value < 16#80# then
            Append (Text, Character'Val (Value));
            return;
         end if;
         --  Lua accepts extended UTF-8 values through 0x7fffffff.
         loop
            Bytes (First) := Character'Val (16#80# + Remaining mod 64);
            Remaining := Remaining / 64;
            First := First - 1;
            Prefix := Prefix + Capacity;
            Capacity := Capacity / 2;
            exit when Remaining < Capacity;
         end loop;
         Bytes (First) := Character'Val (Prefix + Remaining);
         Append (Text, Bytes (First .. Bytes'Last));
      end Append_UTF8;

      procedure Quoted_String (Text : out Unbounded_String) is
         Quote : constant Character := Peek;
         Value : Natural;
         Count : Natural;
         Code  : Character;
      begin
         Text := Null_Unbounded_String;
         Advance;
         while Peek /= Quote loop
            if Cursor.Offset > Input'Last or else
              Peek in Latin.CR | Latin.LF
            then
               Fail ("unfinished string");
            end if;
            if Peek /= '\' then
               Append (Text, Peek);
               Advance;
            else
               Advance;
               Code := Peek;
               case Code is
                  when 'a' => Append (Text, Latin.BEL); Advance;
                  when 'b' => Append (Text, Latin.BS); Advance;
                  when 'f' => Append (Text, Latin.FF); Advance;
                  when 'n' => Append (Text, Latin.LF); Advance;
                  when 'r' => Append (Text, Latin.CR); Advance;
                  when 't' => Append (Text, Latin.HT); Advance;
                  when 'v' => Append (Text, Latin.VT); Advance;
                  when '\' | '"' | ''' =>
                     Append (Text, Code); Advance;
                  when Latin.CR | Latin.LF =>
                     Append (Text, Latin.LF); Advance;
                  when 'z' =>
                     Advance;
                     while Is_Space (Peek) loop
                        Advance;
                     end loop;
                  when 'x' =>
                     Advance;
                     Value := 0;
                     for Index in 1 .. 2 loop
                        if Hex_Value (Peek) < 0 then
                           Fail ("hexadecimal digit expected");
                        end if;
                        Value := Value * 16 + Hex_Value (Peek);
                        Advance;
                     end loop;
                     Append (Text, Character'Val (Value));
                  when 'u' =>
                     Advance;
                     if Peek /= '{' then
                        Fail ("missing '{' in Unicode escape");
                     end if;
                     Advance;
                     Value := 0;
                     Count := 0;
                     while Hex_Value (Peek) >= 0 loop
                        if Value > (16#7FFF_FFFF# -
                          Hex_Value (Peek)) / 16
                        then
                           Fail ("Unicode escape is too large");
                        end if;
                        Value := Value * 16 + Hex_Value (Peek);
                        Count := Count + 1;
                        Advance;
                     end loop;
                     if Count = 0 or else Peek /= '}' then
                        Fail ("invalid Unicode escape");
                     end if;
                     Advance;
                     Append_UTF8 (Text, Value);
                  when '0' .. '9' =>
                     Value := 0;
                     Count := 0;
                     while Count < 3 and then Is_Digit (Peek) loop
                        Value := Value * 10 + Character'Pos (Peek) -
                          Character'Pos ('0');
                        Count := Count + 1;
                        Advance;
                     end loop;
                     if Value > 255 then
                        Fail ("decimal escape is too large");
                     end if;
                     Append (Text, Character'Val (Value));
                  when others => Fail ("invalid escape sequence");
               end case;
            end if;
         end loop;
         Advance;
      end Quoted_String;

      Start : Source_Location;
      Kind  : Token_Kind;
      Text  : Unbounded_String;
      Level : Integer;
   begin
      while Cursor.Offset <= Input'Last loop
         Start := Cursor;
         if Is_Space (Peek) then
            Advance;
         elsif Peek = '-' and then Peek (1) = '-' then
            Advance;
            Advance;
            Level := Long_Level;
            if Level >= 0 then
               Long_String (Level, Text);
            else
               while Cursor.Offset <= Input'Last and then
                 Peek not in Latin.CR | Latin.LF
               loop
                  Advance;
               end loop;
            end if;
         elsif Is_Letter (Peek) then
            while Is_Letter (Peek) or else Is_Digit (Peek) loop
               Advance;
            end loop;
            declare
               Name : constant String :=
                 Input (Start.Offset .. Cursor.Offset - 1);
            begin
               Emit (Keyword (Name), Start, Name);
            end;
         elsif Is_Digit (Peek) or else
           (Peek = '.' and then Is_Digit (Peek (1)))
         then
            loop
               if Peek in 'e' | 'E' | 'p' | 'P' then
                  Advance;
                  if Peek in '+' | '-' then
                     Advance;
                  end if;
               elsif Is_Letter (Peek) or else Is_Digit (Peek) or else
                 Peek = '.'
               then
                  Advance;
               else
                  exit;
               end if;
            end loop;
            --  Numeric grammar/range validation belongs to the number parser.
            Emit (Number_Literal, Start,
                  Input (Start.Offset .. Cursor.Offset - 1));
         elsif Peek in '"' | ''' then
            Quoted_String (Text);
            Emit (String_Literal, Start, To_String (Text));
         elsif Long_Level >= 0 then
            Long_String (Long_Level, Text);
            Emit (String_Literal, Start, To_String (Text));
         elsif Peek = '[' and then Peek (1) = '=' then
            Fail ("invalid long string delimiter");
         else
            case Peek is
               when '+' => Kind := Plus;
               when '-' => Kind := Minus;
               when '*' => Kind := Star;
               when '/' => Kind := Slash;
               when '%' => Kind := Percent;
               when '^' => Kind := Power;
               when '#' => Kind := Length;
               when '&' => Kind := Bit_And;
               when '|' => Kind := Bit_Or;
               when '~' => Kind := Bit_Xor;
               when '=' => Kind := Assign;
               when '<' => Kind := Less;
               when '>' => Kind := Greater;
               when '(' => Kind := Left_Paren;
               when ')' => Kind := Right_Paren;
               when '{' => Kind := Left_Brace;
               when '}' => Kind := Right_Brace;
               when '[' => Kind := Left_Bracket;
               when ']' => Kind := Right_Bracket;
               when ';' => Kind := Semicolon;
               when ':' => Kind := Colon;
               when ',' => Kind := Comma;
               when '.' => Kind := Dot;
               when others => Fail ("unexpected source byte");
            end case;
            Advance;
            case Kind is
               when Slash =>
                  if Peek = '/' then
                     Kind := Floor_Divide; Advance;
                  end if;
               when Assign | Bit_Xor | Less | Greater =>
                  if Peek = '=' then
                     Kind := (case Kind is
                                when Assign => Equal,
                                when Bit_Xor => Not_Equal,
                                when Less => Less_Equal,
                                when others => Greater_Equal);
                     Advance;
                  elsif Kind = Less and then Peek = '<' then
                     Kind := Shift_Left; Advance;
                  elsif Kind = Greater and then Peek = '>' then
                     Kind := Shift_Right; Advance;
                  end if;
               when Colon =>
                  if Peek = ':' then
                     Kind := Double_Colon; Advance;
                  end if;
               when Dot =>
                  if Peek = '.' then
                     Kind := Concatenate; Advance;
                     if Peek = '.' then
                        Kind := Varargs; Advance;
                     end if;
                  end if;
               when others => null;
            end case;
            Emit (Kind, Start, Input (Start.Offset .. Cursor.Offset - 1));
         end if;
      end loop;
      Emit (End_Of_Input, Cursor, "");
      return Result;
   exception
      when Failed =>
         Result.Tokens.Clear;
         return Result;
      when Storage_Error =>
         Result.Tokens.Clear;
         Result.Status := Resource_Error;
         Result.Location := Cursor;
         Result.Message := To_Unbounded_String ("scanner storage exhausted");
         return Result;
   end Scan;
end Lua.Lexers;
