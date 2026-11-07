-- Temporary_Right: A convertible left operand reports the actual invalid right type.
do
  local function f()
    return 1 .. {}
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to concatenate a table value]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Nil_Local: A nil local retains its real operand binding and source.
do
  local function f()
    local x;return x .. 'a'
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to concatenate a nil value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Stripped_Operand: Missing debug data keeps unknown source and no invented local name.
do
  local function f()
    local x;return x .. 'a'
  end
  f=assert(load(string.dump(f,true)))
  local ok,e=pcall(f);assert(not ok and e==[=[?:?: attempt to concatenate a nil value]=],tostring(e))
end

-- Boolean_Global: A failed global load keeps its current global name.
do
  local function f()
    bad_concat=false;return 'a' .. bad_concat
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to concatenate a boolean value (global 'bad_concat')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- First_Invalid_Left: Two invalid operands report the first rather than the second.
do
  local function f()
    local x={};return x .. true
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to concatenate a table value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Captured_Right: A captured concatenation operand reports its real upvalue.
do
  local function f()
    local x={};return (function()return 'a'..x end)()
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to concatenate a table value (upvalue 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Field_Right: A loaded table field retains its field provenance.
do
  local function f()
    local t={x={}};return 'a'..t.x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to concatenate a table value (field 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Integer_Field: Integer table lookup uses the actual integer-index description.
do
  local function f()
    local t={{}};return 'a'..t[1]
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to concatenate a table value (field 'integer index')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Right_Fold: A grouped CONCAT reports the actual failing rightmost pair.
do
  local function f()
    local a={};local b={};return a..'x'..b
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to concatenate a table value (local 'b')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Intermediate_Result: A later fold resolves the real overwritten register after a handler.
do
  local function f()
    local b=setmetatable({},{__concat=function()return {}end});return 'x'..b..'y'
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to concatenate a table value (local 'b')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Named_Type: Raw string __name controls the diagnostic type description.
do
  local function f()
    local x=setmetatable({},{__name='Box'});return 1 .. x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to concatenate a Box value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Nul_Type: Diagnostic use of a counted __name stops at its C-string NUL boundary.
do
  local function f()
    local x=setmetatable({},{__name='A\0B'});return 1 .. x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to concatenate a A value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Nonstring_Type: A nonstring __name preserves the primitive table category.
do
  local function f()
    local x=setmetatable({},{__name=false});return 1 .. x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to concatenate a table value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Call_Nul_Type: The shared type diagnostic obeys the same NUL boundary for call errors.
do
  local function f()
    local x=setmetatable({},{__name='A\0B'});x()
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to call a A value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Multiline_Operand: The failure source is the current CONCAT line.
do
  local function f()
    local x={}
    local y='a'
    return y..x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+3)..': '..[=[attempt to concatenate a table value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Grouped_Source_Line: A merged right-associated run retains its inner CONCAT source line.
do
  local function f()
    local a={};local b={};local c={}
    return a ..
    b ..
    c
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+3)..': '..[=[attempt to concatenate a table value (local 'b')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Capture_Before_RHS: The left value is captured before a later callback mutates its binding.
do
  local x='old';local function rhs()x='new';return 'right'end
  local result=x..rhs();assert(result=='oldright' and x=='new')
end

-- Active_Destination: Concatenation cannot overwrite its destination binding before RHS evaluation.
do
  local x='old';local y='right'
  x='left'..(function()assert(x=='old' and y=='right');return y end)()
  assert(x=='leftright' and y=='right')
end

-- Right_Run_Order: All right-associated operand expressions precede the first handler.
do
  local events={};local mt
  mt={__concat=function(x,y)events[#events+1]=x.id..y.id;return setmetatable({id='r'},mt)end}
  local a=setmetatable({id='a'},mt);local b=setmetatable({id='b'},mt)
  local function rhs()events[#events+1]='c';return setmetatable({id='c'},mt)end
  local result=a..b..rhs();assert(result.id=='r' and table.concat(events,',')=='c,bc,ar')
end

-- Parenthesized_Left_Order: A parenthesized left concatenation finishes before the outer RHS.
do
  local events={};local mt
  mt={__concat=function(x,y)events[#events+1]=x.id..y.id;return setmetatable({id='r'},mt)end}
  local a=setmetatable({id='a'},mt);local b=setmetatable({id='b'},mt)
  local function rhs()events[#events+1]='c';return setmetatable({id='c'},mt)end
  local result=(a..b)..rhs();assert(result.id=='r' and table.concat(events,',')=='ab,c,rc')
end

print('operation error compiler phases OK')
