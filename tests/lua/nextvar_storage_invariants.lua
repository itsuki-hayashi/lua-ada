-- Source-linked companions for nextvar.lua:144-322, not a replacement file.
-- Explicit modes distinguish public native observations from mandatory walks
-- of Ada's actual storage. Neither mode invents C array/hash capacities.
local mode, selected = ...
assert(mode == 'public' or mode == 'ada-storage', 'explicit storage mode required')
local inspect
if mode == 'ada-storage' then
  assert(T and type(T.ada_check_table_storage) == 'function')
  inspect = T.ada_check_table_storage
end

local function check(t, expected)
  local count = 0
  for k, v in pairs(t) do
    assert(v ~= nil and t[k] == v)
    count = count + 1
  end
  assert(count == expected)
  if inspect then
    local rows, live = inspect(t)
    assert(math.type(rows) == 'integer' and rows >= 0)
    assert(math.type(live) == 'integer' and live == expected and rows >= live)
  end
end

-- Retain the evaluated ordinary logarithm/ceil/power inequalities from
-- nextvar.lua:151-155 even though no private geometry is compared.
local function mp2(n)
  local mp = 2^math.ceil(math.log(n, 2))
  assert((mp == 0 or mp/2 < n) and n <= mp)
  return mp
end
local sizes = {0, 1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17,
               30, 31, 32, 33, 34, 254, 255, 256, 257, 500, 1001}
local cases = {
  {'Library', function()
    local n = 0
    for _ in pairs(math) do n = n + 1 end
    assert(mp2(n) >= n)
    check(math, n)
  end},
  {'Constructors', function()
    local calls = 0
    for _, sa in ipairs(sizes) do
      local arr = {'return {'}
      for i = 1, sa do arr[1+i] = '1,' end
      for _, sh in ipairs(sizes) do
        for j = 1, sh do arr[1+sa+j] = string.format('k%x=%d,', j, j) end
        arr[1+sa+sh+1] = '}'
        local f = assert(load(table.concat(arr)))
        collectgarbage('stop')
        f() -- The actual warm call remains distinct from the observed call.
        local t = f()
        collectgarbage('restart')
        assert(#t == sa and mp2(sh) >= sh)
        for i = 1, sa do assert(t[i] == 1) end
        for j = 1, sh do assert(t[string.format('k%x', j)] == j) end
        check(t, sa+sh)
        calls = calls + 1
      end
    end
    assert(calls == 529)
  end},
  {'Open_Constructor', function()
    local a = {}
    for i = 1, sizes[#sizes] do a[i] = i end
    for k in ipairs(sizes) do
      local t = {table.unpack(a, 1, k)}
      assert(#t == k)
      for i = 1, k do assert(t[i] == i) end
      check(t, k)
      t = {1, 2, 3, table.unpack(a, 1, k)}
      assert(#t == k+3)
      for i = 1, 3 do assert(t[i] == i) end
      for i = 1, k do assert(t[i+3] == i) end
      check(t, k+3)
    end
  end},
  {'Dense', function()
    local a = {}; a[2] = 1; check(a, 1)
    a = {}; a[0] = 1; check(a, 1)
    a[2] = 1; check(a, 2)
    a = {}; a[0] = 1; a[1] = 1; check(a, 2)
    a = {}
    for i = 1, 130 do
      a[i] = i
      assert(#a == i and mp2(i) >= i)
      check(a, i)
    end
    for i = 1, 130 do assert(a[i] == i) end
  end},
  {'Hash', function()
    local a = {}
    for i = 1, 130 do
      a['a'..i] = i
      assert(#a == 0 and mp2(i) >= i)
      check(a, i)
    end
    for i = 1, 130 do assert(a['a'..i] == i) end
  end},
  {'Reverse', function()
    local a, n = {}, 2^10
    for i = n, 1, -1 do a[i] = i end
    assert(mp2(n) >= n and #a == n)
    check(a, n)
    for i = 1, n do assert(a[i] == i) end
  end},
  {'Sparse', function()
    local a, count = {}, 0
    for i = 1, 257 do
      if i % 3 ~= 1 then
        a[i] = true; count = count + 1
        assert(mp2(i) >= i)
        check(a, count)
      end
    end
    for i = 1, 257 do assert(a[i] == (i % 3 ~= 1 or nil)) end
  end},
  {'Array_Churn', function()
    -- nextvar.lua:249-265's surviving keys are the value map. This loop is
    -- finite regardless of whether this implementation reuses one row.
    local a = {}
    for i = 1, 16 do a[i] = i end
    for i = 1, 11 do a[i] = nil end
    a[30] = true; a[30] = nil; a[10] = 1
    local function retained()
      check(a, 6); assert(a[10] == 1)
      for i = 12, 16 do assert(a[i] == i) end
    end
    retained()
    for i = 10001, 11024 do
      a[i] = true; assert(a[i] == true); a[i] = nil
      if i % 128 == 0 then collectgarbage(); retained() end
    end
    retained()
    for i = 1, 14 do a[i] = true; a[i] = nil end
    a[31] = true; a[32] = true
    check(a, 4)
    assert(a[15] == 15 and a[16] == 16 and a[31] and a[32])
  end},
  {'Hash_Churn', function()
    -- nextvar.lua:293-305: keep all 255 original string bindings through
    -- real fresh-key insertion, deletion and collections; no shape trigger.
    local a = {}
    for i = 1, 256 do a[i..''] = true end
    a['256'] = nil
    local function retained()
      check(a, 255)
      for i = 1, 255 do assert(a[i..''] == true) end
      assert(a['256'] == nil)
    end
    retained()
    for i = 10001, 11024 do
      a[i] = true; assert(a[i] == true); a[i] = nil
      if i % 128 == 0 then collectgarbage(); retained() end
    end
    retained()
  end},
  {'Vararg', function()
    local function foo(n, ...)
      local arg = {...}
      assert(select('#', ...) == n and #arg == n)
      check(arg, n)
      for i = 1, n do assert(arg[i] == i) end
      arg[n+1] = true
      assert(mp2(n+1) >= n+1 and #arg == n+1)
      check(arg, n+1)
      arg.x = true
      check(arg, n+2)
    end
    local a = {}
    for i = 1, 35 do a[i] = i; foo(i, table.unpack(a)) end
  end},
  {'Object_Lifetime', function()
    local key, value = {}, {payload = 37}
    local a, weak = {[key] = value}, setmetatable({}, {__mode = 'v'})
    weak[1], weak[2] = key, value
    key, value = nil, nil
    collectgarbage(); check(a, 1)
    assert(type(weak[1]) == 'table' and a[weak[1]] == weak[2])
    assert(weak[2].payload == 37)
    a[weak[1]] = nil
    collectgarbage(); collectgarbage(); check(a, 0)
    assert(weak[1] == nil and weak[2] == nil and next(a) == nil)
    local fresh = {}; a[fresh] = 42; a[3] = 17; a.alo = 29
    collectgarbage(); check(a, 3)
    assert(a[fresh] == 42 and a[3] == 17 and a.alo == 29)
  end},
}
local ran = 0
for _, case in ipairs(cases) do
  if selected == nil or selected == case[1] then
    case[2](); ran = ran + 1
    print('PASS nextvar storage '..case[1])
  end
end
assert(ran == (selected and 1 or #cases), 'unknown storage case')
return 29
