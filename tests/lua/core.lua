global <const> *

-- Arithmetic, scopes, closures, recursion, and mutable captured cells.
local function factorial(n)
  if n == 0 then return 1 end
  return n * factorial(n - 1)
end
assert(factorial(6) == 720)

local function counter()
  local value = 0
  return function(step)
    value = value + step
    return value
  end
end
local first, second = counter(), counter()
assert(first(2) == 2 and first(3) == 5 and second(1) == 1)

local value = 7
local function captured() return value end
local value = 9
assert(captured() == 7 and value == 9)

local function many(...) return ... end
local a, b, c = many(1, 2, 3)
assert(a == 1 and b == 2 and c == 3)
assert(select('#', many(1, nil, 3)) == 3)
local swapped = {a, b}
swapped[1], swapped[2] = swapped[2], swapped[1]
assert(swapped[1] == 2 and swapped[2] == 1)

local touched = false
local function touch() touched = true; return 42 end
assert((false and touch()) == false)
assert((17 or touch()) == 17 and not touched)
print('core ok')
