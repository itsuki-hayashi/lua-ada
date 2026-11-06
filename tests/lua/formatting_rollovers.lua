-- Native alternate-general formatting differs when rounding changes notation.
-- Exact binary quarters vary sign/precision/exponent without relying on one
-- decimal input. C and Ada must agree on raw same-host output; no masks/skips.
global <const> *
for precision = 1, 12 do
  local boundary = 10.0 ^ precision
  local formats = {
    "%#." .. precision .. "g", "%#." .. precision .. "G",
    "%#020." .. precision .. "g", "%." .. precision .. "g",
    "%#." .. (precision - 1) .. "e",
  }
  for _, sign in ipairs({1, -1}) do
    local value = sign * (boundary - 0.25)
    for _, format in ipairs(formats) do
      print("carry", precision, sign, format, string.format(format, value))
    end
  end
  if precision > 1 then
    -- Already scientific and non-transitioning fixed values retain ordinary
    -- alternate precision. A blanket removal of zeroes fails these guards.
    local format = "%#." .. precision .. "g"
    print("stable", precision, string.format(format, boundary),
          string.format(format, boundary - 10))
  end
end
print("FORMAT ROLLOVER CAMPAIGN OK")
