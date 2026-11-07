-- Named auxiliary argument diagnostics compared with pinned C Lua.
-- Math_File: A full userdata numeric argument reports its actual FILE* name.
do
  local f=assert(load([=[math.sin(io.stdin)]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'sin' (number expected, got FILE*)]=],tostring(e))
end

-- Math_Abs_File: The core numeric path uses the same userdata diagnostic policy.
do
  local f=assert(load([=[math.abs(io.stdin)]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'abs' (number expected, got FILE*)]=],tostring(e))
end

-- Math_Named_Table: Auxiliary numeric checks honor a raw table type name.
do
  local f=assert(load([=[math.sin(setmetatable({},{__name='Box'}))]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'sin' (number expected, got Box)]=],tostring(e))
end

-- Math_Primitive_Name: Auxiliary checks honor primitive metatable names unlike VM faults.
do
  local f=assert(load([=[local old=debug.getmetatable(false);debug.setmetatable(false,{__name='Flag'});local ok,e=pcall(function()math.sin(false)end);debug.setmetatable(false,old);error(e,0)]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'sin' (number expected, got Flag)]=],tostring(e))
end

-- Math_Nul_Name: An auxiliary type name ends at its first embedded NUL.
do
  local f=assert(load([=[math.sin(setmetatable({},{__name='A\0B'}))]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'sin' (number expected, got A)]=],tostring(e))
end

-- Math_Nonstring_Name: A nonstring type-name field leaves the primitive table category.
do
  local f=assert(load([=[math.sin(setmetatable({},{__name=23}))]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'sin' (number expected, got table)]=],tostring(e))
end

-- Math_Raw_Name: Type-name lookup never invokes an index handler on the metatable.
do
  local f=assert(load([=[local mt=setmetatable({},{__index={__name='Fake'}});math.sin(setmetatable({},mt))]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'sin' (number expected, got table)]=],tostring(e))
end

-- Math_Missing: An absent numeric argument remains distinct from explicit nil.
do
  local f=assert(load([=[math.sin()]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'sin' (number expected, got no value)]=],tostring(e))
end

-- Math_Explicit_Nil: An explicit nil numeric argument retains its nil category.
do
  local f=assert(load([=[math.sin(nil)]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'sin' (number expected, got nil)]=],tostring(e))
end

