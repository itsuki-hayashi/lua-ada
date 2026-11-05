-- First-party deterministic M2b campaign, not an upstream-suite substitute.
-- Seed 0x25a51 and 1,120 bounded cases are part of the regression contract.
-- Print only primitive values and byte strings: pointer images and diagnostic
-- wording are intentionally absent from cross-language comparisons.
package.path = "./?.lua;./?/init.lua"
local seed = 0x25a51
local function random()
  seed = (seed * 1103515245 + 12345) & 0x7fffffff
  return seed
end

local patterns = {
  "(%a+)", "()(%d+)", "%b()", "%f[%a](%a+)%f[%A]",
  "(%a+)%d+%1", "[a-z]-[0-9]+", "[^%d]+", "()",
}

for case = 1, 1120 do
  local family = (case - 1) % 8 + 1
  local a = random() % 32768
  local b = random() % 32768
  if family == 1 then
    -- Pattern choices include captures, byte positions, balancing, frontiers,
    -- a backreference, lazy expansion, negated sets, and empty progression.
    local word = string.char(97 + a % 26, 97 + b % 26)
    local subject = word .. a .. word .. "((" .. word .. "))"
    local pattern = patterns[random() % #patterns + 1]
    local first, last = string.find(subject, pattern)
    local matches, calls = {}, 0
    for wordpart, digits in string.gmatch(subject, "(%a+)(%d*)") do
      matches[#matches + 1] = wordpart .. ":" .. digits
    end
    local changed, count = string.gsub(subject, pattern, function(capture)
      calls = calls + 1
      return "[" .. tostring(capture) .. "]"
    end)
    local replaced = string.gsub("aabb", "(.)", {a = "X", b = false})
    print(case, family, first, last, changed, count, calls,
          table.concat(matches, "/"), replaced)
  elseif family == 2 then
    -- Mixed byte order, fixed and variable byte strings, floating values,
    -- and returned cursor positions exercise independent format transitions.
    local signed = a * 2 - 32768
    local unsigned = (a << 16) | b
    local real = (b - 16384) / 8
    local bytes = string.char(0, a % 256, b % 256)
    local variable = bytes .. "end"
    local packed = string.pack("<i2>I4<d c3 s1 z",
                               signed, unsigned, real, bytes, variable, "ok")
    local x, y, z, fixed, sized, terminated, after =
      string.unpack("<i2>I4<d c3 s1 z", packed)
    local aligned = string.pack("!4 b I4", 1, unsigned)
    print(case, family, #packed, x, y, z, fixed == bytes,
          sized == variable, terminated, after, #aligned,
          string.packsize("!4 b I4"), string.byte(packed, 1, 2))
  elseif family == 3 then
    -- Strict scalar decoding and lax extended encodings deliberately share
    -- the same iteration API. No platform character encoding is involved.
    local points = {a % 128, 0x80 + b % 0x780,
                    0x800 + a % 0x5000, 0x10000 + b}
    local text = utf8.char(table.unpack(points))
    local sum, positions = 0, {}
    for position, point in utf8.codes(text) do
      sum = sum + point
      positions[#positions + 1] = position
    end
    local start, finish = utf8.offset(text, 3)
    local extended = utf8.char(0x7fffffff - a)
    local valid, bad = utf8.len(extended)
    local strict = pcall(utf8.codepoint, extended)
    print(case, family, #text, utf8.len(text), sum,
          table.concat(positions, ","), start, finish,
          utf8.codepoint(text, start), #extended,
          utf8.len(extended, 1, -1, true), valid, bad, strict,
          utf8.codepoint(extended, 1, -1, true))
  elseif family == 4 then
    -- Both directions of overlapping moves must read each source cell before
    -- it is overwritten. Pack preserves a nil hole through its explicit n.
    local values = {a, b, 3, 4, 5}
    table.move(values, 1, 4, 2)
    table.move(values, 2, 5, 1)
    table.insert(values, 2, 9)
    local removed = table.remove(values, 3)
    local packet = table.pack(a, nil, b)
    local real = (a - b) / 8
    local integer, fraction = math.modf(real)
    print(case, family, table.concat(values, ":"), removed, packet.n,
          select("#", table.unpack(packet, 1, packet.n)),
          math.abs(a - b), math.floor(real), math.ceil(real),
          integer, fraction, math.fmod(a, 7),
          math.max(a, b), math.min(a, b), math.type(math.tointeger(a + 0.0)),
          math.ult(-1, a))
  elseif family == 5 then
    -- User callbacks run through arithmetic, indexing, assignment, calls,
    -- concatenation, tostring and pairs rather than helper-only code paths.
    local meta = {
      __index = function(_, key) return key == "missing" and a or nil end,
      __newindex = function(self, key, value) rawset(self, key, value * 2) end,
      __call = function(_, value) return value + b, a end,
      __add = function(_, value) return value + a end,
      __len = function() return b end,
      __concat = function(_, value) return "joined:" .. value end,
      __tostring = function() return "object:" .. a end,
      __pairs = function() return next, {only = a + b}, nil, nil end,
    }
    local object = setmetatable({}, meta)
    object.saved = a
    local first, second = object(3)
    local sum = 0
    for _, value in pairs(object) do sum = sum + value end
    print(case, family, object.missing, rawget(object, "missing"),
          object.saved, rawlen(object), #object, object + 7,
          first, second, object .. "end", string.format("<%s>", object), sum)
  elseif family == 6 then
    -- Every load owns its initial environment. Reader pieces remain rooted
    -- while nested Lua calls request additional source from the reader.
    local environment = {x = a}
    local closure = assert(load("return x + 3", "campaign-env", "t",
                                environment))
    local pieces, index = {"return ", tostring(b), " + 4"}, 0
    local reader = assert(load(function()
      index = index + 1
      return pieces[index]
    end, "campaign-reader", "t"))
    local invalid, message = load("local =", "campaign-invalid", "t")
    local explicitnil = assert(load("return 5", "campaign-nil", "t", nil))
    local rejected, modemessage = load("return 1", "campaign-mode", "b")
    environment.x = environment.x + 1
    print(case, family, closure(), reader(), index, invalid,
          type(message), explicitnil(), rejected, type(modemessage))
  elseif family == 7 then
    -- Registry-equivalent cache ownership survives replacement of public
    -- package.loaded; false loader results deliberately request another load.
    local key = "m2b.campaign." .. case
    local calls = 0
    package.preload[key] = function(name, data)
      assert(name == key and data == ":preload:")
      calls = calls + 1
      return false
    end
    local first, data = require(key)
    local second = require(key)
    package.preload[key] = function() return a end
    local third = require(key)
    local public = package.loaded
    package.loaded = {}
    local cached = table.pack(require(key))
    package.loaded = public
    local customkey = key .. ".custom"
    table.insert(package.searchers, 1, function(name)
      if name == customkey then
        return function(loadername, loaderdata)
          assert(loadername == customkey and loaderdata == "custom-data")
          return b
        end, "custom-data"
      end
      return "\nnot the campaign module"
    end)
    local custom, customdata = require(customkey)
    table.remove(package.searchers, 1)
    print(case, family, first, data, second, calls, third,
          cached[1], cached.n, custom, customdata)
    public[key], public[customkey], package.preload[key] = nil, nil, nil
  else
    -- Binary quoting, ASCII-only case conversion, numeric-string arithmetic,
    -- primitive bitwise rejection, and protected malformed patterns coexist.
    local bytes = string.char(0, 10, 34, 92, 255) .. "9"
    local upper = string.upper("ab" .. string.char(255))
    local wrongpattern = pcall(string.match, "abc", "[abc")
    local bitcoercion = pcall(function() return "7" & 3 end)
    local hexmodifiers = pcall(string.format, "%.0a", 1.5)
    print(case, family, string.format("%q", bytes), upper,
          string.reverse(string.sub("abcdef", -4, -2)),
          string.rep("ab", a % 4, ":"),
          string.format("%08x %.3f %.4g", a, b / 8, (a + 1) / (b + 1)),
          "7" + 3, "7" * 3, wrongpattern, bitcoercion,
          math.tointeger(3.5), math.type(3.0), math.type(3),
          string.format("%a", 1e-308), string.format("%q", 0x1p-1074),
          string.format("%g", 0/0), hexmodifiers)
  end
end
print("M2b library campaign OK", 1120, "seed", 0x25a51)
