-- closure.lua:39-42 consumes a weak lookup before allocating its loop RHS.
-- Force that collection point so correctness cannot depend on GC cadence.
collectgarbage("stop")
local weak = setmetatable({{}}, {__mode = "v"})
local calls = 0
local function collect_rhs()
  collectgarbage("collect")
  calls = calls + 1
  return ""
end
while weak[1] do
  local unused = "" .. collect_rhs()
  if calls == 3 then break end
end
collectgarbage("restart")
assert(calls == 1 and weak[1] == nil, "consumed while guard retained")
print("WEAK WHILE GUARD OK")
