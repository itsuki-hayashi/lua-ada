-- Dump this complete graph with C Lua when comparing exact hook counts.
-- Both runtimes then execute identical words; source compilers may otherwise
-- choose different instruction counts without changing Lua results.
local debug = require "debug"
local function empty()
  for index, value in
  ipairs{}
  do
    local observed = index + value
  end
end
local function two_values()
  for index, value in
  ipairs{10, 20}
  do
    local observed = index + value
  end
end
for index, target in ipairs{empty, two_values} do
  local count = 0
  local thread = coroutine.create(target)
  debug.sethook(thread, function() count = count + 1 end, "", 1)
  assert(coroutine.resume(thread))
  print("iterator count", index, count)
end
print("OK")
