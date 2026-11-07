-- First-party native/Ada observations for deferred assignment operands.
-- Each named block isolates one public evaluation, source or root lifetime.
-- The adjacent AUnit cases explain setup, action and the protected result.

-- Local_Environment
do
  local old,new={},{};local function f()local _ENV=old;x=(function()_ENV=new;return 41 end)()end;f();assert(old.x==nil and new.x==41)
end
print("Local_Environment")

-- Upvalue_Environment
do
  local old,new={},{};do local _ENV=old;local function f()x=(function()_ENV=new;return 42 end)()end;f()end;assert(old.x==nil and new.x==42)
end
print("Upvalue_Environment")

-- Local_Table_And_Key
do
  local old,new={},{};local t,k=old,1;t[k]=(function()t=new;k=2;return 43 end)();assert(old[1]==nil and new[2]==43)
end
print("Local_Table_And_Key")

-- Upvalue_Integer_Table
do
  local old,new={},{};local t=old;local function f()t[1]=(function()t=new;return 44 end)()end;f();assert(old[1]==44 and new[1]==nil)
end
print("Upvalue_Integer_Table")

-- Upvalue_String_Table
do
  local old,new={},{};local t=old;local function f()t.x=(function()t=new;return 45 end)()end;f();assert(old.x==nil and new.x==45)
end
print("Upvalue_String_Table")

-- Upvalue_After_Key_Callback
do
  local old,new={},{};local t=old;local function key()t=new;return 1 end;local function f()t[key()]=46 end;f();assert(old[1]==nil and new[1]==46)
end
print("Upvalue_After_Key_Callback")

-- Parallel_Environment_Conflict
do
  local old,new,third={},{},{};do local _ENV=old;x,_ENV=(function()_ENV=third;return 47,new end)()end;assert(old.x==47 and new.x==nil and third.x==nil)
end
print("Parallel_Environment_Conflict")

-- Parallel_Table_Key_Conflict
do
  local old,new={},{};local t,k=old,1;t[k],t,k=48,new,2;assert(old[1]==48 and new[2]==nil and t==new and k==2)
end
print("Parallel_Table_Key_Conflict")

-- Computed_Table_Order
do
  local trace='';local old=setmetatable({},{__newindex=function(_,k,v)trace=trace..'s';assert(k==1 and v==49)end});local new={};local t=old;local function base()trace=trace..'b';return t end;local function key()trace=trace..'k';t=new;return 1 end;local function rhs()trace=trace..'r';return 49 end;base()[key()]=rhs();assert(trace=='bkrs' and new[1]==nil)
end
print("Computed_Table_Order")

-- Computed_Table_Root
do
  local w=setmetatable({},{__mode='v'});local function base()local t={};w[1]=t;return t end;base().x=(function()collectgarbage();assert(w[1]~=nil);return 50 end)();collectgarbage();assert(w[1]==nil)
end
print("Computed_Table_Root")

-- Computed_Key_Root
do
  local w=setmetatable({},{__mode='v'});local t={};local function key()local k={};w[1]=k;return k end;t[key()]=(function()collectgarbage();assert(w[1]~=nil);return 51 end)();assert(t[w[1]]==51);for k in pairs(t)do t[k]=nil end;collectgarbage();assert(w[1]==nil)
end
print("Computed_Key_Root")

-- Local_Arithmetic_Operand
do
  local x=1;local function rhs()x=3;return 4 end;assert(x+rhs()==7)
end
print("Local_Arithmetic_Operand")

-- Indexed_Arithmetic_Operand
do
  local t={x=1};local function rhs()t={x=3};return 4 end;assert(t.x+rhs()==5)
end
print("Indexed_Arithmetic_Operand")

-- Multiline_Index_Phases
do
  local co=coroutine.create(assert(load('local b={10}\na=b[1]\n+\nb[1]\nb=4\n')));local t={};debug.sethook(co,function(e,l)t[#t+1]=l end,'l');assert(coroutine.resume(co));local want={1,3,4,3,4,5};assert(#t==#want);for i=1,#t do assert(t[i]==want[i])end
end
print("Multiline_Index_Phases")

-- Store_Current_Line
do
  local t=setmetatable({},{__newindex=function(self,k,v)assert(debug.getinfo(2,'l').currentline==2);rawset(self,k,v)end});local f=assert(load('t.x=\n52\n','=store-phase','t',{t=t}));f();assert(t.x==52)
end
print("Store_Current_Line")

-- Concat_Local_Snapshot
do
  local x='old';local function rhs()x='new';return 'r' end
  assert(x..rhs()=='oldr')
end
print("Concat_Local_Snapshot")
print("OK")
