-- Local_Nil: A direct nil local uses its real caller name and source.
do
  local f=assert(load("local x;x()",'=callcase'));local ok,e=pcall(f);assert(not ok and e=="callcase:1: attempt to call a nil value (local 'x')",tostring(e))
end

-- Global_Nil: A missing global resolves from the actual calling register.
do
  local f=assert(load("missing_call()",'=callcase'));local ok,e=pcall(f);assert(not ok and e=="callcase:1: attempt to call a nil value (global 'missing_call')",tostring(e))
end

-- Field_Nil: A noncallable field retains its field provenance.
do
  local f=assert(load("local t={};t.missing()",'=callcase'));local ok,e=pcall(f);assert(not ok and e=="callcase:1: attempt to call a nil value (field 'missing')",tostring(e))
end

-- Method_Nil: A method call retains its actual method name.
do
  local f=assert(load("local t={};t:missing()",'=callcase'));local ok,e=pcall(f);assert(not ok and e=="callcase:1: attempt to call a nil value (method 'missing')",tostring(e))
end

-- Upvalue_Nil: An invalid captured callee reports its upvalue identity.
do
  local f=assert(load("local x;local function f()x()end;f()",'=callcase'));local ok,e=pcall(f);assert(not ok and e=="callcase:1: attempt to call a nil value (upvalue 'x')",tostring(e))
end

-- Custom_Type: Call diagnostics honor a raw string type name.
do
  local f=assert(load("local x=setmetatable({},{__name='example'});x()",'=callcase'));local ok,e=pcall(f);assert(not ok and e=="callcase:1: attempt to call a example value (local 'x')",tostring(e))
end

-- Removed_Close: A removed handler is called as nil at the real close opcode.
do
  local f=assert(load("local x <close> =setmetatable({},{__close=function()end});getmetatable(x).__close=nil",'=callcase'));local ok,e=pcall(f);assert(not ok and e=="callcase:1: attempt to call a nil value (metamethod 'close')",tostring(e))
end

-- Numeric_Close: A numeric replacement retains normal close provenance.
do
  local f=assert(load("local x <close> =setmetatable({},{__close=function()end});getmetatable(x).__close=4",'=callcase'));local ok,e=pcall(f);assert(not ok and e=="callcase:1: attempt to call a number value (metamethod 'close')",tostring(e))
end

-- Boolean_Close: A false replacement remains a noncallable handler value.
do
  local f=assert(load("local x <close> =setmetatable({},{__close=function()end});getmetatable(x).__close=false",'=callcase'));local ok,e=pcall(f);assert(not ok and e=="callcase:1: attempt to call a boolean value (metamethod 'close')",tostring(e))
end

-- Error_Removed_Close: An error close has unwound to C protection before its call.
do
  local f=assert(load("local x <close> =setmetatable({},{__close=function()end});getmetatable(x).__close=nil;error('original')",'=callcase'));local ok,e=pcall(f);assert(not ok and e=="attempt to call a nil value",tostring(e))
end

-- Error_Numeric_Close: A replacement error close cannot borrow its retired Lua site.
do
  local f=assert(load("local x <close> =setmetatable({},{__close=function()end});getmetatable(x).__close=4;error('original')",'=callcase'));local ok,e=pcall(f);assert(not ok and e=="attempt to call a number value",tostring(e))
end

-- Coroutine_Removed_Close: Coroutine closing uses its surviving native call boundary.
do
  local co=coroutine.create(function()local x <close> =setmetatable({},{__close=function()end});getmetatable(x).__close=nil;coroutine.yield()end);assert(coroutine.resume(co));local ok,e=coroutine.close(co);assert(not ok and e=='attempt to call a nil value',tostring(e))
end

-- Protected_Nil: A direct protected nil call adds no invented Lua caller.
do
  local ok,e=pcall(nil);assert(not ok and e=='attempt to call a nil value',tostring(e))
end

-- Invalid_Call_Handler: A noncallable call handler preserves its original calling site.
do
  local f=assert(load("local x=setmetatable({},{__call=4});x()",'=callcase'));local ok,e=pcall(f);assert(not ok and e=="callcase:1: attempt to call a number value (local 'x')",tostring(e))
end

-- Stripped_Call: A stripped caller retains unknown source and line markers.
do
  local f=assert(load(string.dump(function()local x;x()end,true)));local ok,e=pcall(f);assert(not ok and e=='?:?: attempt to call a nil value',tostring(e))
end

-- Close_Error_Replacement: An outer closer receives the actual replacement call error.
do
  local got;local f=assert(load("local outer <close> =setmetatable({},{__close=function(_,e)captured_error=e end});local inner <close> =setmetatable({},{__close=function()end});getmetatable(inner).__close=nil",'=callcase'));local ok,e=pcall(f);assert(not ok and e=="callcase:1: attempt to call a nil value (metamethod 'close')" and captured_error==e,tostring(e))
end

print('call error phases OK')
