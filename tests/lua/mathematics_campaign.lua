-- First-party deterministic mathematics/RNG differential campaign.
-- Fixed seed pairs and binary encodings preserve every random/float bit.
-- This is focused compatibility evidence, not an upstream-suite substitute.
global <const> *
local function realbits(value)
  return (string.pack(">d", value):gsub(".", function(byte)
    return string.format("%02x", string.byte(byte))
  end))
end

local seeds = {
  {0, 0}, {17, -9}, {math.maxinteger, math.mininteger}, {-1, -1},
}
for pair, seed in ipairs(seeds) do
  print("seed", pair, math.randomseed(seed[1], seed[2]))
  for case = 1, 128 do
    -- Alternate float extraction, full-width words and several interval
    -- shapes. Rejection sampling changes all later results if biased or if
    -- it consumes the wrong number of generator transitions.
    local family = case % 6
    local result
    if family == 0 then result = realbits(math.random())
    elseif family == 1 then result = string.format("%016x", math.random(0))
    elseif family == 2 then result = math.random(-17, 25)
    elseif family == 3 then
      result = math.random(math.mininteger, math.maxinteger)
    elseif family == 4 then result = math.random(0, 1 << 40)
    else result = math.random(1)
    end
    print("random", pair, case, family, result)
  end
end

local smallest = string.unpack(">d", "\0\0\0\0\0\0\0\1")
local inputs = {-1, -0.0, 0, smallest, 0.5, 1, 2, math.huge, -math.huge, 0/0}
local names = {
  "sin", "cos", "tan", "asin", "acos", "atan", "exp", "sqrt",
  "deg", "rad", "frexp", "log",
}
for _, name in ipairs(names) do
  for index, value in ipairs(inputs) do
    -- Numeric exceptional values are ordinary results. Pack them instead
    -- of hiding signs/payloads behind decimal or textual NaN formatting.
    local result, exponent = math[name](value)
    -- C frexp does not specify the exponent for infinity/NaN. Compare its
    -- fraction result, while finite cases retain both observable outputs.
    if name == "frexp" and
       (value ~= value or value == math.huge or value == -math.huge) then
      exponent = nil
    end
    print(name, index, realbits(result), exponent)
  end
end
for _, base in ipairs({2, 10, 1, -1, 0, math.huge}) do
  for index, value in ipairs(inputs) do
    print("logbase", realbits(base), index, realbits(math.log(value, base)))
  end
end
for _, exponent in ipairs({-1074, -1073, 0, 1, 1024, 1 << 32 | 1,
                          math.mininteger, math.maxinteger}) do
  print("ldexp", exponent, realbits(math.ldexp(0.75, exponent)))
end

-- Pinned Lua draws a random word before argument validation. Failed calls
-- therefore consume a word; invalid randomseed calls leave the old seed alone.
math.randomseed(0, 0)
for _, arguments in ipairs({{false}, {1, 2, 3}, {-1}, {3, 2}, {0.5}}) do
  local ok = pcall(math.random, table.unpack(arguments))
  print("protected", ok, string.format("%016x", math.random(0)))
end
local badseed = pcall(math.randomseed, nil)
print("badseed", badseed)
print("afterbadseed", string.format("%016x", math.random(0)))
print("numericstrings", realbits(math.cos("0x0p0")),
      realbits(math.ldexp("0.75", "1")))
local x, y = math.randomseed(-7, nil)
print("optionalseed", x, y)

-- Compatibility exports are present only in the instrumented profile.
-- Do not turn their deliberate absence from default into a skipped test.
print("compatibility", math.pow ~= nil)
if math.pow then
  print("compat", realbits(math.pow(-2, 3)), realbits(math.log10(100)),
        realbits(math.cosh(0)), realbits(math.sinh(-0.0)),
        realbits(math.tanh(-0.0)), realbits(math.atan2(-0.0, -1)))
end
