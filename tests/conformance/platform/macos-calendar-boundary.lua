-- Darwin's mktime does not reject a seconds carry at INT_MAX tm_year.
-- Pinned C-oracle observations show it discards the day carry, retaining
-- December 31. Verify that exact native behavior, and separately exercise
-- rejection at the actual calendar-field boundary followed by recovery.
local maximum = (1 << 31) + 1899
local function date(second)
  return {year=maximum, month=12, day=31, hour=23, min=59, sec=second}
end
local last = assert(os.time(date(59)))
for second = 60, 61 do
  local value = date(second)
  local stamp = assert(os.time(value))
  assert(stamp == last - 86399 + second - 60)
  assert(value.year == maximum and value.month == 12 and value.day == 31)
  assert(value.hour == 0 and value.min == 0 and value.sec == second - 60)
  local decoded = assert(os.date('*t', stamp))
  assert(decoded.year == value.year and decoded.month == value.month)
  assert(decoded.day == value.day and decoded.hour == value.hour)
  assert(decoded.min == value.min and decoded.sec == value.sec)
  assert(os.time(decoded) == stamp)
end
local ok, message = pcall(os.time, {year=maximum+1, month=1, day=1})
assert(not ok and message:find("field 'year' is out-of-bound", 1, true))
local ordinary = {year=2000, month=1, day=2, hour=12, min=34, sec=56}
local stamp = assert(os.time(ordinary))
assert(os.time(os.date('*t', stamp)) == stamp)
print('native macOS calendar boundary counterpart OK')
