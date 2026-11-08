with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Lua.Syntax;
with Lua.Syntax_Trees;
with Test_Support;

package body Lua.Close_Declaration_Tests is
   procedure Check_Syntax
     (Source : String; Expected_Line : Positive; Expected_Message : String;
      Incomplete : Boolean := False);
   procedure Check_Syntax
     (Source : String; Expected_Line : Positive; Expected_Message : String;
      Incomplete : Boolean := False)
   is
      use type Lua.Syntax.Check_Status;
      Result : constant Lua.Syntax.Check_Result :=
        Lua.Syntax.Check (Source, "=close-declaration");
      Unit : Lua.Syntax_Trees.Compilation_Unit;
   begin
      --  Public diagnostic coordinates and raw text must agree with the
      --  loaded-chunk witness below. Check the shared parser's continuation
      --  classification too: semantic checks cannot become incomplete EOF.
      Assert (Result.Status = Lua.Syntax.Syntax_Error and then
              Result.Error.Line = Expected_Line and then
              To_String (Result.Error.Message) = Expected_Message,
              "public closing diagnostic: " &
                To_String (Result.Error.Message));
      Lua.Syntax_Trees.Parse
        (Unit, Source, "=close-declaration", (others => <>));
      Assert (Unit.Result.Status = Lua.Syntax.Syntax_Error and then
              Unit.Result.Incomplete_Input = Incomplete and then
              Unit.Result.Error.Line = Expected_Line,
              "closing boundary changed syntax/continuation classification");
   end Check_Syntax;
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Prefix_Newline;
   procedure Prefix_Newline is
   begin
      Check_Syntax
        ("local <close> a,b" &
         ASCII.LF,
         1, "multiple to-be-closed variables in local list",
         Incomplete => False);
      --  A trailing LF does not move the completed closing declaration
      --  error.
      Check
        ("do" & ASCII.LF &
         "  local source=""local <close> a,b\n""" & ASCII.LF &
         "  local f,e=load(source,'=close-declarat" &
         "ion')" & ASCII.LF &
         "  assert(f==nil and e==[=[close-declarat" &
         "ion:1: multiple to-be-closed variables i" &
         "n local list]=],tostring(e))" & ASCII.LF &
         "end");
   end Prefix_Newline;

   procedure Blank_Tail;
   procedure Blank_Tail is
   begin
      Check_Syntax
        ("local <close> a,b" &
         ASCII.LF &
         ASCII.LF,
         1, "multiple to-be-closed variables in local list",
         Incomplete => False);
      --  Blank EOF lines preserve the last consumed variable's source line.
      Check
        ("do" & ASCII.LF &
         "  local source=""local <close> a,b\n\n""" & ASCII.LF &
         "  local f,e=load(source,'=close-declarat" &
         "ion')" & ASCII.LF &
         "  assert(f==nil and e==[=[close-declarat" &
         "ion:1: multiple to-be-closed variables i" &
         "n local list]=],tostring(e))" & ASCII.LF &
         "end");
   end Blank_Tail;

   procedure Comment_Tail;
   procedure Comment_Tail is
   begin
      Check_Syntax
        ("local <close> a,b --tail" &
         ASCII.LF &
         ASCII.LF,
         1, "multiple to-be-closed variables in local list",
         Incomplete => False);
      --  A scanned line comment is not the semantic declaration token.
      Check
        ("do" & ASCII.LF &
         "  local source=""local <close> a,b --tail" &
         "\n\n""" & ASCII.LF &
         "  local f,e=load(source,'=close-declarat" &
         "ion')" & ASCII.LF &
         "  assert(f==nil and e==[=[close-declarat" &
         "ion:1: multiple to-be-closed variables i" &
         "n local list]=],tostring(e))" & ASCII.LF &
         "end");
   end Comment_Tail;

   procedure Long_Comment_Tail;
   procedure Long_Comment_Tail is
   begin
      Check_Syntax
        ("local <close> a,b --[[" &
         ASCII.LF &
         ASCII.LF &
         "]]" &
         ASCII.LF,
         1, "multiple to-be-closed variables in local list",
         Incomplete => False);
      --  A multiline trailing comment does not become the semantic error
      --  line.
      Check
        ("do" & ASCII.LF &
         "  local source=""local <close> a,b --[[\n" &
         "\n]]\n""" & ASCII.LF &
         "  local f,e=load(source,'=close-declarat" &
         "ion')" & ASCII.LF &
         "  assert(f==nil and e==[=[close-declarat" &
         "ion:1: multiple to-be-closed variables i" &
         "n local list]=],tostring(e))" & ASCII.LF &
         "end");
   end Long_Comment_Tail;

   procedure Semicolon_Lookahead;
   procedure Semicolon_Lookahead is
   begin
      Check_Syntax
        ("local <close> a,b" &
         ASCII.LF &
         ";" &
         ASCII.LF,
         1, "multiple to-be-closed variables in local list",
         Incomplete => False);
      --  An unconsumed semicolon differs from the no-op label run's consumed
      --  semicolon.
      Check
        ("do" & ASCII.LF &
         "  local source=""local <close> a,b\n;\n""" & ASCII.LF &
         "  local f,e=load(source,'=close-declarat" &
         "ion')" & ASCII.LF &
         "  assert(f==nil and e==[=[close-declarat" &
         "ion:1: multiple to-be-closed variables i" &
         "n local list]=],tostring(e))" & ASCII.LF &
         "end");
   end Semicolon_Lookahead;

   procedure Next_Name_Line;
   procedure Next_Name_Line is
   begin
      Check_Syntax
        ("local <close> a," &
         ASCII.LF &
         " b" &
         ASCII.LF,
         2, "multiple to-be-closed variables in local list",
         Incomplete => False);
      --  The second variable's own consumed line supplies the
      --  duplicate-closing error.
      Check
        ("do" & ASCII.LF &
         "  local source=""local <close> a,\n b\n""" & ASCII.LF &
         "  local f,e=load(source,'=close-declarat" &
         "ion')" & ASCII.LF &
         "  assert(f==nil and e==[=[close-declarat" &
         "ion:2: multiple to-be-closed variables i" &
         "n local list]=],tostring(e))" & ASCII.LF &
         "end");
   end Next_Name_Line;

   procedure Explicit_Attributes;
   procedure Explicit_Attributes is
   begin
      Check_Syntax
        ("local a<close>,b<close>" &
         ASCII.LF,
         1, "multiple to-be-closed variables in local list",
         Incomplete => False);
      --  Explicit closing attributes use the same completed semantic check.
      Check
        ("do" & ASCII.LF &
         "  local source=""local a<close>,b<close>\" &
         "n""" & ASCII.LF &
         "  local f,e=load(source,'=close-declarat" &
         "ion')" & ASCII.LF &
         "  assert(f==nil and e==[=[close-declarat" &
         "ion:1: multiple to-be-closed variables i" &
         "n local list]=],tostring(e))" & ASCII.LF &
         "end");
   end Explicit_Attributes;

   procedure Split_Attributes;
   procedure Split_Attributes is
   begin
      Check_Syntax
        ("local a<close>," &
         ASCII.LF &
         " b<" &
         ASCII.LF &
         " close" &
         ASCII.LF &
         " >" &
         ASCII.LF,
         4, "multiple to-be-closed variables in local list",
         Incomplete => False);
      --  A split attribute reports the consumed closing angle rather than
      --  the name.
      Check
        ("do" & ASCII.LF &
         "  local source=""local a<close>,\n b<\n c" &
         "lose\n >\n""" & ASCII.LF &
         "  local f,e=load(source,'=close-declarat" &
         "ion')" & ASCII.LF &
         "  assert(f==nil and e==[=[close-declarat" &
         "ion:4: multiple to-be-closed variables i" &
         "n local list]=],tostring(e))" & ASCII.LF &
         "end");
   end Split_Attributes;

   procedure CRLF_Tail;
   procedure CRLF_Tail is
   begin
      Check_Syntax
        ("local <close> a,b" &
         ASCII.CR &
         ASCII.LF,
         1, "multiple to-be-closed variables in local list",
         Incomplete => False);
      --  CRLF input retains the consumed declaration line.
      Check
        ("do" & ASCII.LF &
         "  local source=""local <close> a,b\r\n""" & ASCII.LF &
         "  local f,e=load(source,'=close-declarat" &
         "ion')" & ASCII.LF &
         "  assert(f==nil and e==[=[close-declarat" &
         "ion:1: multiple to-be-closed variables i" &
         "n local list]=],tostring(e))" & ASCII.LF &
         "end");
   end CRLF_Tail;

   procedure Incomplete_Attribute;
   procedure Incomplete_Attribute is
   begin
      Check_Syntax
        ("local <close> a," &
         ASCII.LF &
         "b<" &
         ASCII.LF,
         3, "<name> expected near <eof>",
         Incomplete => True);
      --  An unfinished attribute still wins as a continuable syntax error.
      Check
        ("do" & ASCII.LF &
         "  local source=""local <close> a,\nb<\n""" & ASCII.LF &
         "  local f,e=load(source,'=close-declarat" &
         "ion')" & ASCII.LF &
         "  assert(f==nil and e==[=[close-declarat" &
         "ion:3: <name> expected near <eof>]=],tos" &
         "tring(e))" & ASCII.LF &
         "end");
   end Incomplete_Attribute;

   procedure Single_Closing;
   procedure Single_Closing is
   begin
      --  A single explicit closer retains its actual once-only handler
      --  lifetime.
      Check
        ("do" & ASCII.LF &
         "  local count=0" & ASCII.LF &
         "  do local a<close>,b=setmetatable({},{_" &
         "_close=function()count=count+1 end}),7;a" &
         "ssert(b==7)end" & ASCII.LF &
         "  assert(count==1)" & ASCII.LF &
         "end");
   end Single_Closing;

   procedure Attribute_Override;
   procedure Attribute_Override is
   begin
      --  An explicit const overrides a prefixed closing default for that
      --  name.
      Check
        ("do" & ASCII.LF &
         "  local <close> a,b<const> = nil,7;asser" &
         "t(b==7)" & ASCII.LF &
         "end");
   end Attribute_Override;

   procedure Reader_Stop;
   procedure Reader_Stop is
   begin
      --  A real reader stops at the completed semantic declaration failure.
      Check
        ("do" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local f,e=load(function()" & ASCII.LF &
         "    calls=calls+1" & ASCII.LF &
         "    if calls==1 then return 'local <clos" &
         "e> a,b'" & ASCII.LF &
         "    elseif calls==2 then return ';more'" & ASCII.LF &
         "    else error('unexpected reader contin" &
         "uation')end" & ASCII.LF &
         "  end,'=close-reader')" & ASCII.LF &
         "  assert(f==nil and e=='close-reader:1: " &
         "multiple to-be-closed variables in local" &
         " list' and calls==2,tostring(e))" & ASCII.LF &
         "end");
   end Reader_Stop;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "close declaration: prefix newline",
         Prefix_Newline'Access);
      Test_Support.Add
        (Suite, "close declaration: blank tail",
         Blank_Tail'Access);
      Test_Support.Add
        (Suite, "close declaration: comment tail",
         Comment_Tail'Access);
      Test_Support.Add
        (Suite, "close declaration: long comment tail",
         Long_Comment_Tail'Access);
      Test_Support.Add
        (Suite, "close declaration: semicolon lookahead",
         Semicolon_Lookahead'Access);
      Test_Support.Add
        (Suite, "close declaration: next name line",
         Next_Name_Line'Access);
      Test_Support.Add
        (Suite, "close declaration: explicit attributes",
         Explicit_Attributes'Access);
      Test_Support.Add
        (Suite, "close declaration: split attributes",
         Split_Attributes'Access);
      Test_Support.Add
        (Suite, "close declaration: crlf tail",
         CRLF_Tail'Access);
      Test_Support.Add
        (Suite, "close declaration: incomplete attribute",
         Incomplete_Attribute'Access);
      Test_Support.Add
        (Suite, "close declaration: single closing",
         Single_Closing'Access);
      Test_Support.Add
        (Suite, "close declaration: attribute override",
         Attribute_Override'Access);
      Test_Support.Add
        (Suite, "close declaration: reader stop",
         Reader_Stop'Access);
   end Register;
end Lua.Close_Declaration_Tests;
