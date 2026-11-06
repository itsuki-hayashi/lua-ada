-- Named, first-party counterparts for Windows-specific files.lua assumptions.
local function test(name, body)
  local ok, message = pcall(body)
  assert(ok, name .. ': ' .. tostring(message))
end
local function rejected(pattern, f, ...)
  local ok, message = pcall(f, ...)
  assert(not ok and tostring(message):find(pattern, 1, true))
end

test('temporary-name lifecycle', function()
  local name = (os.tmpname():gsub('^[/\\]+', ''))
  local f = assert(io.open(name, 'wb'))
  assert(f:write('temporary\0bytes'))
  assert(f:close())
  f = assert(io.open(name, 'rb'))
  assert(f:read('a') == 'temporary\0bytes')
  assert(f:close())
  assert(os.remove(name))
end)

test('native stdin and invalid seek', function()
  local position, message, code = io.stdin:seek('set', 1000)
  assert(position == 1000 and message == nil and code == nil)
  local f = assert(io.tmpfile())
  position, message, code = f:seek('set', -1)
  assert(position == nil and type(message) == 'string' and type(code) == 'number')
  assert(f:close())
end)

test('native null device', function()
  local f = assert(io.open('NUL', 'w'))
  assert(f:write('discarded'))
  assert(f:flush())
  assert(f:close())
end)

test('same implementation pipe copy', function()
  local name = (os.tmpname():gsub('^[/\\]+', ''))
  local writer = assert(io.popen([[lua -e "io.write(io.read('a'))" > ]] .. name, 'w'))
  assert(writer:write('copied bytes'))
  assert(writer:close())
  local reader = assert(io.popen([[lua -e "io.write(io.read('a'))" < ]] .. name, 'r'))
  assert(reader:read('a') == 'copied bytes')
  assert(reader:close())
  assert(os.remove(name))
end)

test('bare and arg child configuration', function()
  local check = T and "assert(T and T.checkmemory and T.alloccount)" or "assert(T==nil)"
  check = check .. "; assert(_soft==nil and _port==nil)"
  assert(os.execute('lua -e "' .. check .. '"'))
  local i = 0
  while arg[i] do i = i - 1 end
  assert(os.execute('""' .. arg[i + 1] .. '" -e "' .. check .. '""'))
end)

test('forced termination and shell status', function()
  for _, command in ipairs{'native-terminate 129', 'native-terminate 137',
                           'cmd /c native-terminate 129'} do
    local code = tonumber(command:match('(%d+)$'))
    local ok, what, actual = assert(io.popen(command)):close()
    assert(ok == nil and what == 'exit' and actual == code)
    ok, what, actual = os.execute(command)
    assert(ok == nil and what == 'exit' and actual == code)
  end
  local ok, what, code = os.execute('dir > NUL')
  assert(ok and what == 'exit' and code == 0)
end)

test('quoted executable and typed exit', function()
  local i = 0
  while arg[i] do i = i - 1 end
  local program = '"' .. arg[i + 1] .. '"'
  for _, code in ipairs{0, 20} do
    local command = '"' .. program .. ' -e "os.exit(' .. code .. ', true)""'
    local ok, what, actual = assert(io.popen(command)):close()
    assert((code == 0 and ok == true or code ~= 0 and ok == nil))
    assert(what == 'exit' and actual == code)
    local other, kind, value = os.execute(command)
    assert(other == ok and kind == what and value == actual)
  end
end)

test('unsupported native date modifiers', function()
  rejected('invalid conversion specifier', os.date, '%Ex')
  rejected('invalid conversion specifier', os.date, '%Oy')
end)

test('large signed date normalization', function()
  local before = os.time{year=2100, month=1, day=0}
  local after = os.time{year=2100, month=1, day=0, sec=(1 << 31)-1}
  assert(after-before == (1 << 31)-1)
  before = os.time{year=2100, month=1, day=1}
  after = os.time{year=2100, month=1, day=1, sec=-(1 << 31)}
  assert(after-before == -(1 << 31))
end)

test('native year representability', function()
  assert(tonumber(os.time{year=3000, month=12, day=31, hour=12, min=0, sec=0}))
  rejected('represented', os.time,
           {year=(1 << 31)+1899, month=12, day=31, hour=23, min=59, sec=59})
end)
print('native Windows file contracts OK')
