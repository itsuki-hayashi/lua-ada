with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Lua.Syntax;
with Lua.Syntax_Trees;
with Test_Support;

package body Lua.Label_Diagnostic_Tests is
   procedure Check_Syntax
     (Source : String; Expected_Line : Positive; Expected_Message : String;
      Incomplete : Boolean := False);
   procedure Check_Syntax
     (Source : String; Expected_Line : Positive; Expected_Message : String;
      Incomplete : Boolean := False)
   is
      use type Lua.Syntax.Check_Status;
      Result : constant Lua.Syntax.Check_Result :=
        Lua.Syntax.Check (Source, "=label-boundary");
      Unit : Lua.Syntax_Trees.Compilation_Unit;
   begin
      --  Public diagnostic coordinates and raw text must agree with the
      --  loaded-chunk witness below. Check the shared parser's continuation
      --  classification too: semantic repeats cannot become incomplete EOF.
      Assert (Result.Status = Lua.Syntax.Syntax_Error and then
              Result.Error.Line = Expected_Line and then
              To_String (Result.Error.Message) = Expected_Message,
              "public label diagnostic: " &
                To_String (Result.Error.Message));
      Lua.Syntax_Trees.Parse
        (Unit, Source, "=label-boundary", (others => <>));
      Assert (Unit.Result.Status = Lua.Syntax.Syntax_Error and then
              Unit.Result.Incomplete_Input = Incomplete and then
              Unit.Result.Error.Line = Expected_Line,
              "label boundary changed syntax/continuation classification");
   end Check_Syntax;
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Trailing_Newline;
   procedure Trailing_Newline is
   begin
      Check_Syntax
        ("::L::" &
         ASCII.LF &
         "::L::" &
         ASCII.LF,
         2, "label 'L' already defined on line 2",
         Incomplete => False);
      --  Adjacent duplicate labels retain the last consumed delimiter line.
      Check
        ("do" & ASCII.LF &
         "  local source=""::L::\n::L::\n""" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":2: label 'L' already defined on line 2]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Trailing_Newline;

   procedure Blank_Tail;
   procedure Blank_Tail is
   begin
      Check_Syntax
        ("::L::" &
         ASCII.LF &
         "::L::" &
         ASCII.LF &
         ASCII.LF,
         2, "label 'L' already defined on line 2",
         Incomplete => False);
      --  Extra blank lines at EOF do not move the completed semantic error.
      Check
        ("do" & ASCII.LF &
         "  local source=""::L::\n::L::\n\n""" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":2: label 'L' already defined on line 2]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Blank_Tail;

   procedure Comment_Tail;
   procedure Comment_Tail is
   begin
      Check_Syntax
        ("::L::" &
         ASCII.LF &
         "::L:: -- tail" &
         ASCII.LF &
         ASCII.LF,
         2, "label 'L' already defined on line 2",
         Incomplete => False);
      --  A trailing line comment does not replace the consumed token line.
      Check
        ("do" & ASCII.LF &
         "  local source=""::L::\n::L:: -- tail\n\n" &
         """" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":2: label 'L' already defined on line 2]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Comment_Tail;

   procedure Long_Comment_Tail;
   procedure Long_Comment_Tail is
   begin
      Check_Syntax
        ("::L::" &
         ASCII.LF &
         "::L:: --[[" &
         ASCII.LF &
         ASCII.LF &
         "]]" &
         ASCII.LF,
         2, "label 'L' already defined on line 2",
         Incomplete => False);
      --  A scanned multiline comment cannot move the semantic error to EOF.
      Check
        ("do" & ASCII.LF &
         "  local source=""::L::\n::L:: --[[\n\n]]\" &
         "n""" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":2: label 'L' already defined on line 2]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Long_Comment_Tail;

   procedure Split_Label;
   procedure Split_Label is
   begin
      Check_Syntax
        ("::L::" &
         ASCII.LF &
         "::" &
         ASCII.LF &
         "L" &
         ASCII.LF &
         "::" &
         ASCII.LF,
         4, "label 'L' already defined on line 2",
         Incomplete => False);
      --  The error uses the closing delimiter while the cited definition
      --  uses its opener.
      Check
        ("do" & ASCII.LF &
         "  local source=""::L::\n::\nL\n::\n""" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":4: label 'L' already defined on line 2]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Split_Label;

   procedure Semicolon_Tail;
   procedure Semicolon_Tail is
   begin
      Check_Syntax
        ("::L::" &
         ASCII.LF &
         "::L::" &
         ASCII.LF &
         ";" &
         ASCII.LF,
         3, "label 'L' already defined on line 2",
         Incomplete => False);
      --  A consumed no-op semicolon participates in the native last-token
      --  line.
      Check
        ("do" & ASCII.LF &
         "  local source=""::L::\n::L::\n;\n""" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":3: label 'L' already defined on line 2]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Semicolon_Tail;

   procedure Triple_Run;
   procedure Triple_Run is
   begin
      Check_Syntax
        ("::L::" &
         ASCII.LF &
         "::X::" &
         ASCII.LF &
         "::L::" &
         ASCII.LF,
         3, "label 'L' already defined on line 3",
         Incomplete => False);
      --  The final label in an adjacent run is defined before earlier
      --  labels.
      Check
        ("do" & ASCII.LF &
         "  local source=""::L::\n::X::\n::L::\n""" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":3: label 'L' already defined on line 3]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Triple_Run;

   procedure Separated_Definition;
   procedure Separated_Definition is
   begin
      Check_Syntax
        ("::L::" &
         ASCII.LF &
         "local x=0" &
         ASCII.LF &
         "::L::" &
         ASCII.LF,
         3, "label 'L' already defined on line 1",
         Incomplete => False);
      --  A prior completed run remains visible to a later duplicate.
      Check
        ("do" & ASCII.LF &
         "  local source=""::L::\nlocal x=0\n::L::\" &
         "n""" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":3: label 'L' already defined on line 1]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Separated_Definition;

   procedure Nested_Shadow;
   procedure Nested_Shadow is
   begin
      Check_Syntax
        ("::L::" &
         ASCII.LF &
         "do" &
         ASCII.LF &
         "::L::" &
         ASCII.LF &
         "end" &
         ASCII.LF,
         3, "label 'L' already defined on line 1",
         Incomplete => False);
      --  An active outer label still prevents an inner duplicate.
      Check
        ("do" & ASCII.LF &
         "  local source=""::L::\ndo\n::L::\nend\n""" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":3: label 'L' already defined on line 1]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Nested_Shadow;

   procedure Following_Return;
   procedure Following_Return is
   begin
      Check_Syntax
        ("::L::" &
         ASCII.LF &
         "::L::" &
         ASCII.LF &
         "return",
         2, "label 'L' already defined on line 2",
         Incomplete => False);
      --  An unconsumed real statement does not supply the semantic line.
      Check
        ("do" & ASCII.LF &
         "  local source=""::L::\n::L::\nreturn""" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":2: label 'L' already defined on line 2]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Following_Return;

   procedure Following_String;
   procedure Following_String is
   begin
      Check_Syntax
        ("::L::" &
         ASCII.LF &
         "::L::" &
         ASCII.LF &
         "[=[" &
         ASCII.LF &
         "text" &
         ASCII.LF &
         "]=]",
         2, "label 'L' already defined on line 2",
         Incomplete => False);
      --  A following multiline lookahead token does not replace last
      --  consumed line.
      Check
        ("do" & ASCII.LF &
         "  local source=""::L::\n::L::\n[=[\ntext\" &
         "n]=]""" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":2: label 'L' already defined on line 2]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end Following_String;

   procedure CRLF_Tail;
   procedure CRLF_Tail is
   begin
      Check_Syntax
        ("::L::" &
         ASCII.CR &
         ASCII.LF &
         "::L::" &
         ASCII.CR &
         ASCII.LF,
         2, "label 'L' already defined on line 2",
         Incomplete => False);
      --  A CRLF boundary preserves the same native semantic source line.
      Check
        ("do" & ASCII.LF &
         "  local source=""::L::\r\n::L::\r\n""" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":2: label 'L' already defined on line 2]" &
         "=],tostring(e))" & ASCII.LF &
         "end");
   end CRLF_Tail;

   procedure Malformed_Later_Label;
   procedure Malformed_Later_Label is
   begin
      Check_Syntax
        ("::L::" &
         ASCII.LF &
         "::L::" &
         ASCII.LF &
         "::oops" &
         ASCII.LF,
         4, "'::' expected near <eof>",
         Incomplete => True);
      --  A later malformed adjacent label fails before deferred repeat
      --  checks.
      Check
        ("do" & ASCII.LF &
         "  local source=""::L::\n::L::\n::oops\n""" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":4: '::' expected near <eof>]=],tostring" &
         "(e))" & ASCII.LF &
         "end");
   end Malformed_Later_Label;

   procedure Ordinary_Expectation;
   procedure Ordinary_Expectation is
   begin
      Check_Syntax
        ("local" &
         ASCII.LF,
         2, "<name> expected near <eof>",
         Incomplete => True);
      --  Unrelated syntax errors retain the current scanned token line.
      Check
        ("do" & ASCII.LF &
         "  local source=""local\n""" & ASCII.LF &
         "  local f,e=load(source,'=label-boundary" &
         "')" & ASCII.LF &
         "  assert(f==nil and e==[=[label-boundary" &
         ":2: <name> expected near <eof>]=],tostri" &
         "ng(e))" & ASCII.LF &
         "end");
   end Ordinary_Expectation;

   procedure Backward_Run;
   procedure Backward_Run is
   begin
      --  All adjacent valid labels are visible to later backward gotos.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load('local n=0;::A:: :" &
         ":B:: n=n+1;if n<3 then goto A end;return" &
         " n'))" & ASCII.LF &
         "  assert(f()==3)" & ASCII.LF &
         "end");
   end Backward_Run;

   procedure Disjoint_Blocks;
   procedure Disjoint_Blocks is
   begin
      --  A label leaves visibility when its actual block closes.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load('do ::L:: end do :" &
         ":L:: end return 7'));assert(f()==7)" & ASCII.LF &
         "end");
   end Disjoint_Blocks;

   procedure Function_Scope;
   procedure Function_Scope is
   begin
      --  A function owns its own independent label namespace.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load('::L:: local funct" &
         "ion f()::L:: return 7 end return f()'));" &
         "assert(f()==7)" & ASCII.LF &
         "end");
   end Function_Scope;

   procedure Terminal_Run;
   procedure Terminal_Run is
   begin
      --  Every terminal label in a no-op run stays outside closed local
      --  scope.
      Check
        ("do" & ASCII.LF &
         "  local f=assert(load('goto A;local x=7;" &
         "::A:: ; ::B::'));assert(select('#',f())=" &
         "=0)" & ASCII.LF &
         "end");
   end Terminal_Run;

   procedure Reader_Precedence;
   procedure Reader_Precedence is
   begin
      --  A real reader reaches the malformed later label before repeat
      --  checks.
      Check
        ("do" & ASCII.LF &
         "  local parts={'::L::','\n','::L::','\n'" &
         ",'::oops','\n'};local calls=0" & ASCII.LF &
         "  local f,e=load(function()calls=calls+1" &
         ";return parts[calls]end,'=label-reader')" & ASCII.LF &
         "  assert(f==nil and e==""label-reader:4: " &
         "'::' expected near <eof>"" and calls==#pa" &
         "rts+1,tostring(e))" & ASCII.LF &
         "end");
   end Reader_Precedence;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "label diagnostics: trailing newline",
         Trailing_Newline'Access);
      Test_Support.Add
        (Suite, "label diagnostics: blank tail",
         Blank_Tail'Access);
      Test_Support.Add
        (Suite, "label diagnostics: comment tail",
         Comment_Tail'Access);
      Test_Support.Add
        (Suite, "label diagnostics: long comment tail",
         Long_Comment_Tail'Access);
      Test_Support.Add
        (Suite, "label diagnostics: split label",
         Split_Label'Access);
      Test_Support.Add
        (Suite, "label diagnostics: semicolon tail",
         Semicolon_Tail'Access);
      Test_Support.Add
        (Suite, "label diagnostics: triple run",
         Triple_Run'Access);
      Test_Support.Add
        (Suite, "label diagnostics: separated definition",
         Separated_Definition'Access);
      Test_Support.Add
        (Suite, "label diagnostics: nested shadow",
         Nested_Shadow'Access);
      Test_Support.Add
        (Suite, "label diagnostics: following return",
         Following_Return'Access);
      Test_Support.Add
        (Suite, "label diagnostics: following string",
         Following_String'Access);
      Test_Support.Add
        (Suite, "label diagnostics: crlf tail",
         CRLF_Tail'Access);
      Test_Support.Add
        (Suite, "label diagnostics: malformed later label",
         Malformed_Later_Label'Access);
      Test_Support.Add
        (Suite, "label diagnostics: ordinary expectation",
         Ordinary_Expectation'Access);
      Test_Support.Add
        (Suite, "label diagnostics: backward run",
         Backward_Run'Access);
      Test_Support.Add
        (Suite, "label diagnostics: disjoint blocks",
         Disjoint_Blocks'Access);
      Test_Support.Add
        (Suite, "label diagnostics: function scope",
         Function_Scope'Access);
      Test_Support.Add
        (Suite, "label diagnostics: terminal run",
         Terminal_Run'Access);
      Test_Support.Add
        (Suite, "label diagnostics: reader precedence",
         Reader_Precedence'Access);
   end Register;
end Lua.Label_Diagnostic_Tests;
