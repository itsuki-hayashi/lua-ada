-- Focused public-language regressions. This file uses only the M1 library.
-- Each block isolates its locals so an earlier declaration cannot mask a bug.

do
  local function f(...t)
    t[2] = 42
    t.n = 3
    return ...
  end
  local a,b,c = f(1,2)
  assert(a == 1 and b == 42 and c == nil)
end

do
  local ok,message = pcall(function() error(nil) end)
  assert(not ok and message == '<no error object>')
  assert(select('#extra',1,2) == 2)
  local good,iterator,state,key = pcall(ipairs,42)
  assert(good and type(iterator) == 'function' and state == 42 and key == 0)
end

do
  local t = {}
  function t:f(...) return select('#',...) end
  local function make() return t,42 end
  assert(make():f() == 0)
end

do
  local count = 0
  for i=9223372036854775806,9223372036854775807 do count=count+1 end
  assert(count == 2)
  local captured = {}
  for i=1,3 do captured[i]=function() return i end end
  assert(captured[1]() == 1 and captured[3]() == 3)
end

do
  local nan = 0/0
  assert(nan ~= nan and not (nan < 1) and not (1 <= nan))
  -- Formatting follows the current target's C library, checked differentially.
  print(1e308*2, 1e308+1e308, 1e308^2, 0^-1, nan)
end

-- Numeric strings convert in some arithmetic/base-function contexts, but
-- primitive bitwise operations must reject them on either operand side.
local bitops = {
  function(a,b) return a & b end, function(a,b) return a | b end,
  function(a,b) return a ~ b end, function(a,b) return a << b end,
  function(a,b) return a >> b end
}
for _, operation in ipairs(bitops) do
  assert(not pcall(operation, "3", 1))
  assert(not pcall(operation, 1, "3"))
end
assert(not pcall(function() return ~"3" end))
print('edge semantics ok')
