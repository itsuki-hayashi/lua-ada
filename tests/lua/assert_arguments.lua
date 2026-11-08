local cases={
 function()
  local ok,e=pcall(assert)
  assert(not ok and e=="bad argument #1 to 'assert' (value expected)")
 end,
 function()
  local f=assert
  local ok,e=pcall(function()f()end)
  assert(not ok and e:find("to 'f' %(value expected%)$"))
 end,
 function()
  local registry=debug.getregistry()
  local loaded=rawget(registry,'_LOADED')
  local meta=getmetatable(registry)
  local calls=0
  rawset(registry,'_LOADED',nil)
  setmetatable(registry,{__index=function(_,key)
   assert(key=='_LOADED')
   calls=calls+1
   collectgarbage()
   return {_G={probe=assert}}
  end})
  local ok,e=pcall(assert)
  rawset(registry,'_LOADED',loaded)
  setmetatable(registry,meta)
  assert(not ok and calls==1 and e=="bad argument #1 to 'probe' (value expected)")
 end,
 function()
  local ok,e=pcall(assert,nil,nil)
  assert(not ok and type(e)=='string' and not e:find('value expected'))
 end,
 function()
  local values=table.pack(assert(true,nil,37,nil))
  assert(values.n==4 and values[1]==true and values[2]==nil)
  assert(values[3]==37 and values[4]==nil)
 end,
}
for i,f in ipairs(cases)do f();print('PASS: assert arguments '..i)end
