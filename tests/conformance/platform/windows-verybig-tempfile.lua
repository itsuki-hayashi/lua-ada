-- Focused native Windows tempfile lifecycle; run in an empty disposable CWD.
-- The rooted native name is observed only; temporary file I/O uses .\.
assert(package.config:sub(1, 1) == "\\")
local function check(name, body)
  body()
  print("PASS: windows-verybig-tempfile-" .. name)
end
local function absent(path)
  local file, message, code = io.open(path, "rb")
  if file then
    assert(file:close())
    error("translated tempfile already exists", 0)
  end
  -- ENOENT proves absence, rather than mistaking an unreadable existing file
  -- for a safe output target. Never retry or overwrite such a collision.
  assert(type(message) == "string" and code == 2)
end
local raw = os.tmpname()
check("rooted-name", function()
  assert(type(raw) == "string" and raw:sub(1, 1) == "\\")
  local leaf = raw:sub(2)
  assert(#leaf > 0 and leaf ~= "." and leaf ~= "..")
  assert(not leaf:find("[\\/:]"))
end)
local file = "." .. raw
check("fresh-cwd-name", function()
  assert(file:sub(1, 2) == ".\\")
  absent(file)
end)
local source = "local t={11,22,33};assert(t[1]+t[2]+t[3]==66);return 10\n"
local previous = io.output()
check("write-read", function()
  -- Only the translated path is opened for writing, just as the proposed
  -- expression changes verybig's output target while retaining io.output.
  assert(io.output(file))
  assert(io.write(source))
  assert(io.close())
  assert(io.output(previous) == previous)
  local input = assert(io.open(file, "rb"))
  -- Native Windows text output adds CR before the one final LF. Compare
  -- those actual bytes, then independently check ordinary text-mode reading.
  assert(input:read("a") == source:sub(1, -2) .. "\r\n")
  assert(input:close())
  input = assert(io.open(file, "r"))
  assert(input:read("a") == source)
  assert(input:close())
end)
local chunk
check("text-loadfile", function()
  chunk = assert(loadfile(file, "t"))
  assert(chunk() == 10)
end)
check("dofile", function() assert(dofile(file) == 10) end)
check("binary-load", function()
  local binary = string.dump(chunk)
  local loaded = assert(load(binary, "=windows-verybig-tempfile", "b"))
  assert(loaded() == 10)
end)
check("remove", function()
  assert(os.remove(file))
  absent(file)
end)
return 10
