local function check(modules,label)
  local registry=debug.getregistry()
  local loaded=registry._LOADED
  local oldmeta=getmetatable(registry)
  registry._LOADED=nil
  setmetatable(registry,{__index=function(r,k)
    assert(r==registry and k=='_LOADED')
    return modules
  end})
  local ok,e=pcall(math.sin,{})
  setmetatable(registry,oldmeta)
  rawset(registry,'_LOADED',loaded)
  local expected="bad argument #1 to '"..label
  expected=expected.."' (number expected, got table)"
  assert(not ok and e==expected,e)
end

check({lib={member=math.sin}},'lib.member')
print('PASS: argument-label-1')
check({['Alias\0'..string.rep('x',30000)]=
       {[string.rep('y',30000)]=math.sin}},'Alias')
print('PASS: argument-label-2')
check({_G={['sin\0ignored']=math.sin}},'sin')
print('PASS: argument-label-3')
check({['_G.\0ignored']=math.sin},'')
print('PASS: argument-label-4')
print('PASS: argument label ownership contract')
