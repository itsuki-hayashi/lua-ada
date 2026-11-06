-- First-party deterministic lifecycle differential campaign.
-- Each family has independent invariants as well as raw C/Ada output equality.
-- A failed generated chunk prints its exact bytes for the runner to retain.
local seed = 872641
local state = seed
local count = 0
local function random(n)
  state = (state * 1103515245 + 12345) & 0x7fffffff
  return state % n
end
local function check(ok, source)
  if not ok then
    local hex = (source:gsub('.', function(c)
      return string.format('%02x', string.byte(c))
    end))
    print('MISMATCH_SOURCE_HEX', hex)
    error('lifecycle campaign invariant failed', 0)
  end
end

-- Scope exits all close the inner binding before the outer binding. Vary the
-- transfer rather than deriving the expected close order from VM internals.
for i = 1, 256 do
  local value = random(1000)
  local which = random(4)
  local transfer = ({
    'return ' .. value,
    'goto done',
    'break',
    'error(' .. value .. ')'
  })[which + 1]
  local source = 'return function(make) local a <close> = make(1); ' ..
    'while true do local b <close> = make(2); ' .. transfer ..
    ' end; ::done:: return ' .. value .. ' end'
  local log = {}
  local function make(n)
    return setmetatable({}, {__close = function(_, e)
      log[#log + 1] = n
      if random(2) == 0 then collectgarbage() end
      if which == 3 then check(e == value, source) end
    end})
  end
  local f = assert(load(source, 'scope-' .. i))()
  local ok, result = pcall(f, make)
  check(ok == (which ~= 3) and result == value and
    table.concat(log, ',') == '2,1', source)
  count = count + 1
  print('scope', i, which, result, table.concat(log, ','))
end

-- A handler error replaces the active error for subsequent outer handlers.
-- Expected error evolution is computed from declaration order, not callbacks.
for i = 1, 256 do
  local mask = random(8)
  local original = random(1000) + 10
  local seen, expected = {}, {}
  local current = original
  for n = 3, 1, -1 do
    expected[#expected + 1] = n .. ':' .. current
    if mask & (1 << (n - 1)) ~= 0 then current = n end
  end
  local source = 'return function(make) local a <close> = make(1); ' ..
    'local b <close> = make(2); local c <close> = make(3); ' ..
    'error(' .. original .. ') end'
  local f = assert(load(source, 'error-' .. i))()
  local ok, result = pcall(f, function(n)
    return setmetatable({}, {__close = function(_, e)
      seen[#seen + 1] = n .. ':' .. e
      collectgarbage()
      if mask & (1 << (n - 1)) ~= 0 then error(n) end
    end})
  end)
  check(not ok and result == current and
    table.concat(seen, ',') == table.concat(expected, ','), source)
  count = count + 1
  print('errors', i, mask, result, table.concat(seen, ','))
end

-- Every nested resume preserves resumer state and packets across collection.
for i = 1, 256 do
  local depth = random(5) + 1
  local function chain(n)
    if n == 0 then return function(x)
      local resumed = coroutine.yield(x, nil, x + 1)
      collectgarbage()
      return resumed + 1
    end end
    local child = coroutine.wrap(chain(n - 1))
    return function(x)
      local a, b, c = child(x)
      check(a == x and b == nil and c == x + 1, 'nested packets')
      local nextvalue = coroutine.yield(a, b, c)
      return child(nextvalue) + 1
    end
  end
  local co = coroutine.create(chain(depth))
  local ok, a, b, c = coroutine.resume(co, i)
  check(ok and a == i and b == nil and c == i + 1, 'nested yield')
  collectgarbage()
  ok, a = coroutine.resume(co, 100)
  check(ok and a == 101 + depth and coroutine.status(co) == 'dead',
    'nested resume depth ' .. depth)
  count = count + 1
  print('nested', i, depth, a)
end

-- Weak keys require an ephemeron fixed point; unreachable self-cycles vanish.
for i = 1, 256 do
  local a = setmetatable({}, {__mode = 'k'})
  local b = setmetatable({}, {__mode = 'k'})
  local root = {}
  do
    local middle = {}
    a[root] = middle
    b[middle] = {answer = i}
    local dead = {}
    a[dead] = {back = dead}
  end
  collectgarbage()
  check(b[a[root]].answer == i, 'ephemeron chain ' .. i)
  local entries = 0
  for _ in pairs(a) do entries = entries + 1 end
  check(entries == 1, 'ephemeron dead cycle ' .. i)
  count = count + 1
  print('weak', i, entries, b[a[root]].answer)
end
assert(count == 1024)
print('M3 lifecycle campaign OK', count, 'seed', seed)
