-- Compiled literals share the owning program's immutable string identity.
local literal = '01234567890123456789012345678901234567890123456789'
local function nested()
  return '01234567890123456789012345678901234567890123456789'
end
assert(string.format('%p', literal) == string.format('%p', nested()))
print('nested literal identity', 'OK')

-- Dynamically produced long strings retain separate storage despite equal
-- contents; compiled pooling must not become global runtime interning.
local prefix = '0123456789'
local dynamic = prefix .. '0123456789012345678901234567890123456789'
assert(dynamic == literal)
assert(string.format('%p', dynamic) ~= string.format('%p', literal))
print('dynamic string identity', 'OK')

-- Surviving closures own their graph after the compiling chunk disappears.
local f = assert(load([[return function()
  return '01234567890123456789012345678901234567890123456789'
end]]))()
local saved = f()
collectgarbage()
collectgarbage()
assert(saved == f())
assert(string.format('%p', saved) == string.format('%p', f()))
print('retained literal identity', 'OK')
