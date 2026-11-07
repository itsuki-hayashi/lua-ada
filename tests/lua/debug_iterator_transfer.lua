-- Iterator dispatch companions preserve native hook and transfer behavior.
local debug = require "debug"
local target = assert(load("for i,v in\nipairs{}\ndo\na=i\nend\n"))
local thread = coroutine.create(target)
local prepared, bad = false, false
debug.sethook(thread, function()
  local info = debug.getinfo(2, "fl")
  if info.func == target then
    if info.currentline == 3 then
      prepared = true
    elseif prepared and info.currentline == 2 then
      bad = true
    end
  end
end, "", 1)
assert(coroutine.resume(thread))
assert(prepared and not bad)
print("iterator dispatch count boundary: preserved")

local function iter(_, value)
  coroutine.yield(value)
  if value < 2 then return value + 1 end
end
thread = coroutine.create(function()
  local sum = 0
  for value in iter, nil, 0 do sum = sum + value end
  return sum
end)
for value = 0, 2 do
  local ok, result = coroutine.resume(thread)
  assert(ok and result == value)
end
local ok, result = coroutine.resume(thread)
assert(ok and result == 3 and coroutine.status(thread) == "dead")
print("yielding iterator results: 0,1,2; sum: 3")

local failure = {}
local closed, body = 0, 0
local closer = setmetatable({}, {__close = function(_, err)
  assert(err == failure)
  closed = closed + 1
end})
local function failing_iterator(_, value)
  if value == 0 then return 1 end
  error(failure)
end
local ok, err = pcall(function()
  for value in failing_iterator, nil, 0, closer do body = body + value end
end)
assert(not ok and err == failure and closed == 1 and body == 1)
print("iterator error identity and closer: preserved")
print("OK")
