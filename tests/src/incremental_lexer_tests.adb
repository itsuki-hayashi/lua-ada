with AUnit.Assertions; use AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Lua.Lexers; use Lua.Lexers;
with Lua.Numbers;
with Test_Support;

package body Incremental_Lexer_Tests is
   use type Lua.Numbers.Integer_Value;
   use type Lua.Numbers.Real_Value;
   procedure Incremental_Defers_Error;
   procedure Repeated_Eof;
   procedure Repeated_Failure;
   procedure Numeric_Payloads;
   procedure Hex_Exponent_Boundary;
   procedure Malformed_Numeral;
   procedure Raw_Nul_Token;
   procedure Post_Token_Line;

   procedure Incremental_Defers_Error is
      --  Requesting early tokens must not scan an unrelated later bad escape.
      Reader : Scanner := Open ("local = '\q'");
      Step : Scan_Result;
   begin
      Step := Next (Reader);
      Assert (Step.Status = Success and then
              Step.Tokens.First_Element.Kind = Local_Word, "first token");
      Step := Next (Reader);
      Assert (Step.Status = Success and then
              Step.Tokens.First_Element.Kind = Assign, "early grammar token");
      Step := Next (Reader);
      Assert (Step.Status = Syntax_Error, "later lexical failure deferred");
   end Incremental_Defers_Error;

   procedure Repeated_Eof is
      --  EOF is a stable terminal state, including repeated caller requests.
      Reader : Scanner := Open ("");
      First, Again : Scan_Result;
   begin
      First := Next (Reader);
      Again := Next (Reader);
      Assert (First.Status = Success and then Again.Status = Success,
              "cached EOF does not consume token budget");
      Assert (Again.Tokens.First_Element.Kind = End_Of_Input, "stable EOF");
   end Repeated_Eof;

   procedure Repeated_Failure is
      --  A failure cannot resume scanning partway through the invalid token.
      Reader : Scanner := Open ("'\q'");
      First, Again : Scan_Result;
   begin
      First := Next (Reader);
      Again := Next (Reader);
      Assert (First.Status = Syntax_Error and then
              Again.Status = Syntax_Error, "stable failure");
      Assert (Again.Message = First.Message, "owned diagnostic retained");
   end Repeated_Failure;

   procedure Numeric_Payloads is
      --  Numeral tokens retain both their classification and decoded value.
      Result : constant Scan_Result := Scan ("42 1.5");
   begin
      Assert (Result.Tokens (1).Kind = Integer_Literal, "integer token");
      Assert (Result.Tokens (1).Numeric.Integer_Item = 42, "int64 payload");
      Assert (Result.Tokens (2).Kind = Float_Literal, "float token");
      Assert (Result.Tokens (2).Numeric.Real_Item = 1.5, "binary64 payload");
   end Numeric_Payloads;

   procedure Hex_Exponent_Boundary is
      --  Only p/P introduce hexadecimal exponents; e remains a hex digit.
      Result : constant Scan_Result := Scan ("0xe+1");
   begin
      Assert (Result.Status = Success, "valid hexadecimal expression");
      Assert (Result.Tokens (1).Text = "0xe", "hex digit e is not exponent");
      Assert (Result.Tokens (2).Kind = Plus, "plus remains an operator");
      Assert (Result.Tokens (3).Numeric.Integer_Item = 1, "second integer");
   end Hex_Exponent_Boundary;

   procedure Malformed_Numeral is
      --  Malformed numbers fail in the lexer rather than delayed VM lowering.
      Result : constant Scan_Result := Scan ("1e+");
   begin
      Assert (Result.Status = Syntax_Error, "lexical numeral failure");
      Assert (Result.Tokens.Is_Empty, "batch adapter discards partial input");
   end Malformed_Numeral;

   procedure Raw_Nul_Token is
      --  C Lua hands raw unmatched bytes, including NUL, to the parser.
      Result : constant Scan_Result := Scan (String'(1 => Character'Val (0)));
   begin
      Assert (Result.Status = Success, "NUL is not an EOF sentinel");
      Assert (Result.Tokens (1).Kind = Byte_Symbol, "raw-byte token");
      Assert (Length (Result.Tokens (1).Text) = 1, "NUL payload preserved");
   end Raw_Nul_Token;

   procedure Post_Token_Line is
      --  Multiline literals retain both a start position and scanner end line.
      Result : constant Scan_Result := Scan ("[[a" & Character'Val (10) &
                                            "b]]");
   begin
      Assert (Result.Tokens (1).Location.Line = 1, "start line");
      Assert (Result.Tokens (1).After.Line = 2, "C scanner line after token");
   end Post_Token_Line;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "incremental lexer: Incremental_Defers_Error",
         Incremental_Defers_Error'Access);
      Test_Support.Add
        (Suite, "incremental lexer: Repeated_Eof",
         Repeated_Eof'Access);
      Test_Support.Add
        (Suite, "incremental lexer: Repeated_Failure",
         Repeated_Failure'Access);
      Test_Support.Add
        (Suite, "incremental lexer: Numeric_Payloads",
         Numeric_Payloads'Access);
      Test_Support.Add
        (Suite, "incremental lexer: Hex_Exponent_Boundary",
         Hex_Exponent_Boundary'Access);
      Test_Support.Add
        (Suite, "incremental lexer: Malformed_Numeral",
         Malformed_Numeral'Access);
      Test_Support.Add
        (Suite, "incremental lexer: Raw_Nul_Token",
         Raw_Nul_Token'Access);
      Test_Support.Add
        (Suite, "incremental lexer: Post_Token_Line",
         Post_Token_Line'Access);
   end Register;
end Incremental_Lexer_Tests;
