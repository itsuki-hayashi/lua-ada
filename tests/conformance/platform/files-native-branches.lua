-- Host-adaptive counterparts for the native branches in pinned files.lua.
-- The facts below identify the branch actually available on this host.  They
-- never claim that an inactive upstream branch executed.  Both the independent
-- C oracle and the Ada implementation must execute every named counterpart.
local function rejected (expected, f, ...)
  local ok, message = pcall(f, ...)
  assert(not ok and type(message) == 'string')
  assert(message:find('out%-of%-bound') or message:find('represented'))
  if expected then assert(message:find(expected, 1, true)) end
  return message:find('out%-of%-bound') and 'field-bound' or 'representation'
end

local function calendar (dst)
  return {year=2000, month=1, day=2, hour=12, min=34, sec=56, isdst=dst}
end

local cint = string.packsize('i')
local integer = string.packsize('j')
assert(cint == 4 or cint == 8)
assert(integer == 4 or integer == 8)
print(('native branch facts: cint=%d lua_integer=%d'):format(cint, integer))

-- The eight-byte-C-int source branch asks whether the date fields can hold a
-- very large year.  On a four-byte-C-int host the corresponding obligation is
-- rejection at that actual field boundary, followed by usable date conversion.
-- Keep this distinct from the native time_t range probe below.
if cint == 4 and integer == 8 then
  rejected("field 'year' is out-of-bound", os.time,
           {year=(1 << 31)+1900, month=1, day=1})
  rejected("field 'day' is out-of-bound", os.time,
           {year=2000, month=1, day=1 << 32})
  rejected("field 'month' is out-of-bound", os.time,
           {year=2000, month=-((1 << 31)+1), day=1})
elseif cint == 8 and integer == 8 then
  -- Exactly the representability distinction of the wide-C-int source arm.
  assert(tonumber(os.date('%Y', 1 << 60)))
  rejected('represented', os.time, {year=1 << 60, month=1, day=1})
else
  -- A narrow Lua integer cannot supply an out-of-C-int integer.  Its actual
  -- maximum timestamp must still yield a self-consistent native date table.
  local d = os.date('*t', math.maxinteger)
  assert(os.time(d) == math.maxinteger)
end
local normal = os.time(calendar(nil))
assert(os.time(os.date('*t', normal)) == normal)
print('native C-int field boundary counterpart OK')

-- files.lua chooses its time_t branch with a protected conversion at 2^40.
-- Probe the same value and record the actual outcome, including CRT range
-- restrictions.  Successful conversion must round-trip; failed conversion
-- must be the expected native range error and must leave later calls usable.
local ok, year = pcall(os.date, '%Y', 2^40)
if ok then
  assert(tonumber(year))
  local date = os.date('*t', 2^40)
  assert(type(date) == 'table' and type(date.year) == 'number')
  assert(os.time(date) == 2^40)
  print('native branch facts: time_2pow40=representable')
else
  local reason = rejected(nil, os.date, '%Y', 2^40)
  assert(os.time(os.date('*t', normal)) == normal)
  print('native branch facts: time_2pow40=' .. reason)
end
-- The inactive narrow-time_t arm explicitly checks year 4000.  Exercise that
-- same calendar input against this host's capacity instead of merely probing
-- timestamp formatting, then require conversion remains usable on failure.
local far = {year=4000, month=1, day=1, hour=12, min=0, sec=0}
local farok, instant = pcall(os.time, far)
if farok then
  assert(os.time(os.date('*t', instant)) == instant)
  assert(os.date('*t', instant).year == 4000)
  print('native branch facts: year4000=representable')
else
  rejected('represented', os.time,
           {year=4000, month=1, day=1, hour=12, min=0, sec=0})
  assert(os.time(os.date('*t', normal)) == normal)
  print('native branch facts: year4000=representation')
end
print('native time range recovery counterpart OK')

-- The source permits a missing native isdst field.  Record that observation;
-- independently exercise omission in input even when this host always returns
-- a boolean.  Explicit true/false input must normalize to a date table that
-- reconstructs the same resulting instant; no particular timezone is assumed.
local observed = os.date('*t', normal).isdst
assert(observed == nil or type(observed) == 'boolean')
print('native branch facts: isdst=' .. (observed == nil and 'absent' or 'boolean'))
local inferred = os.date('*t', normal)
inferred.isdst = nil
assert(os.time(inferred) == normal)
for _, mode in ipairs({'omitted', 'false', 'true'}) do
  local d = calendar(nil)
  if mode == 'false' then d.isdst = false end
  if mode == 'true' then d.isdst = true end
  local instant = os.time(d)
  assert(type(instant) == 'number')
  assert(os.time(os.date('*t', instant)) == instant)
end
print('native DST inference counterpart OK')
