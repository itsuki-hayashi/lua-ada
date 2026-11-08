-- Public API-command witnesses, paired unchanged with native T.
-- Driver_Rejection is an additional first-party safety test, excluded here.
assert(type(T)=="table")
local cases={
  {"Light_Upvalues",function()
    assert(debug.getupvalue(T.testC,1)==nil);assert(T.testC('isnull U1;return 1'));assert(T.testC('pushvalue U0;return 1')==debug.getregistry());assert(T.testC('pushcclosure 0;return 1')==T.testC)
  end},
  {"Absent_Upvalue",function()
    local f=T.makeCfunc('isnull U256;isnil U256;return 2');local a,b=f();assert(a==true and b==false)
  end},
  {"Stack_Reordering",function()
    local a,b,c=T.testC('rotate 2 1;copy 2 3;return 3',10,20,30);assert(a==30 and b==30 and c==20);assert(T.testC('settop 10;absindex -1;return 1')==10)
  end},
  {"Raw_Table",function()
    local t=setmetatable({},{__index=function()error('raw')end});T.testC('pushint 37;rawsetp 2 19',t);assert(T.testC('rawgetp 2 19;return 1',t)==37);T.testC('pushstring x;pushint 23;rawset 2',t);assert(T.testC('pushstring x;rawget 2;return 1',t)==23)
  end},
  {"Metatable_Delegation",function()
    local target={};local t=setmetatable({},{__index=function(_,k)collectgarbage();return target[k]end,__newindex=function(_,k,v)target[k]=v end});T.testC('pushint 37;setfield 2 value',t);assert(T.testC('getfield 2 value;return 1',t)==37)
  end},
  {"Arithmetic_Commands",function()
    assert(T.testC('pushint 10;pushint 3;arith +;return 1')==13);local t=setmetatable({},{__unm=function()return 37 end});assert(T.testC('arith _;return 1',t)==37);assert(T.testC('compare LT 2 3;return 1',1,2))
  end},
  {"C_Function_Identity",function()
    local f=T.testC('tocfunction 2;return 1',math.deg);assert(f==math.deg and f(3)==math.deg(3));assert(T.testC('func2num 2;return 1',f)~=0)
  end},
  {"Length_Commands",function()
    local t=setmetatable({1},{__len=function()return '234'end});local a,b,c=T.testC('len 2;Llen 2;objsize 2;return 3',t);assert(a=='234' and b==234 and c==1)
  end},
  {"Loaded_Source",function()
    assert(T.testC('loadstring 2 named t;call 0 1;return 1','return 37')==37);local f=T.testC('loadstring 2 named t;return 1','return 23');assert(f()==23)
  end},
  {"Formatting_Commands",function()
    assert(T.testC('gsub 2 3 4;return 1','a.b.a','a','XX')=='XX.b.XX');assert(T.testC('pushfstringI;return 1','value=%d',37)=='value=37')
  end},
  {"Userdata_Metatable",function()
    local u=T.testC('newuserdata 17;newmetatable TestCommand;pop 1;setmetatable -2;return 1');assert(T.testC('testudata 2 TestCommand;return 1',u));assert(T.testC('objsize 2;return 1',u)==17)
  end},
  {"References",function()
    local t={};local item={};local n=T.ref(item,t);collectgarbage();assert(T.getref(n,t)==item);T.unref(n,t);assert(T.ref({},t)==n);assert(T.ref(nil)==-1);assert(T.getref(-1)==nil)
  end},
  {"Double_Bytes",function()
    local n=12458954321123.0;assert(T.d2s(n)==string.pack('d',n));assert(T.s2d(T.d2s(n))==n);assert(1/T.s2d(T.d2s(-0.0))==-math.huge)
  end},
  {"Mutable_Upvalues",function()
    local f=T.testC('pushint 10;pushint 20;pushcclosure 2;return 1');assert(T.upvalue(f,1)==10 and T.upvalue(f,2)==20);assert(select('#',T.upvalue(f,3))==0);T.upvalue(f,2,'changed');assert(f('pushvalue U2;return 1')=='changed')
  end},
  {"New_Stack",function()
    assert(T.doonnewstack('command_global=37')==0);assert(command_global==37);assert(T.doonnewstack('error(17)')==2)
  end},
  {"External_String",function()
    local s='a'..string.char(0)..string.rep('b',100);local x=T.externstr(s);s=nil;collectgarbage();assert(#x==102 and x:byte(2)==0 and x:sub(3)==string.rep('b',100))
  end},
  {"Warning_Fragments",function()
    if T._installwarning then T._installwarning()end;warn('@store');T.testC([[warningC hello;warning world]]);assert(_WARN=='helloworld');_WARN=false;warn('@normal')
  end},
  {"Hook_Command",function()
    T.testC([[sethook 8 1 'pushint 77;setglobal command_hook']]);local x=1;T.sethook();assert(command_hook==77 and x==1)
  end},
  {"Stack_Reservation",function()
    assert(T.testC('rawcheckstack 32;return 1'));assert(not T.testC('rawcheckstack 2147483647;return 1'));local ok,e=pcall(T.testC,'checkstack 2147483647 required');assert(not ok and e:find('required'))
  end},
  {"Traceback_Command",function()
    local text=T.testC([[traceback "command message" 0;return 1]])
    assert(text:sub(1,32)=='command message\nstack traceback:')
    assert(text:find('testC',1,true))
  end},
  {"Traceback_Dynamic_Level",function()
    local text=T.testC([[pushint 2147483647;traceback deep .;return 1]])
    assert(text=='deep\nstack traceback:')
  end},
  {"Traceback_Suspended_Thread",function()
    local f=assert(load("coroutine.yield('pause');return 37",'@api-trace-thread'))
    local co=coroutine.create(f)
    local ok,value=coroutine.resume(co);assert(ok and value=='pause')
    local text=T.testC(co,[[traceback remote 0;return 1]])
    assert(text:find('remote\nstack traceback:',1,true)==1)
    assert(text:find('api-trace-thread',1,true))
    assert(coroutine.status(co)=='suspended')
    ok,value=coroutine.resume(co);assert(ok and value==37)
  end},
}
for _,case in ipairs(cases)do
  if _API_COMMAND_CASE==nil or _API_COMMAND_CASE==case[1] then
    case[2]()
    print("PASS: API command "..case[1])
  end
end
print("PASS: public API command witnesses")
