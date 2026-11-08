-- Main-state T string-hash invariants, linked to attrib.lua:335-350.
-- Native hash numbers/width and physical table-position queries are private.
assert(T and type(T.hash)=='function' and type(T.externstr)=='function'
  and type(T.externKstr)=='function')
local selected=...
local cases={}
for _,length in ipairs{0,10,39,40,41,1000}do
  cases[#cases+1]={'Length_'..length,function()
    local source=string.rep('a',length)
    local copied=T.externstr(source)
    local borrowed=T.externKstr(source)
    local repeated_copy=T.externstr(copied)
    local repeated_borrow=T.externKstr(borrowed)
    local variants={source,copied,borrowed,repeated_copy,repeated_borrow}
    local expected=T.hash(source)
    assert(math.type(expected)=='integer')
    for _,value in ipairs(variants)do
      assert(value==source and #value==length)
      assert(select('#',T.hash(value))==1 and T.hash(value)==expected)
      local t={[value]=20}
      assert(t[source]==20 and t[value]==20)
      t[source]=10
      assert(t[value]==10 and next(t)==source and next(t,source)==nil)
      collectgarbage();collectgarbage()
      assert(value==source and source==string.rep('a',length))
      assert(t[value]==10 and t[source]==10 and T.hash(value)==expected)
    end
    -- The original Lua strings remain live past both fixed-buffer borrows.
    assert(copied==source and borrowed==source and repeated_borrow==source)
  end}
end
cases[#cases+1]={'Binary',function()
  local source=string.rep('a\0b',40)
  local copied=T.externstr(source)
  local borrowed=T.externKstr(source)
  local t={[copied]=17}
  collectgarbage();collectgarbage()
  assert(source==copied and source==borrowed and #source==120)
  assert(T.hash(source)==T.hash(copied) and T.hash(source)==T.hash(borrowed))
  assert(t[borrowed]==17 and source:sub(1,3)=='a\0b')
end}
cases[#cases+1]={'Invalid_Type',function()
  for _,value in ipairs{17,17.5,false,{},function()end}do
    local ok,err=pcall(T.hash,value)
    assert(not ok and type(err)=='string')
  end
  local ok,err=pcall(T.hash)
  assert(not ok and type(err)=='string')
  assert(math.type(T.hash('retry'))=='integer')
end}
for _,case in ipairs(cases)do
  if selected==nil or selected==case[1]then
    case[2]();print('PASS string hash '..case[1])
  end
end
