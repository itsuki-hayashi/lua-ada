with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Native_Tests is
   procedure Index_Callback;
   procedure Newindex_Raw_Bypass;
   procedure Callable_Handler_Chain;
   procedure Binary_Handler_Selection;
   procedure Unary_Duplicate_Operands;
   procedure Native_Metamethod_Handlers;
   procedure Equality_Handler_Selection;
   procedure Less_Equal_No_Fallback;
   procedure Metatable_Protection;
   procedure Pairs_Four_Results;
   procedure String_Arithmetic_Override;
   procedure Session_Metatable_Isolation;
   procedure Nested_Native_Callbacks;
   procedure Callback_Error_Recovery;
   procedure Callback_Resource_Recovery;
   procedure Callback_Capture_Roots;
   procedure Xpcall_Handler_Arguments;
   procedure Named_Type_Diagnostic;
   procedure Ipairs_Index_Callback;
   procedure Concatenate_Primitive_Bypass;
   procedure Xpcall_Handler_Validation;
   procedure Xpcall_Empty_Handler_Result;
   procedure Protected_Tail_Unwind;
   procedure Succeeds (Source : String);

   procedure Succeeds (Source : String) is
      Self : Session;
      Result : constant Execution_Result := Execute (Self, Source);
   begin
      --  Lua assertions make each expectation visible in its setup script.
      --  Include the structured diagnostic if the embedding boundary fails.
      Assert (Result.Status = Succeeded,
              "execution: " & To_String (Result.Error.Message));
   end Succeeds;

   procedure Index_Callback is
   begin
      --  A present key bypasses __index. A miss passes the original receiver
      --  and key to a Lua handler and adjusts its results to a single value.
      Succeeds
        ("local n=0; local t={present=9}; setmetatable(t,{" &
         "__index=function(self,key) n=n+1; assert(self==t); " &
         "return key..'!',999 end}); " &
         "assert(t.present==9 and n==0); " &
         "assert(t.absent=='absent!' and n==1)");
   end Index_Callback;

   procedure Newindex_Raw_Bypass is
   begin
      --  Ordinary mutation invokes __newindex only for an absent raw key.
      --  rawset inside the handler terminates dispatch rather than recursing.
      Succeeds
        ("local n=0; local t={old=1}; setmetatable(t,{" &
         "__newindex=function(self,key,value) n=n+1; " &
         "assert(self==t and key=='new'); rawset(self,key,value*2) end}); " &
         "t.old=3; t.new=4; assert(n==1 and rawget(t,'new')==8); " &
         "rawset(t,'direct',5); assert(n==1 and t.direct==5)");
   end Newindex_Raw_Bypass;

   procedure Callable_Handler_Chain is
   begin
      --  A callable metamethod may itself be a table. Each layer prepends its
      --  receiver, preserving Lua's handler-chain argument order.
      Succeeds
        ("local t={}; local handler={}; setmetatable(handler,{" &
         "__call=function(self,original,a,b) " &
         "assert(self==handler and original==t); return a+b,17 end}); " &
         "setmetatable(t,{__call=handler}); local a,b=t(2,3); " &
         "assert(a==5 and b==17)");
   end Callable_Handler_Chain;

   procedure Binary_Handler_Selection is
   begin
      --  First use the right operand's fallback, then install a distinct left
      --  handler to protect precedence and unmodified operand order.
      Succeeds
        ("local a,b={},{}; setmetatable(b,{__add=function(x,y) " &
         "assert(x==a and y==b); return 20 end}); assert(a+b==20); " &
         "setmetatable(a,{__add=function(x,y) " &
         "assert(x==a and y==b); return 10 end}); assert(a+b==10)");
   end Binary_Handler_Selection;

   procedure Unary_Duplicate_Operands is
   begin
      --  Lua unary handlers receive the same operand twice. Testing arity as
      --  well as identity catches an easy one-argument native shortcut.
      Succeeds
        ("local t={}; local function unary(...) " &
         "assert(select('#',...)==2); local a,b=...; " &
         "assert(a==t and b==t); return 7 end; " &
         "setmetatable(t,{__unm=unary,__bnot=unary}); " &
         "assert(-t==7 and ~t==7)");
   end Unary_Duplicate_Operands;

   procedure Native_Metamethod_Handlers is
   begin
      --  Metamethod values can be native functions as well as Lua closures.
      --  rawlen must bypass the very __len handler which invoked it.
      Succeeds
        ("local t={4,5}; setmetatable(t,{__len=rawlen,__call=type}); " &
         "assert(#t==2 and t()=='table'); " &
         "local empty=setmetatable({},{__index=rawget}); " &
         "assert(empty.absent==nil)");
   end Native_Metamethod_Handlers;

   procedure Equality_Handler_Selection is
   begin
      --  Distinct equality handlers need not be identical. Identity remains
      --  primitive; otherwise left lookup precedes right-only fallback.
      Succeeds
        ("local a,b={},{}; local n=0; setmetatable(a,{" &
         "__eq=function(x,y) n=n+1; assert(x==a or rawequal(x,a)); " &
         "return true end}); setmetatable(b,{__eq=function() " &
         "error('wrong equality handler') end}); " &
         "assert(a==a and n==0); assert(a==b and n==1); " &
         "setmetatable(a,{}); setmetatable(b,{__eq=function(x,y) " &
         "assert(rawequal(x,a) and rawequal(y,b)); return true end}); " &
         "assert(a==b); assert(not rawequal(a,b))");
   end Equality_Handler_Selection;

   procedure Less_Equal_No_Fallback is
   begin
      --  Lua 5.5 removed the historical reversed __lt fallback for <=.
      --  Failure must be catchable and must not execute that obsolete path.
      Succeeds
        ("local n=0; local a,b={},{}; local mt={__lt=function() " &
         "n=n+1; return true end}; setmetatable(a,mt); " &
         "setmetatable(b,mt); assert(a<b and n==1); " &
         "local ok=pcall(function() return a<=b end); " &
         "assert(not ok and n==1); mt.__le=function() return true end; " &
         "assert(a<=b)");
   end Less_Equal_No_Fallback;

   procedure Metatable_Protection is
   begin
      --  A protected metatable is replaced by its public token on lookup and
      --  rejects replacement, while raw table access still bypasses __index.
      Succeeds
        ("local t={}; local mt={__metatable='locked',__index={x=8}}; " &
         "assert(setmetatable(t,mt)==t and getmetatable(t)=='locked'); " &
         "assert(t.x==8 and rawget(t,'x')==nil); " &
         "local ok=pcall(setmetatable,t,{}); assert(not ok); " &
         "assert(getmetatable(t)=='locked')");
   end Metatable_Protection;

   procedure Pairs_Four_Results is
   begin
      --  The fourth closing value belongs to the protocol even though M2b
      --  defers closing execution. Preserve all four __pairs return slots.
      Succeeds
        ("local t={}; local function iter() end; local marker={}; " &
         "setmetatable(t,{__pairs=function(self) assert(self==t); " &
         "return iter,marker,42,'fourth' end}); " &
         "local f,s,k,c=pairs(t); " &
         "assert(f==iter and s==marker and k==42 and c=='fourth'); " &
         "assert(select('#',pairs({}))==4)");
   end Pairs_Four_Results;

   procedure String_Arithmetic_Override is
   begin
      --  Numeric-string arithmetic belongs to the initial string handlers.
      --  User overrides therefore win; primitive bitwise coercion stays off.
      Succeeds
        ("assert('2'+3==5); local mt=getmetatable(''); " &
         "mt.__add=function(a,b) assert(a=='2' and b==3); return 77 end; " &
         "assert('2'+3==77); " &
         "assert(not pcall(function() return '2' & 3 end))");
   end String_Arithmetic_Override;

   procedure Session_Metatable_Isolation is
      Left, Right : Session;
      Changed : constant Execution_Result := Execute
        (Left, "getmetatable('').__add=function() return 77 end; " &
         "assert('2'+3==77)");
      Unchanged : constant Execution_Result := Execute
        (Right, "assert('2'+3==5)");
   begin
      --  Distinct owners must never share the mutable type-metatable state.
      Assert (Changed.Status = Succeeded, "left metatable mutation");
      Assert (Unchanged.Status = Succeeded, "right metatable isolation");
      Reset (Left);
      declare
         Fresh : constant Execution_Result := Execute
           (Left, "assert('2'+3==5)");
      begin
         Assert (Fresh.Status = Succeeded, "reset reinstalls string handlers");
      end;
   end Session_Metatable_Isolation;

   procedure Nested_Native_Callbacks is
   begin
      --  gsub suspends for Lua, which calls pcall and then tostring, which
      --  suspends for another Lua handler. Every continuation resumes once.
      Succeeds
        ("local n=0; local obj=setmetatable({},{__tostring=function() " &
         "n=n+1; return 'X' end}); local s,c=string.gsub('aba','a'," &
         "function() local ok,value=pcall(tostring,obj); " &
         "assert(ok); return value end); " &
         "assert(s=='XbX' and c==2 and n==2)");
   end Nested_Native_Callbacks;

   procedure Callback_Error_Recovery is
      Self : Session;
      Failed : constant Execution_Result := Execute
        (Self, "string.gsub('abc','.',function() error('callback') end)");
      Recovered : constant Execution_Result := Execute
        (Self, "local ok,e=pcall(function() string.gsub('abc','.'," &
         "function() error('inside') end) end); " &
         "assert(not ok and type(e)=='string'); print('recovered')");
   begin
      --  An unprotected callback unwinds the abandoned native frame. The next
      --  chunk can protect the same failure and continue using this session.
      Assert (Failed.Status = Runtime_Error, "unprotected callback error");
      Assert (Recovered.Status = Succeeded, "protected callback recovery");
      Assert (To_String (Recovered.Output) =
                "recovered" & Ada.Characters.Latin_1.LF,
              "execution continues after callback error");
   end Callback_Error_Recovery;

   procedure Callback_Resource_Recovery is
      Self : Session;
      Bounds : Execution_Limits;
   begin
      --  Protected calls cannot catch budget exhaustion. Abandoned callback
      --  continuations are released; the next chunk receives a fresh budget.
      Bounds.Instructions := 1_000;
      Set_Limits (Self, Bounds);
      declare
         Failed : constant Execution_Result := Execute
           (Self, "pcall(function() string.gsub('a','a',function() " &
            "while true do end end) end)");
         Recovered : constant Execution_Result := Execute
           (Self, "assert(1+1==2)");
      begin
         Assert (Failed.Status = Resource_Error,
                 "callback budget cannot become protected Lua failure");
         Assert (Recovered.Status = Succeeded, "fresh chunk budget");
      end;
   end Callback_Resource_Recovery;

   procedure Callback_Capture_Roots is
   begin
      --  Allocations force collection while a suspended gsub retains its Lua
      --  callback and captured graph. Both callbacks must see that same graph.
      Succeeds
        ("local keep={value='Z'}; local function replace() " &
         "for i=1,1000 do local garbage={i,{i}} end; " &
         "return keep.value end; local result,n=string.gsub('aa','a'," &
         "replace); assert(result=='ZZ' and n==2 and keep.value=='Z')");
   end Callback_Capture_Roots;

   procedure Xpcall_Handler_Arguments is
   begin
      --  xpcall forwards explicit arguments only to the protected function;
      --  its error handler receives the error object and returns one result.
      Succeeds
        ("local ok,v=xpcall(function(a,b) assert(a==2 and b==3); " &
         "error('original') end,function(e) assert(type(e)=='string'); " &
         "return 'handled',999 end,2,3); assert(not ok and v=='handled'); " &
         "local success,a,b=xpcall(function(x) return x,8 end, " &
         "function() error('unexpected handler') end,7); " &
         "assert(success and a==7 and b==8)");
   end Xpcall_Handler_Arguments;

   procedure Named_Type_Diagnostic is
   begin
      --  A type name in the metatable improves the applicable arithmetic
      --  diagnostic without making a table into a different primitive type.
      Succeeds
        ("local value=setmetatable({},{__name='Widget'}); " &
         "local ok,e=pcall(function() return value+1 end); " &
         "assert(not ok and string.find(e,'Widget',1,true)); " &
         "assert(type(value)=='table')");
   end Named_Type_Diagnostic;

   procedure Ipairs_Index_Callback is
   begin
      --  ipairs performs ordinary indexing on each step, including the nil
      --  terminator. A table proxy therefore resumes its Lua __index handler
      --  for every control value instead of silently behaving like rawget.
      Succeeds
        ("local seen={}; local p=setmetatable({}, {__index=function(_,i) " &
         "seen[#seen+1]=i; if i<3 then return i*10 end end}); " &
         "local sum=0; for i,v in ipairs(p) do sum=sum+i+v end; " &
         "assert(sum==33 and table.concat(seen,',')=='1,2,3')");
   end Ipairs_Index_Callback;

   procedure Concatenate_Primitive_Bypass is
   begin
      --  An installed string handler cannot intercept the primitive
      --  concatenation of a string and number. It applies only after either
      --  operand fails the normal string/number conversion.
      Succeeds
        ("getmetatable('').__concat=function() return 'wrong' end; " &
         "assert('x'..1=='x1' and 2 ..'x'=='2x')");
   end Concatenate_Primitive_Bypass;

   procedure Xpcall_Handler_Validation is
   begin
      --  The second argument is checked before running the protected
      --  function, even when that function would succeed without using it.
      Succeeds
        ("local ran=false; local ok=pcall(xpcall,function() ran=true end, " &
         "{}); assert(not ok and not ran)");
   end Xpcall_Handler_Validation;

   procedure Xpcall_Empty_Handler_Result is
   begin
      --  A missing first handler result adjusts to nil, then Lua 5.5's
      --  luaG_errormsg normalizes that nil to its no-error-object string.
      --  The pinned C oracle confirms the result, not an out-of-range read.
      Succeeds
        ("local ok,e=xpcall(function() error('x',0) end, " &
         "function() end); assert(not ok and e=='<no error object>')");
   end Xpcall_Empty_Handler_Result;

   procedure Protected_Tail_Unwind is
   begin
      --  The protected native tail call replaces the chunk activation.
      --  Catching its callback's error leaves an empty activation stack,
      --  which is successful chunk completion rather than an absent caller.
      Succeeds
        ("return pcall(string.gsub,'a','a', " &
         "function() error('x',0) end)");
   end Protected_Tail_Unwind;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "native: index callback", Index_Callback'Access);
      Test_Support.Add
        (Suite, "native: newindex raw bypass", Newindex_Raw_Bypass'Access);
      Test_Support.Add
        (Suite, "native: callable handler chain",
         Callable_Handler_Chain'Access);
      Test_Support.Add
        (Suite, "native: binary handler selection",
         Binary_Handler_Selection'Access);
      Test_Support.Add
        (Suite, "native: unary duplicated operands",
         Unary_Duplicate_Operands'Access);
      Test_Support.Add
        (Suite, "native: native metamethod handlers",
         Native_Metamethod_Handlers'Access);
      Test_Support.Add
        (Suite, "native: equality handler selection",
         Equality_Handler_Selection'Access);
      Test_Support.Add
        (Suite, "native: less equal has no fallback",
         Less_Equal_No_Fallback'Access);
      Test_Support.Add
        (Suite, "native: metatable protection", Metatable_Protection'Access);
      Test_Support.Add
        (Suite, "native: pairs four results", Pairs_Four_Results'Access);
      Test_Support.Add
        (Suite, "native: string arithmetic override",
         String_Arithmetic_Override'Access);
      Test_Support.Add
        (Suite, "native: session metatable isolation",
         Session_Metatable_Isolation'Access);
      Test_Support.Add
        (Suite, "native: nested native callbacks",
         Nested_Native_Callbacks'Access);
      Test_Support.Add
        (Suite, "native: callback error recovery",
         Callback_Error_Recovery'Access);
      Test_Support.Add
        (Suite, "native: callback resource recovery",
         Callback_Resource_Recovery'Access);
      Test_Support.Add
        (Suite, "native: callback capture roots",
         Callback_Capture_Roots'Access);
      Test_Support.Add
        (Suite, "native: xpcall handler arguments",
         Xpcall_Handler_Arguments'Access);
      Test_Support.Add
        (Suite, "native: named type diagnostic", Named_Type_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: ipairs index callback", Ipairs_Index_Callback'Access);
      Test_Support.Add
        (Suite, "native: concatenation primitive bypass",
         Concatenate_Primitive_Bypass'Access);
      Test_Support.Add
        (Suite, "native: xpcall handler validation",
         Xpcall_Handler_Validation'Access);
      Test_Support.Add
        (Suite, "native: xpcall empty handler result",
         Xpcall_Empty_Handler_Result'Access);
      Test_Support.Add
        (Suite, "native: protected tail unwind", Protected_Tail_Unwind'Access);
   end Register;
end Native_Tests;
