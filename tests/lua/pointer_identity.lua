-- Public default rendering uses the same real identity as %p.
local cases = {
  function()
    assert(tostring(nil)=='nil' and tostring(false)=='false')
    assert(tostring(true)=='true' and tostring(17)=='17')
    assert(tostring(17.0)=='17.0')
  end,
  function()
    local t={};assert(tostring(t)=='table: '..string.format('%p',t))
  end,
  function()
    local t=setmetatable({},{__name='My Type'})
    assert(tostring(t)=='My Type: '..string.format('%p',t))
  end,
  function()
    local t=setmetatable({},{__name='Box\0unprinted'})
    assert(tostring(t)=='Box: '..string.format('%p',t))
  end,
  function()
    local t=setmetatable({},{__name=''})
    assert(tostring(t)==': '..string.format('%p',t))
  end,
  function()
    local t=setmetatable({},{__name='\0unprinted'})
    assert(tostring(t)==': '..string.format('%p',t))
  end,
  function()
    local t=setmetatable({},{__name=42})
    assert(tostring(t)=='table: '..string.format('%p',t))
  end,
  function()
    local n=0;local mt=setmetatable({},{__index=function()n=n+1 end})
    local t=setmetatable({},mt)
    assert(tostring(t)=='table: '..string.format('%p',t) and n==0)
  end,
  function()
    local f=function()end
    assert(tostring(f)=='function: '..string.format('%p',f))
  end,
  function()
    assert(tostring(assert)=='function: '..string.format('%p',assert))
  end,
  function()
    local old=debug.getmetatable(assert)
    debug.setmetatable(assert,{__name='Callable\0unprinted'})
    local s=tostring(assert);debug.setmetatable(assert,old)
    assert(s=='Callable: '..string.format('%p',assert))
  end,
  function()
    local co=coroutine.create(function()coroutine.yield(1);return 2 end)
    local p=string.format('%p',co)
    assert(tostring(co)=='thread: '..p)
    assert(coroutine.resume(co));assert(string.format('%p',co)==p)
    assert(coroutine.resume(co));assert(tostring(co)=='thread: '..p)
  end,
  function()
    local s=string.rep('long',100)
    assert(string.format('%p',tostring(s))==string.format('%p',s))
  end,
  function()
    local s=string.rep('result',100)
    local t=setmetatable({},{__tostring=function()return s end})
    assert(string.format('%p',tostring(t))==string.format('%p',s))
  end,
  function()
    local t=setmetatable({},{__tostring=function()return 42 end})
    assert(tostring(t)=='42')
  end,
  function()
    local t=setmetatable({},{__tostring=function()return 42.0 end})
    assert(tostring(t)=='42.0')
  end,
  function()
    local t=setmetatable({},{__tostring=function()return false end})
    local ok,e=pcall(tostring,t)
    assert(not ok and e=="'__tostring' must return a string",tostring(e))
  end,
  function()
    local ok,e=pcall(tostring)
    assert(not ok and e=="bad argument #1 to 'tostring' (value expected)",e)
  end,
  function()
    for _,v in ipairs({false,17,17.0})do
      assert(string.format('%p',v)=='(null)')
    end
    assert(string.format('%p',nil)=='(null)')
  end,
  function()
    local t={}
    assert(#string.format('%20p',t)==20)
    assert(#string.format('%-20p',t)==20)
    assert(string.format('%20p',nil)==string.rep(' ',14)..'(null)')
  end,
  function()
    local old=debug.getmetatable(0)
    debug.setmetatable(0,{__name='Named Number'})
    local a,b=tostring(17),tostring(17.0)
    debug.setmetatable(0,old);assert(a=='17' and b=='17.0')
  end,
  function()
    local s=string.rep('handler',100);local old=debug.getmetatable('')
    debug.setmetatable('',{__tostring=function()return s end})
    local result=tostring('input');debug.setmetatable('',old)
    assert(string.format('%p',result)==string.format('%p',s))
  end,
  function()
    local weak=setmetatable({},{__mode='v'})
    local function make()
      local co=coroutine.create(function()end);weak[1]=co;tostring(co)
    end
    make();collectgarbage();collectgarbage();assert(weak[1]==nil)
  end,
}
for i,f in ipairs(cases) do f();print('PASS: pointer-identity-'..i) end
print('PASS: Lua pointer identity contract')
