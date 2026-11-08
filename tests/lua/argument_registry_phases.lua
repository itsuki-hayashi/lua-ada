-- Real auxiliary registry-name lookups; the same bodies run as named AUnit cases.

-- Callback_Loaded: One actual registry lookup supplies the module graph.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r);local calls=0
  r._LOADED=nil;setmetatable(r,{__index=function(t,k)assert(t==r and k=='_LOADED');calls=calls+1;return loaded end})
  local ok,e=pcall(math.sin,{})
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and calls==1 and e=="bad argument #1 to 'math.sin' (number expected, got table)",tostring(e))
end

-- Plain_Temporaries: The original C frame owns detail, target and getfield key.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r)
  r._LOADED=nil;setmetatable(r,{__index=function()
    assert(debug.getinfo(2,'f').func==math.sin)
    local n,a=debug.getlocal(2,1);assert(n=='(C temporary)' and type(a)=='table')
    local _,detail=debug.getlocal(2,2);local _,f=debug.getlocal(2,3);local _,key=debug.getlocal(2,4)
    assert(detail=='number expected, got table' and f==math.sin and key=='_LOADED' and debug.getlocal(2,5)==nil)
    return loaded
  end})
  local ok,e=pcall(math.sin,{})
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and e=="bad argument #1 to 'math.sin' (number expected, got table)",tostring(e))
end

-- Named_Temporaries: A raw __name precedes the formatted detail in real slots.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r)
  r._LOADED=nil;setmetatable(r,{__index=function()
    local _,name=debug.getlocal(2,2);local _,detail=debug.getlocal(2,3)
    local _,f=debug.getlocal(2,4);local _,key=debug.getlocal(2,5)
    assert(name=='Named' and detail=='number expected, got Named' and f==math.sin and key=='_LOADED' and debug.getlocal(2,6)==nil)
    return loaded
  end})
  local ok,e=pcall(math.sin,setmetatable({},{__name='Named'}))
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and e=="bad argument #1 to 'math.sin' (number expected, got Named)",tostring(e))
end

-- Error_Identity: A lookup error replaces the pending argument diagnostic.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r);local marker={}
  r._LOADED=nil;setmetatable(r,{__index=function()error(marker)end})
  local ok,e=pcall(math.sin,{})
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and e==marker)
end

-- Empty_Result: A handler returning no values produces the unknown name.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r);local calls=0
  r._LOADED=nil;setmetatable(r,{__index=function()calls=calls+1 end})
  local ok,e=pcall(math.sin,{})
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and calls==1 and e=="bad argument #1 to '?' (number expected, got table)",tostring(e))
end

-- Nested_Errors: Nested lookups retain independent original types and indices.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r);local calls=0
  r._LOADED=nil;setmetatable(r,{__index=function()
    calls=calls+1
    if calls==1 then local ok,e=pcall(math.cos,false);assert(not ok and e=="bad argument #1 to 'math.cos' (number expected, got boolean)",tostring(e))end
    return loaded
  end})
  local ok,e=pcall(math.sin,{})
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and calls==2 and e=="bad argument #1 to 'math.sin' (number expected, got table)",tostring(e))
end

-- Table_Forwarding: The registry can forward the lookup through a table.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r)
  r._LOADED=nil;setmetatable(r,{__index={_LOADED=loaded}})
  local ok,e=pcall(math.sin,{})
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and e=="bad argument #1 to 'math.sin' (number expected, got table)",tostring(e))
end

-- Cannot_Yield: Registry callbacks cannot suspend synchronous argument checking.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r)
  r._LOADED=nil;setmetatable(r,{__index=coroutine.yield})
  local co=coroutine.create(function()return pcall(math.sin,{})end)
  local resumed,ok,e=coroutine.resume(co)
  setmetatable(r,mt);r._LOADED=loaded
  assert(resumed and not ok and e=='attempt to yield across a C-call boundary' and coroutine.status(co)=='dead',tostring(e))
end

-- Nul_Module_Name: The actual returned module name has C string rendering.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r)
  r._LOADED=nil;setmetatable(r,{__index=function()return {['A\0B']={f=math.sin}}end})
  local ok,e=pcall(math.sin,{})
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and e=="bad argument #1 to 'A' (number expected, got table)",tostring(e))
end

-- Operand_Collection: A callback dropping the actual C argument removes its last edge.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r);local weak=setmetatable({},{__mode='v'})
  local function factory()return math.sin end
  local function bad()local a={};weak[1]=a;return (factory())(a)end
  local function clear()
    -- A native C tail call can retain its Lua caller until the C return.
    -- Clear every actual caller slot, then retire this helper's own reads.
    for level=3,10 do
      if not debug.getinfo(level,'f')then break end
      for index=1,40 do local name,value=debug.getlocal(level,index)
        if not name then break end
        if value==weak[1]then debug.setlocal(level,index,nil)end
      end
    end
  end
  r._LOADED=nil;setmetatable(r,{__index=function()
    assert(debug.getinfo(2,'f').func==math.sin);clear();collectgarbage();assert(weak[1]==nil)
    return loaded
  end})
  local ok,e=pcall(bad)
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and e:match("bad argument #1 to 'math.sin' %(number expected, got table%)$"),tostring(e))
end

-- Known_Name_Bypass: A known Lua call name never searches the registry.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r);local calls=0
  r._LOADED=nil;setmetatable(r,{__index=function()calls=calls+1;return loaded end})
  local ok,e=pcall(function()math.sin({})end)
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and calls==0 and e:match(": bad argument #1 to 'sin' %(number expected, got table%)$"),tostring(e))
end

-- Non_Table_Modules: A non-table callback result still produces the unknown name.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r);local calls=0
  r._LOADED=nil;setmetatable(r,{__index=function()calls=calls+1;return 37 end})
  local ok,e=pcall(math.sin,{})
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and calls==1 and e=="bad argument #1 to '?' (number expected, got table)",tostring(e))
end

-- Returned_Modules: Name search uses the callback result even if it rewrites the registry.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r)
  r._LOADED=nil;setmetatable(r,{__index=function()r._LOADED=loaded;return {alias=math.sin}end})
  local ok,e=pcall(math.sin,{})
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and e=="bad argument #1 to 'alias' (number expected, got table)",tostring(e))
end

-- Third_Argument: A deferred type error preserves its original third argument index.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r)
  r._LOADED=nil;setmetatable(r,{__index=function()return loaded end})
  local ok,e=pcall(debug.setuservalue,nil,{},false)
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and e=="bad argument #3 to 'debug.setuservalue' (number expected, got boolean)",tostring(e))
end

-- Representation_Temporaries: Direct argerror retains no invented type-error detail slot.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r)
  r._LOADED=nil;setmetatable(r,{__index=function()
    assert(debug.getinfo(2,'f').func==debug.setuservalue)
    local _,f=debug.getlocal(2,4);local _,key=debug.getlocal(2,5)
    assert(f==debug.setuservalue and key=='_LOADED' and debug.getlocal(2,6)==nil)
    return loaded
  end})
  local ok,e=pcall(debug.setuservalue,nil,{},1.5)
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and e=="bad argument #3 to 'debug.setuservalue' (number has no integer representation)",tostring(e))
end

print('argument registry phases OK')
