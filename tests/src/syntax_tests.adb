with AUnit.Assertions; use AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Lua.Syntax; use Lua.Syntax;
with Lua.Sessions;
with Test_Support;
with Lua.Test_Configuration;

package body Syntax_Tests is
   procedure Empty;
   procedure Contextual_Global;
   procedure Global_Field;
   procedure Global_Function;
   procedure Global_Collective;
   procedure Global_Const;
   procedure Local_Prefix_Const;
   procedure Local_Override_Attribute;
   procedure Close_Syntax;
   procedure Close_Without_Initializer;
   procedure Vararg_Name;
   procedure Named_Vararg_Index_Write;
   procedure Nested_Capture;
   procedure Method;
   procedure Constructor;
   procedure Calls;
   procedure Return_Parentheses;
   procedure Precedence;
   procedure Numeric_For;
   procedure Generic_For;
   procedure Repeat_Scope;
   procedure Forward_Goto;
   procedure Backward_Goto;
   procedure Outward_Goto;
   procedure Terminal_Label;
   procedure Terminal_Label_Sequence;
   procedure Disjoint_Labels;
   procedure Function_Local_Labels;
   procedure Const_Assignment;
   procedure Captured_Const_Assignment;
   procedure Close_Assignment;
   procedure Global_Close;
   procedure Duplicate_Close;
   procedure Unknown_Attribute;
   procedure Named_Vararg_Assignment;
   procedure Vararg_Outside_Function;
   procedure Invalid_Target;
   procedure Invalid_Call_Statement;
   procedure Return_Not_Last;
   procedure Break_Outside_Loop;
   procedure Break_Across_Function;
   procedure Unresolved_Goto;
   procedure Duplicate_Label;
   procedure Shadowed_Label;
   procedure Hidden_Label;
   procedure Into_Local_Scope;
   procedure Into_Global_Scope;
   procedure Into_Repeat_Scope;
   procedure Goto_Across_Function;
   procedure Restricted_Global;
   procedure Malformed_Number;
   procedure Malformed_String;
   procedure Unexpected_Byte;
   procedure Syntax_Before_Lexical;
   procedure Function_Recursion;
   procedure Environment_Const;
   procedure Vararg_Chunk;
   procedure Parenthesized_Call;
   procedure Numeric_Control_Const;
   procedure Generic_Control_Const;
   procedure Generic_Value_Mutable;
   procedure Nested_Loop_Control_Const;
   procedure Label_After_Return;
   procedure Environment_Declared_Global;
   procedure Const_Global_Assignment;
   procedure Collective_Global_Assignment;
   procedure Nested_Undeclared_Global;
   procedure Forward_Label_Across_Function;
   procedure Node_Budget;
   procedure Flat_Chunk_Check;
   procedure Flat_Chunk_Execute;
   procedure Explicit_Global_Attribute;
   procedure Depth_Budget;
   procedure Token_Budget;
   procedure Source_Budget;
   procedure Arbitrary_Bounds;
   procedure Session_Unaffected;
   procedure Nested_Label_Execution;
   procedure Complete_Validation_First;
   procedure Require (Source : String; Accepted : Boolean);

   procedure Require (Source : String; Accepted : Boolean) is
      Result : constant Check_Result := Check (Source, "syntax-case");
   begin
      Assert ((Result.Status = Success) = Accepted,
              To_String (Result.Error.Message));
      if not Accepted then
         Assert (Result.Status = Syntax_Error, "controlled syntax failure");
         Assert (Length (Result.Error.Message) > 0, "explanatory message");
         Assert (Result.Error.Source = "syntax-case", "owned source label");
      end if;
   end Require;

   procedure Empty is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("",
         True);
   end Empty;

   procedure Contextual_Global is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local global = 1; return global",
         Lua.Test_Configuration.Compatible_Global);
   end Contextual_Global;

   procedure Global_Field is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local t = {global=1}; return t.global",
         Lua.Test_Configuration.Compatible_Global);
   end Global_Field;

   procedure Global_Function is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("global function f() return f end",
         True);
   end Global_Function;

   procedure Global_Collective is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("global *; return undeclared",
         True);
   end Global_Collective;

   procedure Global_Const is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("global<const> x; return x",
         True);
   end Global_Const;

   procedure Local_Prefix_Const is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local<const> x = 1; return x",
         True);
   end Local_Prefix_Const;

   procedure Local_Override_Attribute is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local<const> x, y<close> = 1, nil",
         True);
   end Local_Override_Attribute;

   procedure Close_Syntax is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local x<close> = nil",
         True);
   end Close_Syntax;

   procedure Close_Without_Initializer is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local x<close>",
         True);
   end Close_Without_Initializer;

   procedure Vararg_Name is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("return function(...args) return args, ... end",
         True);
   end Vararg_Name;

   procedure Named_Vararg_Index_Write is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("return function(...args) args[1] = 2 end",
         True);
   end Named_Vararg_Index_Write;

   procedure Nested_Capture is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local x = 1; return function() return x end",
         True);
   end Nested_Capture;

   procedure Method is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("function t:f(x, ...) return self, x, ... end",
         True);
   end Method;

   procedure Constructor is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("return {1, [2]=3, a=4; 5,}",
         True);
   end Constructor;

   procedure Calls is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("f 's'; f {}; (f)()",
         True);
   end Calls;

   procedure Return_Parentheses is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("return (f()), f()",
         True);
   end Return_Parentheses;

   procedure Precedence is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("return -2^2, 2^-2, 1..'s', true or false and nil",
         False);
   end Precedence;

   procedure Numeric_For is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("for i = 1, 10, 2 do if i > 3 then break end end",
         True);
   end Numeric_For;

   procedure Generic_For is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("for k,v in next,t do f(k,v) end",
         True);
   end Generic_For;

   procedure Repeat_Scope is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("repeat local x = f() until x",
         True);
   end Repeat_Scope;

   procedure Forward_Goto is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("goto done; ::done::",
         True);
   end Forward_Goto;

   procedure Backward_Goto is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("::again:: goto again",
         True);
   end Backward_Goto;

   procedure Outward_Goto is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("do local x; goto done end ::done::",
         True);
   end Outward_Goto;

   procedure Terminal_Label is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("goto done; local x; ::done::",
         True);
   end Terminal_Label;

   procedure Terminal_Label_Sequence is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("goto a; local x; ::a::; ::b::;;",
         True);
   end Terminal_Label_Sequence;

   procedure Disjoint_Labels is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("do ::a:: end do ::a:: end",
         True);
   end Disjoint_Labels;

   procedure Function_Local_Labels is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("::a:: local function f() ::a:: end",
         True);
   end Function_Local_Labels;

   procedure Const_Assignment is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local x<const> = 1; x = 2",
         False);
   end Const_Assignment;

   procedure Captured_Const_Assignment is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local x<const> = 1; return function() x = 2 end",
         False);
   end Captured_Const_Assignment;

   procedure Close_Assignment is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local x<close> = nil; x = nil",
         False);
   end Close_Assignment;

   procedure Global_Close is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("global x<close>",
         False);
   end Global_Close;

   procedure Duplicate_Close is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local a<close>, b<close>",
         False);
   end Duplicate_Close;

   procedure Unknown_Attribute is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local x<other>",
         False);
   end Unknown_Attribute;

   procedure Named_Vararg_Assignment is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("return function(...args) args = {} end",
         False);
   end Named_Vararg_Assignment;

   procedure Vararg_Outside_Function is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("return function() return ... end",
         False);
   end Vararg_Outside_Function;

   procedure Invalid_Target is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("(a) = 1",
         False);
   end Invalid_Target;

   procedure Invalid_Call_Statement is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("a",
         False);
   end Invalid_Call_Statement;

   procedure Return_Not_Last is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("return; a = 1",
         False);
   end Return_Not_Last;

   procedure Break_Outside_Loop is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("break",
         False);
   end Break_Outside_Loop;

   procedure Break_Across_Function is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("while true do local function f() break end end",
         False);
   end Break_Across_Function;

   procedure Unresolved_Goto is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("goto missing",
         False);
   end Unresolved_Goto;

   procedure Duplicate_Label is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("::a:: ::a::",
         False);
   end Duplicate_Label;

   procedure Shadowed_Label is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("::a:: do ::a:: end",
         False);
   end Shadowed_Label;

   procedure Hidden_Label is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("goto a; do ::a:: end",
         False);
   end Hidden_Label;

   procedure Into_Local_Scope is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("goto a; local x; ::a:: f()",
         False);
   end Into_Local_Scope;

   procedure Into_Global_Scope is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("goto a; global *; ::a:: f()",
         False);
   end Into_Global_Scope;

   procedure Into_Repeat_Scope is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("repeat goto a; local x; ::a:: until x",
         False);
   end Into_Repeat_Scope;

   procedure Goto_Across_Function is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("goto a; local function f() ::a:: end",
         False);
   end Goto_Across_Function;

   procedure Restricted_Global is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("global declared; return other",
         False);
   end Restricted_Global;

   procedure Malformed_Number is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("return 1e+",
         False);
   end Malformed_Number;

   procedure Malformed_String is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("return 'unterminated",
         False);
   end Malformed_String;

   procedure Unexpected_Byte is
      --  Reject this invalid grammar/resolution boundary without runtime work.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("@",
         False);
   end Unexpected_Byte;

   procedure Syntax_Before_Lexical is
      --  The invalid declaration on line one must win over a bad escape on
      --  line two. Eagerly scanning the whole source would report line two.
      Result : constant Check_Result := Check
        ("local =" & Character'Val (10) & "'\q'");
   begin
      Assert (Result.Status = Syntax_Error, "invalid declaration");
      Assert (Result.Error.Line = 1, "earlier grammar failure takes priority");
   end Syntax_Before_Lexical;

   procedure Function_Recursion is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local function f(n) if n == 0 then return 1 end return n*f(n" &
         "-1) end",
         True);
   end Function_Recursion;

   procedure Environment_Const is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("local _ENV<const> = {}; return x",
         True);
   end Environment_Const;

   procedure Vararg_Chunk is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("return ...",
         True);
   end Vararg_Chunk;

   procedure Parenthesized_Call is
      --  Accept this valid grammar/resolution boundary without executing it.
      --  The separately named case makes this regression visible in reports.
   begin
      Require
        ("(f)()",
         True);
   end Parenthesized_Call;

   procedure Numeric_Control_Const is
      --  Numeric control variables are read-only in Lua 5.5.
   begin
      Require
        ("for i=1,3 do i=100 end", False);
   end Numeric_Control_Const;

   procedure Generic_Control_Const is
      --  The first generic-for variable is a const control variable.
   begin
      Require
        ("for k,v in next,t do k=1 end", False);
   end Generic_Control_Const;

   procedure Generic_Value_Mutable is
      --  Additional generic-for results remain assignable locals.
   begin
      Require
        ("for k,v in next,t do v=1 end", True);
   end Generic_Value_Mutable;

   procedure Nested_Loop_Control_Const is
      --  Capturing a control variable does not remove its const restriction.
   begin
      Require
        ("for i=1,3 do local function f() i=2 end end", False);
   end Nested_Loop_Control_Const;

   procedure Label_After_Return is
      --  A return terminates the statement list, including trailing labels.
   begin
      Require
        ("return; ::done::", False);
   end Label_After_Return;

   procedure Environment_Declared_Global is
      --  An explicit global _ENV cannot supply lexical environment access.
   begin
      Require
        ("global _ENV; return x", False);
   end Environment_Declared_Global;

   procedure Const_Global_Assignment is
      --  Explicit constant globals reject assignment statically.
   begin
      Require
        ("global<const> x; x=1", False);
   end Const_Global_Assignment;

   procedure Collective_Global_Assignment is
      --  A collective const declaration constrains implicit globals.
   begin
      Require
        ("global<const> *; x=1", False);
   end Collective_Global_Assignment;

   procedure Nested_Undeclared_Global is
      --  Outer named-global restrictions also apply in nested functions.
   begin
      Require
        ("global x; return function() return y end", False);
   end Nested_Undeclared_Global;

   procedure Forward_Label_Across_Function is
      --  A terminal label is outside the local-function declaration's scope.
   begin
      Require
        ("goto done; local function f() end; ::done::", True);
   end Forward_Label_Across_Function;

   procedure Node_Budget is
      --  Tiny syntax storage must fail before an arena index can overflow.
      Result : constant Check_Result := Check
        ("local x = 1", Limits => (Syntax_Nodes => 1, others => <>));
   begin
      Assert (Result.Status = Resource_Error, "node budget");
   end Node_Budget;

   procedure Flat_Chunk_Check is
      --  99,999 statements plus EOF exactly fill the default token budget.
      --  Each statement appends to the same block. Copying that growing
      --  child list on every append would require billions of element copies.
      --  Check acceptance without a fragile machine-dependent timing bound.
      Source : constant String (1 .. 99_999) := [others => ';'];
      Result : constant Check_Result := Check (Source, "flat-check");
   begin
      Assert (Result.Status = Success, "large flat chunk checks successfully");
   end Flat_Chunk_Check;

   procedure Flat_Chunk_Execute is
      --  Ordinary execution shares the frontend, so the same large flat
      --  input must compile before its single VM return instruction runs.
      --  This also protects container-reference lifetimes during arena growth.
      Source : constant String (1 .. 99_999) := [others => ';'];
      Session : Lua.Sessions.Session;
      Result : constant Lua.Sessions.Execution_Result :=
        Session.Execute (Source, "flat-execute");
      use type Lua.Sessions.Execution_Status;
   begin
      Assert (Result.Status = Lua.Sessions.Succeeded,
              To_String (Result.Error.Message));
      Assert (Result.Output = "", "empty statements have no output");
   end Flat_Chunk_Execute;

   procedure Explicit_Global_Attribute is
      --  An outer explicit global retains its own mutability when an inner
      --  collective const declaration restricts otherwise implicit names.
   begin
      Require ("global x; do global<const> *; x=1 end", True);
   end Explicit_Global_Attribute;

   procedure Depth_Budget is
      --  Nesting failure is a resource condition, not invalid Lua grammar.
      Result : constant Check_Result := Check
        ("return (((1)))", Limits => (Nesting => 2, others => <>));
   begin
      Assert (Result.Status = Resource_Error, "nesting budget");
   end Depth_Budget;

   procedure Token_Budget is
      --  EOF counts toward the same token bound for checking and scanning.
      Result : constant Check_Result := Check
        ("return 1", Limits => (Tokens => 2, others => <>));
   begin
      Assert (Result.Status = Resource_Error, "token budget");
   end Token_Budget;

   procedure Source_Budget is
      --  Check source size before doing grammar work.
      Result : constant Check_Result := Check
        ("return 1", Limits => (Source_Bytes => 2, others => <>));
   begin
      Assert (Result.Status = Resource_Error, "source budget");
   end Source_Budget;

   procedure Arbitrary_Bounds is
      --  Source need not start at one; positions remain source-relative.
      Source : constant String (40 .. 47) := "return 1";
      Result : constant Check_Result := Check (Source);
   begin
      Assert (Result.Status = Success, "arbitrary Ada lower bound");
   end Arbitrary_Bounds;

   procedure Session_Unaffected is
      --  Checking cannot mutate an independently owned persistent session.
      Session : Lua.Sessions.Session;
      First : constant Lua.Sessions.Execution_Result :=
        Session.Execute ("x = 41");
      Checked : constant Check_Result := Check ("x = 99; print(x)");
      Last : constant Lua.Sessions.Execution_Result :=
        Session.Execute ("print(x)");
      use type Lua.Sessions.Execution_Status;
   begin
      Assert (First.Status = Lua.Sessions.Succeeded, "session setup");
      Assert (Checked.Status = Success, "check source accepted");
      Assert (Last.Output = "41" & Character'Val (10), "no checking effects");
   end Session_Unaffected;

   procedure Nested_Label_Execution is
      --  A label in a nested function is executable syntax. The outer
      --  chunk must run and retain its normal session side effects.
      Session : Lua.Sessions.Session;
      Result : constant Lua.Sessions.Execution_Result := Session.Execute
        ("x = 99; local function f() ::done:: end; print(x)");
      Later : constant Lua.Sessions.Execution_Result :=
        Session.Execute ("print(x)");
      use type Lua.Sessions.Execution_Status;
   begin
      Assert (Result.Status = Lua.Sessions.Succeeded,
              "resolved nested label executes");
      Assert (Result.Output = "99" & Character'Val (10), "chunk output");
      Assert (Later.Output = "99" & Character'Val (10), "persistent global");
   end Nested_Label_Execution;

   procedure Complete_Validation_First is
      --  A valid label cannot hide a syntax error later in the chunk.
      Session : Lua.Sessions.Session;
      Result : constant Lua.Sessions.Execution_Result :=
        Session.Execute ("::done:: local = 1");
      use type Lua.Sessions.Execution_Status;
   begin
      Assert (Result.Status = Lua.Sessions.Syntax_Error, "syntax first");
   end Complete_Validation_First;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "syntax: large flat chunk checking", Flat_Chunk_Check'Access);
      Test_Support.Add
        (Suite, "syntax: large flat chunk execution",
         Flat_Chunk_Execute'Access);
      Test_Support.Add
        (Suite, "syntax: explicit global attribute",
         Explicit_Global_Attribute'Access);
      Test_Support.Add
        (Suite, "syntax: Empty",
         Empty'Access);
      Test_Support.Add
        (Suite, "syntax: Contextual_Global",
         Contextual_Global'Access);
      Test_Support.Add
        (Suite, "syntax: Global_Field",
         Global_Field'Access);
      Test_Support.Add
        (Suite, "syntax: Global_Function",
         Global_Function'Access);
      Test_Support.Add
        (Suite, "syntax: Global_Collective",
         Global_Collective'Access);
      Test_Support.Add
        (Suite, "syntax: Global_Const",
         Global_Const'Access);
      Test_Support.Add
        (Suite, "syntax: Local_Prefix_Const",
         Local_Prefix_Const'Access);
      Test_Support.Add
        (Suite, "syntax: Local_Override_Attribute",
         Local_Override_Attribute'Access);
      Test_Support.Add
        (Suite, "syntax: Close_Syntax",
         Close_Syntax'Access);
      Test_Support.Add
        (Suite, "syntax: Close_Without_Initializer",
         Close_Without_Initializer'Access);
      Test_Support.Add
        (Suite, "syntax: Vararg_Name",
         Vararg_Name'Access);
      Test_Support.Add
        (Suite, "syntax: Named_Vararg_Index_Write",
         Named_Vararg_Index_Write'Access);
      Test_Support.Add
        (Suite, "syntax: Nested_Capture",
         Nested_Capture'Access);
      Test_Support.Add
        (Suite, "syntax: Method",
         Method'Access);
      Test_Support.Add
        (Suite, "syntax: Constructor",
         Constructor'Access);
      Test_Support.Add
        (Suite, "syntax: Calls",
         Calls'Access);
      Test_Support.Add
        (Suite, "syntax: Return_Parentheses",
         Return_Parentheses'Access);
      Test_Support.Add
        (Suite, "syntax: Precedence",
         Precedence'Access);
      Test_Support.Add
        (Suite, "syntax: Numeric_For",
         Numeric_For'Access);
      Test_Support.Add
        (Suite, "syntax: Generic_For",
         Generic_For'Access);
      Test_Support.Add
        (Suite, "syntax: Repeat_Scope",
         Repeat_Scope'Access);
      Test_Support.Add
        (Suite, "syntax: Forward_Goto",
         Forward_Goto'Access);
      Test_Support.Add
        (Suite, "syntax: Backward_Goto",
         Backward_Goto'Access);
      Test_Support.Add
        (Suite, "syntax: Outward_Goto",
         Outward_Goto'Access);
      Test_Support.Add
        (Suite, "syntax: Terminal_Label",
         Terminal_Label'Access);
      Test_Support.Add
        (Suite, "syntax: Terminal_Label_Sequence",
         Terminal_Label_Sequence'Access);
      Test_Support.Add
        (Suite, "syntax: Disjoint_Labels",
         Disjoint_Labels'Access);
      Test_Support.Add
        (Suite, "syntax: Function_Local_Labels",
         Function_Local_Labels'Access);
      Test_Support.Add
        (Suite, "syntax: Const_Assignment",
         Const_Assignment'Access);
      Test_Support.Add
        (Suite, "syntax: Captured_Const_Assignment",
         Captured_Const_Assignment'Access);
      Test_Support.Add
        (Suite, "syntax: Close_Assignment",
         Close_Assignment'Access);
      Test_Support.Add
        (Suite, "syntax: Global_Close",
         Global_Close'Access);
      Test_Support.Add
        (Suite, "syntax: Duplicate_Close",
         Duplicate_Close'Access);
      Test_Support.Add
        (Suite, "syntax: Unknown_Attribute",
         Unknown_Attribute'Access);
      Test_Support.Add
        (Suite, "syntax: Named_Vararg_Assignment",
         Named_Vararg_Assignment'Access);
      Test_Support.Add
        (Suite, "syntax: Vararg_Outside_Function",
         Vararg_Outside_Function'Access);
      Test_Support.Add
        (Suite, "syntax: Invalid_Target",
         Invalid_Target'Access);
      Test_Support.Add
        (Suite, "syntax: Invalid_Call_Statement",
         Invalid_Call_Statement'Access);
      Test_Support.Add
        (Suite, "syntax: Return_Not_Last",
         Return_Not_Last'Access);
      Test_Support.Add
        (Suite, "syntax: Break_Outside_Loop",
         Break_Outside_Loop'Access);
      Test_Support.Add
        (Suite, "syntax: Break_Across_Function",
         Break_Across_Function'Access);
      Test_Support.Add
        (Suite, "syntax: Unresolved_Goto",
         Unresolved_Goto'Access);
      Test_Support.Add
        (Suite, "syntax: Duplicate_Label",
         Duplicate_Label'Access);
      Test_Support.Add
        (Suite, "syntax: Shadowed_Label",
         Shadowed_Label'Access);
      Test_Support.Add
        (Suite, "syntax: Hidden_Label",
         Hidden_Label'Access);
      Test_Support.Add
        (Suite, "syntax: Into_Local_Scope",
         Into_Local_Scope'Access);
      Test_Support.Add
        (Suite, "syntax: Into_Global_Scope",
         Into_Global_Scope'Access);
      Test_Support.Add
        (Suite, "syntax: Into_Repeat_Scope",
         Into_Repeat_Scope'Access);
      Test_Support.Add
        (Suite, "syntax: Goto_Across_Function",
         Goto_Across_Function'Access);
      Test_Support.Add
        (Suite, "syntax: Restricted_Global",
         Restricted_Global'Access);
      Test_Support.Add
        (Suite, "syntax: Malformed_Number",
         Malformed_Number'Access);
      Test_Support.Add
        (Suite, "syntax: Malformed_String",
         Malformed_String'Access);
      Test_Support.Add
        (Suite, "syntax: Unexpected_Byte",
         Unexpected_Byte'Access);
      Test_Support.Add
        (Suite, "syntax: Syntax_Before_Lexical",
         Syntax_Before_Lexical'Access);
      Test_Support.Add
        (Suite, "syntax: Function_Recursion",
         Function_Recursion'Access);
      Test_Support.Add
        (Suite, "syntax: Environment_Const",
         Environment_Const'Access);
      Test_Support.Add
        (Suite, "syntax: Vararg_Chunk",
         Vararg_Chunk'Access);
      Test_Support.Add
        (Suite, "syntax: Parenthesized_Call",
         Parenthesized_Call'Access);
      Test_Support.Add
        (Suite, "syntax: Numeric_Control_Const",
         Numeric_Control_Const'Access);
      Test_Support.Add
        (Suite, "syntax: Generic_Control_Const",
         Generic_Control_Const'Access);
      Test_Support.Add
        (Suite, "syntax: Generic_Value_Mutable",
         Generic_Value_Mutable'Access);
      Test_Support.Add
        (Suite, "syntax: Nested_Loop_Control_Const",
         Nested_Loop_Control_Const'Access);
      Test_Support.Add
        (Suite, "syntax: Label_After_Return",
         Label_After_Return'Access);
      Test_Support.Add
        (Suite, "syntax: Environment_Declared_Global",
         Environment_Declared_Global'Access);
      Test_Support.Add
        (Suite, "syntax: Const_Global_Assignment",
         Const_Global_Assignment'Access);
      Test_Support.Add
        (Suite, "syntax: Collective_Global_Assignment",
         Collective_Global_Assignment'Access);
      Test_Support.Add
        (Suite, "syntax: Nested_Undeclared_Global",
         Nested_Undeclared_Global'Access);
      Test_Support.Add
        (Suite, "syntax: Forward_Label_Across_Function",
         Forward_Label_Across_Function'Access);
      Test_Support.Add
        (Suite, "syntax: Node_Budget",
         Node_Budget'Access);
      Test_Support.Add
        (Suite, "syntax: Depth_Budget",
         Depth_Budget'Access);
      Test_Support.Add
        (Suite, "syntax: Token_Budget",
         Token_Budget'Access);
      Test_Support.Add
        (Suite, "syntax: Source_Budget",
         Source_Budget'Access);
      Test_Support.Add
        (Suite, "syntax: Arbitrary_Bounds",
         Arbitrary_Bounds'Access);
      Test_Support.Add
        (Suite, "syntax: Session_Unaffected",
         Session_Unaffected'Access);
      Test_Support.Add
        (Suite, "syntax: Nested_Label_Execution",
         Nested_Label_Execution'Access);
      Test_Support.Add
        (Suite, "syntax: Complete_Validation_First",
         Complete_Validation_First'Access);
   end Register;
end Syntax_Tests;
