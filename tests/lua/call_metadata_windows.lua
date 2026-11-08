-- Public zero-growth C entry and real outstanding-record lifetime witnesses.
assert(type(T)=='table')
local code='pcall 0 1 0;pushstatus;return 2'
local function deep(n)if n>0 then deep(n-1)end end
local function run(f,want,status,bytes)
  collectgarbage();collectgarbage();deep(4)
  if bytes then T.totalmem(T.totalmem())else T.alloccount(0)end
  local a,b=T.testC(code,f)
  T.alloccount();T.totalmem(0)
  assert(a==want and b==status)
end
local function eq(a,b)
  T.alloccount(0)
  local value=a==b
  T.alloccount()
  return value
end
local cases={
  {'First_Protected',function()
    run(function()return 10 end,10,'OK')
  end},
  {'Nested_Protected',function()
    local function leaf()return 37 end
    run(function()
      local a,b=T.testC(code,leaf)
      assert(b=='OK');return a
    end,37,'OK')
  end},
  {'Numeric_Error',function()
    run(function()error(17)end,17,'ERRRUN')
  end},
  {'False_Result',function()
    run(function()return false end,false,'OK')
  end},
  {'Byte_Ceiling',function()
    run(function()return 10 end,10,'OK',true)
  end},
  {'Repeated_Entry',function()
    local function f()return 29 end
    collectgarbage();collectgarbage();deep(4)
    T.alloccount(0)
    for i=1,3 do
      local a,b=T.testC(code,f);assert(a==29 and b=='OK')
    end
    T.alloccount()
  end},
  {'Outstanding_Shrink',function()
    deep(48)
    local function f()collectgarbage();collectgarbage();return 37 end
    local a,b=T.testC(code,f);assert(a==37 and b=='OK')
    assert(T.testC('call 0 1;return 1',function()return 29 end)==29)
  end},
  {'Error_After_Shrink',function()
    deep(48)
    local function f()collectgarbage();error(17)end
    local a,b=T.testC(code,f);assert(a==17 and b=='ERRRUN')
    assert(T.testC('call 0 1;return 1',function()return 29 end)==29)
  end},
  {'Cross_Context_Return',function()
    local co=coroutine.create(function()end)
    deep(48)
    _METADATA_CROSS_TARGET=function()
      deep(32);collectgarbage();collectgarbage();return 37
    end
    local a,b=T.testC(code,function()
      local value,status=T.testC(co,
        'getglobal "_METADATA_CROSS_TARGET";pcall 0 1 0;pushstatus;return 2')
      assert(value=='37' and status=='OK');return 29
    end)
    assert(a==29 and b=='OK')
    _METADATA_CROSS_TARGET=nil
    assert(coroutine.close(co))
    assert(T.testC('call 0 1;return 1',function()return 41 end)==41)
  end},
  {'Cross_Context_Error',function()
    local co=coroutine.create(function()end)
    deep(48)
    _METADATA_CROSS_TARGET=function()
      deep(32);collectgarbage();collectgarbage();error(17)
    end
    local a,b=T.testC(code,function()
      local value,status=T.testC(co,
        'getglobal "_METADATA_CROSS_TARGET";pcall 0 1 0;pushstatus;return 2')
      assert(value=='17' and status=='ERRRUN');error(29)
    end)
    assert(a==29 and b=='ERRRUN')
    _METADATA_CROSS_TARGET=nil
    assert(coroutine.close(co))
    assert(T.testC('call 0 1;return 1',function()return 43 end)==43)
  end},
  {'Primitive_Strings',function()
    local a=string.rep('x',4096)
    local b=string.rep('x',4096)
    local c=string.rep('y',4096)
    assert(eq(a,b));assert(not eq(a,c));assert(eq('short','short'))
  end},
  {'Primitive_Numbers',function()
    local nan=0/0
    assert(eq(1,1.0));assert(eq(1.0,1));assert(not eq(1,1.5))
    assert(not eq(nan,nan));assert(eq(-0.0,0.0))
    assert(not eq(9007199254740993,9007199254740992.0))
  end},
  {'Primitive_False_Nil',function()
    assert(eq(nil,nil));assert(eq(false,false));assert(not eq(false,nil))
    assert(not eq(1,'1'));assert(not eq({},nil))
  end},
  {'Same_Object_Equality',function()
    local calls=0
    local mt={__eq=function()calls=calls+1;return false end}
    local t=setmetatable({},mt)
    local u=T.newuserdata(1);debug.setmetatable(u,mt)
    assert(eq(t,t));assert(eq(u,u));assert(calls==0)
  end},
  {'Table_Equality_Yields',function()
    local calls=0
    local mt={__eq=function(a,b)
      calls=calls+1;collectgarbage();return coroutine.yield(17)
    end}
    local a,b=setmetatable({},mt),setmetatable({},mt)
    local co=coroutine.create(function()return a==b end)
    local ok,value=coroutine.resume(co);assert(ok and value==17)
    ok,value=coroutine.resume(co,true);assert(ok and value==true and calls==1)
  end},
  {'Userdata_Equality_Handler',function()
    local calls=0
    local a,b=T.newuserdata(1),T.newuserdata(1)
    debug.setmetatable(a,{__eq=function(x,y)
      assert(x==a and y==b);calls=calls+1;collectgarbage();return false
    end})
    debug.setmetatable(b,{__eq=function()error('wrong handler')end})
    assert(not(a==b));assert(calls==1)
  end},
  {'Assert_Success_Tuple',function()
    local marker={}
    deep(4)
    T.alloccount(0)
    local a,b,c,d=assert(37,nil,marker,nil)
    T.alloccount()
    assert(a==37 and b==nil and c==marker and d==nil)
    assert(select('#',assert(37,nil,marker,nil))==4)
  end},
  {'Assert_Protected_Tuple',function()
    local marker={}
    local ok,a,b,c,d=pcall(assert,37,nil,marker,nil)
    assert(ok and a==37 and b==nil and c==marker and d==nil)
    assert(select('#',pcall(assert,37,nil,marker,nil))==5)
  end},
  {'Independent_Checkstack_Refusal',function()
    local L=assert(T.newstate())
    T.alloccount(0)
    local result=T.testC(L,'rawcheckstack 5000;return 1')
    T.alloccount()
    T.closestate(L)
    assert(result==false)
  end},
}
for _,case in ipairs(cases)do
  if _CALL_METADATA_CASE==nil or _CALL_METADATA_CASE==case[1]then
    case[2]();print('PASS call metadata '..case[1])
  end
end
