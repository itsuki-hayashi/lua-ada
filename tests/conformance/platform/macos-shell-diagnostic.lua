-- Diagnostic observations for files.lua:795-801 at pinned Lua 5.5.1.
-- This does not replace an assertion or confer equivalence acceptance.
-- Flush each row so a later original-file failure retains its native cause.
local commands = {
  {'list', 'ls > /dev/null'},
  {'missing', 'not-to-be-found-command'},
  {'exit3', 'exit 3'},
  {'exit129', 'exit 129'},
  {'directHUP', 'kill -s HUP $$'},
  {'directKILL', 'kill -s KILL $$'},
  {'nestedHUP', "sh -c 'kill -s HUP $$'"},
  {'nestedWaitHUP', "sh -c 'kill -s HUP $$'; result=$?; exit $result"},
}
local traps = assert(io.popen('trap', 'r'))
local text = assert(traps:read('a'))
assert(traps:close())
print('native shell diagnostic traps=' .. string.format('%q', text))
for _, row in ipairs(commands) do
  local pipe = assert(io.popen(row[2]))
  local a, b, c = pipe:close()
  local x, y, z = os.execute(row[2])
  print(('native shell diagnostic %s: popen=%s,%s,%s execute=%s,%s,%s')
        :format(row[1], tostring(a), tostring(b), tostring(c),
                tostring(x), tostring(y), tostring(z)))
  assert(io.stdout:flush())
end

-- Observe Darwin's upper calendar boundary before the unchanged date tests.
-- These rows are diagnostic only: neither success nor failure substitutes for
-- an assertion. Record the mutated calendar as well as the native result so
-- a normalization difference can be distinguished from allocator/runtime bugs.
for _, second in ipairs({59, 60, 61}) do
  local calendar = {year = (1 << 31) + 1899, month = 12, day = 31,
                    hour = 23, min = 59, sec = second}
  local ok, result = pcall(os.time, calendar)
  print(('native date diagnostic sec=%d: ok=%s result=%s calendar=%s/%s/%s %s:%s:%s')
        :format(second, tostring(ok), tostring(result), tostring(calendar.year),
                tostring(calendar.month), tostring(calendar.day),
                tostring(calendar.hour), tostring(calendar.min),
                tostring(calendar.sec)))
  if ok then
    local roundtrip, decoded = pcall(os.date, '*t', result)
    if roundtrip then
      print(('native date roundtrip sec=%d: %s/%s/%s %s:%s:%s')
            :format(second, tostring(decoded.year), tostring(decoded.month),
                    tostring(decoded.day), tostring(decoded.hour),
                    tostring(decoded.min), tostring(decoded.sec)))
    else
      print(('native date roundtrip sec=%d: error=%s')
            :format(second, tostring(decoded)))
    end
  end
  assert(io.stdout:flush())
end
local ok, result = pcall(os.time,
                        {year = (1 << 31) + 1900, month = 1, day = 1})
print(('native date diagnostic next-year: ok=%s result=%s')
      :format(tostring(ok), tostring(result)))
assert(io.stdout:flush())
