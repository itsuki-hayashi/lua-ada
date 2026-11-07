-- Incremental propagation must not permanently rescue a consumed weak read.
-- Keep enough actual graph edges to require several configured work slices.
collectgarbage("stop")
collectgarbage("collect")
local keep = {}
for i = 1, 1000 do keep[i] = {} end
local weak = setmetatable({{}}, {__mode = "v"})
collectgarbage("param", "stepsize", 100)
for i = 1, 2000 do
  if weak[1] then local unused = 0 end
  collectgarbage("step", 0)
end
assert(#keep == 1000 and weak[1] == nil,
       "transient scalar read rescued weak value during propagation")
collectgarbage("restart")
print("INCREMENTAL SCALAR ROOT OK")
