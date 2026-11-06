-- First-party table algorithm differential. Seed: (927, -1701).
-- Compare values and failures, not backend-dependent comparator call counts.
global <const> *
math.randomseed(927,-1701)
for case=1,384 do
  local n=case%97
  local t=table.create(n,case%7)
  for i=1,n do t[i]=math.random(-16,16) end
  local mode=case%4
  if mode==0 then
    table.sort(t)
  elseif mode==1 then
    table.sort(t,function(a,b)return a>b end)
  elseif mode==2 then
    for i=1,n do t[i]=string.char(t[i]+80) end
    table.sort(t)
  else
    local m={__lt=function(a,b)return a.n<b.n end}
    for i=1,n do t[i]=setmetatable({n=t[i]},m) end
    table.sort(t)
    for i=1,n do t[i]=t[i].n end
  end
  print('sort',case,mode,n,table.concat(t,','))
end
for size=0,64 do
  local t=table.create(size,size%11)
  assert(#t==0 and next(t)==nil)
  for i=1,size do t[i]=i end
  t.key='retained'
  print('create',size,#t,t.key,table.concat(t,','))
end
for _,args in ipairs({{-1},{0,-1},{0.5},{1<<31},{0,1<<31},
                       {0,(1<<31)-1}}) do
  local ok,e=pcall(table.create,table.unpack(args))
  print('badcreate',ok,e:find('out of range')~=nil,
        e:find('table overflow')~=nil)
end
for size=4,12 do
  local t={};for i=1,size do t[i]=i end
  local ok,e=pcall(table.sort,t,function()return true end)
  print('badcompare',size,ok,e:find('invalid order function')~=nil)
end
print('TABLE ALGORITHM CAMPAIGN OK')
