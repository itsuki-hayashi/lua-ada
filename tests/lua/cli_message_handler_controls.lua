-- Authored public CLI controls, linked to lua.c:msghandler/docall/report.
-- Each named operation is a separate process/AUnit obligation. This fixture
-- does not replace, skip or adapt any original main.lua assertion.
global *
local name = ... or arg[1]
local actions = {}

actions.string = function()
  local function inner() error("E_STRING", 0) end
  local function outer() inner(); return 1 end
  outer()
end
actions.table = function() error({}, 0) end
actions["table-name"] = function()
  error(setmetatable({}, {__name = "Widget"}), 0)
end
actions["tostring-string"] = function()
  local e
  e = setmetatable({}, {__tostring = function(self)
    assert(self == e)
    io.write("MM_ENTER\n")
    return "MM_STRING"
  end})
  error(e, 0)
end
actions["tostring-number"] = function()
  error(setmetatable({}, {__tostring = function()
    io.write("MM_ENTER\n"); return 37
  end}), 0)
end
actions["tostring-nil"] = function()
  error(setmetatable({}, {__tostring = function()
    io.write("MM_ENTER\n"); return nil
  end}), 0)
end
actions["tostring-throws"] = function()
  error(setmetatable({}, {__tostring = function()
    io.write("MM_ENTER\n"); error("MM_THROW", 0)
  end}), 0)
end
actions["tostring-nul"] = function()
  error(setmetatable({}, {__tostring = function() return "MM\0TAIL" end}), 0)
end
actions.numeric = function() error(37, 0) end
actions["numeric-meta"] = function()
  debug.setmetatable(0, {__tostring = function()
    io.write("NUM_MM\n"); return "BAD_NUM"
  end})
  error(37, 0)
end
actions["callable-meta"] = function()
  local callable, e
  callable = setmetatable({}, {__call = function(self, value)
    assert(self == callable and value == e)
    return "MM_CALLABLE"
  end})
  e = setmetatable({}, {__tostring = callable})
  error(e, 0)
end
actions["raw-meta"] = function()
  local mt = setmetatable({}, {__index = function()
    io.write("META_INDEX\n")
    return function() return "BAD_META" end
  end})
  error(setmetatable({}, mt), 0)
end
actions["mutate-parent"] = function()
  local e
  e = setmetatable({}, {__tostring = function(self)
    local n, v = debug.getlocal(2, 1)
    assert(n == "(C temporary)" and v == e and self == e)
    assert(debug.setlocal(2, 1, 37) == "(C temporary)")
    return false
  end})
  error(e, 0)
end
actions.frames = function()
  local e
  e = setmetatable({}, {__tostring = function(self)
    local parent = debug.getinfo(2, "Sf")
    assert(parent.what == "C" and parent.func ~= tostring)
    local n, v = debug.getlocal(2, 1)
    assert(n == "(C temporary)" and v == self and self == e)
    assert(not coroutine.isyieldable())
    assert(debug.getinfo(3, "f").func == error)
    collectgarbage()
    local trace = debug.traceback("IN_CALLBACK", 1)
    assert(trace:find("stack traceback:", 1, true))
    assert(trace:find("[C]: in ?", 1, true))
    io.write("FRAME_CONTROLS\n")
    return "FRAME_MESSAGE"
  end})
  local function inner() error(e, 0) end
  local function outer() inner(); return 1 end
  outer()
end
actions["weak-error"] = function()
  weak_error_watch = setmetatable({}, {__mode = "v"})
  local function make()
    local e = setmetatable({}, {__tostring = function(self)
      collectgarbage()
      assert(weak_error_watch[1] == self)
      return "WEAK_MESSAGE"
    end})
    weak_error_watch[1] = e
    return e
  end
  error(make(), 0)
end
actions["handler-yield"] = function()
  error(setmetatable({}, {__tostring = function() coroutine.yield() end}), 0)
end
actions["closer-error"] = function()
  local c <close> = setmetatable({}, {__close = function(_, value)
    assert(value == "CLOSE_MESSAGE")
    io.write("CLOSED_AFTER_HANDLER\n")
  end})
  error(setmetatable({}, {__tostring = function() return "CLOSE_MESSAGE" end}), 0)
end
actions["exit-close"] = function()
  error(setmetatable({}, {__tostring = function()
    io.write("EXIT_HANDLER\n"); os.exit(37, true)
  end}), 0)
end
actions["exit-no-close"] = function()
  error(setmetatable({}, {__tostring = function()
    io.write("EXIT_HANDLER\n"); os.exit(37, false)
  end}), 0)
end
actions.memory = function()
  local control, rep = T.alloccount, string.rep
  io.write("ARMED\n"); control(0); rep("x", 100000)
end
actions["entered-handler-memory"] = function()
  local control = T.alloccount
  error(setmetatable({}, {__tostring = function()
    io.write("HANDLER_ARMED\n"); control(0); return 37
  end}), 0)
end

assert(actions[name], name)()
