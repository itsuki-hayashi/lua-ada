global <const> *

local total = 0
local values = {10, 20, 30, label = 'values'}
for i = 1, #values do total = total + values[i] end
assert(total == 60)
local visits = 0
for key, value in pairs(values) do
  if type(key) == 'number' then
    assert(value == values[key])
  end
  visits = visits + 1
end
assert(visits == 4)
for i, value in ipairs(values) do assert(value == i * 10) end

local n = 3
while n > 0 do n = n - 1 end
repeat n = n + 1 until n == 3
for i = 10, 1, -1 do
  if i == 8 then break end
  n = n + 1
end
assert(n == 5)
local cycle = {}; cycle.self = cycle
assert(rawequal(cycle, cycle.self))
rawset(cycle, 'answer', 42)
assert(rawget(cycle, 'answer') == 42)
assert(rawlen(values) == 3)
print('tables ok')
