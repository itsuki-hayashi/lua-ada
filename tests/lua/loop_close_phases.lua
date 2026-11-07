-- Empty_Numeric_Every_Instruction: An empty loop executes its real FORLOOP once per iteration.
do
  local a=0;debug.sethook(function()a=a+1 end,'',1);a=0;for i=1,1000 do end;local n=a;debug.sethook();assert(1000<n and n<1012)
end

-- Empty_Numeric_Period_Four: Count periods follow the actual loop words without a no-op close.
do
  local a=0;debug.sethook(function()a=a+1 end,'',4);a=0;for i=1,1000 do end;local n=a;debug.sethook();assert(250<n and n<255)
end

-- Empty_Numeric_Sparse_Count: A sparse count period remains unexpired across an empty loop.
do
  local a=0;debug.sethook(function()a=a+1 end,'',1500);a=0;for i=1,1000 do end;local n=a;debug.sethook();assert(n==0)
end

-- Captured_Numeric_Cells: Captured controls detach before the next iteration and collection.
do
  local t={};for i=1,5 do t[i]=function()return i end;collectgarbage()end;collectgarbage();for i=1,5 do assert(t[i]()==i)end
end

-- Captured_Generic_Cells: Generic control captures retain their own iteration values.
do
  local t={};for i,v in ipairs({11,22,33})do t[i]=function()return i,v end;collectgarbage()end;collectgarbage();for i=1,3 do local k,v=t[i]();assert(k==i and v==i*11)end
end

-- Reused_Uncaptured_Register: A previous captured control cannot mark a new loop's reused slot.
do
  local t={};for i=1,2 do t[i]=function()return i end end;local a=0;debug.sethook(function()a=a+1 end,'',1);a=0;for i=1,1000 do end;local n=a;debug.sethook();assert(1000<n and n<1012);assert(t[1]()==1 and t[2]()==2)
end

-- Shadowed_Control_Cell: A captured body-local shadow remains distinct from loop control.
do
  local t={};for i=1,3 do local i=i*10;t[#t+1]=function()return i end;collectgarbage()end;for i=1,3 do assert(t[i]()==i*10)end
end

-- Transitive_Control_Capture: An intermediate child captures a control used by its own child.
do
  local t={};for i=1,3 do t[i]=function()return function()return i end end end;collectgarbage();for i=1,3 do assert(t[i]()()==i)end
end

-- Suppressed_Hook_Count_Phase: Suppressed Lua hook words still decrement and reset the period.
do
  local a=0;debug.sethook(function()a=a+1;local x=1 end,'',4);a=0;for i=1,1000 do end;local n=a;debug.sethook();assert(330<n and n<340)
end

-- Suppressed_Hook_Larger_Period: A longer hook body shifts the next callback without reentry.
do
  local a=0;debug.sethook(function()a=a+1;local x,y,z,q=1,2,3,4 end,'',7);a=0;for i=1,1000 do end;local n=a;debug.sethook();assert(165<n and n<172)
end

-- Immediate_Add_Minimum: The signed immediate minimum reaches the real add fallback.
do
  local n=0;local x;x=setmetatable({},{__add=function(a,b)assert(a==x and b==-127);n=n+1;return 9 end});local y=x+-127;assert(y==9 and n==1)
end

-- Immediate_Add_Maximum: The signed immediate maximum reaches the real add fallback.
do
  local n=0;local x;x=setmetatable({},{__add=function(a,b)assert(a==x and b==128);n=n+1;return 9 end});local y=x+128;assert(y==9 and n==1)
end

-- Outside_Add_Immediate: An integer beyond the byte range keeps its register operand.
do
  local n=0;local x;x=setmetatable({},{__add=function(a,b)assert(a==x and b==129);n=n+1;return 9 end});local y=x+129;assert(y==9 and n==1)
end

-- Immediate_Add_Wrap: Immediate arithmetic retains Lua integer wrap and numeric type.
do
  local n=math.maxinteger;assert(n+1==math.mininteger);assert(math.type(2.0+1)=='float');assert(('2'+1)==3)
end

print('loop close phases OK')
