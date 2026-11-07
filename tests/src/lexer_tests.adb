with Ada.Characters.Latin_1;
with Ada.Containers;
with Ada.Numerics.Discrete_Random;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Lexers; use Lua.Lexers;
with Lua.Test_Configuration;
with Test_Support;

package body Lexer_Tests is
   use type Ada.Containers.Count_Type;
   package Latin renames Ada.Characters.Latin_1;
   type Kind_Array is array (Positive range <>) of Token_Kind;
   procedure Check_Kinds (Source : String; Expected : Kind_Array);
   procedure Check_String (Source, Expected : String);
   procedure Check_Bad (Source : String);
   procedure Keywords;
   procedure Keyword_Prefix_Names;
   procedure Longest_Operators;
   procedure Decimal_Exponent_Token;
   procedure Hex_Exponent_Token;
   procedure Embedded_Nul;
   procedure Decimal_Byte;
   procedure Unicode_Bytes;
   procedure Extended_Unicode;
   procedure Simple_Escapes;
   procedure Whitespace_Escape;
   procedure Escaped_Newline;
   procedure Long_Initial_Newline;
   procedure Long_Newline_Normalization;
   procedure Comment_At_Eof;
   procedure Long_Comment_Separator;
   procedure CRLF_Location;
   procedure Non_One_Lower_Bound;
   procedure Exact_Token_Budget;
   procedure Exceeded_Token_Budget;
   procedure Empty_Chunk;
   procedure Independent_Scans;
   procedure Unknown_Escape;
   procedure Decimal_Escape_Overflow;
   procedure Invalid_Hex_Escape;
   procedure Empty_Unicode_Escape;
   procedure Unicode_Overflow;
   procedure Unclosed_Quote;
   procedure Unclosed_Long_String;
   procedure Unclosed_Long_Comment;
   procedure Invalid_Long_Delimiter;
   procedure Unexpected_Byte;
   procedure Arbitrary_Bytes;

   procedure Check_Kinds (Source : String; Expected : Kind_Array) is
      R : constant Scan_Result := Scan (Source);
   begin
      Assert (R.Status = Success, To_String (R.Message));
      Assert (R.Tokens.Length = Expected'Length, "token count");
      for Index in Expected'Range loop
         Assert (R.Tokens (Index).Kind = Expected (Index),
                 "token kind at" & Index'Image);
      end loop;
   end Check_Kinds;

   procedure Check_String (Source, Expected : String) is
      R : constant Scan_Result := Scan (Source);
   begin
      Assert (R.Status = Success, To_String (R.Message));
      Assert (R.Tokens.Length = 2, "one literal plus EOF");
      Assert (R.Tokens (1).Kind = String_Literal, "decoded string token");
      Assert (R.Tokens (1).Text = Expected, "exact decoded bytes");
   end Check_String;

   procedure Check_Bad (Source : String) is
      R : constant Scan_Result := Scan (Source);
   begin
      Assert (R.Status = Syntax_Error, "expected lexical syntax error");
      Assert (R.Tokens.Is_Empty, "failed scan has no partial tokens");
      Assert (Length (R.Message) > 0, "nonempty lexical diagnostic");
   end Check_Bad;

   procedure Keywords is
      --  Each Lua keyword is recognized independently of ordinary names.
      Expected : constant Kind_Array :=
        [And_Word, Break_Word, Do_Word, Else_Word, Elseif_Word, End_Word,
         False_Word, For_Word, Function_Word,
         (if Lua.Test_Configuration.Compatible_Global then Identifier
          else Global_Word), Goto_Word,
         If_Word, In_Word, Local_Word, Nil_Word, Not_Word, Or_Word,
         Repeat_Word, Return_Word, Then_Word, True_Word, Until_Word,
         While_Word, End_Of_Input];
   begin
      Check_Kinds
        ("and break do else elseif end false for function global goto " &
         "if in local nil not or repeat return then true until while",
         Expected);
   end Keywords;

   procedure Keyword_Prefix_Names is
      --  A keyword prefix is not itself a keyword when followed by name
      --  bytes.
   begin
      Check_Kinds ("locality globalized",
                   [Identifier, Identifier, End_Of_Input]);
   end Keyword_Prefix_Names;

   procedure Longest_Operators is
      --  Two- and three-byte operators must use maximal munch.
   begin
      Check_Kinds ("// .. ... << >> <= >= == ~= ::",
        [Floor_Divide, Concatenate, Varargs, Shift_Left, Shift_Right,
         Less_Equal, Greater_Equal, Equal, Not_Equal, Double_Colon,
         End_Of_Input]);
   end Longest_Operators;

   procedure Decimal_Exponent_Token is
      --  The exponent sign stays in the numeric token, not an operator
      --  token.
      R : constant Scan_Result := Scan ("1e-3");
   begin
      Assert (R.Status = Success, "decimal exponent scan");
      Assert (R.Tokens (1).Kind in Number_Literal, "number token");
      Assert (R.Tokens (1).Text = "1e-3", "full numeric spelling");
   end Decimal_Exponent_Token;

   procedure Hex_Exponent_Token is
      --  Hexadecimal floating spellings retain the binary exponent sign.
      R : constant Scan_Result := Scan ("0x1.fp+2");
   begin
      Assert (R.Status = Success, "hex exponent scan");
      Assert (R.Tokens (1).Text = "0x1.fp+2", "full hex spelling");
   end Hex_Exponent_Token;

   procedure Embedded_Nul is
      --  A decoded NUL is a byte in the string, not a terminator.
   begin
      Check_String ("'\x00'", String'(1 => Latin.NUL));
   end Embedded_Nul;

   procedure Decimal_Byte is
      --  The largest decimal escape produces exactly one byte.
   begin
      Check_String ("'\255'", String'(1 => Character'Val (255)));
   end Decimal_Byte;

   procedure Unicode_Bytes is
      --  Unicode escape encoding is checked by exact UTF-8 bytes.
   begin
      Check_String ("'\u{20ac}'",
        Character'Val (16#E2#) & Character'Val (16#82#) &
        Character'Val (16#AC#));
   end Unicode_Bytes;

   procedure Extended_Unicode is
      --  Lua extended UTF-8 accepts its six-byte endpoint.
      R : constant Scan_Result := Scan ("'\u{7fffffff}'");
   begin
      Assert (R.Status = Success, "extended UTF-8 accepted");
      Assert (Length (R.Tokens (1).Text) = 6, "six encoded bytes");
   end Extended_Unicode;

   procedure Simple_Escapes is
      --  Named control escapes produce the documented byte sequence.
   begin
      Check_String ("'\a\b\f\n\r\t\v'",
        Latin.BEL & Latin.BS & Latin.FF & Latin.LF & Latin.CR &
        Latin.HT & Latin.VT);
   end Simple_Escapes;

   procedure Whitespace_Escape is
      --  Backslash-z consumes whitespace including line breaks.
   begin
      Check_String ("'\z " & Latin.LF & "  x'", "x");
   end Whitespace_Escape;

   procedure Escaped_Newline is
      --  An escaped CRLF contributes one normalized newline byte.
   begin
      Check_String ("'\" & Latin.CR & Latin.LF & "x'", Latin.LF & 'x');
   end Escaped_Newline;

   procedure Long_Initial_Newline is
      --  The first line break after an opening long bracket is omitted.
   begin
      Check_String ("[=[" & Latin.LF & "text]=]", "text");
   end Long_Initial_Newline;

   procedure Long_Newline_Normalization is
      --  CRLF in a long literal becomes one LF byte.
   begin
      Check_String ("[=[a" & Latin.CR & Latin.LF & "b]=]",
                    'a' & Latin.LF & 'b');
   end Long_Newline_Normalization;

   procedure Comment_At_Eof is
      --  A short comment may end at EOF without a line terminator.
   begin
      Check_Kinds ("-- no newline", [1 => End_Of_Input]);
   end Comment_At_Eof;

   procedure Long_Comment_Separator is
      --  Long comments separate adjacent names even without surrounding
      --  spaces.
   begin
      Check_Kinds ("a--[=[comment]=]b",
                   [Identifier, Identifier, End_Of_Input]);
   end Long_Comment_Separator;

   procedure CRLF_Location is
      --  A CRLF advances one line but two source byte offsets.
      R : constant Scan_Result := Scan ("a" & Latin.CR & Latin.LF & "b");
   begin
      Assert (R.Status = Success, "located scan");
      Assert (R.Tokens (2).Location.Line = 2, "one line advance");
      Assert (R.Tokens (2).Location.Column = 1, "column reset");
      Assert (R.Tokens (2).Location.Offset = 4, "byte offset");
   end CRLF_Location;

   procedure Non_One_Lower_Bound is
      --  Public scanning accepts a String whose lower bound is not one.
      Source : constant String (10 .. 14) := "local";
      R : constant Scan_Result := Scan (Source);
   begin
      Assert (R.Status = Success, "non-one-bound source");
      Assert (R.Tokens (1).Kind = Local_Word, "normalized token");
      Assert (R.Tokens (1).Location.Offset = 1, "logical byte offset");
   end Non_One_Lower_Bound;

   procedure Exact_Token_Budget is
      --  The EOF token counts toward the token budget.
      R : constant Scan_Result := Scan ("a", Maximum_Tokens => 2);
   begin
      Assert (R.Status = Success, "exactly two tokens fit");
      Assert (R.Tokens.Length = 2, "name plus EOF");
   end Exact_Token_Budget;

   procedure Exceeded_Token_Budget is
      --  Resource failure exposes no partial token vector.
      R : constant Scan_Result := Scan ("a b", Maximum_Tokens => 2);
   begin
      Assert (R.Status = Resource_Error, "budget exhaustion");
      Assert (R.Tokens.Is_Empty, "no partial tokens");
   end Exceeded_Token_Budget;

   procedure Empty_Chunk is
      --  An empty chunk needs precisely one EOF token.
      R : constant Scan_Result := Scan ("", Maximum_Tokens => 1);
   begin
      Assert (R.Status = Success, "empty source accepted");
      Assert (R.Tokens.Length = 1, "one EOF token");
   end Empty_Chunk;

   procedure Independent_Scans is
      --  A malformed source must not poison a later independent scan.
      Bad : constant Scan_Result := Scan ("'unfinished");
      Good : constant Scan_Result := Scan ("return 42");
   begin
      Assert (Bad.Status = Syntax_Error, "first source fails");
      Assert (Good.Status = Success, "second source succeeds");
   end Independent_Scans;

   procedure Unknown_Escape is
      --  An unknown backslash escape must not be silently copied.
   begin
      Check_Bad ("'\q'");
   end Unknown_Escape;

   procedure Decimal_Escape_Overflow is
      --  A decimal byte escape cannot exceed 255.
   begin
      Check_Bad ("'\256'");
   end Decimal_Escape_Overflow;

   procedure Invalid_Hex_Escape is
      --  A two-digit hexadecimal escape rejects nonhex characters.
   begin
      Check_Bad ("'\x0g'");
   end Invalid_Hex_Escape;

   procedure Empty_Unicode_Escape is
      --  Unicode escapes require at least one hexadecimal digit.
   begin
      Check_Bad ("'\u{}'");
   end Empty_Unicode_Escape;

   procedure Unicode_Overflow is
      --  Lua's extended UTF-8 escape stops at 0x7fffffff.
   begin
      Check_Bad ("'\u{80000000}'");
   end Unicode_Overflow;

   procedure Unclosed_Quote is
      --  An unfinished quoted literal must not return partial tokens.
   begin
      Check_Bad ("'unfinished");
   end Unclosed_Quote;

   procedure Unclosed_Long_String is
      --  A long literal must find its matching bracket level.
   begin
      Check_Bad ("[=[unfinished");
   end Unclosed_Long_String;

   procedure Unclosed_Long_Comment is
      --  An unfinished long comment is a syntax error, not ordinary EOF.
   begin
      Check_Bad ("--[=[unfinished");
   end Unclosed_Long_Comment;

   procedure Invalid_Long_Delimiter is
      --  A malformed opening bracket level must be rejected.
   begin
      Check_Bad ("[=broken");
   end Invalid_Long_Delimiter;

   procedure Unexpected_Byte is
      --  C Lua returns unmatched bytes to its parser as single-byte tokens.
      --  Rejection belongs to the grammar, rather than lexical analysis.
   begin
      Check_Kinds ("@", [Byte_Symbol, End_Of_Input]);
   end Unexpected_Byte;

   procedure Arbitrary_Bytes is
      --  Seeded arbitrary byte strings exercise scanner termination and
      --  exception containment. This is a unit regression, not a fuzz campaign
      --  or a claim of exhaustive lexical coverage.
      package Random_Bytes is new Ada.Numerics.Discrete_Random (Character);
      Generator : Random_Bytes.Generator;
      Source : String (1 .. 32);
   begin
      Random_Bytes.Reset (Generator, Initiator => 551);
      for Trial in 1 .. 10_000 loop
         for Item of Source loop
            Item := Random_Bytes.Random (Generator);
         end loop;
         declare
            R : constant Scan_Result := Scan (Source (1 .. Trial mod 33));
         begin
            if R.Status = Success then
               Assert (R.Tokens.Last_Element.Kind = End_Of_Input,
                       "successful scan ends in EOF");
            else
               Assert (R.Tokens.Is_Empty, "failure leaves no partial tokens");
            end if;
         end;
      end loop;
   end Arbitrary_Bytes;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "lexer: keywords",
         Keywords'Access);
      Test_Support.Add
        (Suite, "lexer: keyword prefix names",
         Keyword_Prefix_Names'Access);
      Test_Support.Add
        (Suite, "lexer: longest operators",
         Longest_Operators'Access);
      Test_Support.Add
        (Suite, "lexer: decimal exponent token",
         Decimal_Exponent_Token'Access);
      Test_Support.Add
        (Suite, "lexer: hex exponent token",
         Hex_Exponent_Token'Access);
      Test_Support.Add
        (Suite, "lexer: embedded nul",
         Embedded_Nul'Access);
      Test_Support.Add
        (Suite, "lexer: decimal byte",
         Decimal_Byte'Access);
      Test_Support.Add
        (Suite, "lexer: unicode bytes",
         Unicode_Bytes'Access);
      Test_Support.Add
        (Suite, "lexer: extended unicode",
         Extended_Unicode'Access);
      Test_Support.Add
        (Suite, "lexer: simple escapes",
         Simple_Escapes'Access);
      Test_Support.Add
        (Suite, "lexer: whitespace escape",
         Whitespace_Escape'Access);
      Test_Support.Add
        (Suite, "lexer: escaped newline",
         Escaped_Newline'Access);
      Test_Support.Add
        (Suite, "lexer: long initial newline",
         Long_Initial_Newline'Access);
      Test_Support.Add
        (Suite, "lexer: long newline normalization",
         Long_Newline_Normalization'Access);
      Test_Support.Add
        (Suite, "lexer: comment at eof",
         Comment_At_Eof'Access);
      Test_Support.Add
        (Suite, "lexer: long comment separator",
         Long_Comment_Separator'Access);
      Test_Support.Add
        (Suite, "lexer: crlf location",
         CRLF_Location'Access);
      Test_Support.Add
        (Suite, "lexer: non one lower bound",
         Non_One_Lower_Bound'Access);
      Test_Support.Add
        (Suite, "lexer: exact token budget",
         Exact_Token_Budget'Access);
      Test_Support.Add
        (Suite, "lexer: exceeded token budget",
         Exceeded_Token_Budget'Access);
      Test_Support.Add
        (Suite, "lexer: empty chunk",
         Empty_Chunk'Access);
      Test_Support.Add
        (Suite, "lexer: independent scans",
         Independent_Scans'Access);
      Test_Support.Add
        (Suite, "lexer: unknown escape",
         Unknown_Escape'Access);
      Test_Support.Add
        (Suite, "lexer: decimal escape overflow",
         Decimal_Escape_Overflow'Access);
      Test_Support.Add
        (Suite, "lexer: invalid hex escape",
         Invalid_Hex_Escape'Access);
      Test_Support.Add
        (Suite, "lexer: empty unicode escape",
         Empty_Unicode_Escape'Access);
      Test_Support.Add
        (Suite, "lexer: unicode overflow",
         Unicode_Overflow'Access);
      Test_Support.Add
        (Suite, "lexer: unclosed quote",
         Unclosed_Quote'Access);
      Test_Support.Add
        (Suite, "lexer: unclosed long string",
         Unclosed_Long_String'Access);
      Test_Support.Add
        (Suite, "lexer: unclosed long comment",
         Unclosed_Long_Comment'Access);
      Test_Support.Add
        (Suite, "lexer: invalid long delimiter",
         Invalid_Long_Delimiter'Access);
      Test_Support.Add
        (Suite, "lexer: unexpected byte",
         Unexpected_Byte'Access);
      Test_Support.Add
        (Suite, "lexer: arbitrary bytes",
         Arbitrary_Bytes'Access);
   end Register;
end Lexer_Tests;
