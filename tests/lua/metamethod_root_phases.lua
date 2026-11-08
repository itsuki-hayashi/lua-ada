-- Actual metamethod argument ownership compared with pinned C Lua.
-- Concat: Concatenation relinquishes helper copies after actual operands and parameters are dropped.
do
  local weak=setmetatable({},{__mode='v'})
  local function clear()
    for i=1,40 do local n,v=debug.getlocal(3,i);if not n then break end
      if v==weak[1] or v==weak[2] then debug.setlocal(3,i,nil)end
    end
  end
  local mt={__concat=function(x,y)clear();x,y=nil,nil;collectgarbage();assert(weak[1]==nil and weak[2]==nil);return "joined"end};local function f()local a=setmetatable({},mt);local b=setmetatable({},mt);weak[1]=a;weak[2]=b;return a..b end;assert(f()=="joined")
end

-- Add: Arithmetic relinquishes helper copies after actual operands and parameters are dropped.
do
  local weak=setmetatable({},{__mode='v'})
  local function clear()
    for i=1,40 do local n,v=debug.getlocal(3,i);if not n then break end
      if v==weak[1] or v==weak[2] then debug.setlocal(3,i,nil)end
    end
  end
  local mt={__add=function(x,y)clear();x,y=nil,nil;collectgarbage();assert(weak[1]==nil and weak[2]==nil);return 31 end};local function f()local a=setmetatable({},mt);local b=setmetatable({},mt);weak[1]=a;weak[2]=b;return a+b end;assert(f()==31)
end

-- Length: Unary length relinquishes its duplicated private arguments after the handler owns them.
do
  local weak=setmetatable({},{__mode='v'})
  local function clear()
    for i=1,40 do local n,v=debug.getlocal(3,i);if not n then break end
      if v==weak[1] or v==weak[2] then debug.setlocal(3,i,nil)end
    end
  end
  local mt={__len=function(x,y)clear();x,y=nil,nil;collectgarbage();assert(weak[1]==nil);return 31 end};local function f()local a=setmetatable({},mt);weak[1]=a;return #a end;assert(f()==31)
end

-- Index: An index helper relinquishes its receiver once the real handler owns the argument.
do
  local weak=setmetatable({},{__mode='v'})
  local function clear()
    for i=1,40 do local n,v=debug.getlocal(3,i);if not n then break end
      if v==weak[1] or v==weak[2] then debug.setlocal(3,i,nil)end
    end
  end
  local mt={__index=function(x,k)clear();x,k=nil,nil;collectgarbage();assert(weak[1]==nil);return 31 end};local function f()local a=setmetatable({},mt);weak[1]=a;return a.key end;assert(f()==31)
end

-- Newindex: A setter relinquishes receiver and value copies after the real handler owns them.
do
  local weak=setmetatable({},{__mode='v'})
  local function clear()
    for i=1,40 do local n,v=debug.getlocal(3,i);if not n then break end
      if v==weak[1] or v==weak[2] then debug.setlocal(3,i,nil)end
    end
  end
  local mt={__newindex=function(x,k,v)clear();x,k,v=nil,nil,nil;collectgarbage();assert(weak[1]==nil and weak[2]==nil)end};local function f()local a=setmetatable({},mt);local b={};weak[1]=a;weak[2]=b;a.key=b;return "joined"end;assert(f()=="joined")
end

-- Yield: A suspended metamethod retains only its actual surviving operand edges.
do
  local weak=setmetatable({},{__mode='v'})
  local function clear()
    for i=1,40 do local n,v=debug.getlocal(3,i);if not n then break end
      if v==weak[1] or v==weak[2] then debug.setlocal(3,i,nil)end
    end
  end
  local mt={__concat=function(x,y)clear();x,y=nil,nil;coroutine.yield();return "joined"end};local co=coroutine.create(function()local a=setmetatable({},mt);local b=setmetatable({},mt);weak[1]=a;weak[2]=b;return a..b end);assert(coroutine.resume(co));collectgarbage();assert(weak[1]==nil and weak[2]==nil);local ok,v=coroutine.resume(co);assert(ok and v=="joined")
end

-- Error: A message handler sees no stale request or operand roots after the body drops them.
do
  local weak=setmetatable({},{__mode='v'})
  local function clear()
    for i=1,40 do local n,v=debug.getlocal(3,i);if not n then break end
      if v==weak[1] or v==weak[2] then debug.setlocal(3,i,nil)end
    end
  end
  local mt={__concat=function(x,y)clear();x,y=nil,nil;error("marker",0)end};local function f()local a=setmetatable({},mt);local b=setmetatable({},mt);weak[1]=a;weak[2]=b;return a..b end;local ok,e=xpcall(f,function(e)collectgarbage();assert(weak[1]==nil and weak[2]==nil);return e end);assert(not ok and e=="marker")
end

print('metamethod root phases OK')
