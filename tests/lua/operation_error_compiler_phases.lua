-- Direct-code companion for producer/runtime differential checks.
-- The producer compiles each operation instead of deferring it to load.

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

-- Arithmetic_Field: A missing named-vararg field reports the field and its actual arithmetic source.
do
  local function f()
    local function foo (...t) return t.xx+1 end;foo()
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to perform arithmetic on a nil value (field 'xx')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Arithmetic_Global: A numeric left operand selects the wrong right global binding.
do
  local function f()
    bad_arith={};return 3.3/bad_arith
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to perform arithmetic on a table value (global 'bad_arith')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Arithmetic_Local: A table local is the first invalid arithmetic operand.
do
  local function f()
    local x={};return x+1
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to perform arithmetic on a table value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Arithmetic_Upvalue: A captured nil remains an upvalue in the nested arithmetic frame.
do
  local function f()
    local x;return(function()return x+1 end)()
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to perform arithmetic on a nil value (upvalue 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Arithmetic_Right: A numeric left operand leaves the failing local on the right.
do
  local function f()
    local x={};return 1+x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to perform arithmetic on a table value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Arithmetic_Both: Two invalid operands explain the left binding before the right.
do
  local function f()
    local x={};local y=false;return x+y
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to perform arithmetic on a table value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Arithmetic_Named: Raw string __name changes the diagnostic type without losing its binding.
do
  local function f()
    local x=setmetatable({},{__name='Box'});return x+1
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to perform arithmetic on a Box value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Bitwise_Local: A bitwise handler miss explains the actual right table local.
do
  local function f()
    local x={};return 3|x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to perform bitwise operation on a table value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Bitwise_Left: Two wrong bitwise operands explain the left local first.
do
  local function f()
    local x={};return x|true
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to perform bitwise operation on a table value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Bitwise_String: A numeric string stays invalid for primitive bitwise operators.
do
  local function f()
    local x='3';return x|1
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to perform bitwise operation on a string value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Integer_Left: An invalid left conversion inserts the binding before its explanation.
do
  local function f()
    local x=1.1;return x<<2
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[number (local 'x') has no integer representation]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Integer_Right: An invalid right conversion retains its own binding and source.
do
  local function f()
    local x=1.1;return 2<<x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[number (local 'x') has no integer representation]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Integer_Both: Two nonintegral values attribute failed conversion to the first operand.
do
  local function f()
    local x=1.1;local y=2.2;return x|y
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[number (local 'x') has no integer representation]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Unary_Arithmetic: Unary minus explains its real source local after a handler miss.
do
  local function f()
    local x={};return -x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to perform arithmetic on a table value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Unary_Bitwise: Unary bitwise rejects numeric strings using its actual source binding.
do
  local function f()
    local x='3';return ~x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to perform bitwise operation on a string value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Unary_Integer: Unary integer conversion explains the original nonintegral local.
do
  local function f()
    local x=1.1;return ~x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[number (local 'x') has no integer representation]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Unary_Length: Length reports its primitive boolean type and original local.
do
  local function f()
    local x=false;return #x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to get length of a boolean value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Compare_Local: Ordering failure attributes only source and the two compared types.
do
  local function f()
    local x={};return x<1
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to compare table with number]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Zero_Division: Integer division by zero retains its actual Lua operation source.
do
  local function f()
    local x=0;return 1//x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to divide by zero]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Boolean_Name_Ignored: A primitive metatable name cannot replace its boolean diagnostic type.
do
  local function f()
    debug.setmetatable(false,{__name='Flag'});local ok,e=pcall(function()local x=false;return #x end);debug.setmetatable(false,nil);error(e,0)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to get length of a boolean value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Number_Name_Ignored: Ordering retains the primitive number type despite its shared metatable name.
do
  local function f()
    debug.setmetatable(0,{__name='Num'});local ok,e=pcall(function()return 1<{} end);debug.setmetatable(0,nil);error(e,0)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to compare number with table]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Global: A missing global used as receiver keeps the global binding.
do
  local function f()
    bad_index=nil;return bad_index.x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a nil value (global 'bad_index')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Upvalue: A captured nil receiver retains the nested upvalue name.
