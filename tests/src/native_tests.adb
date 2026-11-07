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
   procedure Replacement_Type_Diagnostic;
   procedure Integer_Divide_Zero_Diagnostic;
   procedure Integer_Modulo_Zero_Diagnostic;
   procedure Integer_Field_Diagnostic;
   procedure Integer_Right_Field_Diagnostic;
   procedure Integer_Local_Diagnostic;
   procedure Integer_Metamethod_Precedence;
   procedure Gsub_Unmatched_Identity;
   procedure Gsub_Callback_Unchanged_Identity;
   procedure Gsub_Table_Unchanged_Identity;
   procedure Gsub_Later_Replacement;
   procedure Integer_Register_Diagnostic;
   procedure Integer_First_Invalid_Diagnostic;
   procedure Integer_Unary_Diagnostic;
   procedure Integer_Global_Diagnostic;
   procedure Integer_Upvalue_Diagnostic;
   procedure Integer_Unnamed_Diagnostic;
   procedure Integer_Indexed_Environment_Diagnostic;
   procedure Integer_Stripped_Upvalue_Diagnostic;
   procedure Integer_Unary_Metamethod;
   procedure Integer_Right_Metamethod;
   procedure Gsub_Callback_Substitution_Identity;
   procedure Gsub_String_Substitution_Identity;
   procedure Gsub_Negative_Limit_Identity;
   procedure Gsub_Capture_Index_Diagnostic;
   procedure Integer_Error (Source, Expected : String);
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

   procedure Replacement_Type_Diagnostic is
   begin
      --  Returning a table from the replacement callback is invalid. The
      --  protected call must retain its type in the returned language error,
      --  rather than converting it or reporting the replacement argument.
      Succeeds
        ("local ok,e=pcall(string.gsub,'a','.',function() return {} end); " &
         "assert(not ok and e:find('invalid replacement value %(a table%)'))");
   end Replacement_Type_Diagnostic;

   procedure Integer_Divide_Zero_Diagnostic is
   begin
      --  Evaluate at runtime so the diagnostic belongs to the integer VM
      --  operation and stays catchable through the native protection frame.
      Succeeds
        ("local function f(x) return 2//x end; local ok,e=pcall(f,0); " &
         "assert(not ok and e:find('attempt to divide by zero',1,true))");
   end Integer_Divide_Zero_Diagnostic;

   procedure Integer_Modulo_Zero_Diagnostic is
   begin
      --  Modulo has its own pinned diagnostic; sharing the division helper
      --  must not collapse the two distinct Lua errors into one message.
      Succeeds
        ("local function f(x) return 2%x end; local ok,e=pcall(f,0); " &
         "assert(not ok and e:find(""attempt to perform 'n%0'"",1,true))");
   end Integer_Modulo_Zero_Diagnostic;

   procedure Integer_Field_Diagnostic is
   begin
      --  A failed left conversion must explain the actual table lookup at
      --  the saved fallback PC, including an immediate right shift operand.
      Succeeds
        ("local f=assert(load('return math.huge << 1')); " &
         "local ok,e=pcall(f); " &
         "assert(not ok and e:find(""field 'huge'"",1,true))");
   end Integer_Field_Diagnostic;

   procedure Integer_Right_Field_Diagnostic is
   begin
      --  Reversing the operands must retain the right field's provenance,
      --  rather than attaching the first operand's constant or local name.
      Succeeds
        ("local f=assert(load('return 1 << math.huge')); " &
         "local ok,e=pcall(f); " &
         "assert(not ok and e:find(""field 'huge'"",1,true))");
   end Integer_Right_Field_Diagnostic;

   procedure Integer_Local_Diagnostic is
   begin
      --  Equal numeric values do not identify a source binding. The right
      --  operand is the invalid local while the first operand is integral.
      Succeeds
        ("local function f(bad) return 1 & bad end; " &
         "local ok,e=pcall(f,math.huge); " &
         "assert(not ok and e:find(""local 'bad'"",1,true))");
   end Integer_Local_Diagnostic;

   procedure Integer_Metamethod_Precedence is
   begin
      --  A numeric type's explicit bitwise handler can accept a value which
      --  has no integer representation. Diagnostics run after that lookup.
      Succeeds
        ("debug.setmetatable(0,{__shl=function(a,b) return 17 end}); " &
         "local result=math.huge << 1; debug.setmetatable(0,nil); " &
         "assert(result==17)");
   end Integer_Metamethod_Precedence;

   procedure Gsub_Unmatched_Identity is
   begin
      --  A large noninterned string with no matches must retain its actual
      --  identity; allocating equal bytes would fail the observable %p test.
      Succeeds
        ("local s=string.rep('a',1000); local r,n=s:gsub('z','x'); " &
         "assert(n==0 and string.format('%p',s)==string.format('%p',r))");
   end Gsub_Unmatched_Identity;

   procedure Gsub_Callback_Unchanged_Identity is
   begin
      --  Matches whose callbacks return nil or false count as matches while
      --  preserving the original object even across explicit collection.
      Succeeds
        ("local s=string.rep('a',100); local calls=0; " &
         "local r,n=s:gsub('.',function() calls=calls+1; " &
         "if calls==1 then collectgarbage(); return nil end; " &
         "return false end); assert(n==100 and calls==n); " &
         "assert(string.format('%p',s)==string.format('%p',r))");
   end Gsub_Callback_Unchanged_Identity;

   procedure Gsub_Table_Unchanged_Identity is
   begin
      --  Table lookup uses the same unchanged-result rule as callbacks;
      --  absent and false replacement entries must both preserve identity.
      Succeeds
        ("local s=string.rep('ab',50); local r,n=s:gsub('.',{a=false}); " &
         "assert(n==100 and string.format('%p',s)==string.format('%p',r))");
   end Gsub_Table_Unchanged_Identity;

   procedure Gsub_Later_Replacement is
   begin
      --  An early unchanged result must not hide a later real substitution,
      --  and subsequent false results must not clear the changed flag.
      Succeeds
        ("local r,n=('abc'):gsub('.',function(c) " &
         "if c=='b' then return 'X' else return false end end); " &
         "assert(r=='aXc' and n==3)");
   end Gsub_Later_Replacement;

   procedure Integer_Error (Source, Expected : String) is
   begin
      Succeeds
        ("local f=assert(load([==[" & Source & "]==])); " &
         "local ok,e=pcall(f); assert(not ok and " &
         "e:find([==[" & Expected & "]==],1,true))");
   end Integer_Error;

   procedure Integer_Register_Diagnostic is
   begin
      --  Register-register MMBIN must attribute the second failing argument,
      --  independently of the immediate/constant forms used by math.lua.
      Integer_Error
        ("local function f(a,b) return a|b end; return f(1,2.5)",
         "local 'b'");
   end Integer_Register_Diagnostic;

   procedure Integer_First_Invalid_Diagnostic is
   begin
      --  Both parameters fail conversion; Lua explains the first operand.
      Integer_Error
        ("local function f(a,b) return a|b end; return f(2.5,3.5)",
         "local 'a'");
   end Integer_First_Invalid_Diagnostic;

   procedure Integer_Unary_Diagnostic is
   begin
      --  BNOT names its source register rather than its destination slot.
      Integer_Error
        ("local function f(x) return ~x end; return f(2.5)", "local 'x'");
   end Integer_Unary_Diagnostic;

   procedure Integer_Global_Diagnostic is
   begin
      --  An _ENV lookup describes a global even with explicit table syntax.
      Integer_Error
        ("_ENV.BAD_INTEGER=2.5; return _ENV.BAD_INTEGER|1",
         "global 'BAD_INTEGER'");
   end Integer_Global_Diagnostic;

   procedure Integer_Upvalue_Diagnostic is
   begin
      --  A captured binding is not a local in its nested function's frame.
      Integer_Error
        ("local u=2.5; local function f() return u|1 end; return f()",
         "upvalue 'u'");
   end Integer_Upvalue_Diagnostic;

   procedure Integer_Unnamed_Diagnostic is
   begin
      --  A numeric constant has no variable name; the generic diagnostic
      --  must end without inventing a parenthesized constant attribution.
      Succeeds
        ("local f=assert(load('return 2.3 >> 0')); local ok,e=pcall(f); " &
         "assert(not ok and e:match(" &
         "'number has no integer representation$'))");
   end Integer_Unnamed_Diagnostic;

   procedure Integer_Indexed_Environment_Diagnostic is
   begin
      --  Integer indexing has field provenance even when its table is _ENV.
      Integer_Error
        ("local _ENV={[1]=2.5}; return _ENV[1]|0",
         "field 'integer index'");
   end Integer_Indexed_Environment_Diagnostic;

   procedure Integer_Stripped_Upvalue_Diagnostic is
   begin
      --  Stripping removes the upvalue's name, not its identity or value.
      --  The diagnostic uses the pinned unknown-name marker for that slot.
      Integer_Error
        ("local u=2.5; local f=function() return u|1 end; " &
         "f=assert(load(string.dump(f,true))); debug.setupvalue(f,1,2.5); " &
         "return f()", "upvalue '?'");
   end Integer_Stripped_Upvalue_Diagnostic;

   procedure Integer_Unary_Metamethod is
   begin
      --  Nonintegral BNOT tries the numeric handler before conversion fails.
      Succeeds
        ("debug.setmetatable(0,{__bnot=function(x) assert(x==2.5); " &
         "return 5 end}); local r=~2.5; debug.setmetatable(0,nil); " &
         "assert(r==5)");
   end Integer_Unary_Metamethod;

   procedure Integer_Right_Metamethod is
   begin
      --  An integral left operand cannot make a nonintegral right primitive.
      Succeeds
        ("debug.setmetatable(0,{__shl=function(a,b) " &
         "assert(a==1 and b==math.huge); return 9 end}); " &
         "local r=1 << math.huge; debug.setmetatable(0,nil); assert(r==9)");
   end Integer_Right_Metamethod;

   procedure Gsub_Callback_Substitution_Identity is
   begin
      --  Returning identical bytes still performs a substitution. A long
      --  string must therefore get a distinct object despite byte equality.
      Succeeds
        ("local s=string.rep('a',100); local r,n=s:gsub('.'," &
         "function(c) return c end); assert(r==s and n==100); " &
         "assert(string.format('%p',s)~=string.format('%p',r))");
   end Gsub_Callback_Substitution_Identity;

   procedure Gsub_String_Substitution_Identity is
   begin
      --  The explicit replacement path follows the same identity rule.
      Succeeds
        ("local s=string.rep('a',100); local r,n=s:gsub('a','%0'); " &
         "assert(r==s and n==100); " &
         "assert(string.format('%p',s)~=string.format('%p',r))");
   end Gsub_String_Substitution_Identity;

   procedure Gsub_Negative_Limit_Identity is
   begin
      --  A nonpositive match limit never calls the replacement and must
      --  return the original object even though the pattern could match.
      Succeeds
        ("local s=string.rep('a',100); local r,n=s:gsub('.'," &
         "function() error('must not run') end,-1); assert(n==0); " &
         "assert(string.format('%p',s)==string.format('%p',r))");
   end Gsub_Negative_Limit_Identity;

   procedure Gsub_Capture_Index_Diagnostic is
   begin
      --  Preserve the actual requested index so callers can identify the
      --  bad replacement capture rather than an unrelated pattern failure.
      Succeeds
        ("local ok,e=pcall(string.gsub,'ab','(a)','%2'); " &
         "assert(not ok and e:find('invalid capture index %2',1,true))");
   end Gsub_Capture_Index_Diagnostic;

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
      Test_Support.Add
        (Suite, "native: replacement type diagnostic",
         Replacement_Type_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer divide zero diagnostic",
         Integer_Divide_Zero_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer modulo zero diagnostic",
         Integer_Modulo_Zero_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer field diagnostic",
         Integer_Field_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer right field diagnostic",
         Integer_Right_Field_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer local diagnostic",
         Integer_Local_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer metamethod before conversion error",
         Integer_Metamethod_Precedence'Access);
      Test_Support.Add
        (Suite, "native: gsub unmatched string identity",
         Gsub_Unmatched_Identity'Access);
      Test_Support.Add
        (Suite, "native: gsub unchanged callback identity",
         Gsub_Callback_Unchanged_Identity'Access);
      Test_Support.Add
        (Suite, "native: gsub unchanged table identity",
         Gsub_Table_Unchanged_Identity'Access);
      Test_Support.Add
        (Suite, "native: gsub later replacement retained",
         Gsub_Later_Replacement'Access);
      Test_Support.Add
        (Suite, "native: integer register diagnostic",
         Integer_Register_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer first invalid operand diagnostic",
         Integer_First_Invalid_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer unary diagnostic",
         Integer_Unary_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer global diagnostic",
         Integer_Global_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer upvalue diagnostic",
         Integer_Upvalue_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer unnamed diagnostic",
         Integer_Unnamed_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer indexed environment diagnostic",
         Integer_Indexed_Environment_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer stripped upvalue diagnostic",
         Integer_Stripped_Upvalue_Diagnostic'Access);
      Test_Support.Add
        (Suite, "native: integer unary metamethod before conversion error",
         Integer_Unary_Metamethod'Access);
      Test_Support.Add
        (Suite, "native: integer right metamethod before conversion error",
         Integer_Right_Metamethod'Access);
      Test_Support.Add
        (Suite, "native: gsub callback substitution identity",
         Gsub_Callback_Substitution_Identity'Access);
      Test_Support.Add
        (Suite, "native: gsub string substitution identity",
         Gsub_String_Substitution_Identity'Access);
      Test_Support.Add
        (Suite, "native: gsub negative limit identity",
         Gsub_Negative_Limit_Identity'Access);
      Test_Support.Add
        (Suite, "native: gsub capture index diagnostic",
         Gsub_Capture_Index_Diagnostic'Access);
   end Register;
end Native_Tests;
