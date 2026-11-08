-- Public diagnostics retain argument identity and full Lua integer indices.
local cases={
 {'Concat_Maximum',function()
  local ok,err=pcall(table.concat,{},' ',math.maxinteger,math.maxinteger)
  assert(not ok and err=="invalid value (nil) at index "..
   math.maxinteger.." in table for 'concat'",err)
 end},
 {'Concat_Minimum',function()
  local ok,err=pcall(table.concat,{},' ',math.mininteger,math.mininteger)
  assert(not ok and err=="invalid value (nil) at index "..
   math.mininteger.." in table for 'concat'",err)
 end},
 {'Concat_Zero',function()
  local ok,err=pcall(table.concat,{[0]=false},'',0,0)
  assert(not ok and err==
   "invalid value (boolean) at index 0 in table for 'concat'",err)
 end},
 {'Concat_Proxy',function()
  local receiver=setmetatable({},{__len=function()return 1 end,
   __index=function(_,key)assert(key==math.mininteger)
    collectgarbage();return false end})
  local ok,err=pcall(table.concat,receiver,'',math.mininteger,math.mininteger)
  assert(not ok and err=="invalid value (boolean) at index "..
   math.mininteger.." in table for 'concat'",err)
 end},
 {'Concat_Separator',function()
  local ok,err=pcall(table.concat,{},false)
  assert(not ok and err==
   "bad argument #2 to 'table.concat' (string expected, got boolean)",err)
 end},
 {'Pairs_Missing',function()
  local ok,err=pcall(pairs)
  assert(not ok and err=="bad argument #1 to 'pairs' (value expected)",err)
 end},
 {'Ipairs_Missing',function()
  local ok,err=pcall(ipairs)
  assert(not ok and err=="bad argument #1 to 'ipairs' (value expected)",err)
  local iterator,state,index=ipairs(nil)
  assert(type(iterator)=='function' and state==nil and index==0)
 end},
}
for _,case in ipairs(cases)do
 if _TABLE_ERROR_CASE==nil or _TABLE_ERROR_CASE==case[1]then
  case[2]();print('PASS table error '..case[1])
 end
end
