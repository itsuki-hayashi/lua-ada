-- Minimum_Strings: two numeric-looking strings; preserve lexicographic ordering and the original argument.
do
  assert(math.min('2','11')=='11')
end
print('Minimum_Strings: PASS')

-- Maximum_Strings: two numeric-looking strings; preserve lexicographic ordering and the original argument.
do
  assert(math.max('2','11')=='2')
end
print('Maximum_Strings: PASS')

-- Single_Any_Value: nil, boolean and table arguments; return the argument without imposing numeric validation.
do
  local t={}; assert(math.min(nil)==nil and math.max(false)==false and math.min(t)==t)
end
print('Single_Any_Value: PASS')

-- Minimum_Tie_Type: an integer followed by its equal float; retain original numeric representation at a tie.
do
  assert(math.type(math.min(1,1.0))=='integer'); assert(math.type(math.min(1.0,1))=='float')
end
print('Minimum_Tie_Type: PASS')

-- Maximum_Tie_Type: a float followed by its equal integer; retain original numeric representation at a tie.
do
  assert(math.type(math.max(1,1.0))=='integer'); assert(math.type(math.max(1.0,1))=='float')
end
print('Maximum_Tie_Type: PASS')

-- Minimum_Comparison_Order: three tables with a shared ordering handler; compare each new candidate against the current minimum.
do
  local log={}; local mt={__lt=function(a,b) log[#log+1]=a.n..b.n; return a.n<b.n end}; local a=setmetatable({n=3},mt);local b=setmetatable({n=1},mt);local c=setmetatable({n=2},mt);assert(math.min(a,b,c)==b and log[1]=='13' and log[2]=='21')
end
print('Minimum_Comparison_Order: PASS')

-- Maximum_Comparison_Order: three tables with a shared ordering handler; compare the current maximum against each candidate.
do
  local log={}; local mt={__lt=function(a,b)log[#log+1]=a.n..b.n;return a.n<b.n end};local a=setmetatable({n=1},mt);local b=setmetatable({n=3},mt);local c=setmetatable({n=2},mt);assert(math.max(a,b,c)==b and log[1]=='13' and log[2]=='32')
end
print('Maximum_Comparison_Order: PASS')

-- Extrema_Truthy_Comparison: an ordering handler returning a nonboolean table; apply Lua truth conversion before selecting the argument.
do
  local a=setmetatable({},{__lt=function()return {}end});local b={};assert(math.min(a,b)==b and math.max(a,b)==b)
end
print('Extrema_Truthy_Comparison: PASS')

-- Minimum_Right_Handler: a candidate without its own ordering handler; use ordinary left/right metamethod lookup.
do
  local a={};local b={};setmetatable(a,{__lt=function(x,y)return y==a end});assert(math.min(a,b)==b)
end
print('Minimum_Right_Handler: PASS')

-- Extrema_Mixed_String_Error: numeric strings mixed with numbers; avoid the obsolete numeric-only coercion path.
do
  assert(not pcall(math.min,1,'2'));assert(not pcall(math.max,'2',1))
end
print('Extrema_Mixed_String_Error: PASS')

-- Minimum_Error_Recovery: a table handler raising a real error object; preserve protected error identity and later execution.
do
  local marker={};local a=setmetatable({},{__lt=function()error(marker)end});local ok,e=pcall(math.min,a,a);assert(not ok and e==marker and math.min(4,2)==2)
end
print('Minimum_Error_Recovery: PASS')

-- Maximum_Error_Recovery: a table handler raising a real error object; preserve protected error identity and later execution.
do
  local marker={};local a=setmetatable({},{__lt=function()error(marker)end});local ok,e=pcall(math.max,a,a);assert(not ok and e==marker and math.max(4,2)==4)
end
print('Maximum_Error_Recovery: PASS')

-- Minimum_No_Yield: a yielding comparison inside a coroutine; reject yield instead of suspending the native math call.
do
  local a=setmetatable({},{__lt=function()coroutine.yield(42)end});local co=coroutine.create(function()return math.min(a,a)end);local ok,e=coroutine.resume(co);assert(not ok and e:find('yield',1,true) and coroutine.status(co)=='dead')
end
print('Minimum_No_Yield: PASS')

-- Maximum_No_Yield: a yielding comparison inside a coroutine; reject yield instead of suspending the native math call.
do
  local a=setmetatable({},{__lt=function()coroutine.yield(42)end});local co=coroutine.create(function()return math.max(a,a)end);local ok,e=coroutine.resume(co);assert(not ok and e:find('yield',1,true) and coroutine.status(co)=='dead')
end
print('Maximum_No_Yield: PASS')

-- Language_Less_Yields: a yielding table ordering metamethod; avoid applying native math restrictions to VM comparison.
do
  local a=setmetatable({},{__lt=function()return coroutine.yield(42)end});local co=coroutine.create(function()return a<a end);local ok,v=coroutine.resume(co);assert(ok and v==42);local ok2,v2=coroutine.resume(co,true);assert(ok2 and v2==true)
end
print('Language_Less_Yields: PASS')

-- Minimum_Argument_Mutation: a handler replacing the native first argument; return the actual mutated stack slot rather than a value snapshot.
do
  local replacement={};local a=setmetatable({},{__lt=function()return false end});local b=setmetatable({},{__lt=function()assert(debug.setlocal(2,1,replacement)=='(C temporary)');return false end});assert(math.min(a,b)==replacement)
end
print('Minimum_Argument_Mutation: PASS')

-- Maximum_Argument_Mutation: a handler replacing the native first argument; return the actual mutated stack slot rather than a value snapshot.
do
  local replacement={};local a=setmetatable({},{__lt=function()assert(debug.setlocal(2,1,replacement)=='(C temporary)');return false end});assert(math.max(a,{})==replacement)
end
print('Maximum_Argument_Mutation: PASS')

-- Minimum_Rereads_Best: three arguments and a mutation during the first comparison; use the changed slot again in the following comparison.
do
  local replacement={};local n=0;local a=setmetatable({},{__lt=function()return false end});local b=setmetatable({},{__lt=function()debug.setlocal(2,1,replacement);return false end});local c=setmetatable({},{__lt=function(x,y)n=n+1;assert(y==replacement);return false end});assert(math.min(a,b,c)==replacement and n==1)
end
print('Minimum_Rereads_Best: PASS')

-- Pairs_Yield_Results: a yielding __pairs producing four results; retain arguments and all iterator results across suspension.
do
  local t=setmetatable({},{__pairs=function(self)assert(coroutine.yield('pause',self)==7);return next,{x=5},nil,8 end});local co=coroutine.create(function()return pairs(t)end);local ok,p,self=coroutine.resume(co);assert(ok and p=='pause' and self==t);local ok2,f,s,k,c=coroutine.resume(co,7);assert(ok2 and f==next and s.x==5 and k==nil and c==8)
end
print('Pairs_Yield_Results: PASS')

-- Pairs_Result_Adjustment: handlers returning one and then five values; apply the pinned four-result continuation contract.
do
  local t=setmetatable({},{__pairs=function()return 9 end});local a,b,c,d,e=pairs(t);assert(a==9 and b==nil and c==nil and d==nil and e==nil and select('#',pairs(t))==4);getmetatable(t).__pairs=function()return 1,2,3,4,5 end;assert(select('#',pairs(t))==4)
end
print('Pairs_Result_Adjustment: PASS')

-- Pairs_Lazy_Non_Table: a number and explicit nil as iterator state; reject invalid state only when the iterator is called.
do
  local f,s,k,c=pairs(7);assert(f==next and s==7 and k==nil and c==nil);assert(not pcall(f,s,k));local f2,s2=pairs(nil);assert(f2==next and s2==nil)
end
print('Pairs_Lazy_Non_Table: PASS')

-- Pairs_Missing_Argument: a nil-type __pairs handler and zero arguments; report the missing argument without invoking that handler.
do
  local called=false;debug.setmetatable(nil,{__pairs=function()called=true end});local ok=pcall(pairs);debug.setmetatable(nil,nil);assert(not ok and not called)
end
print('Pairs_Missing_Argument: PASS')

-- Pairs_Fourth_Closing_Value: a generic-for loop resumed through __pairs; run the fourth result closing handler at loop exit.
do
  local count=0;local closer=setmetatable({},{__close=function()count=count+1 end});local t=setmetatable({},{__pairs=function()coroutine.yield('pause');return next,{x=1},nil,closer end});local co=coroutine.create(function()for k,v in pairs(t)do assert(k=='x' and v==1)end;return count end);local ok,v=coroutine.resume(co);assert(ok and v=='pause' and count==0);local ok2,v2=coroutine.resume(co);assert(ok2 and v2==1)
end
print('Pairs_Fourth_Closing_Value: PASS')

-- Standard_Arithmetic_No_Yield: a string arithmetic handler falling through to a Lua rhs handler; honor lua_call rather than treating every continuation as yieldable.
do
  local rhs=setmetatable({},{__add=function()coroutine.yield(9)end});local co=coroutine.create(function()return 'bad'+rhs end);local ok,e=coroutine.resume(co);assert(not ok and e:find('yield',1,true))
end
print('Standard_Arithmetic_No_Yield: PASS')

-- User_String_Override_Yields: a replacement string __add closure; restrict only installed standard arithmetic native handlers.
do
  local mt=getmetatable('');local old=mt.__add;mt.__add=function(a,b)assert(a=='bad' and b==2);return coroutine.yield(42)end;local co=coroutine.create(function()return 'bad'+2 end);local ok,v=coroutine.resume(co);assert(ok and v==42);local ok2,v2=coroutine.resume(co,7);assert(ok2 and v2==7);mt.__add=old
end
print('User_String_Override_Yields: PASS')

-- Standard_Arithmetic_Conversion: mixed numeric primitives and source strings; perform arithmetic on converted values and preserve result kind.
do
  assert('2'+3==5 and '0x10'*'2'==32 and '3.5'-1==2.5 and -'4'==-4)
end
print('Standard_Arithmetic_Conversion: PASS')

-- Direct_Arithmetic_One_Argument: a standard handler called with one numeric string; match the index-two value created by the first conversion.
do
  local mt=getmetatable('');assert(mt.__add('2')==4 and mt.__sub('2')==0 and mt.__mul('2')==4 and mt.__unm('2')==-2)
end
print('Direct_Arithmetic_One_Argument: PASS')

-- Direct_Unary_Second_Argument: an explicit second numeric string argument; preserve lua_arith unary behavior instead of duplicating operands.
do
  assert(getmetatable('').__unm('2','3')==-3)
end
print('Direct_Unary_Second_Argument: PASS')

-- Direct_Unary_Fallback: an invalid first string and rhs table __unm; avoid replacing the real rhs with the unary lhs.
do
  local rhs={};setmetatable(rhs,{__unm=function(a,b)assert(a=='bad' and b==rhs);return 23 end});assert(getmetatable('').__unm('bad',rhs)==23)
end
print('Direct_Unary_Fallback: PASS')

-- Arithmetic_Extra_Root_Trim: a weakly observed third temporary argument; clear discarded scalar roots before the callback can collect.
do
  local weak=setmetatable({},{__mode='v'});local rhs=setmetatable({},{__add=function(a,b)collectgarbage('collect');assert(weak[1]==nil and a=='bad' and b~=nil);return 11 end});local function supply()local t={};weak[1]=t;return t end;assert(getmetatable('').__add('bad',rhs,supply())==11)
end
print('Arithmetic_Extra_Root_Trim: PASS')

