-- First-party, T-dependent lifecycle observations for the API941 proposal.
-- MIT, lua-ada authors. This is not an adapted upstream file or an approval.
assert(type(T) == "table" and type(T.totalmem) == "function")
local observe_capacity = os.getenv("LUA_ADA_FINALIZATION_OBSERVE_CAPACITY") == "1"
local capacity = {0, 0, 0, 0, 0, 0}
local finalized = 0
local mt = {__gc = function(u)
  assert(type(u) == "userdata")
  finalized = finalized + 1
end}
collectgarbage(); collectgarbage()
local initial = T.totalmem("userdata")
for round = 1, 6 do
  collectgarbage("stop")
  for i = 1, 1000 do debug.setmetatable(T.newuserdata(0), mt) end
  assert(T.totalmem("userdata") == initial + 1000)
  collectgarbage()
  assert(finalized == round * 1000)
  assert(T.totalmem("userdata") == initial + 1000)
  collectgarbage()
  assert(finalized == round * 1000 and T.totalmem("userdata") == initial)
  collectgarbage()
  assert(finalized == round * 1000 and T.totalmem("userdata") == initial)
  -- Preserve truthful memory observations. Their values are diagnostic;
  -- this witness asserts no C-specific byte or capacity ceiling.
  capacity[round] = math.floor(collectgarbage("count") * 1024)
end

-- Weak references provide a separate module-visible lifetime observation.
-- A finalizer can still read its weak-key record, while its weak value was
-- removed before the callback. The next cycle reclaims keys and userdata.
local keys = setmetatable({}, {__mode = "k"})
local values = setmetatable({}, {__mode = "v"})
local seen, weak_finalized = {}, 0
local weak_mt = {__gc = function(u)
  local id = keys[u]
  assert(math.type(id) == "integer" and not seen[id])
  assert(values[id] == nil)
  seen[id] = true
  weak_finalized = weak_finalized + 1
end}
collectgarbage("stop")
for i = 1, 64 do
  local u = debug.setmetatable(T.newuserdata(0), weak_mt)
  keys[u], values[i] = i, u
end
collectgarbage()
assert(weak_finalized == 64 and T.totalmem("userdata") == initial + 64)
for i = 1, 64 do assert(seen[i] and values[i] == nil) end
local key_count = 0
for _ in pairs(keys) do key_count = key_count + 1 end
assert(key_count == 64)
collectgarbage()
assert(weak_finalized == 64 and next(keys) == nil)
assert(T.totalmem("userdata") == initial)
collectgarbage()
assert(weak_finalized == 64 and T.totalmem("userdata") == initial)
collectgarbage("restart")
if observe_capacity then
  for round = 1, 6 do print("CAPACITY-BYTES", round, capacity[round]) end
end
print("API FINALIZATION LIFETIMES OK")
