-- Direct-code companion: each producer compiles the actual library operation.

-- Method_Self: A table's colon string method diagnoses the actual bad self.
do
  aaa={};setmetatable(aaa,{__index=string})
  local function f()
    aaa:sub()
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[calling 'sub' on bad self (string expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
  aaa=nil
end

-- Function_Second: The function form retains the second integer argument index.
do
  local function f()
    string.sub('a',{})
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'sub' (number expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Method_Second: A colon call removes self from the reported regular argument index.
do
  local function f()
    ('a'):sub{}
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'sub' (number expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Sub_Missing_Start: Sub requires its start instead of using byte's optional default.
do
  local function f()
    string.sub('abc')
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'sub' (number expected, got no value)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Sub_Nil_Start: An explicitly nil required start differs from an absent argument.
do
  local function f()
    string.sub('abc',nil)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'sub' (number expected, got nil)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Sub_First_Missing: An absent subject is not mislabeled as a nil value.
do
  local function f()
    string.sub()
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'sub' (string expected, got no value)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Sub_Third_Type: The optional end keeps its real third argument index.
do
  local function f()
    string.sub('abc',1,false)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #3 to 'sub' (number expected, got boolean)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Sub_Named_Subject: String checks use the supplied raw auxiliary type name.
do
  local function f()
    string.sub(setmetatable({},{__name='Text'}),1)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'sub' (string expected, got Text)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Sub_Named_Index: Integer checks preserve a named wrong argument type.
do
  local function f()
    string.sub('abc',setmetatable({},{__name='Position'}))
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'sub' (number expected, got Position)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Len_Missing: Length validates its required subject through the real call origin.
do
  local function f()
    string.len()
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'len' (string expected, got no value)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Len_Named: Length shares the auxiliary raw type name policy.
do
  local function f()
    string.len(setmetatable({},{__name='Text'}))
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'len' (string expected, got Text)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Rep_Count_Type: Repeat reports its actual count argument rather than representation failure.
do
  local function f()
    string.rep('a',{})
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'rep' (number expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Rep_Separator_Type: Repeat still validates its separator when only one repetition is needed.
do
  local function f()
    string.rep('a',1,{})
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #3 to 'rep' (string expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Find_Subject: Find checks its subject before its pattern and start.
do
  local function f()
    string.find({},'x')
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'find' (string expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Find_Pattern: Find reports the pattern's own string argument index.
do
  local function f()
    string.find('abc',{})
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'find' (string expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Find_Start: Find validates its start even for a pattern with no match.
do
  local function f()
    string.find('abc','x',{})
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #3 to 'find' (number expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Gmatch_Subject: Gmatch validates the subject before constructing an iterator.
do
  local function f()
    string.gmatch({},'x')
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'gmatch' (string expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Gmatch_Pattern: Gmatch reports its second string argument.
do
  local function f()
    string.gmatch('abc',{})
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'gmatch' (string expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Gmatch_Start: Gmatch reports its optional initial position as an integer argument.
do
  local function f()
    string.gmatch('abc','x',{})
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #3 to 'gmatch' (number expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Gmatch_Order: Gmatch checks the pattern before the optional initial position.
do
  local function f()
    string.gmatch('abc',{},false)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'gmatch' (string expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Gsub_Replacement: Gsub retains the replacement argument's allowed categories.
do
  local function f()
    string.gsub('abc','x',false)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #3 to 'gsub' (string/function/table expected, got boolean)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Gsub_Limit: Gsub reports the optional maximum as the fourth argument.
do
  local function f()
    string.gsub('abc','x','y',{})
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #4 to 'gsub' (number expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Gsub_Validation_Order: Gsub validates its limit before the replacement's category.
do
  local function f()
    string.gsub('abc','x',false,{})
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #4 to 'gsub' (number expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Char_Representation: Char distinguishes a numeric representation failure from a wrong type.
do
  local function f()
    string.char(1.5)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'char' (number has no integer representation)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Char_Type: Char retains the auxiliary number type error.
do
  local function f()
    string.char(false)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'char' (number expected, got boolean)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Char_Second: Char checks copied values without retaining an indexing borrow.
do
  local function f()
    string.char(65,{})
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #2 to 'char' (number expected, got table)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Char_Range: Char reports its actual out-of-range argument after integer conversion.
do
  local function f()
    string.char(256)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'char' (value out of range)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Dump_Type: Dump requires a Lua function using its pinned special argument text.
do
  local function f()
    string.dump({})
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'dump' (Lua function expected)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Dump_C_Function: Dump rejects a C function at the Lua-function argument check.
do
  local function f()
    string.dump(print)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'dump' (Lua function expected)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Format_Type: Format validates its first value through the actual call origin.
do
  local function f()
    string.format(false)
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'format' (string expected, got boolean)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Format_Missing: Format rejects a missing format instead of reading an absent slot.
do
  local function f()
    string.format()
  end
  local info=debug.getinfo(f,'S')
  local expected=info.short_src..':'..(info.linedefined+1)..': '..[=[bad argument #1 to 'format' (string expected, got no value)]=]
  local ok,e=pcall(f);assert(not ok and e==expected,tostring(e))
end

-- Byte_Default: Byte keeps its optional start while sub requires one.
do
  assert(string.byte('abc')==97 and string.sub(123,2)=='23')
end

print('string argument phases OK')
