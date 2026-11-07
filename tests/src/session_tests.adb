with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;
with Lua.Test_Configuration;

package body Session_Tests is
   procedure Check (Source, Expected : String);
   procedure Bitwise_String_Left;
   procedure Bitwise_String_Right;
   procedure Bitwise_String_Unary;
   procedure Named_Vararg_Mutation;
   procedure Select_Hash_Prefix;
   procedure Ipairs_Lazy_State;
   procedure Power_Overflow;
   procedure Method_Self_Is_Scalar;
   procedure Precedence;
   procedure Unary_Power;
   procedure Power_Associativity;
   procedure Float_Formatting;
   procedure Integer_Wrapping;
   procedure Floor_Division;
   procedure Modulo_Sign;
   procedure Logical_Shift;
   procedure Mixed_Key_Equality;
   procedure Large_Integer_Key;
   procedure Truthiness;
   procedure Short_Circuit;
   procedure Local_Shadowing;
   procedure Local_Initializer_Scope;
   procedure Captured_Mutation;
   procedure Recursive_Function;
   procedure Multiple_Results;
   procedure Nonfinal_Call_Collapses;
   procedure Parentheses_Collapse;
   procedure Varargs_Preserve_Nil;
   procedure Assignment_Snapshot;
   procedure Repeated_Assignment_Target;
   procedure Table_Last_Call_Expands;
   procedure Numeric_For;
   procedure Descending_For;
   procedure For_Overflow_Terminates;
   procedure For_Iteration_Captures;
   procedure Generic_For;
   procedure False_Iterator_Control;
   procedure Repeat_Local_Condition;
   procedure Nested_Break;
   procedure Method_Syntax;
   procedure Global_Keyword_Name;
   procedure Explicit_Globals;
   procedure Global_Without_Initializer;
   procedure Global_Shadowed_Environment;
   procedure Environment_Shadowing;
   procedure Protected_Error;
   procedure Nested_Protected_Call;
   procedure Error_Nil;
   procedure Byte_String_Length;
   procedure Explicit_Base_Conversion;
   procedure Table_Cycle;
   procedure Primitive_Infinity;
   procedure Display_All_Results;
   procedure Display_Result_Roots;
   procedure Display_Environment_Handler;
   procedure Display_Error_Recovery;
   procedure Display_Bounded_Policy;
   procedure Host_Warning_Control;

   procedure Check (Source, Expected : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source, "test");
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Assert (To_String (Result.Output) = Expected &
              Ada.Characters.Latin_1.LF,
              "unexpected output: " & To_String (Result.Output));
   end Check;

   procedure Precedence is
      --  Multiplication binds more tightly than addition.
   begin
      Check
       (
        "print(2+3*4)",
         "14");
   end Precedence;

   procedure Unary_Power is
      --  Exponentiation binds more tightly than a leading unary minus.
   begin
      Check
       (
        "print(-2^2)",
         "-4.0");
   end Unary_Power;

   procedure Power_Associativity is
      --  Exponentiation groups right-to-left.
   begin
      Check
       (
        "print(2^3^2)",
         "512.0");
   end Power_Associativity;

   procedure Float_Formatting is
      --  Integer-looking floats keep their Lua .0 suffix.
   begin
      Check
       (
        "print(1.0, 1.25, 0.00001)",
         "1.0" & Ada.Characters.Latin_1.HT &
         "1.25" & Ada.Characters.Latin_1.HT &
         "1e-05");
   end Float_Formatting;

   procedure Integer_Wrapping is
      --  Integer arithmetic wraps while Ada range checks remain enabled.
   begin
      Check
       (
        "print(9223372036854775807+1)",
         "-9223372036854775808");
   end Integer_Wrapping;

   procedure Floor_Division is
      --  Floor division rounds toward minus infinity for negative operands.
   begin
      Check
       (
        "print(-7//3, 7//-3)",
         "-3" & Ada.Characters.Latin_1.HT &
         "-3");
   end Floor_Division;

   procedure Modulo_Sign is
      --  Integer remainder follows the divisor sign.
   begin
      Check
       (
        "print(-7%3, 7%-3)",
         "2" & Ada.Characters.Latin_1.HT &
         "-2");
   end Modulo_Sign;

   procedure Logical_Shift is
      --  Right shifts are logical rather than arithmetic.
   begin
      Check
       (
        "print(-1>>1, 1<<63)",
         "9223372036854775807" & Ada.Characters.Latin_1.HT &
         "-9223372036854775808");
   end Logical_Shift;

   procedure Mixed_Key_Equality is
      --  An integral floating key aliases the corresponding integer key.
   begin
      Check
       (
        "local t={[1]=42}; print(t[1.0])",
         "42");
   end Mixed_Key_Equality;

   procedure Large_Integer_Key is
      --  Adjacent integers beyond double precision remain distinct keys.
   begin
      Check
       (
        "local t={[9007199254740992]=1,[9007199254740993]=2}; " &
        "print(t[9007199254740992],t[9007199254740993])",
         "1" & Ada.Characters.Latin_1.HT &
         "2");
   end Large_Integer_Key;

   procedure Truthiness is
      --  Zero and empty strings are truthy; only nil and false are false.
   begin
      Check
       (
        "print(not 0, not '', not nil, not false)",
         "false" & Ada.Characters.Latin_1.HT &
         "false" & Ada.Characters.Latin_1.HT &
         "true" & Ada.Characters.Latin_1.HT &
         "true");
   end Truthiness;

   procedure Short_Circuit is
      --  An unchosen branch must not call a function with side effects.
   begin
      Check
       (
        "local x=0; local function f() x=x+1 end; local a=false " &
        "and f(); local b=1 or f(); print(x,a,b)",
         "0" & Ada.Characters.Latin_1.HT &
         "false" & Ada.Characters.Latin_1.HT &
         "1");
   end Short_Circuit;

   procedure Local_Shadowing is
      --  A closure captures the declaration visible where it was compiled.
   begin
      Check
       (
        "local x=7; local function f() return x end; local x=9; " &
        "print(f(),x)",
         "7" & Ada.Characters.Latin_1.HT &
         "9");
   end Local_Shadowing;

   procedure Local_Initializer_Scope is
      --  New local names are not visible in their own initializer list.
   begin
      Check
       (
        "local x=7; do local x,y=9,x; print(x,y) end",
         "9" & Ada.Characters.Latin_1.HT &
         "7");
   end Local_Initializer_Scope;

   procedure Captured_Mutation is
      --  Calls share the same captured lexical cell, rather than value
      --  copies.
   begin
      Check
       (
        "local function make() local x=0; return function() " &
        "x=x+1; return x end end; local f=make(); print(f(),f())",
         "1" & Ada.Characters.Latin_1.HT &
         "2");
   end Captured_Mutation;

   procedure Recursive_Function is
      --  A local function is bound before its body captures that name.
   begin
      Check
       (
        "local function f(n) if n==0 then return 1 end return " &
        "n*f(n-1) end; print(f(6))",
         "720");
   end Recursive_Function;

   procedure Multiple_Results is
      --  The final call expands into all remaining assignment slots.
   begin
      Check
       (
        "local function f() return 2,3 end; local a,b,c=1,f(); " &
        "print(a,b,c)",
         "1" & Ada.Characters.Latin_1.HT &
         "2" & Ada.Characters.Latin_1.HT &
         "3");
   end Multiple_Results;

   procedure Nonfinal_Call_Collapses is
      --  A nonfinal call contributes exactly one result.
   begin
      Check
       (
        "local function f() return 1,2 end; local a,b,c=f(),3; " &
        "print(a,b,c)",
         "1" & Ada.Characters.Latin_1.HT &
         "3" & Ada.Characters.Latin_1.HT &
         "nil");
   end Nonfinal_Call_Collapses;

   procedure Parentheses_Collapse is
      --  Parenthesized zero-result calls contribute a single nil.
   begin
      Check
       (
        "local function f() end; " &
        "print(select('#',(f())),select('#',f()))",
         "1" & Ada.Characters.Latin_1.HT &
         "0");
   end Parentheses_Collapse;

   procedure Varargs_Preserve_Nil is
      --  Vararg packets preserve nil holes and their total result count.
   begin
      Check
       (
        "local function f(...) return select('#',...),... end; " &
        "local n,a,b,c=f(1,nil,3); print(n,a,b,c)",
         "3" & Ada.Characters.Latin_1.HT &
         "1" & Ada.Characters.Latin_1.HT &
         "nil" & Ada.Characters.Latin_1.HT &
         "3");
   end Varargs_Preserve_Nil;

   procedure Assignment_Snapshot is
      --  Index lvalues are captured before the RHS and before stores.
   begin
      Check
       (
        "local i=1; local t={}; i,t[i]=i+1,42; print(i,t[1],t[2])",
         "2" & Ada.Characters.Latin_1.HT &
         "42" & Ada.Characters.Latin_1.HT &
         "nil");
   end Assignment_Snapshot;

   procedure Repeated_Assignment_Target is
      --  Lua multiple stores proceed right-to-left.
   begin
      Check
       (
        "local x; x,x=1,2; print(x)",
         "1");
   end Repeated_Assignment_Target;

   procedure Table_Last_Call_Expands is
      --  The final list field in a constructor expands all call results.
   begin
      Check
       (
        "local function f() return 2,3 end; local t={1,f()}; " &
        "print(#t,t[3])",
         "3" & Ada.Characters.Latin_1.HT &
         "3");
   end Table_Last_Call_Expands;

   procedure Numeric_For is
      --  Sum the inclusive sequence; Lua 5.5 control variables are const.
   begin
      Check
       (
        "local n=0; for i=1,3 do n=n+i end; print(n)",
         "6");
   end Numeric_For;

   procedure Descending_For is
      --  Negative steps use the matching inclusive comparison.
   begin
      Check
       (
        "local n=0; for i=5,1,-2 do n=n+i end; print(n)",
         "9");
   end Descending_For;

   procedure For_Overflow_Terminates is
      --  The numeric loop stops rather than wrapping its hidden counter.
   begin
      Check
       (
        "local n=0; for i=9223372036854775806,9223372036854775807 " &
        "do n=n+1 end; print(n)",
         "2");
   end For_Overflow_Terminates;

   procedure For_Iteration_Captures is
      --  Each iteration gets a fresh captured loop-variable cell.
   begin
      Check
       (
        "local t={}; for i=1,3 do t[i]=function() return i end " &
        "end; print(t[1](),t[2](),t[3]())",
         "1" & Ada.Characters.Latin_1.HT &
         "2" & Ada.Characters.Latin_1.HT &
         "3");
   end For_Iteration_Captures;

   procedure Generic_For is
      --  The iterator's first result becomes the next control value.
   begin
      Check
       (
        "local n=0; for i,v in ipairs({10,20,30}) do n=n+i+v end; " &
        "print(n)",
         "66");
   end Generic_For;

   procedure False_Iterator_Control is
      --  Generic iteration terminates on nil, not on false.
   begin
      Check
       (
        "local function f(s,k) if k==nil then return false,42 end " &
        "end; local n=0; for k,v in f do n=n+v end; print(n)",
         "42");
   end False_Iterator_Control;

   procedure Repeat_Local_Condition is
      --  Repeat-body locals remain visible in the until expression.
   begin
      Check
       (
        "local n=0; repeat local x=n+1; n=x until x==3; print(n)",
         "3");
   end Repeat_Local_Condition;

   procedure Nested_Break is
      --  Break unwinds inner lexical scopes and leaves the outer loop alone.
   begin
      Check
       (
        "local n=0; for i=1,3 do while true do do n=n+1; break " &
        "end end end; print(n)",
         "3");
   end Nested_Break;

   procedure Method_Syntax is
      --  Colon definitions and calls supply exactly one self argument.
   begin
      Check
       (
        "local t={n=1}; function t:add(x) self.n=self.n+x; return " &
        "self.n end; print(t:add(4))",
         "5");
   end Method_Syntax;

   procedure Global_Keyword_Name is
      --  Default compatibility permits a name; the instrumented reference
      --  configuration reserves it. Both branches execute the real frontend.
      Universe : Session;
      Result : constant Execution_Result :=
        Universe.Execute ("global=42; print(global)", "global name");
   begin
      if Lua.Test_Configuration.Compatible_Global then
         Assert (Result.Status = Succeeded, "compatible global name");
         Assert (To_String (Result.Output) = "42" &
                 Ada.Characters.Latin_1.LF, "global name result");
      else
         Assert (Result.Status = Syntax_Error, "reserved global name");
      end if;
   end Global_Keyword_Name;

   procedure Explicit_Globals is
      --  A collective declaration allows later named global declarations.
   begin
      Check
       (
        "global *; global answer=42; print(answer)",
         "42");
   end Explicit_Globals;

   procedure Global_Without_Initializer is
      --  A declaration without initialization constrains lexical lookup but
      --  must not attempt a runtime store or read an unrecorded environment.
   begin
      Check ("local p=print; x=41; do global x; p(x+1) end", "42");
   end Global_Without_Initializer;

   procedure Global_Shadowed_Environment is
      --  Initialization resolves _ENV at the declaration point, not to the
      --  chunk's original environment. Use an outer print to observe it.
   begin
      Check ("local p=print; local _ENV={}; global x=42; p(_ENV.x)", "42");
   end Global_Shadowed_Environment;

   procedure Environment_Shadowing is
      --  Global access resolves through the lexically visible _ENV cell.
   begin
      Check
       (
        "local check=assert; local e={}; do local _ENV=e; x=42 " &
        "end; check(e.x==42); print(e.x)",
         "42");
   end Environment_Shadowing;

   procedure Protected_Error is
      --  pcall returns the original error object when error level is zero.
   begin
      Check
       (
        "local ok,e=pcall(function() error('expected',0) end); " &
        "print(ok,e)",
         "false" & Ada.Characters.Latin_1.HT &
         "expected");
   end Protected_Error;

   procedure Nested_Protected_Call is
      --  Nested pcall status packets retain their separate success values.
   begin
      Check
       (
        "local a,b,c=pcall(pcall,function() error(42) end); " &
        "print(a,b,c)",
         "true" & Ada.Characters.Latin_1.HT &
         "false" & Ada.Characters.Latin_1.HT &
         "42");
   end Nested_Protected_Call;

   procedure Error_Nil is
      --  Lua 5.5 normalizes nil to its explicit missing-error-object message.
      --  The expectation is anchored in ldebug.c, not older Lua behavior.
   begin
      Check
       (
        "local ok,e=pcall(function() error(nil) end); print(ok,e)",
         "false" & Ada.Characters.Latin_1.HT &
         "<no error object>");
   end Error_Nil;

   procedure Byte_String_Length is
      --  Decoded NUL, byte 255, and UTF-8 escapes remain byte sequences.
   begin
      Check
       (
        "print(#'\x00\255\u{20ac}')",
         "5");
   end Byte_String_Length;

   procedure Explicit_Base_Conversion is
      --  The base form of tonumber uses Lua integer conversion.
   begin
      Check
       (
        "print(tonumber('ff',16),tonumber('invalid'))",
         "255" & Ada.Characters.Latin_1.HT &
         "nil");
   end Explicit_Base_Conversion;

   procedure Table_Cycle is
      --  Table identity and raw operations support cyclic graphs.
   begin
      Check
       (
        "local t={}; t.self=t; rawset(t,'x',42); " &
        "print(rawequal(t,t.self),rawget(t,'x'))",
         "true" & Ada.Characters.Latin_1.HT &
         "42");
   end Table_Cycle;

   procedure Primitive_Infinity is
      --  IEEE division by zero remains a Lua number.
   begin
      Check
       (
        "print(1/0,-1/0)",
         "inf" & Ada.Characters.Latin_1.HT &
         "-inf");
   end Primitive_Infinity;

   procedure Named_Vararg_Mutation is
      --  Lua 5.5 named varargs are a live table, including its mutable n
      --  field.
   begin
      Check
        (
         "local function f(...t) t[2]=42; t.n=3; return ... " &
         "end; print(f(1,2))",
         "1" & Ada.Characters.Latin_1.HT &
         "42" & Ada.Characters.Latin_1.HT &
         "nil");
   end Named_Vararg_Mutation;

   procedure Select_Hash_Prefix is
      --  The reference accepts any selector string whose first byte is #.
   begin
      Check
        (
         "print(select('#extra',1,2))",
         "2");
   end Select_Hash_Prefix;

   procedure Ipairs_Lazy_State is
      --  ipairs preserves its state and validates indexing only when
      --  iterating.
   begin
      Check
        (
         "local ok,f,s,k=pcall(ipairs,42); " &
         "print(ok,type(f),s,k)",
         "true" & Ada.Characters.Latin_1.HT &
         "function" & Ada.Characters.Latin_1.HT &
         "42" & Ada.Characters.Latin_1.HT &
         "0");
   end Ipairs_Lazy_State;

   procedure Power_Overflow is
      --  A positive floating power overflow is infinity, not a domain NaN.
   begin
      Check
        (
         "print(1e308^2, 0^-1)",
         "inf" & Ada.Characters.Latin_1.HT &
         "inf");
   end Power_Overflow;

   procedure Method_Self_Is_Scalar is
      --  Method self does not expand extra results of the receiver
      --  expression.
   begin
      Check
        (
         "local t={}; function t:f(...) return select('#',...) " &
         "end; local function make() return t,42 end; " &
         "print(make():f())",
         "0");
   end Method_Self_Is_Scalar;

   procedure Bitwise_String_Left is
      --  A valid numeric string is still a string operand. The arithmetic
      --  conversion helper must not make primitive bitwise AND accept it.
   begin
      Check ("print(pcall(function() return '3' & 1 end) == false)", "true");
   end Bitwise_String_Left;

   procedure Bitwise_String_Right is
      --  Test the other operand independently: checking only the left kind
      --  would permit the same invalid coercion through a shift count.
   begin
      Check ("print(pcall(function() return 1 << '3' end) == false)", "true");
   end Bitwise_String_Right;

   procedure Bitwise_String_Unary is
      --  Unary complement has its own dispatch path. It must reject numeric
      --  strings while retaining the session's protected-error behavior.
   begin
      Check ("print(pcall(function() return ~'3' end) == false)", "true");
   end Bitwise_String_Unary;

   procedure Display_All_Results is
      Universe : Session;
      Failed : Boolean;
      Result : Execution_Result;
   begin
      --  A host display preserves the entire result packet, including nil;
      --  an empty packet must not call print at all.
      Result := Universe.Execute_Display ("return 1,nil,3", "=stdin", Failed);
      Assert (Result.Status = Succeeded and then not Failed and then
              To_String (Result.Output) = "1" & Ada.Characters.Latin_1.HT &
                "nil" & Ada.Characters.Latin_1.HT & "3" &
                Ada.Characters.Latin_1.LF, "display result arity");
      Result := Universe.Execute_Display
        ("print=function() error('empty print') end", "=stdin", Failed);
      Assert (Result.Status = Succeeded and then not Failed,
              "empty result packet called print");
   end Display_All_Results;

   procedure Display_Result_Roots is
      Universe : Session;
      Failed : Boolean;
      Result : Execution_Result;
   begin
      --  Replace print in the chunk, then collect before inspecting its
      --  returned table and long string. The second drive must own both.
      Result := Universe.Execute_Display
        ("print=function(t,s) collectgarbage(); " &
         "assert(t[1]==42 and #s==4000); io.write('rooted') end; " &
         "return {42},string.rep('x',4000)", "=stdin", Failed);
      Assert (Result.Status = Succeeded and then not Failed and then
              To_String (Result.Output) = "rooted", "display lost roots");
   end Display_Result_Roots;

   procedure Display_Environment_Handler is
      Universe : Session;
      Failed : Boolean;
      Result : Execution_Result;
   begin
      --  Global lookup has ordinary __index semantics, even when print was
      --  removed by this same chunk. Calling the resolved function is real.
      Result := Universe.Execute_Display
        ("local p=print; print=nil; setmetatable(_G,{__index=" &
         "function(_,k) if k=='print' then return p end end}); return 42",
         "=stdin", Failed);
      Assert (Result.Status = Succeeded and then not Failed and then
              To_String (Result.Output) = "42" & Ada.Characters.Latin_1.LF,
              "display bypassed environment handler");
   end Display_Environment_Handler;

   procedure Display_Error_Recovery is
      Universe : Session;
      Failed : Boolean;
      Result : Execution_Result;
   begin
      --  A failed printer is distinguished from a failed chunk. Neither
      --  failure may leave active frames or contaminate the next drive.
      Result := Universe.Execute_Display
        ("print=function() error('printer',0) end; return 1",
         "=stdin", Failed);
      Assert (Result.Status = Runtime_Error and then Failed and then
              To_String (Result.Error.Message) = "printer",
              "printer failure classification");
      Result := Universe.Execute_Display ("error('chunk',0)",
                                          "=stdin", Failed);
      Assert (Result.Status = Runtime_Error and then not Failed,
              "chunk failure classified as printer");
      Result := Universe.Execute ("io.write('recovered')");
      Assert (Result.Status = Succeeded and then
              To_String (Result.Output) = "recovered",
              "display failure left a live drive");
   end Display_Error_Recovery;

   procedure Display_Bounded_Policy is
      Universe : Session;
      Failed : Boolean;
      Result : Execution_Result;
   begin
      --  A replaced printer is user code; the second drive must consume the
      --  same bounded session budget rather than escaping host policy.
      Universe.Set_Limits ((Instructions => 500, others => <>));
      Result := Universe.Execute_Display
        ("print=function() while true do end end; return 1",
         "=stdin", Failed);
      Assert (Result.Status = Resource_Error and then Failed,
              "printer escaped bounded execution");
      Result := Universe.Execute ("assert(1+1==2)");
      Assert (Result.Status = Succeeded, "bounded display did not recover");
   end Display_Bounded_Policy;

   procedure Host_Warning_Control is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  The host delivers controls through the warning mechanism after Lua
      --  removes warn. Both controls must succeed and leave the VM reusable.
      Result := Universe.Execute ("warn=nil");
      Assert (Result.Status = Succeeded, "warning setup failed");
      Result := Universe.Set_Warnings_Enabled (True);
      Assert (Result.Status = Succeeded, "host warning enable failed");
      Result := Universe.Set_Warnings_Enabled (False);
      Assert (Result.Status = Succeeded, "host warning disable failed");
      Result := Universe.Execute ("assert(warn==nil)");
      Assert (Result.Status = Succeeded, "host warning replaced global");
   end Host_Warning_Control;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "session: global without initializer",
         Global_Without_Initializer'Access);
      Test_Support.Add
        (Suite, "session: global shadowed environment",
         Global_Shadowed_Environment'Access);
      Test_Support.Add (Suite, "session: bitwise string left",
                        Bitwise_String_Left'Access);
      Test_Support.Add (Suite, "session: bitwise string right",
                        Bitwise_String_Right'Access);
      Test_Support.Add (Suite, "session: bitwise string unary",
                        Bitwise_String_Unary'Access);
      Test_Support.Add
        (Suite, "session: precedence",
         Precedence'Access);
      Test_Support.Add
        (Suite, "session: unary power",
         Unary_Power'Access);
      Test_Support.Add
        (Suite, "session: power associativity",
         Power_Associativity'Access);
      Test_Support.Add
        (Suite, "session: float formatting",
         Float_Formatting'Access);
      Test_Support.Add
        (Suite, "session: integer wrapping",
         Integer_Wrapping'Access);
      Test_Support.Add
        (Suite, "session: floor division",
         Floor_Division'Access);
      Test_Support.Add
        (Suite, "session: modulo sign",
         Modulo_Sign'Access);
      Test_Support.Add
        (Suite, "session: logical shift",
         Logical_Shift'Access);
      Test_Support.Add
        (Suite, "session: mixed key equality",
         Mixed_Key_Equality'Access);
      Test_Support.Add
        (Suite, "session: large integer key",
         Large_Integer_Key'Access);
      Test_Support.Add
        (Suite, "session: truthiness",
         Truthiness'Access);
      Test_Support.Add
        (Suite, "session: short circuit",
         Short_Circuit'Access);
      Test_Support.Add
        (Suite, "session: local shadowing",
         Local_Shadowing'Access);
      Test_Support.Add
        (Suite, "session: local initializer scope",
         Local_Initializer_Scope'Access);
      Test_Support.Add
        (Suite, "session: captured mutation",
         Captured_Mutation'Access);
      Test_Support.Add
        (Suite, "session: recursive function",
         Recursive_Function'Access);
      Test_Support.Add
        (Suite, "session: multiple results",
         Multiple_Results'Access);
      Test_Support.Add
        (Suite, "session: nonfinal call collapses",
         Nonfinal_Call_Collapses'Access);
      Test_Support.Add
        (Suite, "session: parentheses collapse",
         Parentheses_Collapse'Access);
      Test_Support.Add
        (Suite, "session: varargs preserve nil",
         Varargs_Preserve_Nil'Access);
      Test_Support.Add
        (Suite, "session: assignment snapshot",
         Assignment_Snapshot'Access);
      Test_Support.Add
        (Suite, "session: repeated assignment target",
         Repeated_Assignment_Target'Access);
      Test_Support.Add
        (Suite, "session: table last call expands",
         Table_Last_Call_Expands'Access);
      Test_Support.Add
        (Suite, "session: numeric for",
         Numeric_For'Access);
      Test_Support.Add
        (Suite, "session: descending for",
         Descending_For'Access);
      Test_Support.Add
        (Suite, "session: for overflow terminates",
         For_Overflow_Terminates'Access);
      Test_Support.Add
        (Suite, "session: for iteration captures",
         For_Iteration_Captures'Access);
      Test_Support.Add
        (Suite, "session: generic for",
         Generic_For'Access);
      Test_Support.Add
        (Suite, "session: false iterator control",
         False_Iterator_Control'Access);
      Test_Support.Add
        (Suite, "session: repeat local condition",
         Repeat_Local_Condition'Access);
      Test_Support.Add
        (Suite, "session: nested break",
         Nested_Break'Access);
      Test_Support.Add
        (Suite, "session: method syntax",
         Method_Syntax'Access);
      Test_Support.Add
        (Suite, "session: global keyword name",
         Global_Keyword_Name'Access);
      Test_Support.Add
        (Suite, "session: explicit globals",
         Explicit_Globals'Access);
      Test_Support.Add
        (Suite, "session: environment shadowing",
         Environment_Shadowing'Access);
      Test_Support.Add
        (Suite, "session: protected error",
         Protected_Error'Access);
      Test_Support.Add
        (Suite, "session: nested protected call",
         Nested_Protected_Call'Access);
      Test_Support.Add
        (Suite, "session: error nil",
         Error_Nil'Access);
      Test_Support.Add
        (Suite, "session: byte string length",
         Byte_String_Length'Access);
      Test_Support.Add
        (Suite, "session: explicit base conversion",
         Explicit_Base_Conversion'Access);
      Test_Support.Add
        (Suite, "session: table cycle",
         Table_Cycle'Access);
      Test_Support.Add
        (Suite, "session: primitive infinity",
         Primitive_Infinity'Access);
      Test_Support.Add
        (Suite, "session: named vararg mutation",
         Named_Vararg_Mutation'Access);
      Test_Support.Add
        (Suite, "session: select hash prefix",
         Select_Hash_Prefix'Access);
      Test_Support.Add
        (Suite, "session: ipairs lazy state",
         Ipairs_Lazy_State'Access);
      Test_Support.Add
        (Suite, "session: power overflow",
         Power_Overflow'Access);
      Test_Support.Add
        (Suite, "session: method self is scalar",
         Method_Self_Is_Scalar'Access);
      Test_Support.Add (Suite, "session: display all results",
                        Display_All_Results'Access);
      Test_Support.Add (Suite, "session: display rooted results",
                        Display_Result_Roots'Access);
      Test_Support.Add (Suite, "session: display environment handler",
                        Display_Environment_Handler'Access);
      Test_Support.Add (Suite, "session: display error recovery",
                        Display_Error_Recovery'Access);
      Test_Support.Add (Suite, "session: display bounded policy",
                        Display_Bounded_Policy'Access);
      Test_Support.Add (Suite, "session: host warning controls",
                        Host_Warning_Control'Access);
   end Register;
end Session_Tests;
