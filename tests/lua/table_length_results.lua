-- Public luaL_len semantics shared by table library continuations.
local functions = {table.insert, table.remove, table.concat, table.unpack}
for _, value in ipairs {'abc', 1.5, math.huge} do
  local t = setmetatable({}, {__len = function () return value end})
  assert(#t == value)
  for _, f in ipairs(functions) do
    local ok, message = pcall(f, t, 1)
    assert(not ok)
    assert(message:find('object length is not an integer', 1, true))
  end
end

-- Numeric strings returned by a metamethod undergo integer conversion.
local t = setmetatable({7, 8}, {__len = function () return '2.0' end})
assert(table.concat(t, ',') == '7,8')
local a, b = table.unpack(t)
assert(a == 7 and b == 8)

-- Length precedes optional bounds, even an explicitly empty result range.
local calls = 0
local explicit = setmetatable({9}, {
  __len = function () calls = calls + 1; return 1 end
})
assert(table.unpack(explicit, 1, 1) == 9 and calls == 1)
assert(select('#', table.unpack(explicit, 2, 1)) == 0 and calls == 2)
getmetatable(explicit).__len = function () error('length first', 0) end
local ok, message = pcall(table.unpack, explicit, 'bad', 1)
assert(not ok and message == 'length first')
print('table length results OK')
