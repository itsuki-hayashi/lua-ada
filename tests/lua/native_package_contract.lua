-- Public package boundaries, runnable unchanged on C Lua and Lua Ada.
-- Copyright (c) 2026 Lua Ada contributors. MIT; see ../../LICENSE.
local function check(name, body)
  body()
  print('PASS: native-package-' .. name)
end

check('empty-templates', function()
  local n = string.char(10, 9)
  local f, e = package.searchpath('absent', ';?.none;;')
  assert(f == nil and e == "no file ''" .. n .. "no file 'absent.none'" ..
    n .. "no file ''" .. n .. "no file ''")
  f, e = package.searchpath('absent', '')
  assert(f == nil and e == "no file ''")
end)

check('c-string-parameters', function()
  local z = string.char(0)
  local f, e = package.searchpath('absent' .. z .. 'tail',
    '?.none' .. z .. 'discard', '.' .. z .. 'tail', '/' .. z .. 'tail')
  assert(f == nil and e == "no file 'absent.none'")
end)

check('c-string-module-key', function()
  local name = 'nul' .. string.char(0) .. 'tail'
  package.loaded[name] = 17
  package.preload.nul = function(n, data)
    assert(n == name and data == ':preload:')
    return 9
  end
  assert(require(name) == 9)
  assert(package.loaded.nul == 9 and package.loaded[name] == 17)
end)

check('loadlib-alias', function()
  local ok, e = pcall(function()
    local alias = package.loadlib
    alias(nil, 'x')
  end)
  assert(not ok and e:find(
    "bad argument #1 to 'alias' (string expected, got nil)", 1, true))
end)

check('loadlib-absent-argument', function()
  local ok, e = pcall(function()
    local alias = package.loadlib
    alias()
  end)
  assert(not ok and e:find(
    "bad argument #1 to 'alias' (string expected, got no value)", 1, true))
end)

check('loadlib-method-self', function()
  local t = {open = package.loadlib}
  local ok, e = pcall(function() t:open('x') end)
  assert(not ok and e:find(
    "calling 'open' on bad self (string expected, got table)", 1, true))
end)

check('loadlib-custom-type', function()
  local alias = package.loadlib
  local value = setmetatable({}, {__name = 'fixture', __metatable = false})
  local ok, e = pcall(function() alias('missing', value) end)
  assert(not ok and e:find(
    "bad argument #2 to 'alias' (string expected, got fixture)", 1, true))
end)

check('missing-open-result', function()
  local f, e, stage = package.loadlib('absent-lua-ada-fixture', 'x')
  assert(f == nil and type(e) == 'string' and stage == 'open')
end)
