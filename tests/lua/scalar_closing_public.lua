-- Ordinary public closing cases retained from the full refusal campaign.
local function closable(fn)return setmetatable({},{__close=fn})end
local cases={
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
 case[2]();print('PASS scalar closing public '..case[1])
end
print('Scalar closing public OK')
