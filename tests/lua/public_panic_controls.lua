-- Public panic and shared-provider witnesses, paired unchanged with native T
-- and with the first-party C helper module against the native interpreter.
assert(type(T)=="table")
local cases={
  {"Trivial",function()
    assert(T.checkpanic('pushstring hi;error')=='hi')
  end},
  {"Status",function()
    assert(T.checkpanic('pushstring hi;error','threadstatus;return 2')=='ERRRUN')
  end},
  {"Stack",function()
    assert(T.checkpanic('pushstring hi;error',[[checkstack 5 XX;pushstring ' alo';pushstring ' mundo';concat 3]])=='hi alo mundo')
  end},
  {"Argument",function()
    assert(T.checkpanic('loadstring 4 name bt')=='bad argument #4 (string expected, got no value)')
  end},
  {"Memory",function()
    local x=T.checkpanic('alloccount 0;newtable','alloccount -1;pushstring XX;threadstatus;concat 2;return 1');T.alloccount();assert(x=='XXnot enough memory')
  end},
  {"Closing",function()
    assert(T.checkpanic([[pushstring "return {__close=function()Y='ho'end}";newtable;loadstring -2 name t;call 0 1;setmetatable -2;toclose -1;pushstring hi;error]],'getglobal Y;concat 2')=='hiho')
  end},
  {"Close_Error",function()
    local x=T.checkpanic([[pushstring "return {__close=function()return 1//0 end}";newtable;loadstring -2 name t;call 0 1;setmetatable -2;toclose -1;pushstring hi;error]]);assert(x:find('divide by zero',1,true))
  end},
  {"Closing_Status",function()
    assert(T.checkpanic([[pushstring "return {__close=function()end}";newtable;loadstring -2 name t;call 0 1;setmetatable -2;toclose -1;pushstring hi;error]],'threadstatus;return 2')=='ERRRUN')
  end},
  {"No_Error",function()
    assert(T.checkpanic('pushint 37')=='no errors')
  end},
  {"Count_Restores_Stack",function()
    local code='alloccount 0;pushvalue 2;alloccount -1;return 1';local x={};T.testC(code,x);assert(T.testC(code,x)==x)
  end},
  {"Child_Byte_Limit",function()
    local st=assert(T.newstate());T.loadlib(st,129,0);assert(T.doremote(st,'return 1')=='1');collectgarbage();local before=T.totalmem();T.totalmem(before+200000);local ok,a,b,c=pcall(T.doremote,st,"return #string.rep('x',1000000)");T.totalmem(0);T.closestate(st);assert(ok and a==nil and b=='not enough memory' and c==4)
  end},
  {"Child_Count_Limit",function()
    local st=assert(T.newstate());T.loadlib(st,1,0);local code=[[local ok,e=pcall(function()T.testC('alloccount 0');return{}end);T.testC('alloccount -1');return(not ok and e=='not enough memory')and 37 or 0]];local ok,a,b,c=pcall(T.doremote,st,code);T.alloccount();T.closestate(st);assert(ok and a=='37' and b==nil and c==nil)
  end},
  {"Load_File",function()
    local f=T.testC('loadfile 2;return 1','tests/lua/public_panic_file.lua');assert(type(f)=='function' and f()==37)
  end},
  {"Oversized_Userdata",function()
    local ok,e=pcall(T.newuserdata,math.maxinteger);assert(not ok and e:find('block too big',1,true))
  end},
}
for _,case in ipairs(cases)do
  if _PANIC_CONTROL_CASE==nil or _PANIC_CONTROL_CASE==case[1]then
    case[2]()
    print('PASS: panic control '..case[1])
  end
end
print('PASS: public panic/provider witnesses')
