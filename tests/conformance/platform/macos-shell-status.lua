-- Darwin's shell may execute its final nested shell directly. Keep an outer
-- shell alive to wait for the nested HUP, preserving the upstream distinction
-- between direct signal termination and a shell reporting its child's status.
local function check(command, kind, code)
  local pipe = assert(io.popen(command))
  local a, b, c = pipe:close()
  local x, y, z = os.execute(command)
  assert(a == nil and x == nil and b == kind and y == kind)
  assert(c == code and z == code)
end
check('kill -s HUP $$', 'signal', 1)
check('kill -s KILL $$', 'signal', 9)
check("sh -c 'kill -s HUP $$'; result=$?; exit $result", 'exit', 129)
print('native macOS nested shell status counterpart OK')
