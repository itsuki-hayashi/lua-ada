-- Direct producer companion: actual setmetatable calls live in emitted code.

-- Missing_Receiver: The required receiver distinguishes no value from nil.
do
  local function f()
    setmetatable()
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'setmetatable' (table expected, got no value)]=]
  local ok,e=pcall(f)
  assert(not ok and e==expected,tostring(e))
end

-- Nil_Receiver: An explicit nil receiver keeps the first argument's actual type.
do
  local function f()
    setmetatable(nil)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'setmetatable' (table expected, got nil)]=]
  local ok,e=pcall(f)
  assert(not ok and e==expected,tostring(e))
end

-- Receiver_First: An invalid receiver is checked before an invalid metatable.
do
  local function f()
    setmetatable(7,false)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'setmetatable' (table expected, got number)]=]
  local ok,e=pcall(f)
  assert(not ok and e==expected,tostring(e))
end

-- Named_Receiver: The receiver check preserves its raw auxiliary type name.
do
  local previous=debug.getmetatable(false);debug.setmetatable(false,{__name='Sequence'})
  local function f()
    setmetatable(false,nil)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'setmetatable' (table expected, got Sequence)]=]
  local ok,e=pcall(f)
  debug.setmetatable(false,previous)
  assert(not ok and e==expected,tostring(e))
end

-- Missing_Metatable: An absent metatable is rejected rather than treated as explicit nil.
do
  local function f()
    setmetatable({})
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'setmetatable' (nil or table expected, got no value)]=]
  local ok,e=pcall(f)
  assert(not ok and e==expected,tostring(e))
end

-- Boolean_Metatable: The second argument retains its allowed categories and type.
do
  local function f()
    setmetatable({},false)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'setmetatable' (nil or table expected, got boolean)]=]
  local ok,e=pcall(f)
  assert(not ok and e==expected,tostring(e))
end

-- Number_Metatable: A numeric metatable is rejected without string coercion.
do
  local function f()
    setmetatable({},7)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'setmetatable' (nil or table expected, got number)]=]
  local ok,e=pcall(f)
  assert(not ok and e==expected,tostring(e))
end

-- Named_Metatable: The invalid metatable check shares the raw auxiliary type policy.
do
  local previous=debug.getmetatable(false);debug.setmetatable(false,{__name='Metadata'})
  local function f()
    setmetatable({},false)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'setmetatable' (nil or table expected, got Metadata)]=]
  local ok,e=pcall(f)
  debug.setmetatable(false,previous)
  assert(not ok and e==expected,tostring(e))
end

-- Argument_Before_Protection: Second-argument validation precedes the protected-metatable lookup.
do
  local function f()
    local t=setmetatable({},{__metatable='locked'});setmetatable(t,false)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'setmetatable' (nil or table expected, got boolean)]=]
  local ok,e=pcall(f)
  assert(not ok and e==expected,tostring(e))
end

-- Method_Self: A colon call diagnoses its actual invalid self.
do
  string.setmetatable=setmetatable
  local function f()
    ('abc'):setmetatable({})
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[calling 'setmetatable' on bad self (table expected, got string)]=]
  local ok,e=pcall(f)
  string.setmetatable=nil
  assert(not ok and e==expected,tostring(e))
end

-- Method_Argument: A valid table self shifts the metatable's regular argument index.
do
  local function f()
    local t={setmetatable=setmetatable};t:setmetatable(false)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'setmetatable' (nil or table expected, got boolean)]=]
  local ok,e=pcall(f)
  assert(not ok and e==expected,tostring(e))
end

-- Gsub_Callback: A real gsub C caller obtains the actual setmetatable registry name.
do
  local function f()
    string.gsub('s','s',setmetatable)
  end
  local info=debug.getinfo(f,'S')
  local expected=[=[bad argument #1 to 'setmetatable' (table expected, got string)]=]
  local ok,e=pcall(f)
  assert(not ok and e==expected,tostring(e))
end

-- Explicit_Nil: Explicit nil removes the actual metatable and returns the receiver.
do
  local t=setmetatable({},{__index={value=7}})
  assert(t.value==7 and setmetatable(t,nil)==t and getmetatable(t)==nil and t.value==nil)
end

-- Actual_Table: A valid table installs actual lookup behavior and preserves identity.
do
  local t,mt={},{__index={value=7}}
  assert(setmetatable(t,mt)==t and getmetatable(t)==mt and t.value==7)
end

-- Registry_Roots: Diagnostic lookup sees actual slot mutation and no stale operand edge.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r)
  local weak=setmetatable({},{__mode='v'});local calls=0
  local function make()local value=function()end;weak[1]=value;return value end
  r._LOADED=nil;setmetatable(r,{__index=function(_,k)
    assert(k=='_LOADED' and debug.getinfo(2,'f').func==setmetatable)
    assert(debug.setlocal(2,2,nil)=='(C temporary)')
    collectgarbage();assert(weak[1]==nil);calls=calls+1;return loaded
  end})
  local ok,e=pcall(setmetatable,{},make())
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and calls==1 and e=="bad argument #2 to 'setmetatable' (nil or table expected, got function)",tostring(e))
end

print('metatable argument phases OK')
