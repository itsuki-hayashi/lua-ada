-- Native Windows path expectations for the attrib.lua author proposal.
-- MIT; see ../../../LICENSE. Run only in a disposable fixture directory.
-- This counterpart retains exact loader data, including a deliberately
-- mixed-separator template, rather than normalizing observed Lua results.
local sep = package.config:sub(1, 1)
assert(sep == "\\")
local function D(name) return "libs" .. sep .. name:gsub("/", sep) end
local function DC(name) return D(name .. ".dll") end
local created = {}
local function write(name, text)
  local path = D(name)
  local file = assert(io.open(path, "w"))
  assert(file:write(text))
  assert(file:close())
  created[#created + 1] = path
end
local function check(name, body)
  body()
  print("PASS: windows-package-paths-" .. name)
end
local function required(name, expected)
  local value, path = require(name)
  assert(type(value) == "table" and value.name == name)
  assert(value.data == expected and path == expected)
  assert(package.searchpath(name, package.path) == expected)
end
local oldpath, oldcpath = package.path, package.cpath
local chunk = "local name,data=...; return {name=name,data=data}"
write("B.lua", chunk)
write("A.lua", chunk)
write("A.lc", chunk)
write("L", "windows_path_loads=(windows_path_loads or 0)+1; return false")
write("XXxX", chunk)
package.path = ("D/?.lua;D/?.lc;D/?;D/??x?;D/L"):gsub("D/", "libs" .. sep)
check("require-b-lua", function() required("B", D"B.lua") end)
check("require-a-lua", function() required("A", D"A.lua") end)
package.loaded.A = nil
assert(os.remove(D"A.lua"))
check("require-a-lc", function() required("A", D"A.lc") end)
check("fallback-l-first", function()
  local value, path = require"K"
  assert(value == false and path == D"L" and windows_path_loads == 1)
end)
check("fallback-l-reload", function()
  local value, path = require"K"
  assert(value == false and path == D"L" and windows_path_loads == 2)
end)
check("require-xx-x", function() required("X", D"XXxX") end)
write("P1/init.lua", chunk)
write("P1/xuxu.lua", chunk)
package.path = ("D/?.lua;D/?/init.lua"):gsub("D/", "libs" .. sep)
check("mixed-subpackage-template", function()
  -- The slash in the template is literal. Only the substituted D/ prefix
  -- uses sep; require must return those exact bytes, with both separators.
  required("P1", "libs" .. sep .. "P1/init.lua")
end)
check("subpackage-separator", function() required("P1.xuxu", D"P1/xuxu.lua") end)
package.cpath = DC"?"
check("hyphen-native-prefix", function()
  local module, path = require"lib2-v2"
  assert(type(module) == "table" and module.id("x") == true)
  assert(path == DC"lib2-v2" and path:find(D"lib2-v2", 1, true))
  assert(_G.x == "lib2-v2" and _G.y == path)
end)
check("c-root-native-prefix", function()
  local module, path = require"lib1.sub"
  assert(type(module) == "table" and module.id(45) == 45)
  assert(path == DC"lib1" and path:find(D"lib1", 1, true))
  assert(_G.x == "lib1.sub" and _G.y == path)
end)
package.path, package.cpath = oldpath, oldcpath
for _, name in ipairs{"B", "A", "K", "X", "P1", "P1.xuxu", "lib2-v2", "lib1.sub"} do
  package.loaded[name] = nil
end
for _, path in ipairs(created) do os.remove(path) end
windows_path_loads, _G.x, _G.y = nil, nil, nil
