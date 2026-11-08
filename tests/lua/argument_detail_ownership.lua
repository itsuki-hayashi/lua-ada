local function check(raw,label)
  local registry=debug.getregistry()
  local loaded=registry._LOADED
  local oldmeta=getmetatable(registry)
  local target=math.sin
  local bad=setmetatable({},{__name=raw})
  _G.detailbad=bad
  local count=0
  local detail='number expected, got '..(label or 'table')
  registry._LOADED=nil
  setmetatable(registry,{__index=function(r,k)
    assert(r==registry and k=='_LOADED')
    count=count+1
    local name,v=debug.getlocal(2,1)
    assert(name and rawequal(v,bad))
    name,v=debug.getlocal(2,2)
    assert(name and rawequal(v,raw))
    name,v=debug.getlocal(2,3)
    assert(name and v==detail)
    name,v=debug.getlocal(2,4)
    assert(name and v==target)
    name,v=debug.getlocal(2,5)
    assert(name and v=='_LOADED')
    return {alias=target}
  end})
  local f=assert(load('(math.sin or print)(detailbad)',
                      '=detail'))
  local ok,e=pcall(f)
  setmetatable(registry,oldmeta)
  rawset(registry,'_LOADED',loaded)
  _G.detailbad=nil
  assert(count==1 and not ok,e)
  local expected="detail:1: bad argument #1 to 'alias' ("
  assert(e==expected..detail..")",e)
end

for i,raw in ipairs{27,false,{}}do
  check(raw)
  print('PASS: argument-detail-'..i)
end
check('Small\0'..string.rep('z',30000),'Small')
print('PASS: argument-detail-4')
print('PASS: argument detail ownership contract')
