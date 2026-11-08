assert(type(T) == 'table', 'REAL T REQUIRED')
local function deep(n)
  if n > 0 then return 1 + deep(n - 1) end
  return 0
end
assert(deep(8) == 8)
local value = setmetatable({}, {__len = function()
  T.alloccount(0)
  return
end})
local n = #value
T.alloccount()
assert(n == nil)
assert(type({}) == 'table')
print('PASS: length-empty-result-refusal')
