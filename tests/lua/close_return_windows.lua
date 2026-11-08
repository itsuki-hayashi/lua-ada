local function replaceCaller(old,new)
  local count,slot=0,1
  while true do
    local name,value=debug.getlocal(3,slot)
    if name==nil then break end
    if value==old then assert(debug.setlocal(3,slot,new));count=count+1 end
    slot=slot+1
  end
  assert(count>0)
end

-- Scalar_Result
do
  local f=function()
    local g <close> = setmetatable({},{__close=function()replaceCaller(11,37)end})
    return 11
  end
  assert(f()==37)
end

-- Tuple_With_Nils
do
  local f=function()
    local g <close> = setmetatable({},{__close=function()
      replaceCaller(11,37);replaceCaller(23,42)
    end})
    return 11,nil,23,nil
  end
  local r=table.pack(f())
  assert(r.n==4 and r[1]==37 and r[2]==nil and r[3]==42 and r[4]==nil)
end

-- Weak_Result_Reclamation
do
  local weak=setmetatable({},{__mode='v'})
  local function factory()local value={};weak[1]=value;return value end
  local f=function()
    local g <close> = setmetatable({},{__close=function()
      replaceCaller(weak[1],nil);collectgarbage('collect')
      assert(weak[1]==nil)
    end})
    return(factory())
  end
  assert(f()==nil)
end

-- Subsequent_Return_Hook
do
  local f
  f=function()
    local g <close> = setmetatable({},{__close=function()replaceCaller(11,37)end})
    return 11
  end
  local hits=0
  debug.sethook(function(e)
    if e=='return' then local i=debug.getinfo(2,'fr');if i.func==f then
      hits=hits+1;local name,value=debug.getlocal(2,i.ftransfer)
      assert(name and value==37);assert(debug.setlocal(2,i.ftransfer,42))
    end end
  end,'r')
  local result=f();debug.sethook()
  assert(result==42 and hits==1)
end

-- Close_Error_Replaces_Return
do
  local f=function()
    local g <close> = setmetatable({},{__close=function()
      replaceCaller(11,37);error(17)
    end})
    return 11
  end
  local ok,e=pcall(f);assert(not ok and e==17)
end

-- Reverse_Closer_Order
do
  local order={}
  local f=function()
    local outer <close> = setmetatable({},{__close=function()
      assert(order[1]=='inner');replaceCaller(23,37);order[2]='outer'
    end})
    local inner <close> = setmetatable({},{__close=function()
      replaceCaller(11,23);order[1]='inner'
    end})
    return 11
  end
  assert(f()==37 and order[1]=='inner' and order[2]=='outer')
end

-- Yielding_Closer_Result
do
  local f=function()
    local g <close> = setmetatable({},{__close=function()
      replaceCaller(11,23);coroutine.yield('closing');replaceCaller(23,37)
    end})
    return 11
  end
  local co=coroutine.create(f)
  local ok,value=coroutine.resume(co);assert(ok and value=='closing')
  ok,value=coroutine.resume(co);assert(ok and value==37)
end

-- Vararg_Return_Range
do
  local f=function(a,...)
    local g <close> = setmetatable({},{__close=function()replaceCaller(11,37)end})
    return a,...
  end
  local r=table.pack(f(11,nil,23))
  assert(r.n==3 and r[1]==37 and r[2]==nil and r[3]==23)
end

print('PASS: close handlers edit actual return windows')
