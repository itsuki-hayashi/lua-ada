-- Exact formatting regression after migrating rational scratch to the owner.
-- Deterministic bit patterns exercise both exponent extremes and halfway
-- decisions; raw C/Ada stdout comparison preserves every resulting byte.
global <const> *

local function frombits(bits)
  return (string.unpack(">d", string.pack(">i8", bits)))
end

local values = {
  0.0, -0.0, 0.1, 0.5, 1.5, 2.5, 3.5, 9.999, 999.9,
  frombits(1), frombits(0x000fffffffffffff),
  frombits(0x0010000000000000), frombits(0x7fefffffffffffff),
  frombits(0x3fefffffffffffff), frombits(0x3ff0000000000001),
}
local state = 0x13579bdf2468ace0
for index = 1, 128 do
  -- Clear one exponent bit to exclude infinity/NaN from generated cases.
  -- Signed zero and all subnormal magnitudes remain legitimate inputs.
  state = state ~ (state << 13)
  state = state ~ (state >> 7)
  state = state ~ (state << 17)
  values[#values + 1] = frombits(state & 0xffefffffffffffff)
end

local formats = {
  "%f", "%g", "%e", "%.0f", "%.17g", "%.17e", "%.99g",
  "%#.3g", "%+020.6f", "%a",
}
for index, value in ipairs(values) do
  for _, format in ipairs(formats) do
    print(index, format, string.format(format, value))
  end
end

-- String conversion and integer-to-real conversion take distinct owned paths.
for _, text in ipairs({"  0x1.8p+2  ", "1.0000000000000001", "1e-4000"}) do
  print("string", text, string.format("%.17g", text))
end
print("integer", string.format("%.17g", math.maxinteger))
print("FORMAT CAMPAIGN OK")
