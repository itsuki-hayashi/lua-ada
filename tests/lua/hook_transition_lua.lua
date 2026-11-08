-- Native-paired hook phases and literal stores with their real destinations.

-- Lua_Same_Line: A real Lua hook return restores the interrupted trace PC.
do
  local t={}
  local function line(e,n)t[#t+1]=e;t[#t+1]=n end
  local origin=debug.getinfo(1,'l').currentline
  debug.sethook(function()debug.sethook(line,'l')end,'',2)
  local a=1;a=1;a=1;a=1;a=1
  a=2
  debug.sethook()
  assert(t[1]=='line' and t[2]==origin+3)
  assert(t[3]=='line' and t[4]==origin+4 and t[5]==nil)
end

-- Lua_Count_Removes_Line: A pending old line phase uses the newly installed hook.
do
  local event
  local function replacement(e)debug.sethook();event=e end
  debug.sethook(function(e)
    if e=='count' then debug.sethook(replacement,'',1000)end
  end,'l',2)
  local a=1
  a=2
  debug.sethook()
  assert(event=='line')
end

-- Literal_Count: Each single local constant store executes one actual word.
do
  local counts={}
  local origin=debug.getinfo(1,'l').currentline
  debug.sethook(function(e)
    if e=='count' then local n=debug.getinfo(2,'l').currentline
      counts[n]=(counts[n]or 0)+1
    end
  end,'',1)
  local a=1
  a=2
  a=3
  a=4
  a=5
  debug.sethook()
  for n=origin+6,origin+10 do assert(counts[n]==1)end
  assert(a==5)
end

-- Integer_Cell: A direct integer literal store updates an existing captured cell.
do
  local a=0;local function read()return a end
  a=37;assert(read()==37 and math.type(read())=='integer')
end

-- Float_Cell: Direct literal placement preserves the Lua numeric kind.
do
  local a=0;local function read()return a end
  a=3.0;assert(read()==3 and math.type(read())=='float')
end

-- Binary_String_Cell: A counted string literal retains its embedded NUL bytes.
do
  local a=0;local function read()return a end
  a='x\0y';assert(read()=='x\0y' and #read()==3)
end

-- Boolean_Cell: A boolean constant store updates the shared cell without coercion.
do
  local a=0;local function read()return a end
  a=false;assert(read()==false)
  a=true;assert(read()==true)
end

-- Nil_Cell: A nil constant retires the old captured value.
do
  local a={};local function read()return a end
  a=nil;assert(read()==nil)
end

-- Callback_RHS: Nonliteral evaluation cannot overwrite the local before callbacks.
do
  local a={37}
  local function rhs()assert(type(a)=='table' and a[1]==37);return 5 end
  a=a[1]+rhs();assert(a==42)
end

-- Multiple_RHS: Multiple stores still wait until every RHS has been evaluated.
do
  local a,b=1,2
  a,b=3,(function()assert(a==1 and b==2);return 4 end)()
  assert(a==3 and b==4)
end

-- Indexed_Store: A literal RHS keeps its ordinary metamethod store behavior.
do
  local calls=0
  local t=setmetatable({},{__newindex=function(self,k,v)
    calls=calls+1;assert(k=='value' and v==41);rawset(self,k,v)
  end})
  t.value=41;assert(t.value==41 and calls==1)
end

print('Lua hook transitions OK')
