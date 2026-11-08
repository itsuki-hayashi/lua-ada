-- Ordinary public controls retained from the real-provider campaign.
local cases={
  {'Table_Equality_Yields',function()
    local calls=0
    local mt={__eq=function(a,b)
      calls=calls+1;collectgarbage();return coroutine.yield(17)
    end}
    local a,b=setmetatable({},mt),setmetatable({},mt)
    local co=coroutine.create(function()return a==b end)
    local ok,value=coroutine.resume(co);assert(ok and value==17)
    ok,value=coroutine.resume(co,true);assert(ok and value==true and calls==1)
  end},
  {'Assert_Protected_Tuple',function()
    local marker={}
    local ok,a,b,c,d=pcall(assert,37,nil,marker,nil)
    assert(ok and a==37 and b==nil and c==marker and d==nil)
    assert(select('#',pcall(assert,37,nil,marker,nil))==5)
  end},
}
for _,case in ipairs(cases)do
  case[2]();print('PASS call metadata public '..case[1])
end
print('Call metadata public OK')