do
  local function f()
    local x;return(function()return x[1]end)()
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a nil value (upvalue 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Field: A missing field used as receiver keeps its field provenance.
do
  local function f()
    local t={};return t.x.y
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a nil value (field 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Set: A false assignment receiver names the actual local.
do
  local function f()
    local x=false;x.y=1
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a boolean value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Environment: A local nil environment is the failing table operand.
do
  local function f()
    local _ENV=nil;return x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a nil value (local '_ENV')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Get_Chain: A redirected __index object cannot borrow the original local name.
do
  local function f()
    local x=setmetatable({},{__index=false});return x.a
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a boolean value]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Set_Chain: A redirected __newindex object cannot borrow the original local name.
do
  local function f()
    local x=setmetatable({},{__newindex=false});x.a=1
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a boolean value]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Nested_Chain: Nested table delegation still attributes only the final primitive type.
do
  local function f()
    local x=setmetatable({},{__index=setmetatable({},{__index=false})});return x.a
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a boolean value]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Primitive_Name: A primitive metatable name does not rename the failing boolean receiver.
do
  local function f()
    debug.setmetatable(false,{__name='Flag'});local ok,e=pcall(function()local x=false;return x.a end);debug.setmetatable(false,nil);error(e,0)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a boolean value (local 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Environment_Capture: Direct environment indexing identifies the actual captured upvalue cell.
do
  local function f()
    local _ENV=nil;return(function()return x end)()
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a nil value (upvalue '_ENV')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Method: A missing method receiver names its preceding field access.
do
  local function f()
    local t={};return t.x:y()
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a nil value (field 'x')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Set_Global: Deferred assignment still identifies its original global receiver.
do
  local function f()
    bad_index=nil;bad_index.x=1
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a nil value (global 'bad_index')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Set_Environment: A nil local environment remains the actual deferred store target.
do
  local function f()
    local _ENV=nil;x=1
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a nil value (local '_ENV')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Arithmetic_Nul_Field: Operand varinfo uses a C name view without changing its counted table key.
do
  local function f()
    local t={['a\0b']={}};return t['a\0b']+1
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to perform arithmetic on a table value (field 'a')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Index_Nul_Field: Indexing a field result reports the prefix before its embedded NUL.
do
  local function f()
    local t={['a\0b']=false};return t['a\0b'].x
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to index a boolean value (field 'a')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Concat_Nul_Field: A failed concatenation has the same C view of a field name.
do
  local function f()
    local t={['a\0b']={}};return 'x'..t['a\0b']
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to concatenate a table value (field 'a')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Call_Nul_Field: Invalid-call diagnostics share the counted owner's C name view.
do
  local function f()
    local t={['a\0b']=false};t['a\0b']()
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[attempt to call a boolean value (field 'a')]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Info_Nul_Field: Lua getinfo and C metadata share the same borrowed field-name prefix.
do
  local t={};t['a\0b']=function()local i=debug.getinfo(1,'n');assert(i.namewhat=='field' and i.name=='a')end
  t['a\0b']();assert(t.a==nil and type(t['a\0b'])=='function')
end

-- Loader_Nul_Field: Loader argument diagnostics render the same NUL-terminated borrowed call name.
do
  local t={['a\0b']=loadfile};local ok,e=pcall(function()t['a\0b']({})end)
  assert(not ok and e:find("bad argument #1 to 'a' (string expected, got table)",1,true) and not e:find('\0',1,true),tostring(e))
end

-- Filename_Before_Mode: Loadfile validates a wrong filename before inspecting a wrong mode.
do
  local ok,e=pcall(function()loadfile({},{})end)
  assert(not ok and e:find("bad argument #1 to 'loadfile' (string expected, got table)",1,true),tostring(e))
end

-- Mode_Before_Open: A wrong optional mode is rejected before opening a missing filename.
do
  local ok,e=pcall(function()loadfile('__missing_loader_file__',{})end)
  assert(not ok and e:find("bad argument #2 to 'loadfile' (string expected, got table)",1,true),tostring(e))
end

-- Dofile_Nul_Field: Dofile validates its optional filename with the same borrowed C call name.
do
  local t={['a\0b']=dofile};local ok,e=pcall(function()t['a\0b']({},{})end)
  assert(not ok and e:find("bad argument #1 to 'a' (string expected, got table)",1,true) and not e:find('\0',1,true),tostring(e))
end

-- For_Initial_Table: An invalid initial control reports its actual table type and Lua source.
do
  local function f()
    for i={},10 do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad 'for' initial value (number expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_Limit_String: A nonnumeric limit string reports the limit role.
do
  local function f()
    for i=1,'x',10 do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad 'for' limit (number expected, got string)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_Limit_Table: An integer loop reports a failed limit conversion with its table type.
do
  local function f()
    for i=1,{} do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad 'for' limit (number expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_Step_Function: A failed step conversion reports the function type.
do
  local function f()
    for i=1,10,print do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad 'for' step (number expected, got function)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_Named_Type: Numeric-for diagnostics honor raw table __name.
do
  local function f()
    local x=setmetatable({},{__name='Box'});for i=x,10 do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad 'for' initial value (number expected, got Box)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_File_Type: An actual full userdata control reports its FILE* metatable name.
do
  local function f()
    for i=io.stdin,10 do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad 'for' initial value (number expected, got FILE*)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_Limit_First: The float path validates limit before step and initial values.
do
  local function f()
    for i={},false,{} do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad 'for' limit (number expected, got boolean)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_Step_Before_Initial: A valid float limit leaves step validation before the initial value.
do
  local function f()
    for i={},10,false do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad 'for' step (number expected, got boolean)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_Zero_Integer: An integer zero step is rejected before converting a bad limit.
do
  local function f()
    for i=1,{},0 do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=['for' step is zero]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_Zero_Float: The float path converts a bad limit before testing its zero step.
do
  local function f()
    for i=1.0,{},0 do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad 'for' limit (number expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_Initial_Before_Float_Zero: A float-path initial conversion fails before testing a zero step.
do
  local function f()
    for i={},10,0 do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad 'for' initial value (number expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_Zero_Actual_Float: A real zero step retains its actual numeric-for source.
do
  local function f()
    for i=1,10,0.0 do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=['for' step is zero]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_Nul_Type: The raw diagnostic __name ends at its embedded NUL.
do
  local function f()
    local x=setmetatable({},{__name='A\0B'});for i=1,x do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad 'for' limit (number expected, got A)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_Multiline: A multiline loop failure uses the real FORPREP header source event.
do
  local function f()
    for i={},
    10 do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+2)..': '..[=[bad 'for' initial value (number expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_Zero_String: A coerced string zero step preserves zero-step diagnostics.
do
  local function f()
    for i=1,10,'0' do end
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=['for' step is zero]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- For_String_Coercion: String controls still select the float loop and retain their values.
do
  local sum=0;for i='1','3','1' do assert(math.type(i)=='float');sum=sum+i end
  assert(sum==6)
end

-- For_Integer_Limit_Coercion: Coercing only the limit preserves the integer loop representation.
do
  local sum=0;for i=1,'3',1 do assert(math.type(i)=='integer');sum=sum+i end
  assert(sum==6)
end

print('operation error compiler phases OK')
