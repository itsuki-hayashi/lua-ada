local function mutate(fn, action, ...)
  local hits = 0
  debug.sethook(function(event)
    if event == 'return' then
      local info = debug.getinfo(2, 'fr')
      if info.func == fn then hits = hits + 1; action(info) end
    end
  end, 'r')
  local values = table.pack(fn(...))
  debug.sethook()
  assert(hits == 1)
  return values
end

-- Closure_Scalar
do
  local r = mutate(function() return 11 end, function(i)
    assert(i.ntransfer == 1)
    assert(debug.setlocal(3, i.ftransfer, 37))
  end)
  assert(r.n == 1 and r[1] == 37)
end

-- Closure_Tuple
do
  local r = mutate(function() return 11, nil, 23 end, function(i)
    assert(i.ntransfer == 3)
    assert(debug.setlocal(3, i.ftransfer, 37))
    assert(debug.setlocal(3, i.ftransfer + 2, 42))
  end)
  assert(r.n == 3 and r[1] == 37 and r[2] == nil and r[3] == 42)
end

-- Builtin_Appended_Result
do
  local r = mutate(math.abs, function(i)
    assert(debug.setlocal(3, i.ftransfer, 37))
  end, 4)
  assert(r.n == 1 and r[1] == 37)
end

-- Builtin_Argument_Reuse
do
  local r = mutate(assert, function(i)
    assert(i.ntransfer == 3)
    assert(debug.setlocal(3, i.ftransfer, false))
    assert(debug.setlocal(3, i.ftransfer + 1, nil))
    assert(debug.setlocal(3, i.ftransfer + 2, 37))
  end, true, 11, 23)
  assert(r.n == 3 and r[1] == false and r[2] == nil and r[3] == 37)
end

-- Pcall_Success_Status
do
  local r = mutate(pcall, function(i)
    assert(i.ntransfer == 2)
    assert(debug.setlocal(3, i.ftransfer, 37))
    assert(debug.setlocal(3, i.ftransfer + 1, 42))
  end, function() return 11 end)
  assert(r.n == 2 and r[1] == 37 and r[2] == 42)
end

-- Pcall_Error_Status
do
  local r = mutate(pcall, function(i)
    assert(i.ntransfer == 2)
    assert(debug.setlocal(3, i.ftransfer, 'changed'))
    assert(debug.setlocal(3, i.ftransfer + 1, 37))
  end, function() error(17) end)
  assert(r.n == 2 and r[1] == 'changed' and r[2] == 37)
end

-- Xpcall_Success_Status
do
  local r = mutate(xpcall, function(i)
    assert(i.ntransfer == 2)
    assert(debug.setlocal(3, i.ftransfer, false))
    assert(debug.setlocal(3, i.ftransfer + 1, 37))
  end, function() return 11 end, function(e) return e end)
  assert(r.n == 2 and r[1] == false and r[2] == 37)
end

-- Weak_Lua_Result
do
  local weak = setmetatable({}, {__mode = 'v'})
  local function factory() local v = {}; weak[1] = v; return v end
  local r = mutate(function() return (factory()) end, function(i)
    assert(debug.setlocal(3, i.ftransfer, nil))
    -- A compiler can leave other copies in its exposed actual reservation.
    -- Clear every matching real temporary before testing stale packet roots.
    local slot=1
    while true do
      local name,value=debug.getlocal(3,slot)
      if name==nil then break end
      if value==weak[1] then assert(debug.setlocal(3,slot,nil)) end
      slot=slot+1
    end
    collectgarbage('collect')
    assert(weak[1] == nil)
  end)
  assert(r.n == 1 and r[1] == nil)
end

-- Weak_Builtin_Result
do
  local weak = setmetatable({}, {__mode = 'v'})
  local r = mutate(string.gmatch, function(i)
    local name, old = debug.getlocal(3, i.ftransfer)
    assert(name and type(old) == 'function'); weak[1] = old; old = nil
    assert(debug.setlocal(3, i.ftransfer, nil))
    collectgarbage('collect')
    assert(weak[1] == nil)
  end, 'abc', '.')
  assert(r.n == 1 and r[1] == nil)
end

-- Close_Before_Return_Hook
do
  local order = {}
  local fn = function()
    local guard <close> = setmetatable({}, {__close = function()
      order[#order + 1] = 'close'
    end})
    return 11
  end
  local r = mutate(fn, function(i)
    assert(order[1] == 'close' and #order == 1)
    order[2] = 'hook'
    assert(debug.setlocal(3, i.ftransfer, 37))
  end)
  assert(r.n == 1 and r[1] == 37 and order[2] == 'hook')
end

-- Coroutine_Resume_Return
do
  local hits, closed = 0, false
  local fn = function()
    local guard <close> = setmetatable({}, {__close = function() closed=true end})
    coroutine.yield('pause')
    return 11
  end
  local co = coroutine.create(fn)
  debug.sethook(co, function(e)
    if e == 'return' then local i=debug.getinfo(2,'fr'); if i.func==fn then
      hits=hits+1; assert(closed); assert(debug.setlocal(2,i.ftransfer,37))
    end end
  end, 'r')
  local ok,v=coroutine.resume(co); assert(ok and v=='pause' and not closed)
  ok,v=coroutine.resume(co); assert(ok and v==37 and closed and hits==1)
end

-- Return_Hook_Cannot_Yield
do
  local fn = function() return 11 end
  local co=coroutine.create(function()
    local r=mutate(fn,function(i)
      local ok,e=pcall(coroutine.yield,9)
      assert(not ok and e:find('C%-call boundary'))
      assert(debug.setlocal(3,i.ftransfer,37))
    end)
    assert(r[1]==37); return 42
  end)
  local ok,v=coroutine.resume(co); assert(ok and v==42)
end

-- Return_Hook_Error_Recovery
do
  local ok,e=pcall(mutate,function()return 11 end,function()error(17)end)
  debug.sethook()
  assert(not ok and e==17)
  local r=mutate(function()return 12 end,function(i)
    assert(debug.setlocal(3,i.ftransfer,37))
  end)
  assert(r[1]==37)
end

-- Zero_Result_Return
do
  local r=mutate(function()end,function(i)assert(i.ntransfer==0)end)
  assert(r.n==0)
end

-- Vararg_Return_Range
do
  local r=mutate(function(a,...)return a,... end,function(i)
    assert(i.ntransfer==3)
    assert(debug.setlocal(3,i.ftransfer+1,37))
  end,11,nil,23)
  assert(r.n==3 and r[1]==11 and r[2]==37 and r[3]==23)
end

-- Native_Tail_Observe
do
  local r=mutate(function()return math.abs(-11)end,function(i)
    local name,value=debug.getlocal(3,i.ftransfer)
    assert(name and i.ntransfer==1 and value==11)
  end)
  assert(r.n==1 and r[1]==11)
end

-- Native_Tail_Mutate
do
  local r=mutate(function(a,b)return math.abs(a-b)end,function(i)
    local name,value=debug.getlocal(3,i.ftransfer)
    assert(name and i.ntransfer==1 and value==11)
    assert(debug.setlocal(3,i.ftransfer,37))
  end,3,14)
  assert(r.n==1 and r[1]==37)
end

-- Native_Tail_Zero_Results
do
  local t={}
  local r=mutate(function()return table.insert(t,11)end,function(i)
    assert(i.ntransfer==0)
  end)
  assert(r.n==0 and #t==1 and t[1]==11)
end

print('PASS: return hook actual result mutation')
