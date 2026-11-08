local cases={
  function()
    local message=string.rep('x',6000)..string.char(0)..'tail'
    local pointer=string.format('%p',message)
    local ok,value=pcall(error,message,0)
    assert(not ok and value==message and #value==6005)
    assert(string.format('%p',value)==pointer)
    collectgarbage();collectgarbage()
    assert(value==message and string.format('%p',value)==pointer)
  end,
  function()
    local message=string.rep('y',6000)
    local pointer=string.format('%p',message)
    local calls=0
    local ok,value=xpcall(function()error(message,0)end,function(original)
      assert(original==message and string.format('%p',original)==pointer)
      for i=1,3 do
        local f,err=load('local =','nested-diagnostic')
        assert(f==nil and type(err)=='string')
        collectgarbage();collectgarbage()
        assert(string.format('%p',original)==pointer)
      end
      calls=calls+1
      return original
    end)
    assert(not ok and value==message and calls==1)
    assert(string.format('%p',value)==pointer)
  end,
  function()
    local marker={payload=string.rep('z',6000)}
    local pointer=string.format('%p',marker)
    local ok,value=xpcall(function()error(marker,0)end,function(original)
      assert(original==marker)
      local f,err=load('local =','nested-table-diagnostic')
      assert(f==nil and type(err)=='string')
      collectgarbage();collectgarbage()
      return original
    end)
    assert(not ok and value==marker and string.format('%p',value)==pointer)
  end,
  function()
    local original=string.rep('o',6000)
    local replacement=string.rep('r',6000)..string.char(0)..'end'
    local pointer=string.format('%p',replacement)
    local closed=0
    local function fail()
      local resource <close> = setmetatable({},{__close=function(_,err)
        assert(err==original)
        closed=closed+1
        collectgarbage()
        error(replacement,0)
      end})
      error(original,0)
    end
    local ok,value=pcall(fail)
    assert(not ok and value==replacement and closed==1 and #value==6004)
    assert(string.format('%p',value)==pointer)
  end,
  function()
    local message=string.rep('c',6000)
    local pointer=string.format('%p',message)
    local co=coroutine.create(function()error(message,0)end)
    local ok,value=coroutine.resume(co)
    assert(not ok and value==message and coroutine.status(co)=='dead')
    collectgarbage();collectgarbage()
    assert(string.format('%p',value)==pointer)
    local closed,err=coroutine.close(co)
    assert(not closed and err==message and string.format('%p',err)==pointer)
  end,
  function()
    local prefix=string.rep('z',300)
    local mode=prefix..string.char(0)..'t'
    local f,e=load('return 37','mode',mode)
    assert(f==nil and e=="attempt to load a text chunk (mode is '"..prefix.."')")
  end,
}
for i,f in ipairs(cases)do f();print('PASS: error storage identity '..i)end
