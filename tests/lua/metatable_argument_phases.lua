-- Native-paired base setmetatable argument origins and validation order.

-- Missing_Receiver: The required receiver distinguishes no value from nil.
do
  local f=assert(load([=[setmetatable()]=],'=metatable-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[metatable-argument:1: bad argument #1 to 'setmetatable' (table expected, got no value)]=],tostring(e))
end

-- Nil_Receiver: An explicit nil receiver keeps the first argument's actual type.
do
  local f=assert(load([=[setmetatable(nil)]=],'=metatable-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[metatable-argument:1: bad argument #1 to 'setmetatable' (table expected, got nil)]=],tostring(e))
end

-- Receiver_First: An invalid receiver is checked before an invalid metatable.
do
  local f=assert(load([=[setmetatable(7,false)]=],'=metatable-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[metatable-argument:1: bad argument #1 to 'setmetatable' (table expected, got number)]=],tostring(e))
end

-- Named_Receiver: The receiver check preserves its raw auxiliary type name.
do
  local previous=debug.getmetatable(false);debug.setmetatable(false,{__name='Sequence'})
  local f=assert(load([=[setmetatable(false,nil)]=],'=metatable-argument'))
  local ok,e=pcall(f)
  debug.setmetatable(false,previous)
  assert(not ok and e==[=[metatable-argument:1: bad argument #1 to 'setmetatable' (table expected, got Sequence)]=],tostring(e))
end

-- Missing_Metatable: An absent metatable is rejected rather than treated as explicit nil.
do
  local f=assert(load([=[setmetatable({})]=],'=metatable-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[metatable-argument:1: bad argument #2 to 'setmetatable' (nil or table expected, got no value)]=],tostring(e))
end

-- Boolean_Metatable: The second argument retains its allowed categories and type.
do
  local f=assert(load([=[setmetatable({},false)]=],'=metatable-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[metatable-argument:1: bad argument #2 to 'setmetatable' (nil or table expected, got boolean)]=],tostring(e))
end

-- Number_Metatable: A numeric metatable is rejected without string coercion.
do
  local f=assert(load([=[setmetatable({},7)]=],'=metatable-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[metatable-argument:1: bad argument #2 to 'setmetatable' (nil or table expected, got number)]=],tostring(e))
end

-- Named_Metatable: The invalid metatable check shares the raw auxiliary type policy.
do
  local previous=debug.getmetatable(false);debug.setmetatable(false,{__name='Metadata'})
  local f=assert(load([=[setmetatable({},false)]=],'=metatable-argument'))
  local ok,e=pcall(f)
  debug.setmetatable(false,previous)
  assert(not ok and e==[=[metatable-argument:1: bad argument #2 to 'setmetatable' (nil or table expected, got Metadata)]=],tostring(e))
end

-- Argument_Before_Protection: Second-argument validation precedes the protected-metatable lookup.
do
  local f=assert(load([=[local t=setmetatable({},{__metatable='locked'});setmetatable(t,false)]=],'=metatable-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[metatable-argument:1: bad argument #2 to 'setmetatable' (nil or table expected, got boolean)]=],tostring(e))
end

-- Method_Self: A colon call diagnoses its actual invalid self.
do
  string.setmetatable=setmetatable
  local f=assert(load([=[('abc'):setmetatable({})]=],'=metatable-argument'))
  local ok,e=pcall(f)
  string.setmetatable=nil
  assert(not ok and e==[=[metatable-argument:1: calling 'setmetatable' on bad self (table expected, got string)]=],tostring(e))
end

-- Method_Argument: A valid table self shifts the metatable's regular argument index.
do
  local f=assert(load([=[local t={setmetatable=setmetatable};t:setmetatable(false)]=],'=metatable-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[metatable-argument:1: bad argument #1 to 'setmetatable' (nil or table expected, got boolean)]=],tostring(e))
end

-- Gsub_Callback: A real gsub C caller obtains the actual setmetatable registry name.
do
  local f=assert(load([=[string.gsub('s','s',setmetatable)]=],'=metatable-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[bad argument #1 to 'setmetatable' (table expected, got string)]=],tostring(e))
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
