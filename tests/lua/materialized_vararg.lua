-- Public named-vararg materialization semantics; no T helper is consulted.
local function pack(...t)return t end
local cases={
 {'Payload_Types',function()
  local t=pack(10,20,30,40,'hello')
  assert(type(t)=='table' and t.n==5)
  for i=1,4 do assert(t[i]==i*10 and math.type(t[i])=='integer')end
  assert(type(t[5])=='string' and t[5]=='hello' and t[6]==nil)
 end},
 {'Nil_Holes',function()
  local t=pack(nil,20,nil,40,nil)
  assert(type(t)=='table' and t.n==5)
  assert(t[1]==nil and t[2]==20 and t[3]==nil and t[4]==40 and t[5]==nil)
  assert(pack().n==0 and pack(nil).n==1)
 end},
 {'Fresh_Aliases',function()
  local payload={value=37}
  local a=pack(nil,payload,nil,payload,nil)
  local b=pack(nil,payload,nil,payload,nil)
  assert(a~=b and a.n==5 and b.n==5)
  assert(a[2]==payload and a[4]==payload and b[2]==payload)
  a[1]=42;a[2].value=43;a.n=9
  assert(b[1]==nil and b[2].value==43 and b.n==5)
  assert(payload.value==43 and a[4]==b[4])
 end},
 {'Captured_Table',function()
  local weak=setmetatable({},{__mode='v'})
  local function retain(...t)
   weak[1]=t
   return function()return t end
  end
  local payload={value=37}
  local getter=retain(payload,nil,'hello',nil)
  collectgarbage();collectgarbage()
  assert(getter()==weak[1] and getter().n==4)
  assert(getter()[1]==payload and getter()[2]==nil and getter()[4]==nil)
  getter()[1].value=42;assert(payload.value==42)
  getter=nil;collectgarbage();collectgarbage();assert(weak[1]==nil)
 end},
}
for _,case in ipairs(cases)do
 if _MATERIALIZED_VARARG_CASE==nil or _MATERIALIZED_VARARG_CASE==case[1]then
  case[2]();print('PASS materialized vararg '..case[1])
 end
end
