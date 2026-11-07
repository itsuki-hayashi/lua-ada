with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Syntax; use Lua.Syntax;
with Lua.Sessions;
with Test_Support;

package body Syntax_Diagnostic_Tests is
   procedure Check (Source, Expected : String);
   procedure Invalid_Prefix;
   procedure Expected_Name;
   procedure Short_String;
   procedure Long_String;
   procedure Control_Byte;
   procedure Number_Spelling;
   procedure Semantic_Const;
   procedure Break_Token;
   procedure Loaded_String_Source;
   procedure Reader_Source_Label;
   procedure Return_Count_Limit;
   procedure Goto_Source_Line;
   procedure Duplicate_Label_Line;
   procedure Goto_Scope_Line;
   procedure Embedded_Nul_Token;
   procedure Embedded_Nul_Load_Name;
   procedure Execute_Check (Source : String);

   procedure Execute_Check (Source : String) is
      Universe : Lua.Sessions.Session;
      Result : constant Lua.Sessions.Execution_Result :=
        Universe.Execute (Source, "=diagnostic-case");
      use type Lua.Sessions.Execution_Status;
   begin
      Assert (Result.Status = Lua.Sessions.Succeeded,
              To_String (Result.Error.Message));
   end Execute_Check;

   procedure Check (Source, Expected : String) is
      Result : constant Check_Result := Lua.Syntax.Check (Source, "=diag");
   begin
      --  Compare complete diagnostic bytes, not just failure status. The
      --  standalone Lua counterpart verifies the same pinned C suffixes.
      Assert (Result.Status = Syntax_Error, "source was not rejected");
      Assert (To_String (Result.Error.Message) = Expected,
              "diagnostic bytes: " & To_String (Result.Error.Message));
   end Check;

   procedure Invalid_Prefix is
   begin
      Check ("*a=123", "unexpected symbol near '*'");
   end Invalid_Prefix;

   procedure Expected_Name is
   begin
      Check ("local", "<name> expected near <eof>");
   end Expected_Name;

   procedure Short_String is
   begin
      --  The delimiters remain visible around the decoded string token.
      Check ("'aa'", "unexpected symbol near ''aa''");
   end Short_String;

   procedure Long_String is
   begin
      --  Long delimiters preserve their exact equals-sign level.
      Check ("[==[aa]==]", "unexpected symbol near '[==[aa]==]'");
   end Long_String;

   procedure Control_Byte is
   begin
      Check ([1 => Character'Val (1)], "unexpected symbol near '<\1>'");
      Check ([1 => Character'Val (255)], "unexpected symbol near '<\255>'");
   end Control_Byte;

   procedure Number_Spelling is
   begin
      --  Keep the token spelling rather than reformatting its numeric value.
      Check ("1.000", "unexpected symbol near '1.000'");
   end Number_Spelling;

   procedure Semantic_Const is
   begin
      --  luaK_semerror suppresses token context for binding diagnostics.
      Check ("local a <const> = 1; a=2",
             "attempt to assign to const variable 'a'");
   end Semantic_Const;

   procedure Break_Token is
   begin
      --  Validate break before consuming it; the next token is not the cause.
      Check ("break; print(1)", "break outside loop near 'break'");
   end Break_Token;

   procedure Loaded_String_Source is
   begin
      --  A default string-load name is quoted source, while an explicit
      --  equals label strips its marker through the shared chunk-id helper.
      Execute_Check
        ("local f,e=load('local'); assert(not f and " &
         "e=='[string ""local""]:1: <name> expected near <eof>'); " &
         "f,e=load('local','=named'); assert(not f and " &
         "e=='named:1: <name> expected near <eof>')");
   end Loaded_String_Source;

   procedure Reader_Source_Label is
   begin
      --  A function reader's omitted name remains the pinned =(load) label;
      --  it must not be confused with source naming for string input.
      Execute_Check
        ("local done=false; local f,e=load(function() if done then " &
         "return nil end; done=true; return '*a=123' end); " &
         "assert(not f and e==""(load):1: unexpected symbol near '*'"")");
   end Reader_Source_Label;

   procedure Return_Count_Limit is
   begin
      --  254 fixed results fit B=count+1. One more is a syntax/encoding
      --  limit, not an internal field-packing exception or host abort.
      Execute_Check
        ("local s='return 10'..string.rep(',10',253); " &
         "assert(select('#',assert(load(s))())==254); " &
         "local f,e=load(s..',10'); assert(not f and " &
         "e:find('too many returns',1,true)); assert(6*7==42)");
   end Return_Count_Limit;

   procedure Goto_Source_Line is
   begin
      Check (Character'Val (10) & "goto absent",
             "no visible label 'absent' for <goto> at line 2");
   end Goto_Source_Line;

   procedure Duplicate_Label_Line is
   begin
      Check ("::L::" & Character'Val (10) & "::L::",
             "label 'L' already defined on line 1");
   end Duplicate_Label_Line;

   procedure Goto_Scope_Line is
   begin
      Check ("goto L; local a; ::L:: print(a)",
             "<goto L> at line 1 jumps into the scope of 'a'");
   end Goto_Scope_Line;

   procedure Embedded_Nul_Token is
   begin
      --  Preserve actual source bytes, but txtToken's C formatting ends at
      --  the first decoded NUL; no closing delimiter follows that payload.
      Check ("'a" & Character'Val (0) & "b'",
             "unexpected symbol near ''a'");
   end Embedded_Nul_Token;

   procedure Embedded_Nul_Load_Name is
   begin
      Execute_Check
        ("local f,e=load('local','=name'..string.char(0)..'tail'); " &
         "assert(not f and e=='name:1: <name> expected near <eof>'); " &
         "local c=assert(load('return 42','=name'..string.char(0).." &
         "'tail')); assert(debug.getinfo(c,'S').source=='=name')");
   end Embedded_Nul_Load_Name;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "syntax diagnostic: invalid prefix token",
                        Invalid_Prefix'Access);
      Test_Support.Add (Suite, "syntax diagnostic: expected name at EOF",
                        Expected_Name'Access);
      Test_Support.Add (Suite, "syntax diagnostic: quoted string token",
                        Short_String'Access);
      Test_Support.Add (Suite, "syntax diagnostic: long string token",
                        Long_String'Access);
      Test_Support.Add (Suite, "syntax diagnostic: control byte token",
                        Control_Byte'Access);
      Test_Support.Add (Suite, "syntax diagnostic: numeric spelling",
                        Number_Spelling'Access);
      Test_Support.Add (Suite, "syntax diagnostic: semantic const context",
                        Semantic_Const'Access);
      Test_Support.Add (Suite, "syntax diagnostic: break validation token",
                        Break_Token'Access);
      Test_Support.Add (Suite, "syntax diagnostic: loaded string source",
                        Loaded_String_Source'Access);
      Test_Support.Add (Suite, "syntax diagnostic: reader source label",
                        Reader_Source_Label'Access);
      Test_Support.Add (Suite, "syntax diagnostic: fixed return limit",
                        Return_Count_Limit'Access);
      Test_Support.Add (Suite, "syntax diagnostic: goto source line",
                        Goto_Source_Line'Access);
      Test_Support.Add (Suite, "syntax diagnostic: duplicate label line",
                        Duplicate_Label_Line'Access);
      Test_Support.Add (Suite, "syntax diagnostic: goto scope line",
                        Goto_Scope_Line'Access);
      Test_Support.Add (Suite, "syntax diagnostic: embedded NUL token",
                        Embedded_Nul_Token'Access);
      Test_Support.Add (Suite, "syntax diagnostic: embedded NUL load name",
                        Embedded_Nul_Load_Name'Access);
   end Register;
end Syntax_Diagnostic_Tests;
