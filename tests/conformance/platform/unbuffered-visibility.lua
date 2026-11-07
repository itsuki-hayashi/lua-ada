-- First-party file buffering regression shared by the C and Ada launchers.
-- The upstream no-buffer example ignores a write on a read-only file. Here
-- a second real handle must observe bytes before the writer flushes/closes.
local name = os.tmpname()
if package.config:sub(1, 1) == '\\' then
  name = name:gsub('^[/\\]+', '')
end
do
  local writer <close> = assert(io.open(name, 'wb'))
  assert(writer:setvbuf('no'))
  local reader <close> = assert(io.open(name, 'rb'))
  assert(writer:write('visible\0bytes') == writer)
  assert(reader:read(13) == 'visible\0bytes')
  assert(reader:close())
  assert(writer:close())
end
assert(os.remove(name))
print('native unbuffered visibility counterpart OK')
