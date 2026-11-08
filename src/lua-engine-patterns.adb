with Ada.Characters.Latin_1;
with Interfaces.C;
with Lua.Platform_Locales;

package body Lua.Engine.Patterns is
   use type Interfaces.C.int;
   function Find
     (State : in out World; Subject, Pattern : String;
      Start : Natural := 0; Allow_Anchor : Boolean := True)
      return Match_Result
   is
      S : constant String (1 .. Subject'Length) := Subject;
      P : constant String (1 .. Pattern'Length) := Pattern;
      Result : Match_Result;
      Anchored : constant Boolean := Allow_Anchor and then
        P'Length > 0 and then P (1) = '^';

      procedure Work (Count : Natural := 1);
      function Class (Byte, Code : Character) return Boolean;
      function Class_End (At_Pos : Natural) return Natural;
      function Bracket
        (Byte : Character; First, After : Natural) return Boolean;
      function Single
        (At_Pos, Pattern_Pos, After : Natural) return Boolean;
      function Match
        (At_Pos, Pattern_Pos : Natural; Captures : in out Match_Result;
         Depth : Natural := 0) return Integer;

      procedure Work (Count : Natural := 1) is
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

      function Class (Byte, Code : Character) return Boolean is
         Lower : constant Character :=
           (if Code in 'A' .. 'Z' then
              Character'Val (Character'Pos (Code) + 32) else Code);
         Hit : Boolean;
         function Native
           (Category : Lua.Platform_Locales.Character_Class) return Boolean
         is (Lua.Platform_Locales.Matches
               (Interfaces.C.unsigned_char (Character'Pos (Byte)), Category)
             /= 0);
      begin
         --  Pattern grammar and uppercase inversion remain Ada operations.
         --  Only the recognized byte classes consult libc's current ctype
         --  category, matching os.setlocale without changing lexer policy.
         case Lower is
            when 'a' => Hit := Native (Lua.Platform_Locales.Alphabetic);
            when 'c' => Hit := Native (Lua.Platform_Locales.Control);
            when 'd' => Hit := Native (Lua.Platform_Locales.Decimal);
            when 'g' => Hit := Native (Lua.Platform_Locales.Graphic);
            when 'l' => Hit := Native (Lua.Platform_Locales.Lowercase);
            when 'p' => Hit := Native (Lua.Platform_Locales.Punctuation);
            when 's' => Hit := Native (Lua.Platform_Locales.Whitespace);
            when 'u' => Hit := Native (Lua.Platform_Locales.Uppercase);
            when 'w' => Hit := Native (Lua.Platform_Locales.Alphanumeric);
            when 'x' => Hit := Native (Lua.Platform_Locales.Hexadecimal);
            when 'z' => Hit := Byte = Ada.Characters.Latin_1.NUL;
            when others => return Byte = Code;
         end case;
         return (if Code in 'A' .. 'Z' then not Hit else Hit);
      end Class;

      function Class_End (At_Pos : Natural) return Natural is
         Cursor : Natural := At_Pos + 1;
      begin
         if P (At_Pos + 1) = '%' then
            if Cursor = P'Length then
               Fail (State, "malformed pattern (ends with '%')");
            end if;
            return Cursor + 1;
         elsif P (At_Pos + 1) /= '[' then
            return Cursor;
         end if;
         if Cursor < P'Length and then P (Cursor + 1) = '^' then
            Cursor := Cursor + 1;
         end if;
         --  The first ] is a literal member. Consume at least one bracket
         --  member before recognizing the closing delimiter.
         loop
            Work;
            if Cursor >= P'Length then
               Fail (State, "malformed pattern (missing ']')");
            end if;
            if P (Cursor + 1) = '%' and then Cursor + 1 < P'Length then
               Cursor := Cursor + 1;
            end if;
            Cursor := Cursor + 1;
            exit when Cursor < P'Length and then P (Cursor + 1) = ']';
         end loop;
         return Cursor + 1;
      end Class_End;

      function Bracket
        (Byte : Character; First, After : Natural) return Boolean
      is
         Cursor : Natural := First + 1;
         Negated : constant Boolean := Cursor < After - 1 and then
           P (Cursor + 1) = '^';
         Hit : Boolean := False;
      begin
         if Negated then
            Cursor := Cursor + 1;
         end if;
         while Cursor < After - 1 loop
            Work;
            if P (Cursor + 1) = '%' then
               Cursor := Cursor + 1;
               Hit := Class (Byte, P (Cursor + 1));
            elsif Cursor + 2 < After - 1 and then
              P (Cursor + 2) = '-'
            then
               Hit := P (Cursor + 1) <= Byte and then
                 Byte <= P (Cursor + 3);
               Cursor := Cursor + 2;
            else
               Hit := Byte = P (Cursor + 1);
            end if;
            exit when Hit;
            Cursor := Cursor + 1;
         end loop;
         return Hit /= Negated;
      end Bracket;

      function Single
        (At_Pos, Pattern_Pos, After : Natural) return Boolean
      is
      begin
         Work;
         if At_Pos >= S'Length then
            return False;
         end if;
         case P (Pattern_Pos + 1) is
            when '.' => return True;
            when '%' => return Class
              (S (At_Pos + 1), P (Pattern_Pos + 2));
            when '[' => return Bracket
              (S (At_Pos + 1), Pattern_Pos, After);
            when others => return S (At_Pos + 1) = P (Pattern_Pos + 1);
         end case;
      end Single;

      function Match
        (At_Pos, Pattern_Pos : Natural; Captures : in out Match_Result;
         Depth : Natural := 0) return Integer
      is
         Cursor : Natural := At_Pos;
         Pattern_Cursor : Natural := Pattern_Pos;
         After, Last, Index, Minimum : Natural;
         Length : Natural;
         Attempt : Integer;
         Saved : Match_Result;
         Code, Suffix : Character;
         Previous, Following : Character;
      begin
         --  Ordinary matching is iterative. Only choices/captures recurse;
         --  a fixed Lua-compatible depth guard bounds the Ada call stack.
         if Depth >= 200 then
            Fail (State, "pattern too complex");
         end if;
         loop
            Work;
            if Pattern_Cursor = P'Length then
               return Integer (Cursor);
            end if;
            Code := P (Pattern_Cursor + 1);
            if Code = '(' then
               if Captures.Count = Maximum_Captures then
                  Fail (State, "too many captures");
               end if;
               Saved := Captures;
               Captures.Count := Captures.Count + 1;
               Captures.Captures (Captures.Count) := (Cursor, -2);
               if Pattern_Cursor + 1 < P'Length and then
                 P (Pattern_Cursor + 2) = ')'
               then
                  Captures.Captures (Captures.Count).Length := -1;
                  After := Pattern_Cursor + 2;
               else
                  After := Pattern_Cursor + 1;
               end if;
               Attempt := Match (Cursor, After, Captures, Depth + 1);
               if Attempt < 0 then
                  Captures := Saved;
               end if;
               return Attempt;
            elsif Code = ')' then
               Index := Captures.Count;
               while Index > 0 and then
                 Captures.Captures (Index).Length /= -2
               loop
                  Index := Index - 1;
               end loop;
               if Index = 0 then
                  Fail (State, "invalid pattern capture");
               end if;
               Saved := Captures;
               Captures.Captures (Index).Length :=
                 Integer (Cursor - Captures.Captures (Index).First);
               Attempt := Match
                 (Cursor, Pattern_Cursor + 1, Captures, Depth + 1);
               if Attempt < 0 then
                  Captures := Saved;
               end if;
               return Attempt;
            elsif Code = '$' and then Pattern_Cursor + 1 = P'Length then
               return (if Cursor = S'Length then Integer (Cursor) else -1);
            elsif Code = '%' and then Pattern_Cursor + 1 < P'Length and then
              P (Pattern_Cursor + 2) = 'b'
            then
               if Pattern_Cursor + 3 >= P'Length then
                  Fail (State,
                        "malformed pattern (missing arguments to '%b')");
               end if;
               if Cursor >= S'Length or else
                 S (Cursor + 1) /= P (Pattern_Cursor + 3)
               then
                  return -1;
               end if;
               Length := 1;
               Cursor := Cursor + 1;
               while Cursor < S'Length loop
                  Work;
                  if S (Cursor + 1) = P (Pattern_Cursor + 4) then
                     Length := Length - 1;
                  elsif S (Cursor + 1) = P (Pattern_Cursor + 3) then
                     Length := Length + 1;
                  end if;
                  Cursor := Cursor + 1;
                  exit when Length = 0;
               end loop;
               if Length /= 0 then
                  return -1;
               end if;
               Pattern_Cursor := Pattern_Cursor + 4;
            elsif Code = '%' and then Pattern_Cursor + 1 < P'Length and then
              P (Pattern_Cursor + 2) = 'f'
            then
               Pattern_Cursor := Pattern_Cursor + 2;
               if Pattern_Cursor >= P'Length or else
                 P (Pattern_Cursor + 1) /= '['
               then
                  Fail (State, "missing '[' after '%f' in pattern");
               end if;
               After := Class_End (Pattern_Cursor);
               Previous := (if Cursor = 0 then Ada.Characters.Latin_1.NUL
                            else S (Cursor));
               Following := (if Cursor = S'Length
                             then Ada.Characters.Latin_1.NUL
                             else S (Cursor + 1));
               if Bracket (Previous, Pattern_Cursor, After) or else
                 not Bracket (Following, Pattern_Cursor, After)
               then
                  return -1;
               end if;
               Pattern_Cursor := After;
            elsif Code = '%' and then Pattern_Cursor + 1 < P'Length and then
              P (Pattern_Cursor + 2) in '0' .. '9'
            then
               Index := Character'Pos (P (Pattern_Cursor + 2)) -
                 Character'Pos ('0');
               if Index = 0 or else Index > Captures.Count or else
                 Captures.Captures (Index).Length = -2
               then
                  Fail (State, "invalid capture index %" &
                        P (Pattern_Cursor + 2));
               end if;
               if Captures.Captures (Index).Length = -1 then
                  return -1;
               end if;
               Length := Natural (Captures.Captures (Index).Length);
               if Length <= S'Length - Cursor then
                  --  Greedy capture backtracking may compare the same long
                  --  byte ranges repeatedly. Charge their full length before
                  --  the native slice comparison, even for an early mismatch,
                  --  so this otherwise quadratic work remains bounded.
                  Work (Length);
               end if;
               if Length > S'Length - Cursor or else
                 S (Cursor + 1 .. Cursor + Length) /=
                 S (Captures.Captures (Index).First + 1 ..
                    Captures.Captures (Index).First + Length)
               then
                  return -1;
               end if;
               Cursor := Cursor + Length;
               Pattern_Cursor := Pattern_Cursor + 2;
            else
               After := Class_End (Pattern_Cursor);
               Suffix := (if After < P'Length then P (After + 1)
                          else Ada.Characters.Latin_1.NUL);
               if Suffix in '*' | '+' | '-' | '?' then
                  Last := Cursor;
                  while Single (Last, Pattern_Cursor, After) loop
                     Last := Last + 1;
                     exit when Suffix = '?';
                  end loop;
                  if Suffix = '+' and then Last = Cursor then
                     return -1;
                  end if;
                  --  Restore all capture state before every alternative;
                  --  a failed branch must never leak a partially closed group.
                  Saved := Captures;
                  if Suffix = '-' then
                     for Position in Cursor .. Last loop
                        Captures := Saved;
                        Attempt := Match
                          (Position, After + 1, Captures, Depth + 1);
                        if Attempt >= 0 then
                           return Attempt;
                        end if;
                     end loop;
                  else
                     Minimum := (if Suffix = '+' then Cursor + 1 else Cursor);
                     for Position in reverse Minimum .. Last loop
                        Captures := Saved;
                        Attempt := Match
                          (Position, After + 1, Captures, Depth + 1);
                        if Attempt >= 0 then
                           return Attempt;
                        end if;
                     end loop;
                  end if;
                  Captures := Saved;
                  return -1;
               elsif Single (Cursor, Pattern_Cursor, After) then
                  Cursor := Cursor + 1;
                  Pattern_Cursor := After;
               else
                  return -1;
               end if;
            end if;
         end loop;
      end Match;
      After : Integer;
   begin
      if Start > S'Length then
         return Result;
      end if;
      for Position in Start .. S'Length loop
         Result.Count := 0;
         After := Match (Position, Boolean'Pos (Anchored), Result);
         if After >= 0 then
            Result.Found := True;
            Result.First := Position;
            Result.After := Natural (After);
            return Result;
         end if;
         exit when Anchored;
      end loop;
      return Result;
   end Find;

   function Capture_Values
     (State : in out World; Subject : String; Item : Match_Result;
      Whole_If_None : Boolean := True) return Values.Vector
   is
      S : constant String (1 .. Subject'Length) := Subject;
      Result : Values.Vector := Owned_Values (State);
   begin
      if not Item.Found then
         return Result;
      elsif Item.Count = 0 and then Whole_If_None then
         Result.Append (New_String
           (State, S (Item.First + 1 .. Item.After)));
      else
         for Index in 1 .. Item.Count loop
            declare
               Cap : constant Capture := Item.Captures (Index);
            begin
               if Cap.Length = -2 then
                  Fail (State, "unfinished capture");
               elsif Cap.Length = -1 then
                  Result.Append
                    (Value'(Integer_Kind, Integer_Value (Cap.First + 1)));
               else
                  Result.Append (New_String
                    (State, S (Cap.First + 1 ..
                               Cap.First + Natural (Cap.Length))));
               end if;
            end;
         end loop;
      end if;
      return Result;
   end Capture_Values;
end Lua.Engine.Patterns;
