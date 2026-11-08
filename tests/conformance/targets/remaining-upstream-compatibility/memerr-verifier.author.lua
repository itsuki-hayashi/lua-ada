-- First-party diagnostic of verifier allocation timing; MIT, lua-ada authors.
-- This is not an adapted upstream file or an acceptance witness. T comes from
-- the actual native test build or first-party instrumented Ada harness.
local phase = os.getenv("LUA_ADA_MEMERR_VERIFIER_PHASE")
assert(phase == "limited-verifier" or phase == "restored-verifier")
assert(type(T) == "table" and type(T.alloccount) == "function")
local restored = phase == "restored-verifier"
local application_errors = 0
local function checkerr(msg, f, ...)
  local stat, err = pcall(f, ...)
  -- The application has already run under the active refusal control. Only
  -- the verifier's own false-status/error-text assertion may use new storage.
  if restored then T.alloccount() end
  assert(not stat and string.find(err, msg))
  assert(type(err) == "string")
  application_errors = application_errors + 1
end

checkerr("block too big", T.newuserdata, math.maxinteger)
collectgarbage()
local f = assert(load([[
  local a={}
  for i=1,100000 do a[i]=i end
  return a[1], a[100000], #a
]]))
T.alloccount(10)
checkerr("not enough memory", f)
T.alloccount()
assert(application_errors == 2)
local first, last, count = f()
assert(math.type(first) == "integer" and first == 1)
assert(math.type(last) == "integer" and last == 100000)
assert(math.type(count) == "integer" and count == 100000)
collectgarbage(); collectgarbage()
T.checkmemory()
assert(pcall(function() return 37 end))
print("MEMERR VERIFIER COMPONENT OK")
