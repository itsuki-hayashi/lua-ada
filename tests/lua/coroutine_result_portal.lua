local limit=assert(_PORTAL_LIMIT)
local names,values,sum={},{},{}
for i=1,64 do names[i]='a'..i;values[i]='1';sum[i]='a'..i end
local source='return function(n,mode) local '..table.concat(names,',')..'='..
  table.concat(values,',')..'; '..[[
local closed=0
local body=function()
 local guard <close> = setmetatable({},{__close=function()closed=closed+1 end})
 if mode=='yield' or mode=='wrapped' then
  coroutine.yield(table.unpack({},1,n));return 37
 end
 return table.unpack({},1,n)
end
local co,wrapped
if mode=='wrapped' then
 wrapped=coroutine.wrap(body);local name;name,co=debug.getupvalue(wrapped,1)
else co=coroutine.create(body)end
if mode=='success' then
 local count=select('#',coroutine.resume(co));assert(count==n+1)
else
 local ok,r,message
 if wrapped then
  ok,message=pcall(wrapped)
  assert(not ok and message:find('too many results to resume',1,true))
 else
  ok,r,message=pcall(coroutine.resume,co)
  assert(ok,'capacity error escaped: '..tostring(r))
  assert(r==false and message=='too many results to resume')
 end
end
if mode=='yield' or mode=='wrapped' then
 assert(coroutine.status(co)=='suspended' and closed==0)
 if wrapped then assert(wrapped()==37)
 else local ok,value=coroutine.resume(co);assert(ok and value==37)end
 assert(closed==1)
else assert(coroutine.status(co)=='dead' and closed==1)end
]]..' assert('..table.concat(sum,'+')..'==64)end'
local check=assert(load(source,'=resume-portal'))()

-- Completed_Result_Overflow
do
  check(limit-30,'return')
end
collectgarbage('collect')

-- Yielded_Result_Overflow
do
  check(limit-30,'yield')
end
collectgarbage('collect')

-- Wrapped_Yield_Preserves_Child
do
  check(limit-30,'wrapped')
end
collectgarbage('collect')

-- Sufficient_Parent_Capacity
do
  check(limit//2,'success')
end

-- Wrapped_Body_Error_Still_Closes
do
  local closed=0
  local wrapped=coroutine.wrap(function()
    local guard <close> = setmetatable({},{__close=function()
      closed=closed+1;error(29)
    end})
    error(17)
  end)
  local ok,value=pcall(wrapped)
  assert(not ok and value==29 and closed==1)
end

print('PASS: coroutine result capacity and recipients')
