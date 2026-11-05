global <const> *

local ok, value = pcall(function() error('expected', 0) end)
assert(not ok and value == 'expected')
ok, value = pcall(function() return 42 end)
assert(ok and value == 42)
assert(type(tonumber('42')) == 'number' and tonumber('42') == 42)
assert(tonumber('ff', 16) == 255)
assert(tonumber('invalid') == nil)
assert(tostring(true) == 'true' and tostring(nil) == 'nil')
local bytes = '\x00\255\u{20ac}'
assert(#bytes == 5)
assert([=[
hello]=] == 'hello')
assert(1 << 4 == 16 and -7 // 3 == -3 and -7 % 3 == 2)
assert((9223372036854775807 + 1) == -9223372036854775807 - 1)
print('errors and bytes ok')
