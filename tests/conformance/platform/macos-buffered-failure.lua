-- First-party native counterpart for the macOS-absent /dev/full device.
-- Preserve the public FILE/closer, default-stream ownership, repeated failed
-- flush ordering and physical close. Run identically against C and Ada.
local old = io.output()
local f = assert(io.tmpfile())
assert(_test_failing_stream(f) == f)
io.output(f)
assert(f:write('abcd') == f, 'macOS first buffered write')
local ok, message, code = f:flush()
assert(ok == nil and type(message) == 'string' and code > 0,
       'macOS first native flush')
assert(f:write('abcd') == f, 'macOS second buffered write')
ok, message, code = io.flush()
assert(ok == nil and type(message) == 'string' and code > 0,
       'macOS second native flush')
local closed, close_message, close_code = f:close()
assert(closed == nil and type(close_message) == 'string' and close_code > 0,
       'macOS native buffered close error')
assert(io.type(f) == 'closed file')
io.output(old)
assert(not pcall(_test_failing_stream, {}))
assert(not pcall(_test_failing_stream, f))
-- Unlike buffered close, an unbuffered refusal has no queued bytes to retry.
local unbuffered = _test_failing_stream(assert(io.tmpfile()))
assert(unbuffered:setvbuf('no'))
local result, message, code, count = unbuffered:write('abcd')
assert(result == nil and type(message) == 'string' and code > 0 and count == 0)
assert(unbuffered:close())
assert(io.type(unbuffered) == 'closed file')
print('native macOS buffered failure counterpart OK')
