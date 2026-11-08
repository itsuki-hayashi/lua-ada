-- Native Windows transport counterpart; never an adapted main.lua.
-- Run in a fresh disposable directory with a frozen image path containing
-- spaces. Original main source, SIGINT, readline and TTY gates stay separate.
assert(package.config:sub(1, 1) == '\\')
local interpreter = assert(arg[1])
local configuration = assert(arg[2])
assert(interpreter:find(' ', 1, true))
-- These authored controlled names deliberately exclude cmd expansions and
-- metacharacters. They are not a general shell-escaping implementation.
assert(not interpreter:find('["%%!&|<>%^\r\n]'))
local function quote(s)
  assert(not s:find('["%%!&|<>%^\r\n]'))
  assert(s:sub(-1) ~= '\\')
  return '"' .. s .. '"'
end
local function command(arguments)
  -- Native cmd /C strips the first/last quote when several quoted operands
  -- follow a quoted executable. The outer pair protects the executable pair.
  return '"' .. quote(interpreter) .. ' ' .. arguments .. '"'
end
local function mark(name)
  print('PASS: windows-main-transport-' .. name)
end
local names, raw = {}, {}
for i = 1, 3 do
  raw[i] = os.tmpname()  -- retain each actual native generator call
  assert(raw[i]:sub(1, 1) == '\\')
  local leaf = raw[i]:sub(2)
  assert(#leaf > 0 and not leaf:find('[\\/:]'))
  -- tmpnam may contain a trailing dot or a numeric dot suffix. A plain
  -- generated leaf is also a valid module name: require rewrites dots.
  -- Keep the actual generator, and assert all mapped names are distinct.
  assert(leaf:match('^[%w_.-]+$'))
  names[i] = (leaf:gsub('%.', '_'))
  for j = 1, i - 1 do assert(names[i] ~= names[j]) end
  local f, message, code = io.open(names[i], 'rb')
  assert(f == nil and type(message) == 'string' and code == 2)
end
mark('fresh-private-paths')
local prog, otherprog, out = table.unpack(names)
local function write(path, text)
  local f = assert(io.open(path, 'wb'))
  assert(f:write(text))
  assert(f:close())
end
local function take()
  local f = assert(io.open(out))
  local value = assert(f:read('a'))
  assert(f:close())
  assert(os.remove(out))
  return value
end
local function run(arguments)
  local ok, kind, code = os.execute(command(arguments))
  assert(ok == true and kind == 'exit' and code == 0)
end
run('-v > ' .. quote(out))
assert(take():find('Lua 5.5.1', 1, true))
mark('actual-version-redirection')
write(prog, '')
run('- < ' .. quote(prog) .. ' > ' .. quote(out))
assert(take() == '')
mark('empty-explicit-stdin')
write(prog, 'print(10)\nprint(2)\n')
run('- -- < ' .. quote(prog) .. ' > ' .. quote(out))
assert(take() == '10\n2\n')
mark('multiline-explicit-stdin')
local ok, kind, code = os.execute('type ' .. quote(prog) .. ' | ' ..
  quote(interpreter) .. ' - > ' .. quote(out))
assert(ok == true and kind == 'exit' and code == 0)
assert(take() == '10\n2\n')
mark('native-type-pipe')
-- Main240 and260 place paths into Lua literals without escaping. Establish
-- the actual Windows failure independently, then prove %q retains all bytes.
assert(load("return '" .. raw[1] .. "'") == nil)
assert(load("return '" .. interpreter .. "'") == nil)
assert(assert(load(('return %q'):format(raw[1])))() == raw[1])
assert(assert(load(('return %q'):format(interpreter)))() == interpreter)
mark('literal-path-counterpart')
write(prog, ('assert(arg[-1]=="--" and arg[-2]=="-e " and arg[-3]==%q);' ..
  'assert(arg[1]=="a" and arg[2]=="b" and arg[3]=="c");' ..
  'local a,b,c=...;assert(a=="a" and b=="b" and c=="c");print("ARGS")\n'):
  format(interpreter))
run('"-e " -- ' .. quote(prog) .. ' a b c > ' .. quote(out))
assert(take() == 'ARGS\n')
mark('exact-argv-selected-child')
-- Native Windows SET applies only to the shell child and its Lua child.
-- This is a new counterpart for a small env block, not an env -i emulator.
write(prog, 'assert(package.path=="x");print("ENV")\n')
ok, kind, code = os.execute('set "LUA_INIT="&&set "LUA_INIT_5_5="&&' ..
  'set "LUA_PATH_5_5="&&set "LUA_PATH=x"&&' ..
  quote(interpreter) .. ' ' .. quote(prog) .. ' > ' .. quote(out))
assert(ok == true and kind == 'exit' and code == 0)
assert(take() == 'ENV\n')
mark('native-set-environment')
-- A replacement library name is a Lua value; %q makes that independent of
-- both cmd quoting and the native path separator spelling.
write(prog, 'print(1);return {x=15}\n')
write(otherprog, ('assert(_G[%q].x==15);print("LIB")\n'):format(prog))
ok, kind, code = os.execute('set "LUA_PATH=?;;"&&' ..
  quote(interpreter) .. ' -l ' .. quote(prog) .. ' ' .. quote(otherprog) .. ' > ' .. quote(out))
assert(ok == true and kind == 'exit' and code == 0)
assert(take() == '1\nLIB\n')
mark('actual-require-literal-name')
write(prog, 'io.write("OUT");io.stderr:write("ERR")\n')
run(quote(prog) .. ' > ' .. quote(out) .. ' 2>&1')
local merged = take()
assert(merged:find('OUT', 1, true) and merged:find('ERR', 1, true))
mark('stdout-stderr-routing')
write(prog, 'error("MAIN TRANSPORT FAILURE",0)\n')
ok, kind, code = os.execute(command(quote(prog) .. ' > ' .. quote(out) .. ' 2>&1'))
assert(ok == nil and kind == 'exit' and code == 1)
assert(take():find('MAIN TRANSPORT FAILURE', 1, true))
mark('actual-child-failure-status')
local pipe = assert(io.popen(command('--conformance-config'), 'r'))
local config = assert(pipe:read('a'))
ok, kind, code = pipe:close()
assert(ok == true and kind == 'exit' and code == 0)
assert(config:find('"configuration":"' .. configuration .. '"', 1, true))
assert(config:find('"allocator_limit_bytes":2147483648', 1, true))
mark('actual-popen-child-identity')
assert(os.remove(prog))
assert(os.remove(otherprog))
assert(not os.remove(out))
mark('owned-temp-cleanup')
