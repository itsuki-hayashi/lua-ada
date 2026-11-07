-- An until expression's consumed value is dead before the following RHS.
collectgarbage("stop")
local weak = setmetatable({{}}, {__mode = "v"})
local calls = 0
local function collect_rhs()
  collectgarbage("collect")
  calls = calls + 1
  return ""
end
repeat until weak[1]
local unused = "" .. collect_rhs()
collectgarbage("restart")
assert(calls == 1 and weak[1] == nil, "consumed repeat guard retained")
print("WEAK REPEAT GUARD OK")
