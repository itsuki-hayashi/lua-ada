-- A truthy if condition is dead before the first allocating RHS in its body.
collectgarbage("stop")
local weak = setmetatable({{}}, {__mode = "v"})
local calls = 0
local function collect_rhs()
  collectgarbage("collect")
  calls = calls + 1
  return ""
end
if weak[1] then
  local unused = "" .. collect_rhs()
end
collectgarbage("restart")
assert(calls == 1 and weak[1] == nil, "consumed if guard retained")
print("WEAK IF GUARD OK")
