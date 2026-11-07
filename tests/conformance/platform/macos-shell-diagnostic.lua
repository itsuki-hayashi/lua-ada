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
