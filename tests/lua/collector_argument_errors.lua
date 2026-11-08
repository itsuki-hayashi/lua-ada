local cases={
  function()
    local f=assert(load('(collectgarbage or print){}','=collector'))
    local ok,e=pcall(f)
    assert(not ok and e=="collector:1: bad argument #1 to 'collectgarbage' (string expected, got table)",e)
  end,
  function()
    local f=assert(load('collectgarbage(false)','=collector'))
    local ok,e=pcall(f)
    assert(not ok and e=="collector:1: bad argument #1 to 'collectgarbage' (string expected, got boolean)",e)
  end,
  function()
    _G.badmode=setmetatable({},{__name='Collector Box\0suffix'})
    local f=assert(load('collectgarbage(badmode)','=collector'))
    local ok,e=pcall(f);_G.badmode=nil
    assert(not ok and e=="collector:1: bad argument #1 to 'collectgarbage' (string expected, got Collector Box)",e)
  end,
  function()
    local a,b=collectgarbage(),collectgarbage(nil)
    assert(a==0 and b==0 and math.type(a)=='integer' and math.type(b)=='integer')
  end,
}
for i,f in ipairs(cases)do f();print('PASS: collector-argument-'..i)end
print('PASS: collector argument contract')
