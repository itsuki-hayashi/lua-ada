-- First-party counterpart for the Windows-absent T.nonblock block.
-- The CRT refuses oversized nonblocking writes atomically. Earlier arguments
-- still count as actual partial progress in Lua's multiargument file:write.
local f = _test_failing_stream(assert(io.tmpfile()))
assert(f:setvbuf('no'))
local ok, message, err, count = f:write('abcd')
assert(ok == nil and type(message) == 'string' and err > 0 and count == 0)
assert(f:close())

local writer, reader = assert(io.tmpfile()), assert(io.tmpfile())
local a, b = _test_nonblocking_pair(writer, reader)
assert(a == writer and b == reader)
assert(writer:setvbuf('no'))
assert(reader:setvbuf('no'))
assert(writer:write(string.rep('a', 100)))
ok, message, err, count = writer:write(string.rep('b', 10000), string.rep('c', 2^17))
assert(ok == nil and type(message) == 'string' and err > 0 and count == 10000)
assert(reader:read(10100) == string.rep('a', 100) .. string.rep('b', 10000))
assert(writer:close())
assert(reader:read(1) == nil)
assert(reader:close())
print('native Windows partial write counterpart OK')
