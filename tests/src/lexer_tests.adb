with Ada.Characters.Latin_1;
with Ada.Containers;
with Ada.Numerics.Discrete_Random;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Lexers; use Lua.Lexers;

package body Lexer_Tests is
   use type Ada.Containers.Count_Type;

   procedure Keywords_And_Operators (Self : in out Fixture) is
      pragma Unreferenced (Self);
      Result : constant Scan_Result := Scan
        ("global local function and break do else elseif end false for " &
         "goto if in nil not or repeat return then true until while " &
         "// .. ... << >> <= >= == ~= :: + - * / % ^ # & | ~ = " &
         "< > ( ) { } [ ] ; : , . name .5 0x1.fp+2 1e-3");
      Expected : constant array (Positive range <>) of Token_Kind :=
        [Global_Word, Local_Word, Function_Word, And_Word, Break_Word,
         Do_Word, Else_Word, Elseif_Word, End_Word, False_Word, For_Word,
         Goto_Word, If_Word, In_Word, Nil_Word, Not_Word, Or_Word,
         Repeat_Word, Return_Word, Then_Word, True_Word, Until_Word,
         While_Word, Floor_Divide, Concatenate, Varargs, Shift_Left,
         Shift_Right, Less_Equal, Greater_Equal, Equal, Not_Equal,
         Double_Colon, Plus, Minus, Star, Slash, Percent, Power, Length,
         Bit_And, Bit_Or, Bit_Xor, Assign, Less, Greater, Left_Paren,
         Right_Paren, Left_Brace, Right_Brace, Left_Bracket, Right_Bracket,
         Semicolon, Colon, Comma, Dot, Identifier, Number_Literal,
         Number_Literal, Number_Literal, End_Of_Input];
   begin
      Assert (Result.Status = Success, To_String (Result.Message));
      Assert (Result.Tokens.Length = Expected'Length, "token count");
      for Index in Expected'Range loop
         Assert (Result.Tokens (Index).Kind = Expected (Index),
                 "token" & Index'Image);
      end loop;
   end Keywords_And_Operators;

   procedure Strings_And_Locations (Self : in out Fixture) is
      pragma Unreferenced (Self);
      package Latin renames Ada.Characters.Latin_1;
      Result : constant Scan_Result := Scan
        ("-- comment" & Latin.CR & Latin.LF &
         "[==[" & Latin.LF & "a" & Latin.CR & Latin.LF & "b]==] " &
         "'\x00\255\u{20ac}\z " & Latin.LF & "q' --[=[x]=]");
      Offset_Source : constant String (10 .. 14) := "local";
      Offset_Result : constant Scan_Result := Scan (Offset_Source);
      Escapes : constant Scan_Result :=
        Scan ("'\a\b\f\n\r\t\v\\\" & '"' & "\''");
   begin
      Assert (Result.Status = Success, To_String (Result.Message));
      Assert (Result.Tokens.Length = 3, "two strings and EOF");
      Assert (To_String (Result.Tokens (1).Text) =
              "a" & Latin.LF & "b", "long string newlines");
      Assert (Result.Tokens (1).Location.Line = 2, "CRLF is one line");
      Assert (To_String (Result.Tokens (2).Text) =
              Latin.NUL & Character'Val (255) &
              Character'Val (16#E2#) & Character'Val (16#82#) &
              Character'Val (16#AC#) & 'q', "decoded string bytes");
      Assert (Offset_Result.Tokens (1).Kind = Local_Word,
              "non-one source bounds");
      Assert (Escapes.Status = Success, "simple escapes accepted");
      Assert (Length (Escapes.Tokens (1).Text) = 10, "escape length");
   end Strings_And_Locations;

   procedure Rejected_Input (Self : in out Fixture) is
      pragma Unreferenced (Self);
      procedure Check_Bad (Source : String);

      procedure Check_Bad (Source : String) is
         Result : constant Scan_Result := Scan (Source);
      begin
         Assert (Result.Status = Syntax_Error, "expected syntax error");
         Assert (Result.Tokens.Is_Empty, "no partial result on failure");
         Assert (Length (Result.Message) > 0, "located diagnostic");
      end Check_Bad;

      Budget  : constant Scan_Result := Scan ("a b", Maximum_Tokens => 2);
      Empty   : constant Scan_Result := Scan ("", Maximum_Tokens => 1);
      Good    : constant Scan_Result := Scan ("return 42");
   begin
      Check_Bad ("'\q'");
      Check_Bad ("'\256'");
      Check_Bad ("'\x0g'");
      Check_Bad ("'\u{}'");
      Check_Bad ("'\u{80000000}'");
      Check_Bad ("'unfinished");
      Check_Bad ("[=[unfinished");
      Check_Bad ("--[=[unfinished");
      Check_Bad ("[=broken");
      Check_Bad ("@");
      Assert (Budget.Status = Resource_Error, "token budget includes EOF");
      Assert (Budget.Tokens.Is_Empty, "budget failure clears tokens");
      Assert (Empty.Status = Success and then Empty.Tokens.Length = 1,
              "empty chunk at exact budget");
      Assert (Good.Status = Success, "failure does not poison later scans");
   end Rejected_Input;

   procedure Arbitrary_Bytes (Self : in out Fixture) is
      pragma Unreferenced (Self);
      package Random_Bytes is new Ada.Numerics.Discrete_Random (Character);
      Generator : Random_Bytes.Generator;
      Source    : String (1 .. 32);
   begin
      Random_Bytes.Reset (Generator, Initiator => 551);
      for Trial in 1 .. 1_000 loop
         for Item of Source loop
            Item := Random_Bytes.Random (Generator);
         end loop;
         declare
            Result : constant Scan_Result :=
              Scan (Source (1 .. Trial mod 33));
         begin
            if Result.Status = Success then
               Assert (Result.Tokens.Last_Element.Kind = End_Of_Input,
                       "successful byte scan must terminate");
            else
               Assert (Result.Tokens.Is_Empty,
                       "failed byte scan must not expose partial tokens");
            end if;
         end;
      end loop;
   end Arbitrary_Bytes;
end Lexer_Tests;
