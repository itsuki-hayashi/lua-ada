local function check(name,short)
  local original=assert(load('math.sin({})',name))
  local changed=name:gsub('X','\0')
  local bytes,n=string.dump(original):gsub(name,changed,1)
  assert(n==1)
  local f=assert(load(bytes))
  local info=debug.getinfo(f,'S')
  assert(info.source==changed)
  assert(info.short_src==short,
         string.format('%q',info.short_src))
  local ok,e=pcall(f)
  local expected=short..":1: bad argument #1 to 'sin' "
  expected=expected..'(number expected, got table)'
  assert(not ok and e==expected,string.format('%q',e))
end
check('=aXb','a')
print('PASS: binary-source-nul-1')
check('@aXb','a')
print('PASS: binary-source-nul-2')
check('aXb','[string "a')
print('PASS: binary-source-nul-3')
check('@aXb'..string.rep('z',100),'...'..string.rep('z',56))
print('PASS: binary-source-nul-4')
print('PASS: binary source NUL contract')
