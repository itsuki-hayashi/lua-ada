-- Public object-key lifetime and same-table behavior; no private geometry.

-- Anonymous_Key: The original collectable key dies after public deletion.
do
  collectgarbage('stop')
  local a = {[{}] = 4, [3] = 0, alo = 1,
             a1234567890123456789012345678901234567890 = 10}
  local weak=setmetatable({},{__mode='v'})
  local count=0
  for k in pairs(a)do
    count=count+1
    if type(k)=='table'then weak[1]=k end
  end
  assert(count==4 and type(weak[1])=='table')
  for k in pairs(a)do a[k]=nil end
  collectgarbage()
  assert(weak[1]==nil and next(a)==nil)
  collectgarbage('restart')
end

-- Live_Key: An actually reachable object key and its value survive collection.
do
  local key={};local value={payload=37};local a={[key]=value}
  local weak=setmetatable({key},{__mode='v'})
  collectgarbage()
  assert(weak[1]==key and a[key]==value and a[key].payload==37)
  local count=0
  for k,v in pairs(a)do
    count=count+1;assert(k==key and v==value)
  end
  assert(count==1)
end

-- Same_Table: A collected object key cannot corrupt later use of that table.
do
  collectgarbage('stop')
  local a={[{}]=4,[3]=0,alo=1,
           a1234567890123456789012345678901234567890=10}
  local weak=setmetatable({},{__mode='v'})
  for k in pairs(a)do if type(k)=='table'then weak[1]=k end end
  for k in pairs(a)do a[k]=nil end
  collectgarbage()
  assert(weak[1]==nil and next(a)==nil)
  local fresh={};a[fresh]=42;a[3]=17;a.alo=29
  collectgarbage()
  local count=0
  for k,v in pairs(a)do
    count=count+1
    assert((k==fresh and v==42)or(k==3 and v==17)or(k=='alo'and v==29))
  end
  assert(count==3 and a[fresh]==42 and a[3]==17 and a.alo==29)
  collectgarbage('restart')
end

print('Table storage public OK')
