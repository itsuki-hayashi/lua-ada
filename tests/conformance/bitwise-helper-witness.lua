-- Execute the pinned primary and its unchanged required helper first. The
-- checks below make the helper's dispatch paths observable without counting
-- this wrapper as a second primary file or changing either upstream source.
dofile("bitwise.lua")

local string_metatable = getmetatable("")
for _, name in ipairs({"__band", "__bor", "__bxor", "__shl", "__shr", "__bnot"}) do
  assert(type(rawget(string_metatable, name)) == "function")
end

-- These operations must use the installed byte-string handlers and produce
-- actual integer values. Both numeric operands are converted before the
-- primitive operation; integral float text and negative counts remain valid.
assert("12.0" & "7.0" == 4)
assert("12" | "5" == 13)
assert("12" ~ "5" == 9)
assert("1e1" << "2" == 40)
assert("8" >> "-1" == 16)
assert(~"0" == -1)
assert(math.type("12.0" & "7.0") == "integer")

-- The string handler is selected before a right-hand table's handler. On
-- failed integer conversion it must raw-lookup that actual second handler,
-- preserve operand order, and preserve its first result even if false/nil.
local left = "not an integer"
local right
local calls = {}
local function handler(name, value)
  return function(a, b)
    assert(a == left and b == right)
    calls[#calls + 1] = name
    return value, "discarded extra result"
  end
end
local methods = {
  __band = handler("band", false),
  __bor = handler("bor", nil),
  __bxor = handler("bxor", "xor result"),
  __shl = handler("shl", "left result"),
  __shr = handler("shr", "right result"),
}
right = setmetatable({}, methods)
assert((left & right) == false)
assert((left | right) == nil)
assert((left ~ right) == "xor result")
assert((left << right) == "left result")
assert((left >> right) == "right result")
assert(table.concat(calls, ",") == "band,bor,bxor,shl,shr")

-- Secondary metamethod lookup bypasses the metatable's own __index. Failed
-- string/string conversion must also report a language error rather than
-- redispatching the same string handler recursively.
local index_calls = 0
setmetatable(methods, {__index = function()
  index_calls = index_calls + 1
  error("secondary handler lookup must be raw")
end})
methods.__bor = nil
local ok, message = pcall(function() return left | right end)
assert(not ok and message:find("bor") and index_calls == 0)
local failure_source = debug.getinfo(1, "S").short_src
local failure_line = debug.getinfo(1, "l").currentline + 1
ok, message = pcall(function() return left & "also not an integer" end)
assert(not ok and message:find("band"))
assert(message:find(failure_source .. ":" .. failure_line .. ":", 1, true))
ok, message = pcall(function() return ~"2.5" end)
assert(not ok and message:find("bnot"))
for _, case in ipairs({
  {"bxor", function() return left ~ "also not an integer" end},
  {"shl", function() return left << "also not an integer" end},
  {"shr", function() return left >> "also not an integer" end},
}) do
  ok, message = pcall(case[2])
  assert(not ok and message:find(case[1]))
end
ok, message = pcall(function() return "12" | false end)
assert(not ok and message:find("bor"))

print("BWCOERCION HELPER OK")
