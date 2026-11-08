-- Real public C API wrapper; callers retain borrowed input payloads.
assert(T and type(T.externKstr)=='function')
local cases={
 {'Short_Binary',function()
  local source='hello\0there'
  local external=T.externKstr(source)
  collectgarbage();collectgarbage()
  assert(external==source and #external==11)
  assert(external:sub(6,7)=='\0t' and source:sub(1,5)=='hello')
 end},
 {'Long_Borrow',function()
  local source=string.rep('abc\0def',100)
  local external=T.externKstr(source)
  local table={[external]=37}
  collectgarbage();collectgarbage()
  assert(source==external and #source==700)
  assert(table[source]==37 and external:sub(-7)=='abc\0def')
 end},
 {'Child_State',function()
  local child=assert(T.newstate())
  T.loadlib(child,~0,0)
  local result=T.doremote(child,[[
   local source=string.rep('remote',100)
   local external=T.externKstr(source)
   collectgarbage();assert(external==source and #source==600)
   return external
  ]])
  T.closestate(child)
  collectgarbage();assert(result==string.rep('remote',100))
 end},
 {'Invalid_Type',function()
  local ok,err=pcall(T.externKstr,{})
  assert(not ok and type(err)=='string' and err:find('string expected',1,true))
  assert(T.externKstr('recovered')=='recovered')
 end},
}
for _,case in ipairs(cases)do
 if _FIXED_EXTERNAL_CASE==nil or _FIXED_EXTERNAL_CASE==case[1]then
  case[2]();print('PASS fixed external '..case[1])
 end
end