-- Math_Second: A later numeric argument preserves its actual position.
do
  local f=assert(load([=[math.atan(1,{})]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #2 to 'atan' (number expected, got table)]=],tostring(e))
end

-- Math_Integer: Integer conversion retains its argument index and actual call name.
do
  local f=assert(load([=[math.random(1.1)]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'random' (number has no integer representation)]=],tostring(e))
end

-- Debug_Light_Userdata: Setting a light userdata reports its auxiliary special type name.
do
  local f=assert(load([=[local x=debug.upvalueid(function()return debug end,1);debug.setuservalue(x,{})]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'setuservalue' (userdata expected, got light userdata)]=],tostring(e))
end

-- Debug_Explicit_Nil: Setting explicit nil reports userdata expected and nil received.
do
  local f=assert(load([=[debug.setuservalue(nil,{})]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'setuservalue' (userdata expected, got nil)]=],tostring(e))
end

-- Debug_Missing: A missing userdata argument reports no value.
do
  local f=assert(load([=[debug.setuservalue()]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'setuservalue' (userdata expected, got no value)]=],tostring(e))
end

-- Debug_Missing_Value: A valid full userdata requires its second value before slot lookup.
do
  local f=assert(load([=[debug.setuservalue(io.stdin)]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #2 to 'setuservalue' (value expected)]=],tostring(e))
end

-- IO_Named_Table: IO handle checks preserve raw names of rejected table arguments.
do
  local f=assert(load([=[io.input(setmetatable({},{__name='Box'}))]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'input' (FILE* expected, got Box)]=],tostring(e))
end

-- IO_Primitive_Name: IO auxiliary type checks honor primitive metatable names.
do
  local f=assert(load([=[local old=debug.getmetatable(false);debug.setmetatable(false,{__name='Flag'});local ok,e=pcall(function()io.input(false)end);debug.setmetatable(false,old);error(e,0)]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'input' (FILE* expected, got Flag)]=],tostring(e))
end

-- IO_Explicit_Nil: Explicit nil is rejected by io.close rather than selecting its default.
do
  local f=assert(load([=[io.close(nil)]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'close' (FILE* expected, got nil)]=],tostring(e))
end

-- IO_Missing_File: A missing file-method argument retains its real call identity.
do
  local f=assert(load([=[getmetatable(io.stdin).__gc()]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to '__gc' (FILE* expected, got no value)]=],tostring(e))
end

-- Method_Self: A bad colon-call self has its distinct diagnostic spelling.
do
  local f=assert(load([=[local t={bad=math.sin};t:bad()]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: calling 'bad' on bad self (number expected, got table)]=],tostring(e))
end

-- Method_Regular_Index: A regular colon-call argument is counted after self.
do
  local f=assert(load([=[local old=debug.getmetatable(0);debug.setmetatable(0,{__index={go=math.atan}});local ok,e=pcall(function()local n=1;n:go({})end);debug.setmetatable(0,old);error(e,0)]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'go' (number expected, got table)]=],tostring(e))
end

-- Callable_Extra: A prepended callable-object value has an extra-argument index.
do
  local f=assert(load([=[local m=setmetatable({},{__call=math.sin});m()]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad extra argument #1 to 'm' (number expected, got table)]=],tostring(e))
end

-- Callable_Method_Extra: Extra callable values precede method self in diagnostic numbering.
do
  local f=assert(load([=[local m=setmetatable({},{__call=math.sin});local t={f=setmetatable({},{__call=m})};t:f()]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad extra argument #1 to 'f' (number expected, got table)]=],tostring(e))
end

-- Global_Fallback: A C caller obtains the actual function name from loaded modules.
do
  local f=assert(load([=[local ok,e=pcall(math.sin,{});error(e,0)]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[bad argument #1 to 'math.sin' (number expected, got table)]=],tostring(e))
end

-- Nul_Call_Name: A field call name has the same rendered C prefix as debug metadata.
do
  local f=assert(load([=[local t={['a\0b']=math.sin};t['a\0b']({})]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #1 to 'a' (number expected, got table)]=],tostring(e))
end

-- Loaded_Modules_Name: Fallback name lookup observes the actual registry table and its C name.
do
  local f=assert(load([=[local registry=debug.getregistry();local old=registry._LOADED;registry._LOADED={['a\0b']={f=math.sin}};local ok,e=pcall(math.sin,{});registry._LOADED=old;error(e,0)]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[bad argument #1 to 'a' (number expected, got table)]=],tostring(e))
end

-- Stripped_Source: Auxiliary errors omit stripped source while retaining the callable field.
do
  local f=assert(load([=[local f=function()math.sin({})end;f=assert(load(string.dump(f,true)));f()]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[bad argument #1 to 'sin' (number expected, got table)]=],tostring(e))
end

-- Debug_Index_Type_Order: Optional uservalue index conversion occurs before target validation.
do
  local f=assert(load([=[debug.setuservalue(nil,{},false)]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #3 to 'setuservalue' (number expected, got boolean)]=],tostring(e))
end

-- Debug_Index_Representation_Order: A nonintegral optional slot reports its own representation failure.
do
  local f=assert(load([=[debug.setuservalue(nil,{},1.5)]=],'=argument'))
  local ok,e=pcall(f);assert(not ok and e==[=[argument:1: bad argument #3 to 'setuservalue' (number has no integer representation)]=],tostring(e))
end

-- Debug_String_Slot: Numeric string slot coercion keeps the real userdata operation.
do
  assert(debug.setuservalue(io.stdin,{},'1')==nil)
end

print('argument error phases OK')
