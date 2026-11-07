-- Focused public-C-driver regressions, run by check-instrumented.ps1.
-- This file is deliberately instrumented:
-- an absent T is a setup failure and cannot turn these cases into a pass.
assert(type(T) == "table", "the real C API test adapter is required")

-- A stack command observes actual argument adjustment and returns the selected
-- values. Unknown instructions must raise instead of reporting fake success.
assert(T.testC("pushvalue 2; return 1", 42) == 42)
assert(not pcall(T.testC, "invented command"))
assert(not pcall(T.testC, "pushint 999999999999999999999999; return 1"))
print("PASS: C API driver operands and errors")

-- A suspended C closure must keep its real upvalue cells, and resumption must
-- call the saved continuation after abandoning the original C stack.
local f = T.makeCfunc("pushint 12; yieldk 1 U2; invalid command",
                     "pushvalue U3; return 1", "retained")
local co = coroutine.wrap(f)
assert(co() == 12)
assert(co() == "retained")
assert(not pcall(co))
print("PASS: C closure yield continuation and captures")

-- A protected continuation receives the actual runtime error status and its
-- context index, preserving the caller's preceding stack marker.
co = coroutine.wrap(function()
  return T.testC("pushstring failure; pcallk 1 0 2; invalid command",
                "return *", "marker", error)
end)
local values = table.pack(co())
assert(values.n == 4 and values[3] == "marker" and values[4] == "failure")
assert(status == "ERRRUN" and ctx == 2)
print("PASS: protected C continuation error transport")

-- A count hook can yield repeatedly without dropping the interrupted frame's
-- live registers. Resume consumes real hook suspensions until the body ends.
local result
local thread = coroutine.create(function()
  T.sethook("pushint 99; yield 0", "", 1)
  local a, b, c = 10, 20, 30
  result = a + b + c
  T.sethook()
end)
local resumes = 0
repeat
  assert(T.resume(thread))
  resumes = resumes + 1
until coroutine.status(thread) == "dead"
assert(result == 60 and resumes > 1)
print("PASS: yielding C count hook preserves registers")

-- A line-hook yield occurs before its interrupted instruction. Inspecting
-- that suspended frame must report the upcoming line and the same live local
-- lifetime that getlocal/setlocal use, rather than the preceding call line.
thread = coroutine.create(function(a, ...)
  T.sethook("yield 0", "l")
  local b = a
  return ...
end)
assert(coroutine.resume(thread, 1, 2, 3))
local info = debug.getinfo(thread, 0)
assert(info.currentline == info.linedefined + 2)
local name, value = debug.getlocal(thread, 0, 1)
assert(name == "a" and value == 1)
assert(debug.setlocal(thread, 0, 1, 10))
assert(coroutine.resume(thread))
name, value = debug.getlocal(thread, 0, 3)
assert(name == "b" and value == 10)
local resumed = table.pack(coroutine.resume(thread))
assert(resumed.n == 3 and resumed[1] and resumed[2] == 2 and resumed[3] == 3)
print("PASS: suspended C line hook exposes interrupted frame")

-- Invalid hook yield operands are rejected before installing a pending C
-- transfer. These are first-party safety checks: the native debug build treats
-- invalid hook API operands as assertion failures rather than Lua errors.
for _, command in ipairs({"pushint 1; yield 1", "yieldk 0 1"}) do
  thread = coroutine.create(function()
    T.sethook(command, "", 1)
    local value = 10
    return value
  end)
  local accepted, failure = coroutine.resume(thread)
  assert(not accepted and failure:find("invalid yield from a hook", 1, true))
  assert(coroutine.status(thread) == "dead")
  debug.sethook(thread)
end
local yielded, yield_error = pcall(T.testC, "yield 0")
assert(not yielded and
       yield_error == "attempt to yield from outside a coroutine")
print("PASS: invalid C hook yields leave no pending transfer")

-- The selected library masks open base/package and preload coroutine in an
-- independent real universe. The loaded-module registry must preserve T's
-- identity across the driver's repeated requiref calls.
local other = assert(T.newstate())
T.loadlib(other, 1 | 2, 4)
assert(T.doremote(other, "coroutine=require'coroutine'; return type(coroutine)")
       == "table")
assert(T.doremote(other, "return 42") == "42")
local ok, message, code = T.doremote(other, "error('remote failure')")
assert(ok == nil and message:find("remote failure") and code == 2)
assert(T.doremote(other, "return 'recovered'") == "recovered")
T.closestate(other)
print("PASS: independent C states and remote errors")
print("T COROUTINE API OK")
