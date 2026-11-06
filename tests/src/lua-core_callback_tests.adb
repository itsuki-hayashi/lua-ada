with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Lua.Core_Callback_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result :=
        Universe.Execute (Source, "core-callback-test");
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Minimum_Strings;
   procedure Maximum_Strings;
   procedure Single_Any_Value;
   procedure Minimum_Tie_Type;
   procedure Maximum_Tie_Type;
   procedure Minimum_Comparison_Order;
   procedure Maximum_Comparison_Order;
   procedure Extrema_Truthy_Comparison;
   procedure Minimum_Right_Handler;
   procedure Extrema_Mixed_String_Error;
   procedure Minimum_Error_Recovery;
   procedure Maximum_Error_Recovery;
   procedure Minimum_No_Yield;
   procedure Maximum_No_Yield;
   procedure Language_Less_Yields;
   procedure Minimum_Argument_Mutation;
   procedure Maximum_Argument_Mutation;
   procedure Minimum_Rereads_Best;
   procedure Pairs_Yield_Results;
   procedure Pairs_Result_Adjustment;
   procedure Pairs_Lazy_Non_Table;
   procedure Pairs_Missing_Argument;
   procedure Pairs_Fourth_Closing_Value;
   procedure Standard_Arithmetic_No_Yield;
   procedure User_String_Override_Yields;
   procedure Standard_Arithmetic_Conversion;
   procedure Direct_Arithmetic_One_Argument;
   procedure Direct_Unary_Second_Argument;
   procedure Direct_Unary_Fallback;
   procedure Arithmetic_Extra_Root_Trim;
   procedure Arithmetic_Short_Circuit_Budget;

   procedure Minimum_Strings is
   begin
      --  Setup: two numeric-looking strings.
      --  Action: exercise minimum compares strings without numeric coercion.
      --  Expected: preserve lexicographic ordering and the original argument.
      Check
        ("assert(math.min('2','11')=='11')");
   end Minimum_Strings;

   procedure Maximum_Strings is
   begin
      --  Setup: two numeric-looking strings.
      --  Action: exercise maximum compares strings without numeric coercion.
      --  Expected: preserve lexicographic ordering and the original argument.
      Check
        ("assert(math.max('2','11')=='2')");
   end Maximum_Strings;

   procedure Single_Any_Value is
   begin
      --  Setup: nil, boolean and table arguments.
      --  Action: exercise single-argument extrema accept any Lua value.
      --  Expected: return the argument without imposing numeric validation.
      Check
        ("local t={}; assert(math.min(nil)==nil and " &
         "math.max(false)==false and math.min(t)==t)");
   end Single_Any_Value;

   procedure Minimum_Tie_Type is
   begin
      --  Setup: an integer followed by its equal float.
      --  Action: exercise minimum preserves the first tied argument.
      --  Expected: retain original numeric representation at a tie.
      Check
        ("assert(math.type(math.min(1,1.0))=='integer'); " &
         "assert(math.type(math.min(1.0,1))=='float')");
   end Minimum_Tie_Type;

   procedure Maximum_Tie_Type is
   begin
      --  Setup: a float followed by its equal integer.
      --  Action: exercise maximum preserves the first tied argument.
      --  Expected: retain original numeric representation at a tie.
      Check
        ("assert(math.type(math.max(1,1.0))=='integer'); " &
         "assert(math.type(math.max(1.0,1))=='float')");
   end Maximum_Tie_Type;

   procedure Minimum_Comparison_Order is
   begin
      --  Setup: three tables with a shared ordering handler.
      --  Action: exercise minimum invokes reversed candidate comparison.
      --  Expected: compare each new candidate against the current minimum.
      Check
        ("local log={}; local mt={__lt=function(a,b) " &
         "log[#log+1]=a.n..b.n; return a.n<b.n end}; local " &
         "a=setmetatable({n=3},mt);local b=setmetatable({n=1},mt);local " &
         "c=setmetatable({n=2},mt);assert(math.min(a,b,c)==b and " &
         "log[1]=='13' and log[2]=='21')");
   end Minimum_Comparison_Order;

   procedure Maximum_Comparison_Order is
   begin
      --  Setup: three tables with a shared ordering handler.
      --  Action: exercise maximum invokes current-best comparison.
      --  Expected: compare the current maximum against each candidate.
      Check
        ("local log={}; local mt={__lt=function(a,b)log[#log+1]=a.n..b.n;" &
         "return a.n<b.n end};local a=setmetatable({n=1},mt);local " &
         "b=setmetatable({n=3},mt);local c=setmetatable({n=2},mt);" &
         "assert(math.max(a,b,c)==b and log[1]=='13' and log[2]=='32')");
   end Maximum_Comparison_Order;

   procedure Extrema_Truthy_Comparison is
   begin
      --  Setup: an ordering handler returning a nonboolean table.
      --  Action: exercise extrema accept truthy metamethod results.
      --  Expected: apply Lua truth conversion before selecting the argument.
      Check
        ("local a=setmetatable({},{__lt=function()return {}end});local " &
         "b={};assert(math.min(a,b)==b and math.max(a,b)==b)");
   end Extrema_Truthy_Comparison;

   procedure Minimum_Right_Handler is
   begin
      --  Setup: a candidate without its own ordering handler.
      --  Action: exercise minimum selects the right operand handler.
      --  Expected: use ordinary left/right metamethod lookup.
      Check
        ("local a={};local b={};setmetatable(a,{__lt=function(x,y)return " &
         "y==a end});assert(math.min(a,b)==b)");
   end Minimum_Right_Handler;

   procedure Extrema_Mixed_String_Error is
   begin
      --  Setup: numeric strings mixed with numbers.
      --  Action: exercise extrema reject mixed string/number ordering.
      --  Expected: avoid the obsolete numeric-only coercion path.
      Check
        ("assert(not pcall(math.min,1,'2'));assert(not " &
         "pcall(math.max,'2',1))");
   end Extrema_Mixed_String_Error;

   procedure Minimum_Error_Recovery is
   begin
      --  Setup: a table handler raising a real error object.
      --  Action: exercise minimum propagates comparison errors safely.
      --  Expected: preserve protected error identity and later execution.
      Check
        ("local marker={};local " &
         "a=setmetatable({},{__lt=function()error(marker)end});local " &
         "ok,e=pcall(math.min,a,a);assert(not ok and e==marker and " &
         "math.min(4,2)==2)");
   end Minimum_Error_Recovery;

   procedure Maximum_Error_Recovery is
   begin
      --  Setup: a table handler raising a real error object.
      --  Action: exercise maximum propagates comparison errors safely.
      --  Expected: preserve protected error identity and later execution.
      Check
        ("local marker={};local " &
         "a=setmetatable({},{__lt=function()error(marker)end});local " &
         "ok,e=pcall(math.max,a,a);assert(not ok and e==marker and " &
         "math.max(4,2)==4)");
   end Maximum_Error_Recovery;

   procedure Minimum_No_Yield is
   begin
      --  Setup: a yielding comparison inside a coroutine.
      --  Action: exercise minimum comparison is a nonyieldable C boundary.
      --  Expected: reject yield instead of suspending the native math call.
      Check
        ("local a=setmetatable({},{__lt=function()coroutine.yield(42)end" &
         "});local co=coroutine.create(function()return " &
         "math.min(a,a)end);local ok,e=coroutine.resume(co);assert(not " &
         "ok and e:find('yield',1,true) and " &
         "coroutine.status(co)=='dead')");
   end Minimum_No_Yield;

   procedure Maximum_No_Yield is
   begin
      --  Setup: a yielding comparison inside a coroutine.
      --  Action: exercise maximum comparison is a nonyieldable C boundary.
      --  Expected: reject yield instead of suspending the native math call.
      Check
        ("local a=setmetatable({},{__lt=function()coroutine.yield(42)end" &
         "});local co=coroutine.create(function()return " &
         "math.max(a,a)end);local ok,e=coroutine.resume(co);assert(not " &
         "ok and e:find('yield',1,true) and " &
         "coroutine.status(co)=='dead')");
   end Maximum_No_Yield;

   procedure Language_Less_Yields is
   begin
      --  Setup: a yielding table ordering metamethod.
      --  Action: exercise ordinary language comparisons remain yieldable.
      --  Expected: avoid applying native math restrictions to VM comparison.
      Check
        ("local a=setmetatable({},{__lt=function()return " &
         "coroutine.yield(42)end});local " &
         "co=coroutine.create(function()return a<a end);local " &
         "ok,v=coroutine.resume(co);assert(ok and v==42);local " &
         "ok2,v2=coroutine.resume(co,true);assert(ok2 and v2==true)");
   end Language_Less_Yields;

   procedure Minimum_Argument_Mutation is
   begin
      --  Setup: a handler replacing the native first argument.
      --  Action: exercise minimum retains the current argument index.
      --  Expected: return the actual mutated stack slot rather than a value
      --  snapshot.
      Check
        ("local replacement={};local " &
         "a=setmetatable({},{__lt=function()return false end});local " &
         "b=setmetatable({},{__lt=function()assert(debug.setlocal(2,1,re" &
         "placement)=='(C temporary)');return false end});" &
         "assert(math.min(a,b)==replacement)");
   end Minimum_Argument_Mutation;

   procedure Maximum_Argument_Mutation is
   begin
      --  Setup: a handler replacing the native first argument.
      --  Action: exercise maximum retains the current argument index.
      --  Expected: return the actual mutated stack slot rather than a value
      --  snapshot.
      Check
        ("local replacement={};local " &
         "a=setmetatable({},{__lt=function()assert(debug.setlocal(2,1,re" &
         "placement)=='(C temporary)');return false end});" &
         "assert(math.max(a,{})==replacement)");
   end Maximum_Argument_Mutation;

   procedure Minimum_Rereads_Best is
   begin
      --  Setup: three arguments and a mutation during the first comparison.
      --  Action: exercise minimum rereads a handler-mutated current argument.
      --  Expected: use the changed slot again in the following comparison.
      Check
        ("local replacement={};local n=0;local " &
         "a=setmetatable({},{__lt=function()return false end});local " &
         "b=setmetatable({},{__lt=function()debug.setlocal(2,1,replaceme" &
         "nt);return false end});local " &
         "c=setmetatable({},{__lt=function(x,y)n=n+1;" &
         "assert(y==replacement);return false end});" &
         "assert(math.min(a,b,c)==replacement and n==1)");
   end Minimum_Rereads_Best;

   procedure Pairs_Yield_Results is
   begin
      --  Setup: a yielding __pairs producing four results.
      --  Action: exercise pairs resumes its yieldable metamethod.
      --  Expected: retain arguments and all iterator results across
      --  suspension.
      Check
        ("local t=setmetatable({},{__pairs=function(self)assert(coroutin" &
         "e.yield('pause',self)==7);return next,{x=5},nil,8 end});local " &
         "co=coroutine.create(function()return pairs(t)end);local " &
         "ok,p,self=coroutine.resume(co);assert(ok and p=='pause' and " &
         "self==t);local ok2,f,s,k,c=coroutine.resume(co,7);assert(ok2 " &
         "and f==next and s.x==5 and k==nil and c==8)");
   end Pairs_Yield_Results;

   procedure Pairs_Result_Adjustment is
   begin
      --  Setup: handlers returning one and then five values.
      --  Action: exercise pairs pads and truncates four results.
      --  Expected: apply the pinned four-result continuation contract.
      Check
        ("local t=setmetatable({},{__pairs=function()return 9 end});" &
         "local a,b,c,d,e=pairs(t);assert(a==9 and b==nil and c==nil and " &
         "d==nil and e==nil and select('#',pairs(t))==4);" &
         "getmetatable(t).__pairs=function()return 1,2,3,4,5 end;" &
         "assert(select('#',pairs(t))==4)");
   end Pairs_Result_Adjustment;

   procedure Pairs_Lazy_Non_Table is
   begin
      --  Setup: a number and explicit nil as iterator state.
      --  Action: exercise pairs defers raw-table validation to next.
      --  Expected: reject invalid state only when the iterator is called.
      Check
        ("local f,s,k,c=pairs(7);assert(f==next and s==7 and k==nil and " &
         "c==nil);assert(not pcall(f,s,k));local f2,s2=pairs(nil);" &
         "assert(f2==next and s2==nil)");
   end Pairs_Lazy_Non_Table;

   procedure Pairs_Missing_Argument is
   begin
      --  Setup: a nil-type __pairs handler and zero arguments.
      --  Action: exercise pairs checks presence before nil-type metatable.
      --  Expected: report the missing argument without invoking that handler.
      Check
        ("local called=false;" &
         "debug.setmetatable(nil,{__pairs=function()called=true end});" &
         "local ok=pcall(pairs);debug.setmetatable(nil,nil);assert(not " &
         "ok and not called)");
   end Pairs_Missing_Argument;

   procedure Pairs_Fourth_Closing_Value is
   begin
      --  Setup: a generic-for loop resumed through __pairs.
      --  Action: exercise yielded pairs preserves its closing value.
      --  Expected: run the fourth result closing handler at loop exit.
      Check
        ("local count=0;local " &
         "closer=setmetatable({},{__close=function()count=count+1 end});" &
         "local t=setmetatable({},{__pairs=function()coroutine.yield('pa" &
         "use');return next,{x=1},nil,closer end});local " &
         "co=coroutine.create(function()for k,v in pairs(t)do " &
         "assert(k=='x' and v==1)end;return count end);local " &
         "ok,v=coroutine.resume(co);assert(ok and v=='pause' and " &
         "count==0);local ok2,v2=coroutine.resume(co);assert(ok2 and " &
         "v2==1)");
   end Pairs_Fourth_Closing_Value;

   procedure Standard_Arithmetic_No_Yield is
   begin
      --  Setup: a string arithmetic handler falling through to a Lua rhs
      --  handler.
      --  Action: exercise standard string fallback forbids yielding callbacks.
      --  Expected: honor lua_call rather than treating every continuation as
      --  yieldable.
      Check
        ("local rhs=setmetatable({},{__add=function()coroutine.yield(9)e" &
         "nd});local co=coroutine.create(function()return 'bad'+rhs end);" &
         "local ok,e=coroutine.resume(co);assert(not ok and " &
         "e:find('yield',1,true))");
   end Standard_Arithmetic_No_Yield;

   procedure User_String_Override_Yields is
   begin
      --  Setup: a replacement string __add closure.
      --  Action: exercise user string arithmetic overrides remain yieldable.
      --  Expected: restrict only installed standard arithmetic native
      --  handlers.
      Check
        ("local mt=getmetatable('');local old=mt.__add;" &
         "mt.__add=function(a,b)assert(a=='bad' and b==2);return " &
         "coroutine.yield(42)end;local " &
         "co=coroutine.create(function()return 'bad'+2 end);local " &
         "ok,v=coroutine.resume(co);assert(ok and v==42);local " &
         "ok2,v2=coroutine.resume(co,7);assert(ok2 and v2==7);" &
         "mt.__add=old");
   end User_String_Override_Yields;

   procedure Standard_Arithmetic_Conversion is
   begin
      --  Setup: mixed numeric primitives and source strings.
      --  Action: exercise standard arithmetic converts decimal and hex
      --  strings.
      --  Expected: perform arithmetic on converted values and preserve result
      --  kind.
      Check
        ("assert('2'+3==5 and '0x10'*'2'==32 and '3.5'-1==2.5 and " &
         "-'4'==-4)");
   end Standard_Arithmetic_Conversion;

   procedure Direct_Arithmetic_One_Argument is
   begin
      --  Setup: a standard handler called with one numeric string.
      --  Action: exercise direct standard arithmetic observes pushed
      --  conversions.
      --  Expected: match the index-two value created by the first conversion.
      Check
        ("local mt=getmetatable('');assert(mt.__add('2')==4 and " &
         "mt.__sub('2')==0 and mt.__mul('2')==4 and mt.__unm('2')==-2)");
   end Direct_Arithmetic_One_Argument;

   procedure Direct_Unary_Second_Argument is
   begin
      --  Setup: an explicit second numeric string argument.
      --  Action: exercise direct standard unary uses the top converted value.
      --  Expected: preserve lua_arith unary behavior instead of duplicating
      --  operands.
      Check
        ("assert(getmetatable('').__unm('2','3')==-3)");
   end Direct_Unary_Second_Argument;

   procedure Direct_Unary_Fallback is
   begin
      --  Setup: an invalid first string and rhs table __unm.
      --  Action: exercise direct unary fallback retains original operands.
      --  Expected: avoid replacing the real rhs with the unary lhs.
      Check
        ("local rhs={};setmetatable(rhs,{__unm=function(a,b)assert(a=='b" &
         "ad' and b==rhs);return 23 end});" &
         "assert(getmetatable('').__unm('bad',rhs)==23)");
   end Direct_Unary_Fallback;

   procedure Arithmetic_Extra_Root_Trim is
   begin
      --  Setup: a weakly observed third temporary argument.
      --  Action: exercise string arithmetic discards extra arguments before
      --  fallback.
      --  Expected: clear discarded scalar roots before the callback can
      --  collect.
      Check
        ("local weak=setmetatable({},{__mode='v'});local " &
         "rhs=setmetatable({},{__add=function(a,b)collectgarbage('collec" &
         "t');assert(weak[1]==nil and a=='bad' and b~=nil);return 11 " &
         "end});local function supply()local t={};weak[1]=t;return t end;" &
         "assert(getmetatable('').__add('bad',rhs,supply())==11)");
   end Arithmetic_Extra_Root_Trim;

   procedure Arithmetic_Short_Circuit_Budget is
      Universe : Session;
      Setup : constant Execution_Result :=
        Universe.Execute ("rhs=string.rep('x',100000)", "arithmetic-setup");
      Result : Execution_Result;
   begin
      --  Setup: retain a large rhs in the session before lowering its budget.
      --  Action: enter standard string arithmetic with an invalid boolean lhs.
      --  Expected: reject lhs without scanning rhs. An eager second conversion
      --  would turn a catchable type error into an uncatchable host quota
      --  abort.
      Assert (Setup.Status = Succeeded, "large rhs setup failed");
      Universe.Set_Limits ((Instructions => 2_000, others => <>));
      Result := Universe.Execute
        ("local ok,e=pcall(function()return false+rhs end); " &
         "assert(not ok and type(e)=='string')", "arithmetic-short-circuit");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Arithmetic_Short_Circuit_Budget;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite,
         "Core callbacks: minimum compares strings without numeric " &
         "coercion",
         Minimum_Strings'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: maximum compares strings without numeric " &
         "coercion",
         Maximum_Strings'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: single-argument extrema accept any Lua value",
         Single_Any_Value'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: minimum preserves the first tied argument",
         Minimum_Tie_Type'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: maximum preserves the first tied argument",
         Maximum_Tie_Type'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: minimum invokes reversed candidate comparison",
         Minimum_Comparison_Order'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: maximum invokes current-best comparison",
         Maximum_Comparison_Order'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: extrema accept truthy metamethod results",
         Extrema_Truthy_Comparison'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: minimum selects the right operand handler",
         Minimum_Right_Handler'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: extrema reject mixed string/number ordering",
         Extrema_Mixed_String_Error'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: minimum propagates comparison errors safely",
         Minimum_Error_Recovery'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: maximum propagates comparison errors safely",
         Maximum_Error_Recovery'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: minimum comparison is a nonyieldable C " &
         "boundary",
         Minimum_No_Yield'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: maximum comparison is a nonyieldable C " &
         "boundary",
         Maximum_No_Yield'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: ordinary language comparisons remain yieldable",
         Language_Less_Yields'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: minimum retains the current argument index",
         Minimum_Argument_Mutation'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: maximum retains the current argument index",
         Maximum_Argument_Mutation'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: minimum rereads a handler-mutated current " &
         "argument",
         Minimum_Rereads_Best'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: pairs resumes its yieldable metamethod",
         Pairs_Yield_Results'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: pairs pads and truncates four results",
         Pairs_Result_Adjustment'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: pairs defers raw-table validation to next",
         Pairs_Lazy_Non_Table'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: pairs checks presence before nil-type " &
         "metatable",
         Pairs_Missing_Argument'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: yielded pairs preserves its closing value",
         Pairs_Fourth_Closing_Value'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: standard string fallback forbids yielding " &
         "callbacks",
         Standard_Arithmetic_No_Yield'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: user string arithmetic overrides remain " &
         "yieldable",
         User_String_Override_Yields'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: standard arithmetic converts decimal and hex " &
         "strings",
         Standard_Arithmetic_Conversion'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: direct standard arithmetic observes pushed " &
         "conversions",
         Direct_Arithmetic_One_Argument'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: direct standard unary uses the top converted " &
         "value",
         Direct_Unary_Second_Argument'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: direct unary fallback retains original " &
         "operands",
         Direct_Unary_Fallback'Access);
      Test_Support.Add
        (Suite,
         "Core callbacks: string arithmetic discards extra arguments " &
         "before fallback",
         Arithmetic_Extra_Root_Trim'Access);
      Test_Support.Add
        (Suite, "Core callbacks: short-circuit conversion preserves budget",
         Arithmetic_Short_Circuit_Budget'Access);
   end Register;
end Lua.Core_Callback_Tests;

