-- Scalar result owners and actual protected success publication.

-- Cold_Find: A fresh scalar producer delivers both indices and an absent result.
do
  local a,b=string.find('abc','bc',1,true);assert(a==2 and b==3)
  assert(string.find('abc','missing',1,true)==nil)
end

-- Cold_Empty_Byte: An empty range returns zero values through the owned arena.
do
  assert(select('#',string.byte('',1,0))==0)
end

-- Warm_Find: Repeated protected scalar delivery reuses the actual waiting caller.
do
  local f,s,p=string.find,'abc','bc'
  for i=1,100 do local ok,a,b=pcall(f,s,p);assert(ok and a==2 and b==3)end
end

-- Multiple_Status: A success prefix retains nil and false child results exactly once.
do
  local r=table.pack(pcall(function()return nil,false,7,9 end))
  assert(r.n==5 and r[1]==true and r[2]==nil and r[3]==false and r[4]==7 and r[5]==9)
end

-- Zero_Status: A child with no values still contributes exactly one success boolean.
do
  local r=table.pack(pcall(function()end));assert(r.n==1 and r[1]==true)
end

-- Xpcall_Status: Xpcall publishes its own success status and preserves false results.
do
  local r=table.pack(xpcall(function(a,b)return false,a,b end,function(e)return e end,7,9))
  assert(r.n==4 and r[1]==true and r[2]==false and r[3]==7 and r[4]==9)
end

-- Repeated_Status: Reusing a protected frame cannot accumulate success prefixes.
do
  local f=function()return false,7 end
  for i=1,100 do local r=table.pack(pcall(f));assert(r.n==3 and r[1]==true and r[2]==false and r[3]==7)end
end

-- Yield_Status: A suspended protected call prefixes success only after final completion.
do
  local co=coroutine.create(function()return pcall(function()local x=coroutine.yield(7);return false,x end)end)
  local ok,v=coroutine.resume(co);assert(ok and v==7)
  local resumed,protected,raw,last=coroutine.resume(co,9)
  assert(resumed and protected and raw==false and last==9 and coroutine.status(co)=='dead')
end

-- Protected_Error: The existing arbitrary error packet receives no success prefix.
do
  local marker={};local ok,e=pcall(function()error(marker,0)end)
  assert(not ok and e==marker)
end

-- Xpcall_Error: An error handler's arbitrary result remains an error result.
do
  local marker,changed={},{};local ok,e=xpcall(function()error(marker,0)end,function(v)assert(v==marker);return changed end)
  assert(not ok and e==changed)
end

-- Weak_Output: Reused native output arenas retain no values after actual callers depart.
do
  local weak=setmetatable({},{__mode='v'})
  local function make()return {} end
  local function produce()
    local ok,inner,value=pcall(pcall,make);assert(ok and inner)
    weak[1]=value;collectgarbage();assert(weak[1]==value)
  end
  produce();collectgarbage();assert(weak[1]==nil)
end

print('string result phases OK')
