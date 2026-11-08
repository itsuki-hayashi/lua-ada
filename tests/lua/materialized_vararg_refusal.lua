-- Exact companion fault campaign: T absence must be a failure, never a skip.
assert(T and type(T.alloccount)=='function' and type(T.totalmem)=='function')
local function deep(n)if n>0 then deep(n-1)end end
local function pack(...t)return t end
local function make()return pack(10,20,30,40,'hello')end
local code='pcall 0 1 0;pushstatus;return 2'
_MATERIALIZED_VARARG_MEASUREMENTS={}
local function payload(t)
 assert(type(t)=='table' and t.n==5)
 assert(t[1]==10 and t[2]==20 and t[3]==30 and t[4]==40 and t[5]=='hello')
 for i=1,4 do assert(math.type(t[i])=='integer')end
 assert(type(t[5])=='string')
end
local cases={
 {'Count_Faults',function()
  local completed,failures=false,0
  for count=0,128 do
   collectgarbage();collectgarbage();deep(4)
   T.alloccount(count)
   local result,status=T.testC(code,make)
   T.alloccount()
   if status=='OK'then
    payload(result);completed=true
    _MATERIALIZED_VARARG_MEASUREMENTS.count=count
    break
   end
   assert(result=='not enough memory' and status==result)
   failures=failures+1
  end
  assert(completed and failures>0)
  payload(make())
 end},
 {'Byte_Faults',function()
  collectgarbage();local initial=T.totalmem()
  local completed,failures=false,0
  for step=0,16384 do
   collectgarbage();collectgarbage();deep(4)
   T.totalmem(initial+step*7)
   local result,status=T.testC(code,make)
   T.totalmem(0)
   if status=='OK'then
    payload(result);completed=true
    _MATERIALIZED_VARARG_MEASUREMENTS.extra_bytes=step*7
    break
   end
   assert(result=='not enough memory' and status==result)
   failures=failures+1
  end
  assert(completed and failures>0)
  payload(make())
 end},
 {'Partial_Release',function()
  local weak=setmetatable({},{__mode='v'})
  local completed,failures=false,0
  for count=0,128 do
   local value={value=37};weak[1]=value
   local function build()return pack(value,nil,30,40,'hello')end
   collectgarbage();collectgarbage();deep(4);T.alloccount(count)
   local result,status=T.testC(code,build)
   T.alloccount()
   if status=='OK'then
    assert(type(result)=='table' and result.n==5)
    assert(result[1]==value and result[2]==nil and result[3]==30)
    assert(result[4]==40 and result[5]=='hello')
    assert(math.type(result[3])=='integer' and type(result[5])=='string')
    completed=true
   else
    assert(result=='not enough memory' and status==result)
    failures=failures+1
   end
   result=nil;build=nil;value=nil
   collectgarbage();collectgarbage()
   assert(weak[1]==nil,'partial vararg table retained its payload')
   if completed then break end
  end
  assert(completed and failures>0)
  payload(make())
 end},
 {'Retained_Recovery',function()
  local weak=setmetatable({},{__mode='v'})
  local retained=make();weak[1]=retained
  collectgarbage();collectgarbage();deep(4);T.alloccount(0)
  local result,status=T.testC(code,make)
  T.alloccount()
  assert(result=='not enough memory' and status==result)
  collectgarbage();payload(retained);assert(weak[1]==retained)
  local recovered=make();payload(recovered);assert(recovered~=retained)
  retained=nil;collectgarbage();collectgarbage();assert(weak[1]==nil)
 end},
}
for _,case in ipairs(cases)do
 if _MATERIALIZED_VARARG_CASE==nil or _MATERIALIZED_VARARG_CASE==case[1]then
  case[2]();print('PASS materialized vararg refusal '..case[1])
 end
end
