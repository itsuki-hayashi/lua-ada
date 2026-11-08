-- Native-paired sort argument origin, validation phase and failed-root checks.

-- Missing_Receiver: A missing sequence uses the actual first argument and absent-value type.
do
  local f=assert(load([=[table.sort()]=],'=sort-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[sort-argument:1: bad argument #1 to 'sort' (table expected, got no value)]=],tostring(e))
end

-- Nil_Receiver: An explicitly nil sequence differs from an absent sequence.
do
  local f=assert(load([=[table.sort(nil)]=],'=sort-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[sort-argument:1: bad argument #1 to 'sort' (table expected, got nil)]=],tostring(e))
end

-- Number_Receiver: The ordinary table capability gate retains its auxiliary type error.
do
  local f=assert(load([=[table.sort(7)]=],'=sort-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[sort-argument:1: bad argument #1 to 'sort' (table expected, got number)]=],tostring(e))
end

-- Named_Receiver: A non-table receiver retains its raw auxiliary type name.
do
  local previous=debug.getmetatable(false);debug.setmetatable(false,{__name='Sequence'})
  local f=assert(load([=[table.sort(false)]=],'=sort-argument'))
  local ok,e=pcall(f)
  debug.setmetatable(false,previous)
  assert(not ok and e==[=[sort-argument:1: bad argument #1 to 'sort' (table expected, got Sequence)]=],tostring(e))
end

-- Comparator_Type: The nontrivial comparator check diagnoses its real second argument.
do
  local f=assert(load([=[table.sort({2,1},{})]=],'=sort-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[sort-argument:1: bad argument #2 to 'sort' (function expected, got table)]=],tostring(e))
end

-- Named_Comparator: Comparator validation preserves a named invalid type.
do
  local f=assert(load([=[table.sort({2,1},setmetatable({},{__name='Ordering'}))]=],'=sort-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[sort-argument:1: bad argument #2 to 'sort' (function expected, got Ordering)]=],tostring(e))
end

-- Callable_Comparator: A callable table still fails the pinned actual-function comparator check.
do
  local f=assert(load([=[table.sort({2,1},setmetatable({},{__call=function()return false end}))]=],'=sort-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[sort-argument:1: bad argument #2 to 'sort' (function expected, got table)]=],tostring(e))
end

-- Nested_Sort: Sort used as a C comparator resolves its actual registry function name.
do
  local f=assert(load([=[table.sort({1,2,3},table.sort)]=],'=sort-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[bad argument #1 to 'table.sort' (table expected, got number)]=],tostring(e))
end

-- Array_Size: An oversized length reports the first argument before comparator validation.
do
  local f=assert(load([=[table.sort(setmetatable({},{__len=function()return 2147483647 end}))]=],'=sort-argument'))
  local ok,e=pcall(f)
  assert(not ok and e==[=[sort-argument:1: bad argument #1 to 'sort' (array too big)]=],tostring(e))
end

-- Method_Self: A method capability failure diagnoses the actual bad self.
do
  string.sort=table.sort
  local f=assert(load([=[('abc'):sort()]=],'=sort-argument'))
  local ok,e=pcall(f)
  string.sort=nil
  assert(not ok and e==[=[sort-argument:1: calling 'sort' on bad self (table expected, got string)]=],tostring(e))
end

-- Trivial_Empty: An empty interval does not validate an unused comparator.
do
  local t={};table.sort(t,{});assert(#t==0)
end

-- Trivial_Single: A singleton retains the early return before comparator type checks.
do
  local t={7};table.sort(t,{});assert(t[1]==7)
end

-- Optional_Nil: An explicit nil comparator uses the default comparison normally.
do
  local t={2,1};table.sort(t,nil);assert(t[1]==1 and t[2]==2)
end

-- Length_First: A real length callback throws before an invalid comparator is checked.
do
  local marker={};local t=setmetatable({},{__len=function()error(marker,0)end})
  local ok,e=pcall(table.sort,t,{});assert(not ok and e==marker)
end

-- Registry_Roots: Failed sort captures release operands removed from all actual slots.
do
  local r=debug.getregistry();local loaded,mt=r._LOADED,getmetatable(r)
  local weak=setmetatable({},{__mode='v'});local calls=0
  local function make()local value={};weak[1]=value;return value end
  r._LOADED=nil;setmetatable(r,{__index=function(_,k)
    assert(k=='_LOADED' and debug.getinfo(2,'f').func==table.sort)
    assert(debug.setlocal(2,2,nil)=='(C temporary)')
    collectgarbage();assert(weak[1]==nil);calls=calls+1
    return loaded
  end})
  local ok,e=pcall(table.sort,{2,1},make())
  setmetatable(r,mt);r._LOADED=loaded
  assert(not ok and calls==1 and e=="bad argument #2 to 'table.sort' (function expected, got table)",tostring(e))
end

print('sort argument phases OK')
