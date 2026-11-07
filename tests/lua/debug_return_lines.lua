-- Observe root/nested implicit-return lines through the public hook API.
local debug = require "debug"
local cases = {
  {"if\nmath.sin(1)\nthen\n a=1\nelse\n a=2\nend\n", "2,4,7"},
  {"local x=1\n-- trailing comment\n\n", "1"},
  {"\n-- comment\n\n", "1"},
  {"local function foo()\nend\nfoo()\nA=1\nA=2\nA=3\n", "2,3,2,4,5,6"},
  {"do\nreturn\nend\n", "2"},
  {"return\n1,\n2\n", "2,3"},
  {"return\n1\n;\n", "2"},
  {"while math.sin(1) do\nif math.sin(1)\nthen break\nend\nend\na=1",
   "1,2,3,6"},
  {"for i=1,3 do\na=i\nend\n", "1,2,1,2,1,2,1,3"},
  {"for i=\n1,\n2\ndo\na=i\nend\n", "2,3,4,5,1,5,1,6"},
  {"for i,v in pairs{'a','b'} do\na=tostring(i)..v\nend\n", "1,2,1,2,1,3"},
  {"for i,v in\nipairs{1,2}\ndo\na=i\nend\n", "2,3,4,2,4,2,5"},
  {"for i,v in\nipairs{}\ndo\na=i\nend\n", "2,3,5"},
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
local function parameters(first, second, ...) local body end
assert(debug.getlocal(parameters, 1) == "first")
assert(debug.getlocal(parameters, 2) == "second")
assert(debug.getlocal(parameters, 3) == nil)
co = coroutine.create(parameters)
assert(debug.getlocal(co, parameters, 1) == "first")
assert(debug.getlocal(co, parameters, 2) == "second")
assert(debug.getlocal(co, parameters, 3) == nil)
local function named_parameters(first, second, ...tail) local body end
assert(debug.getlocal(named_parameters, 1) == "first")
assert(debug.getlocal(named_parameters, 2) == "second")
assert(debug.getlocal(named_parameters, 3) == nil)
print("vararg fixed parameter names: first,second")
print("OK")
