-- First-party native counterpart for the macOS-absent /dev/full device.
-- Preserve the public FILE/closer, default-stream ownership, repeated failed
-- flush ordering and physical close. Run identically against C and Ada.
local old = io.output()
local f = assert(io.tmpfile())
assert(_test_failing_stream(f) == f)
io.output(f)
assert(f:write('abcd') == f)
local ok, message, code = f:flush()
assert(ok == nil and type(message) == 'string' and code > 0)
assert(f:write('abcd') == f)
ok, message, code = io.flush()
assert(ok == nil and type(message) == 'string' and code > 0)
assert(f:close())
assert(io.type(f) == 'closed file')
io.output(old)
assert(not pcall(_test_failing_stream, {}))
assert(not pcall(_test_failing_stream, f))
print('native macOS buffered failure counterpart OK')
