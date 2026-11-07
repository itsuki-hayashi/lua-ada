-- Public debug metadata observations shared by C Lua and Lua Ada.
-- Keep each result deterministic: receiver counts and line membership come
-- from live calls/prototypes, never from addresses or memory measurements.
local debug = require "debug"

local function receiver_count(...)
  local info = debug.getinfo(1, "t")
  assert(select("#", ...) == info.extraargs + 3)
  return info.extraargs
end

local callable = receiver_count
for count = 0, 15 do
  assert(callable("a", nil, "c") == count)
  callable = setmetatable({}, {__call = callable})
end
assert(receiver_count("a", nil, "c") == 0)
assert(debug.getinfo(receiver_count, "t").extraargs == 0)
assert(debug.getinfo(print, "t").extraargs == 0)
print("metacall receiver counts: 0..15")

local function yielding_receiver(self, value)
  coroutine.yield(value)
  assert(debug.getinfo(1, "t").extraargs == 1)
  return value
end
callable = setmetatable({}, {__call = yielding_receiver})
local co = coroutine.create(function()
  local result = callable(42)
  return result
end)
local ok, value = coroutine.resume(co)
assert(ok and value == 42)
assert(debug.getinfo(co, 1, "t").extraargs == 1)
ok, value = coroutine.resume(co)
assert(ok and value == 42)
print("suspended metacall: 1")

local function leaf()
  local info = debug.getinfo(1, "t")
  return info.extraargs, info.istailcall
end
callable = setmetatable({}, {__call = function() return leaf() end})
local count, tail = callable()
assert(count == 1 and tail)
callable = setmetatable({}, {__call = leaf})
local function tailcall() return callable() end
count, tail = tailcall()
assert(count == 0 and tail)
print("tail replacement receiver counts: 1,0")

local sorted = setmetatable({3, 1, 2}, {__call = table.sort})
local seen = false
sorted(function(a, b)
  seen = true
  assert(debug.getinfo(2, "t").extraargs == 1)
  return a < b
end)
assert(seen and sorted[1] == 1 and sorted[3] == 3)
print("native metacall: 1")
sorted[1], sorted[2], sorted[3] = 3, 1, 2
seen = false
local function sort_tail()
  return sorted(function(a, b)
    seen = true
    assert(debug.getinfo(2, "t").extraargs == 1)
    return a < b
  end)
end
sort_tail()
assert(seen and sorted[1] == 1 and sorted[3] == 3)
print("native tail metacall: 1")

assert(debug.getinfo(print, "L").activelines == nil)
local iterator = string.gmatch("abc", ".")
assert(debug.getinfo(iterator, "L").activelines == nil)
assert(debug.getinfo(0, "L").activelines == nil)
print("native active lines: nil")

local f = assert(load("return function(...)\n\nlocal x=1\nreturn x\nend"))()
local lines = debug.getinfo(f, "L").activelines
assert(lines[1] == nil and lines[2] == nil and lines[3] and lines[4] and lines[5])
lines[3], lines[4], lines[5] = nil, nil, nil
assert(next(lines) == nil)
f = assert(load(string.dump(f, true)))
lines = debug.getinfo(f, "L").activelines
assert(type(lines) == "table" and next(lines) == nil)
print("vararg active lines: 3,4,5; stripped: empty")
f = assert(load(string.dump(function()
  local inspected = require "debug"
  return inspected.getinfo(1, "l").currentline
end, true)))
assert(f() == -1)
print("stripped current line: -1")
print("OK")
