-- Live_Count_Assertion: A live count assertion consumes comparison branches directly.
do
  local a=0;debug.sethook(function()a=a+1 end,'',1);a=0;for i=1,1000 do end;assert(1000<a and a<1012);debug.sethook()
end

-- Live_Period_Four: The upstream period-four bound includes its live assertion words.
do
  local a=0;debug.sethook(function()a=a+1 end,'',4);a=0;for i=1,1000 do end;assert(250<a and a<255);debug.sethook()
end

-- Live_Sparse_Period: An unexpired sparse period cannot fire inside the assertion.
do
  local a=0;debug.sethook(function()a=a+1 end,'',4000);a=0;for i=1,1000 do end;assert(a==0);debug.sethook()
end

-- Equal_Branches: Equal comparisons feed both short-circuit outcomes correctly.
do
  local a,b=1,2;local x=a==b and 13;local y=a==a and 17;local z=a==b or 19;local q=a==a or 23;assert(x==false and y==17 and z==19 and q==true)
end

-- Not_Equal_Branches: Negated equality inverts the actual comparison branch flag.
do
  local a,b=1,2;local x=a~=b and 13;local y=a~=a and 17;local z=a~=b or 19;local q=a~=a or 23;assert(x==13 and y==false and z==true and q==23)
end

-- Less_Branches: Less-than comparisons retain true and false branch values.
do
  local a,b=1,2;local x=a<b and 13;local y=b<a and 17;local z=a<b or 19;local q=b<a or 23;assert(x==13 and y==false and z==true and q==23)
end

-- Less_Equal_Branches: Less-equal comparison preserves equality and ordered outcomes.
do
  local a,b=1,2;local x=a<=a and 13;local y=b<=a and 17;local z=a<=b or 19;local q=b<=a or 23;assert(x==13 and y==false and z==true and q==23)
end

-- Greater_Branches: Greater-than lowering swaps operands before its real branch.
do
  local a,b=1,2;local x=b>a and 13;local y=a>b and 17;local z=b>a or 19;local q=a>b or 23;assert(x==13 and y==false and z==true and q==23)
end

-- Greater_Equal_Branches: Greater-equal lowering retains the swapped equality predicate.
do
  local a,b=1,2;local x=a>=a and 13;local y=a>=b and 17;local z=b>=a or 19;local q=a>=b or 23;assert(x==13 and y==false and z==true and q==23)
end

-- Standalone_Boolean: Standalone comparisons materialize actual booleans on both paths.
do
  local a,b=1,2;assert((a<b)==true and (b<a)==false);assert((a~=a)==false and (a~=b)==true)
end

-- Preserved_Right_Value: A selected right operand keeps its table identity or nil value.
do
  local a,b=1,2;local t={};local x=a<b and t;local y=b<a or t;local z=a<b and nil;assert(x==t and y==t and z==nil)
end

-- Skipped_Right_Effects: A selected left comparison prevents all right-side effects.
do
  local n=0;local function f()n=n+1;error('must skip')end;local a,b=1,2;local x=b<a and f();local y=a<b or f();assert(x==false and y==true and n==0)
end

-- Metamethod_Ordering: A comparison handler runs once before the selected right call.
do
  local order='';local mt={__lt=function()order=order..'c';return true end};local a,b=setmetatable({},mt),setmetatable({},mt);local function f()order=order..'r';return 9 end;local x=a<b and f();assert(x==9 and order=='cr')
end

-- Yielding_Comparison: A suspended comparison resumes its real branch and right value.
do
  local co=coroutine.create(function()local mt={__lt=function()coroutine.yield('cmp');return true end};local a,b=setmetatable({},mt),setmetatable({},mt);return a<b and 9 end);local ok,v=coroutine.resume(co);assert(ok and v=='cmp');collectgarbage();ok,v=coroutine.resume(co);assert(ok and v==9)
end

-- Failing_Comparison: A comparison error prevents the right operand from executing.
do
  local n=0;local function f()local mt={__lt=function()error(91)end};local a,b=setmetatable({},mt),setmetatable({},mt);local function rhs()n=n+1 end;return a<b and rhs()end;local ok,e=pcall(f);assert(not ok and e==91 and n==0)
end

-- NaN_Booleans: Unordered numeric comparisons still produce proper booleans.
do
  local a=0/0;local b=1;local x=a<b and 7;local y=a>=b or 9;local z=a~=a and 11;assert(x==false and y==9 and z==11)
end

print('comparison branch phases OK')
