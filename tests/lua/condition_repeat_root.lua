-- Consuming a repeat condition must preserve its real closing local.
collectgarbage("stop")
local weak = setmetatable({{}}, {__mode = "v"})
local calls = 0
repeat
  local closing <close> = setmetatable({}, {__close = function(self)
    assert(type(self) == "table")
    collectgarbage("collect")
    calls = calls + 1
  end})
until weak[1]
collectgarbage("restart")
assert(calls == 1)
print("REPEAT GUARD CLOSE OK")
