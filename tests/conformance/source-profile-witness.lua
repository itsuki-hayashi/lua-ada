-- Measure the native conditions used by the unchanged selected sources.
-- This runs in their actual process and configuration before the source file;
-- it neither substitutes an operator nor consumes/reseeds the random stream.
local integer_bits = math.floor(math.log(math.maxinteger, 2) + 0.5) + 1
assert(1 << integer_bits == 0)
local mantissa_bits = 24
local p = 2.0 ^ mantissa_bits
while p < p + 1.0 do
  p = p * 2.0
  mantissa_bits = mantissa_bits + 1
end
local max_exponent = 0
p = 2.0
while p < math.huge do
  max_exponent = max_exponent + 1
  p = p + p
end
local byte_order = string.pack("i2", 1) == "\1\0" and "little" or "big"
local bitwise_precision = 2.0 ^ 50 < 2.0 ^ 50 + 1.0
                          and 2.0 ^ 50 < (-1 >> 1)
print(string.format('source profile facts: {"integer_bits":%d,' ..
                    '"mantissa_bits":%d,"max_exponent":%d,' ..
                    '"byte_order":"%s","bitwise_precision":%s}',
                    integer_bits, mantissa_bits, max_exponent, byte_order,
                    tostring(bitwise_precision)))
