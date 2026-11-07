-- Observe root/nested implicit-return lines through the public hook API.
local debug = require "debug"
local cases = {
  {"if\nmath.sin(1)\nthen\n a=1\nelse\n a=2\nend\n", "2,4,7"},
  {"local x=1\n-- trailing comment\n\n", "1"},
  {"\n-- comment\n\n", "1"},
  {"local function foo()\nend\nfoo()\nA=1\nA=2\nA=3\n", "2,3,2,4,5,6"},
}
for index, case in ipairs(cases) do
  local co = coroutine.create(assert(load(case[1])))
  local lines = {}
  debug.sethook(co, function(event, line)
    assert(event == "line")
    lines[#lines + 1] = line
  end, "l")
  assert(coroutine.resume(co))
  local observed = table.concat(lines, ",")
  assert(observed == case[2])
  print("root", index, observed)
end

local nested = assert(load(
  "return function()\nlocal x=1\nend\n-- trailing comment\n\n"))()
local lines = {}
local co = coroutine.create(nested)
debug.sethook(co, function(event, line)
  assert(event == "line")
  lines[#lines + 1] = line
end, "l")
assert(coroutine.resume(co))
local observed = table.concat(lines, ",")
assert(observed == "2,3")
print("nested", observed)
print("OK")
