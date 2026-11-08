local function check(source, message)
  local f, err = load(source, '=diag')
  assert(f == nil and err == 'diag:1: ' .. message, err)
end
check('*a=123', "unexpected symbol near '*'")
check('local', '<name> expected near <eof>')
check("'aa'", "unexpected symbol near ''aa''")
check('[==[aa]==]', "unexpected symbol near '[==[aa]==]'")
check(string.char(1), "unexpected symbol near '<\\1>'")
check(string.char(255), "unexpected symbol near '<\\255>'")
check('1.000', "unexpected symbol near '1.000'")
check('local a <const> = 1; a=2',
      "attempt to assign to const variable 'a'")
check('break; print(1)', "break outside loop near 'break'")
local f, message = load('local')
assert(not f and message == '[string "local"]:1: <name> expected near <eof>')
local done = false
f, message = load(function()
  if done then return nil end
  done = true
  return '*a=123'
end)
assert(not f and message == "(load):1: unexpected symbol near '*'")
local source = 'return 10' .. string.rep(',10', 253)
assert(select('#', assert(load(source))()) == 254)
f, message = load(source .. ',10')
assert(not f and message:find('too many returns', 1, true))
check('goto absent', "no visible label 'absent' for <goto> at line 1")
check('::L:: ::L::', "label 'L' already defined on line 1")
check('goto L; local a; ::L:: print(a)',
      "<goto L> at line 1 jumps into the scope of 'a'")
check("'a" .. string.char(0) .. "b'", "unexpected symbol near ''a'")
f, message = load('local', '=name' .. string.char(0) .. 'tail')
assert(not f and message == 'name:1: <name> expected near <eof>')
local c = assert(load('return 42', '=name' .. string.char(0) .. 'tail'))
assert(debug.getinfo(c, 'S').source == '=name')
print('syntax diagnostic tokens OK')
