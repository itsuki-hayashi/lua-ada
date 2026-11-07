local cases={
  function()
    local f=assert(load('(io.write or print){}','=write'))
    local ok,e=pcall(f)
    assert(not ok and e=="write:1: bad argument #1 to 'io.write' (string expected, got table)",e)
  end,
  function()
    local f=assert(load('io.write(false)','=write'))
    local ok,e=pcall(f)
    assert(not ok and e=="write:1: bad argument #1 to 'write' (string expected, got boolean)",e)
  end,
  function()
    _G.writefile=io.stdout
    local f=assert(load("writefile:write({})",'=write'))
    local ok,e=pcall(f);_G.writefile=nil
    assert(not ok and e=="write:1: bad argument #1 to 'write' (string expected, got table)",e)
  end,
  function()
    local file=assert(io.tmpfile());_G.writefile=file
    local f=assert(load("writefile:write('saved',{})",'=write'))
    local ok,e=pcall(f);file:seek('set');local bytes=file:read('a');file:close();_G.writefile=nil
    assert(not ok and e=="write:1: bad argument #2 to 'write' (string expected, got table)",e)
    assert(bytes=='saved')
  end,
  function()
    local file=assert(io.tmpfile());_G.writefile=file
    _G.writevalue=setmetatable({},{__name='Write Box\0suffix'})
    local f=assert(load('writefile:write(writevalue)','=write'))
    local ok,e=pcall(f);file:close();_G.writefile=nil;_G.writevalue=nil
    assert(not ok and e=="write:1: bad argument #1 to 'write' (string expected, got Write Box)",e)
  end,
  function()
    local file=assert(io.tmpfile())
    assert(file:write()==file);file:close()
  end,
}
for i,f in ipairs(cases)do f();print('PASS: io-write-argument-'..i)end
print('PASS: I/O write argument contract')
