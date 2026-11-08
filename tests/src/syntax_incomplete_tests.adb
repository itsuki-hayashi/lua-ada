with AUnit.Assertions; use AUnit.Assertions;
with Lua.Syntax; use Lua.Syntax;
with Test_Support;

package body Syntax_Incomplete_Tests is
   procedure Expect (Source : String; Incomplete : Boolean);
   procedure Short_Quote;
   procedure Trailing_Escape;
   procedure Long_String;
   procedure Long_Comment;
   procedure Missing_Parenthesis;
   procedure Missing_Brace;
   procedure Missing_Block_End;
   procedure Missing_Expression;
   procedure Missing_Method_Arguments;
   procedure Malformed_Number;
   procedure Malformed_Escape;
   procedure Malformed_Escape_EOF;
   procedure Unresolved_Goto;
   procedure Semantic_Break;
   procedure Unexpected_Token;
   procedure Successful_Input;
   procedure Resource_Input;

   procedure Expect (Source : String; Incomplete : Boolean) is
      Result : constant Check_Result := Check (Source, "interactive-case");
   begin
      Assert (Result.Status = Syntax_Error, "actual syntax rejection");
      Assert (Result.Incomplete_Input = Incomplete,
              "structured input classification for " & Source);
   end Expect;

   procedure Short_Quote is
   begin
      --  A quoted token ending at actual EOF can receive its closing quote.
      Expect ("return 'abc", True);
   end Short_Quote;

   procedure Trailing_Escape is
   begin
      --  EOF directly after a backslash is still an unfinished token, rather
      --  than a completed invalid escape spelling.
      Expect ("return 'abc" & '\', True);
   end Trailing_Escape;

   procedure Long_String is
   begin
      --  The matching long delimiter may be supplied on another input line.
      Expect ("return [=[abc", True);
   end Long_String;

   procedure Long_Comment is
   begin
      --  Long comments share the exact delimiter/EOF scanner lifecycle.
      Expect ("--[=[abc", True);
   end Long_Comment;

   procedure Missing_Parenthesis is
   begin
      Expect ("return (1", True);
   end Missing_Parenthesis;

   procedure Missing_Brace is
   begin
      Expect ("return {1", True);
   end Missing_Brace;

   procedure Missing_Block_End is
   begin
      Expect ("do local x=1", True);
   end Missing_Block_End;

   procedure Missing_Expression is
   begin
      Expect ("return 1 +", True);
   end Missing_Expression;

   procedure Missing_Method_Arguments is
   begin
      Expect ("f:m", True);
   end Missing_Method_Arguments;

   procedure Malformed_Number is
   begin
      --  A completed malformed numeral is a final lexical error even when
      --  the scanner needed EOF to finish examining its spelling.
      Expect ("return 1e+", False);
   end Malformed_Number;

   procedure Malformed_Escape is
   begin
      Expect ("return '\q'", False);
   end Malformed_Escape;

   procedure Malformed_Escape_EOF is
   begin
      --  A missing required hexadecimal escape digit remains a malformed
      --  escape, distinct from an otherwise unfinished short literal.
      Expect ("return '\x", False);
   end Malformed_Escape_EOF;

   procedure Unresolved_Goto is
   begin
      --  Resolution happens after scanning EOF. That timing must not make a
      --  static label error request an unrelated next interactive line.
      Expect ("goto missing", False);
   end Unresolved_Goto;

   procedure Semantic_Break is
   begin
      Expect ("break", False);
   end Semantic_Break;

   procedure Unexpected_Token is
   begin
      --  The scanner has prefetched EOF after ')', but the actual rejected
      --  grammar token is punctuation, not an incomplete EOF expectation.
      Expect (")", False);
   end Unexpected_Token;

   procedure Successful_Input is
      Empty : constant Check_Result := Check ("");
      Complete : constant Check_Result := Check ("return 1");
   begin
      Assert (Empty.Status = Success and then not Empty.Incomplete_Input,
              "empty input is complete");
      Assert (Complete.Status = Success and then not Complete.Incomplete_Input,
              "successful input never requests another line");
   end Successful_Input;

   procedure Resource_Input is
      Result : constant Check_Result := Check
        ("return", Limits => (Source_Bytes => 2, others => <>));
   begin
      Assert (Result.Status = Resource_Error and then
              not Result.Incomplete_Input,
              "host checking limits remain final resource failures");
   end Resource_Input;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "incomplete input: short quote", Short_Quote'Access);
      Test_Support.Add
        (Suite, "incomplete input: trailing backslash",
         Trailing_Escape'Access);
      Test_Support.Add
        (Suite, "incomplete input: long string", Long_String'Access);
      Test_Support.Add
        (Suite, "incomplete input: long comment", Long_Comment'Access);
      Test_Support.Add
        (Suite, "incomplete input: missing parenthesis",
         Missing_Parenthesis'Access);
      Test_Support.Add
        (Suite, "incomplete input: missing brace", Missing_Brace'Access);
      Test_Support.Add
        (Suite, "incomplete input: missing block end",
         Missing_Block_End'Access);
      Test_Support.Add
        (Suite, "incomplete input: missing expression",
         Missing_Expression'Access);
      Test_Support.Add
        (Suite, "incomplete input: missing method arguments",
         Missing_Method_Arguments'Access);
      Test_Support.Add
        (Suite, "incomplete input: malformed numeral is final",
         Malformed_Number'Access);
      Test_Support.Add
        (Suite, "incomplete input: malformed escape is final",
         Malformed_Escape'Access);
      Test_Support.Add
        (Suite, "incomplete input: malformed escape EOF is final",
         Malformed_Escape_EOF'Access);
      Test_Support.Add
        (Suite, "incomplete input: unresolved goto is final",
         Unresolved_Goto'Access);
      Test_Support.Add
        (Suite, "incomplete input: semantic break is final",
         Semantic_Break'Access);
      Test_Support.Add
        (Suite, "incomplete input: punctuation is final",
         Unexpected_Token'Access);
      Test_Support.Add
        (Suite, "incomplete input: successful chunks are complete",
         Successful_Input'Access);
      Test_Support.Add
        (Suite, "incomplete input: resources are final",
         Resource_Input'Access);
   end Register;
end Syntax_Incomplete_Tests;
