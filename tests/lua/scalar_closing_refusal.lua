-- Scalar closing metadata must reuse actual reserved stack links. Every
-- provider limit below affects the real allocator; the actual closer lifts it.
local function deep(n)n=((n==0)or deep(n-1))end
local function closable(fn)return setmetatable({},{__close=fn})end
local cases={
 {'Original_Failure',function()
  local message
  local closer=closable(function(self,msg)T.alloccount();message=msg end)
  local function enter()deep(10);T.alloccount(0);message=nil;return closer end
  local function f()local x <close> =enter();local y={}end
  local ok,msg=pcall(f)
  assert(not ok and msg=='not enough memory' and message==msg)
 end},
 {'Multiple_Failure',function()
  local message
  local closer=closable(function(self,msg)T.alloccount();message=msg end)
  local function enter()deep(10);T.alloccount(0);message=nil;return closer end
  local function f()
   local outer <close> =closable(function(self,msg)
    assert(msg=='not enough memory');error(1000)
   end)
   local middle <close> =closable(function(self,msg)
    assert(msg=='not enough memory')
   end)
   local inner <close> =enter();local y={}
  end
  local ok,msg=pcall(f)
  assert(not ok and msg==1000 and message=='not enough memory')
 end},
 {'Closer_Failure',function()
  local lifted=false
  local function f()
   local outer <close> =closable(function(self,msg)
    T.alloccount();lifted=true;assert(msg=='not enough memory')
   end)
   local inner <close> =closable(function()
    T.alloccount(0);local rejected={}
   end)
   error(1000)
  end
  deep(10);local ok,msg=pcall(f)
  assert(not ok and msg=='not enough memory' and lifted)
 end},
 {'Cold_True',function()
  local closed=0
  local value=closable(function()T.alloccount();closed=closed+1 end)
  local function cold(v)local x <close> =v;return 37 end
  deep(10);T.alloccount(0)
  local result=cold(value)
  assert(result==37 and closed==1)
 end},
 {'Nil_Entry',function()
  local function cold(v)local x <close> =v;return 37 end
  deep(10);T.alloccount(0)
  local result=cold(nil)
  T.alloccount();assert(result==37)
 end},
 {'False_Entry',function()
  local function cold(v)local x <close> =v;return 37 end
  deep(10);T.alloccount(0)
  local result=cold(false)
  T.alloccount();assert(result==37)
 end},
 {'Closed_Upvalue',function()
  local log={};local getter
  local a=closable(function()log[#log+1]='a'end)
  local b=closable(function()log[#log+1]='b'end)
  local function f()
   local x <close> =a
   getter=function()return x end
   local y <close> =closable(function()
    assert(debug.setupvalue(getter,1,b)=='x');collectgarbage()
   end)
  end
  f();assert(table.concat(log)== 'a' and getter()==b)
 end},
 {'Mutable_Stack',function()
  local log={};local getter
  local a=closable(function()log[#log+1]='a'end)
  local b=closable(function()log[#log+1]='b'end)
  local function f()
   local x <close> =a
   getter=function()return x end
   local y <close> =closable(function()
    local i=1
    while true do
     local name=debug.getlocal(2,i);assert(name)
     if name=='x'then assert(debug.setlocal(2,i,b)=='x');break end
     i=i+1
    end
    collectgarbage()
   end)
  end
  f();assert(table.concat(log)=='b' and getter()==a)
 end},
 {'Suspended_Roots',function()
  local weak=setmetatable({},{__mode='v'});local closed=0
  local co=coroutine.create(function()
   local x <close> =closable(function()closed=closed+1 end)
   weak[1]=x;coroutine.yield(37)
  end)
  local ok,result=coroutine.resume(co);assert(ok and result==37)
  collectgarbage();assert(weak[1] and closed==0)
  assert(coroutine.close(co));assert(closed==1)
  collectgarbage();collectgarbage();assert(weak[1]==nil)
 end},
 {'Captured_Suspended',function()
  local getter;local closed=0
  local co=coroutine.create(function()
   local x <close> =closable(function()closed=closed+1 end)
   getter=function()return x end
   coroutine.yield(37)
  end)
  assert(coroutine.resume(co));local value=getter();collectgarbage()
  assert(coroutine.close(co));assert(closed==1 and getter()==value)
 end},
 {'Generic_For_Scope',function()
  local order={}
  local iterator=closable(function()T.alloccount();order[#order+1]='i'end)
  local function nextitem()return nil end
  local function setup()
   deep(10);T.alloccount(0);return nextitem,nil,nil,iterator
  end
  local function f()
   local outer <close> =closable(function()order[#order+1]='o'end)
   for x in setup()do error('unexpected iteration')end
   assert(order[1]=='i' and order[2]==nil)
   return 37
  end
  assert(f()==37 and table.concat(order)=='io')
 end},
 {'Jump_Scope',function()
  local log={}
  local function f()
   local outer <close> =closable(function()log[#log+1]='o'end)
   do
    local inner <close> =closable(function()log[#log+1]='i'end)
    goto finished
   end
   ::finished::
   assert(table.concat(log)=='i');return 37
  end
  assert(f()==37 and table.concat(log)=='io')
 end},
}
for _,case in ipairs(cases)do
 if _SCALAR_CLOSING_CASE==nil or _SCALAR_CLOSING_CASE==case[1]then
  case[2]();print('PASS scalar closing '..case[1])
 end
end
