-- A marked scalar remains marked after debug writes nil/false into it.
local function closable(fn)return setmetatable({},{__close=fn})end
local function replaceLower(value)
 local i=1
 while true do
  local name=debug.getlocal(3,i);assert(name)
  if name=='x'then assert(debug.setlocal(3,i,value)=='x');return end
  i=i+1
 end
end
local function isCloseError(msg)
 return type(msg)=='string' and msg:find('attempt to call a nil value',1,true)
  and msg:find("metamethod 'close'",1,true)
end
local cases={
 {'Nil_Mutation',function()
  local oldCalled=false
  local function f()
   local x <close> =closable(function()oldCalled=true end)
   local y <close> =closable(function()replaceLower(nil)end)
   return 37
  end
  local ok,msg=pcall(f)
  assert(not ok and isCloseError(msg) and not oldCalled)
 end},
 {'False_Mutation',function()
  local oldCalled=false
  local function f()
   local x <close> =closable(function()oldCalled=true end)
   local y <close> =closable(function()replaceLower(false)end)
   return 37
  end
  local ok,msg=pcall(f)
  assert(not ok and isCloseError(msg) and not oldCalled)
 end},
 {'False_Type_Closer',function()
  local previous=debug.getmetatable(false)
  local normal,failed,oldCalled=0,0,false
  local ok,msg=pcall(function()
   debug.setmetatable(false,{__close=function(value,...)
    assert(value==false)
    if select('#',...)==0 then normal=normal+1
    else assert(select('#',...)==1 and (...)==17);failed=failed+1 end
   end})
   local function f(fail)
    local x <close> =closable(function()oldCalled=true end)
    do
     local y <close> =closable(function()replaceLower(false)end)
    end
    if fail then error(17)end
    return 37
   end
   assert(f(false)==37)
   local success,err=pcall(f,true);assert(not success and err==17)
   do local inactive <close> =false end
   assert(normal==1 and failed==1 and not oldCalled)
  end)
  debug.setmetatable(false,previous)
  assert(ok,msg)
 end},
 {'Outer_Error_GC_Recovery',function()
  local weak=setmetatable({},{__mode='v'})
  local received,outerCalled,oldCalled=nil,0,false
  local function make()
   local value=closable(function()oldCalled=true end)
   weak[1]=value;return value
  end
  local function f()
   local outer <close> =closable(function(self,msg)
    received=msg;outerCalled=outerCalled+1
    collectgarbage();collectgarbage();assert(weak[1]==nil)
   end)
   local x <close> =make()
   local y <close> =closable(function()
    replaceLower(nil);collectgarbage();collectgarbage()
    assert(weak[1]==nil)
   end)
   return 37
  end
  local ok,msg=pcall(f)
  assert(not ok and isCloseError(msg) and received==msg)
  assert(outerCalled==1 and not oldCalled and weak[1]==nil)
  local closed=false
  local function healthy()
   local value <close> =closable(function()closed=true end)
   return 42
  end
  assert(healthy()==42 and closed)
 end},
}
for _,case in ipairs(cases)do
 if _SCALAR_MUTATION_CASE==nil or _SCALAR_MUTATION_CASE==case[1]then
  case[2]();print('PASS scalar mutation '..case[1])
 end
end
