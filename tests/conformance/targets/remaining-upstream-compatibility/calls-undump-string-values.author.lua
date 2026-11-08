-- First-party public counterpart for the calls.lua private-pool proposal.
-- MIT, lua-ada authors. No T inspector, adapted upstream source or approval.
local str = "|" .. string.rep("X", 50) .. "|"
local foo = assert(load(string.format([[
  local str <const> = "%s"
  return {
    function () return str end,
    function () return str end,
    function () return str end
  }
]], str)))
local dump = string.dump(foo)
local _, count = string.gsub(dump, str, {})
assert(count == 2)
local funcs = assert(load(dump))()
assert(type(funcs) == "table" and #funcs == 3)
for i = 1, 3 do
  assert(type(funcs[i]) == "function")
  local result = table.pack(funcs[i]())
  assert(result.n == 1 and type(result[1]) == "string")
  assert(#result[1] == 52 and result[1] == str)
  local pointer = string.format("%p", result[1])
  assert(type(pointer) == "string" and #pointer > 0)
  collectgarbage(); collectgarbage()
  assert(string.format("%p", result[1]) == pointer)
  assert(result[1] == str)
  local child = assert(load(string.dump(funcs[i])))
  local copied = table.pack(child())
  assert(copied.n == 1 and type(copied[1]) == "string")
  assert(copied[1] == str)
end

-- Equal long-string values need not share one runtime allocation. The
-- optional diagnostic reports this actual implementation choice; the public
-- counterpart requires equality and stable identifiers for each held value.
local same = string.sub("!" .. str, 2)
assert(same == str)
local first, second = string.format("%p", str), string.format("%p", same)
assert(string.format("%p", str) == first)
assert(string.format("%p", same) == second)
if os.getenv("LUA_ADA_CALLS_OBSERVE_POINTERS") == "1" then
  print("EQUAL-VALUES-POINTERS-SHARED", first == second)
end
print("CALLS UNDUMP STRING VALUES OK")
