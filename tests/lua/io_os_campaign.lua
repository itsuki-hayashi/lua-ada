-- First-party raw-byte IO/OS differential. Seed: (0x527a91, -1907).
-- Run each interpreter independently in the same working directory. Every
-- native temporary file is closed; this fixture creates no named input file.
-- stdout deliberately includes NUL/high bytes: compare complete raw streams.
global <const> *
math.randomseed(0x527a91, -1907)

for case = 0, 128 do
  local parts = {}
  local size = (case * 73) % 513
  for i = 1, size do
    parts[i] = string.char(math.random(0, 255))
  end
  local bytes = table.concat(parts)
  local f = assert(io.tmpfile())
  assert(f:write(bytes) == f)
  assert(f:seek('set') == 0)
  local wanted = (case * 19) % (size + 4)
  local first = f:read(wanted)
  local rest = f:read('a')
  local expected = bytes:sub(1, wanted)
  if wanted == 0 and size == 0 or wanted > 0 and size == 0 then
    assert(first == nil)
  else
    assert(first == expected)
  end
  assert((first or '') .. rest == bytes)
  io.write(string.pack('<I2I2I2', case, size, #(first or '')))
  io.stdout:write(bytes, first or '', rest)
  print('bytes', case, size, wanted, first ~= nil, #rest, f:seek())
  assert(f:close())
  assert(io.type(f) == 'closed file')
end

for case = 1, 64 do
  local f = assert(io.tmpfile())
  local size = (case * 31) % 257
  local first = string.rep(string.char(case % 9 + 65, 0, 255), size)
  f:write(first, '\n\nlast')
  f:seek('set')
  local iterator = f:lines('L')
  local a, b, c = iterator(), iterator(), iterator()
  assert(a == first .. '\n' and b == '\n' and c == 'last')
  assert(select('#', iterator()) == 0)
  io.write(a, b, c)
  print('lines', case, #a, #b, #c, io.type(f))
  assert(f:close())
end

local numerals = {
  '  -1.25e2;', '+0x1.8p+2!', '1e+z', '0xe+1$', '.5?', '0x.p0?',
  '0XffP-1|', '  +00012.50e-1#', '-0;', '0x8000000000000000!',
  'nan!', 'infinity?', string.rep('1', 200) .. '!',
  string.rep('1', 201) .. '!', '2.5e-324;', '1e309!', '0x1p-1074?'
}
for case, text in ipairs(numerals) do
  local f = assert(io.tmpfile())
  f:write(text)
  f:seek('set')
  local value = f:read('*number suffix')
  local rest = f:read('a')
  print('number', case, value, math.type(value), #rest, f:seek())
  io.write(rest)
  print('end-number', case)
  assert(f:close())
end

-- Validate sequential effects, not implementation-dependent diagnostic names.
for case = 1, 32 do
  local f = assert(io.tmpfile())
  local text = string.rep(string.char(case, 0, 255), case)
  f:write(text)
  f:seek('set')
  local ok, message = pcall(f.read, f, case, '?')
  assert(not ok and message:find('invalid format', 1, true))
  local rest = f:read('a')
  assert(rest == text:sub(case + 1))
  local too_large, large_message = pcall(f.read, f, -1)
  assert(not too_large and large_message:find('resulting string too large',
                                            1, true))
  io.write(rest)
  print('effects', case, #rest)
  assert(f:close())
end

for _, stamp in ipairs{0, 1, 60, 86400, 946684800, 1700000000} do
  local d = os.date('!*t', stamp)
  print('date', stamp, os.date('!%Y-%m-%d %H:%M:%S', stamp),
        d.year, d.month, d.day, d.hour, d.min, d.sec, d.wday, d.yday, d.isdst)
  assert(os.date('x\0y', stamp) == 'x\0y')
end
assert(os.difftime(1700000001, 1700000000) == 1.0)

-- Real normalized date fields use ordered metamethod callbacks. The actual
-- timestamp depends on the same host timezone and is compared directly.
for case = 1, 32 do
  local reads, writes = {}, {}
  local input = {year=2020 + case % 5, month=case % 14 + 1,
                 day=case % 35 + 1, hour=12, min=case % 60, sec=0}
  local date = setmetatable({}, {
    __index=function(_, key)
      reads[#reads + 1] = key
      return input[key]
    end,
    __newindex=function(self, key, value)
      writes[#writes + 1] = key
      rawset(self, key, value)
    end
  })
  local stamp = os.time(date)
  print('normalize', case, stamp, table.concat(reads, ','),
        table.concat(writes, ','), date.year, date.month, date.day,
        date.hour, date.min, date.sec, date.wday, date.yday, date.isdst)
end

-- A real file's finalizer closes it; a replacement handler may resurrect it
-- without hidden fallback close. Restore the shared FILE* metatable each time.
for case = 1, 16 do
  --  Drain earlier manually closed files through their original handler;
  --  the replacement below must observe only this iteration's new target.
  collectgarbage()
  collectgarbage()
  local f = assert(io.tmpfile())
  local meta, held = getmetatable(f)
  local original = meta.__gc
  meta.__gc = function(file) held = file end
  f = nil
  collectgarbage()
  meta.__gc = original
  assert(io.type(held) == 'file')
  held:write('alive', string.char(case, 0, 255))
  held:seek('set')
  local payload = held:read('a')
  assert(payload == 'alive' .. string.char(case, 0, 255))
  io.write(payload)
  print('resurrection', case, io.type(held))
  held:close()
  held = nil
  collectgarbage()
end
io.flush()
print('IO-OS-CAMPAIGN-OK')
