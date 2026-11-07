-- and/or return operand values; their TEST instructions cannot clear them.
collectgarbage("stop")
local weak = setmetatable({{}}, {__mode = "v"})
local held = weak[1] or error("truthy operand lost")
collectgarbage("collect")
assert(weak[1] == held)
local other = true and held
held = nil
collectgarbage("collect")
assert(weak[1] == other)
collectgarbage("restart")
print("SHORT CIRCUIT ROOT OK")
