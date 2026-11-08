with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Return_Hook_Mutation_Tests is
   Preamble : constant String :=
     "local function mutate(fn, action, ...)" &
     ASCII.LF &
     "  local hits = 0" &
     ASCII.LF &
     "  debug.sethook(function(event)" &
     ASCII.LF &
     "    if event == 'return' then" &
     ASCII.LF &
     "      local info = debug.getinfo(2, 'fr')" &
     ASCII.LF &
     "      if info.func == fn then hits = hits + 1; actio" &
     "n(info) end" &
     ASCII.LF &
     "    end" &
     ASCII.LF &
     "  end, 'r')" &
     ASCII.LF &
     "  local values = table.pack(fn(...))" &
     ASCII.LF &
     "  debug.sethook()" &
     ASCII.LF &
     "  assert(hits == 1)" &
     ASCII.LF &
     "  return values" &
     ASCII.LF &
     "end" &
     ASCII.LF &
     ASCII.LF;
   --  The standalone native/Ada fixture supplies the same public hook helper.
   --  Each case runs in a real session, with no invented event or result.

   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result :=
        Universe.Execute (Preamble & Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Closure_Scalar;
   procedure Closure_Scalar is
   begin
      --  Deliver the edited scalar through the actual caller result slot.
      Check
        ("do" &
         ASCII.LF &
         "  local r = mutate(function() return 11 end, functio" &
         "n(i)" &
         ASCII.LF &
         "    assert(i.ntransfer == 1)" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer, 37))" &
         ASCII.LF &
         "  end)" &
         ASCII.LF &
         "  assert(r.n == 1 and r[1] == 37)" &
         ASCII.LF &
         "end");
   end Closure_Scalar;

   procedure Closure_Tuple;
   procedure Closure_Tuple is
   begin
      --  Preserve nil tuple positions while replacing nonnil results.
      Check
        ("do" &
         ASCII.LF &
         "  local r = mutate(function() return 11, nil, 23 end" &
         ", function(i)" &
         ASCII.LF &
         "    assert(i.ntransfer == 3)" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer, 37))" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer + 2, 42))" &
         ASCII.LF &
         "  end)" &
         ASCII.LF &
         "  assert(r.n == 3 and r[1] == 37 and r[2] == nil and" &
         " r[3] == 42)" &
         ASCII.LF &
         "end");
   end Closure_Tuple;

   procedure Builtin_Appended_Result;
   procedure Builtin_Appended_Result is
   begin
      --  Read an appended builtin result at its actual transfer offset.
      Check
        ("do" &
         ASCII.LF &
         "  local r = mutate(math.abs, function(i)" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer, 37))" &
         ASCII.LF &
         "  end, 4)" &
         ASCII.LF &
         "  assert(r.n == 1 and r[1] == 37)" &
         ASCII.LF &
         "end");
   end Builtin_Appended_Result;

   procedure Builtin_Argument_Reuse;
   procedure Builtin_Argument_Reuse is
   begin
      --  Return edited existing argument cells after the body finishes.
      Check
        ("do" &
         ASCII.LF &
         "  local r = mutate(assert, function(i)" &
         ASCII.LF &
         "    assert(i.ntransfer == 3)" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer, false))" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer + 1, nil))" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer + 2, 37))" &
         ASCII.LF &
         "  end, true, 11, 23)" &
         ASCII.LF &
         "  assert(r.n == 3 and r[1] == false and r[2] == nil " &
         "and r[3] == 37)" &
         ASCII.LF &
         "end");
   end Builtin_Argument_Reuse;

   procedure Pcall_Success_Status;
   procedure Pcall_Success_Status is
   begin
      --  Keep the public pcall status editable without wrapping it again.
      Check
        ("do" &
         ASCII.LF &
         "  local r = mutate(pcall, function(i)" &
         ASCII.LF &
         "    assert(i.ntransfer == 2)" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer, 37))" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer + 1, 42))" &
         ASCII.LF &
         "  end, function() return 11 end)" &
         ASCII.LF &
         "  assert(r.n == 2 and r[1] == 37 and r[2] == 42)" &
         ASCII.LF &
         "end");
   end Pcall_Success_Status;

   procedure Pcall_Error_Status;
   procedure Pcall_Error_Status is
   begin
      --  Replace both false and the arbitrary protected error object.
      Check
        ("do" &
         ASCII.LF &
         "  local r = mutate(pcall, function(i)" &
         ASCII.LF &
         "    assert(i.ntransfer == 2)" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer, 'changed')" &
         ")" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer + 1, 37))" &
         ASCII.LF &
         "  end, function() error(17) end)" &
         ASCII.LF &
         "  assert(r.n == 2 and r[1] == 'changed' and r[2] == " &
         "37)" &
         ASCII.LF &
         "end");
   end Pcall_Error_Status;

   procedure Xpcall_Success_Status;
   procedure Xpcall_Success_Status is
   begin
      --  Preserve the edited status and value in the real xpcall tuple.
      Check
        ("do" &
         ASCII.LF &
         "  local r = mutate(xpcall, function(i)" &
         ASCII.LF &
         "    assert(i.ntransfer == 2)" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer, false))" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer + 1, 37))" &
         ASCII.LF &
         "  end, function() return 11 end, function(e) return " &
         "e end)" &
         ASCII.LF &
         "  assert(r.n == 2 and r[1] == false and r[2] == 37)" &
         ASCII.LF &
         "end");
   end Xpcall_Success_Status;

   procedure Weak_Lua_Result;
   procedure Weak_Lua_Result is
   begin
      --  Discarded actual temporaries must not survive in copied packets.
      Check
        ("do" &
         ASCII.LF &
         "  local weak = setmetatable({}, {__mode = 'v'})" &
         ASCII.LF &
         "  local function factory() local v = {}; weak[1] = v" &
         "; return v end" &
         ASCII.LF &
         "  local r = mutate(function() return (factory()) end" &
         ", function(i)" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer, nil))" &
         ASCII.LF &
         "    -- A compiler can leave other copies in its expo" &
         "sed actual reservation." &
         ASCII.LF &
         "    -- Clear every matching real temporary before te" &
         "sting stale packet roots." &
         ASCII.LF &
         "    local slot=1" &
         ASCII.LF &
         "    while true do" &
         ASCII.LF &
         "      local name,value=debug.getlocal(3,slot)" &
         ASCII.LF &
         "      if name==nil then break end" &
         ASCII.LF &
         "      if value==weak[1] then assert(debug.setlocal(3" &
         ",slot,nil)) end" &
         ASCII.LF &
         "      slot=slot+1" &
         ASCII.LF &
         "    end" &
         ASCII.LF &
         "    collectgarbage('collect')" &
         ASCII.LF &
         "    assert(weak[1] == nil)" &
         ASCII.LF &
         "  end)" &
         ASCII.LF &
         "  assert(r.n == 1 and r[1] == nil)" &
         ASCII.LF &
         "end");
   end Weak_Lua_Result;

   procedure Weak_Builtin_Result;
   procedure Weak_Builtin_Result is
   begin
      --  Replacing the iterator removes copied native result roots.
      Check
        ("do" &
         ASCII.LF &
         "  local weak = setmetatable({}, {__mode = 'v'})" &
         ASCII.LF &
         "  local r = mutate(string.gmatch, function(i)" &
         ASCII.LF &
         "    local name, old = debug.getlocal(3, i.ftransfer)" &
         ASCII.LF &
         "    assert(name and type(old) == 'function'); weak[1" &
         "] = old; old = nil" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer, nil))" &
         ASCII.LF &
         "    collectgarbage('collect')" &
         ASCII.LF &
         "    assert(weak[1] == nil)" &
         ASCII.LF &
         "  end, 'abc', '.')" &
         ASCII.LF &
         "  assert(r.n == 1 and r[1] == nil)" &
         ASCII.LF &
         "end");
   end Weak_Builtin_Result;

   procedure Close_Before_Return_Hook;
   procedure Close_Before_Return_Hook is
   begin
      --  Run actual closers before the hook edits the outgoing result.
      Check
        ("do" &
         ASCII.LF &
         "  local order = {}" &
         ASCII.LF &
         "  local fn = function()" &
         ASCII.LF &
         "    local guard <close> = setmetatable({}, {__close " &
         "= function()" &
         ASCII.LF &
         "      order[#order + 1] = 'close'" &
         ASCII.LF &
         "    end})" &
         ASCII.LF &
         "    return 11" &
         ASCII.LF &
         "  end" &
         ASCII.LF &
         "  local r = mutate(fn, function(i)" &
         ASCII.LF &
         "    assert(order[1] == 'close' and #order == 1)" &
         ASCII.LF &
         "    order[2] = 'hook'" &
         ASCII.LF &
         "    assert(debug.setlocal(3, i.ftransfer, 37))" &
         ASCII.LF &
         "  end)" &
         ASCII.LF &
         "  assert(r.n == 1 and r[1] == 37 and order[2] == 'ho" &
         "ok')" &
         ASCII.LF &
         "end");
   end Close_Before_Return_Hook;

   procedure Coroutine_Resume_Return;
   procedure Coroutine_Resume_Return is
   begin
      --  Retain cells across suspension until close and return mutation.
      Check
        ("do" &
         ASCII.LF &
         "  local hits, closed = 0, false" &
         ASCII.LF &
         "  local fn = function()" &
         ASCII.LF &
         "    local guard <close> = setmetatable({}, {__close " &
         "= function() closed=true end})" &
         ASCII.LF &
         "    coroutine.yield('pause')" &
         ASCII.LF &
         "    return 11" &
         ASCII.LF &
         "  end" &
         ASCII.LF &
         "  local co = coroutine.create(fn)" &
         ASCII.LF &
         "  debug.sethook(co, function(e)" &
         ASCII.LF &
         "    if e == 'return' then local i=debug.getinfo(2,'f" &
         "r'); if i.func==fn then" &
         ASCII.LF &
         "      hits=hits+1; assert(closed); assert(debug.setl" &
         "ocal(2,i.ftransfer,37))" &
         ASCII.LF &
         "    end end" &
         ASCII.LF &
         "  end, 'r')" &
         ASCII.LF &
         "  local ok,v=coroutine.resume(co); assert(ok and v==" &
         "'pause' and not closed)" &
         ASCII.LF &
         "  ok,v=coroutine.resume(co); assert(ok and v==37 and" &
         " closed and hits==1)" &
         ASCII.LF &
         "end");
   end Coroutine_Resume_Return;

   procedure Return_Hook_Cannot_Yield;
   procedure Return_Hook_Cannot_Yield is
   begin
      --  Preserve the nonyieldable boundary while the return hook runs.
      Check
        ("do" &
         ASCII.LF &
         "  local fn = function() return 11 end" &
         ASCII.LF &
         "  local co=coroutine.create(function()" &
         ASCII.LF &
         "    local r=mutate(fn,function(i)" &
         ASCII.LF &
         "      local ok,e=pcall(coroutine.yield,9)" &
         ASCII.LF &
         "      assert(not ok and e:find('C%-call boundary'))" &
         ASCII.LF &
         "      assert(debug.setlocal(3,i.ftransfer,37))" &
         ASCII.LF &
         "    end)" &
         ASCII.LF &
         "    assert(r[1]==37); return 42" &
         ASCII.LF &
         "  end)" &
         ASCII.LF &
         "  local ok,v=coroutine.resume(co); assert(ok and v==" &
         "42)" &
         ASCII.LF &
         "end");
   end Return_Hook_Cannot_Yield;

   procedure Return_Hook_Error_Recovery;
   procedure Return_Hook_Error_Recovery is
   begin
      --  Abandon a failing hook and reuse the same owned universe.
      Check
        ("do" &
         ASCII.LF &
         "  local ok,e=pcall(mutate,function()return 11 end,fu" &
         "nction()error(17)end)" &
         ASCII.LF &
         "  debug.sethook()" &
         ASCII.LF &
         "  assert(not ok and e==17)" &
         ASCII.LF &
         "  local r=mutate(function()return 12 end,function(i)" &
         ASCII.LF &
         "    assert(debug.setlocal(3,i.ftransfer,37))" &
         ASCII.LF &
         "  end)" &
         ASCII.LF &
         "  assert(r[1]==37)" &
         ASCII.LF &
         "end");
   end Return_Hook_Error_Recovery;

   procedure Zero_Result_Return;
   procedure Zero_Result_Return is
   begin
      --  Reconstruct a genuine empty result tuple without arithmetic wrap.
      Check
        ("do" &
         ASCII.LF &
         "  local r=mutate(function()end,function(i)assert(i.n" &
         "transfer==0)end)" &
         ASCII.LF &
         "  assert(r.n==0)" &
         ASCII.LF &
         "end");
   end Zero_Result_Return;

   procedure Vararg_Return_Range;
   procedure Vararg_Return_Range is
   begin
      --  Use actual vararg transfer offsets and preserve other results.
      Check
        ("do" &
         ASCII.LF &
         "  local r=mutate(function(a,...)return a,... end,fun" &
         "ction(i)" &
         ASCII.LF &
         "    assert(i.ntransfer==3)" &
         ASCII.LF &
         "    assert(debug.setlocal(3,i.ftransfer+1,37))" &
         ASCII.LF &
         "  end,11,nil,23)" &
         ASCII.LF &
         "  assert(r.n==3 and r[1]==11 and r[2]==37 and r[3]==" &
         "23)" &
         ASCII.LF &
         "end");
   end Vararg_Return_Range;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "Return hooks: closure scalar",
                        Closure_Scalar'Access);
      Test_Support.Add (Suite, "Return hooks: closure tuple",
                        Closure_Tuple'Access);
      Test_Support.Add (Suite, "Return hooks: builtin appended result",
                        Builtin_Appended_Result'Access);
      Test_Support.Add (Suite, "Return hooks: builtin argument reuse",
                        Builtin_Argument_Reuse'Access);
      Test_Support.Add (Suite, "Return hooks: pcall success status",
                        Pcall_Success_Status'Access);
      Test_Support.Add (Suite, "Return hooks: pcall error status",
                        Pcall_Error_Status'Access);
      Test_Support.Add (Suite, "Return hooks: xpcall success status",
                        Xpcall_Success_Status'Access);
      Test_Support.Add (Suite, "Return hooks: weak lua result",
                        Weak_Lua_Result'Access);
      Test_Support.Add (Suite, "Return hooks: weak builtin result",
                        Weak_Builtin_Result'Access);
      Test_Support.Add (Suite, "Return hooks: close before return hook",
                        Close_Before_Return_Hook'Access);
      Test_Support.Add (Suite, "Return hooks: coroutine resume return",
                        Coroutine_Resume_Return'Access);
      Test_Support.Add (Suite, "Return hooks: return hook cannot yield",
                        Return_Hook_Cannot_Yield'Access);
      Test_Support.Add (Suite, "Return hooks: return hook error recovery",
                        Return_Hook_Error_Recovery'Access);
      Test_Support.Add (Suite, "Return hooks: zero result return",
                        Zero_Result_Return'Access);
      Test_Support.Add (Suite, "Return hooks: vararg return range",
                        Vararg_Return_Range'Access);
   end Register;
end Return_Hook_Mutation_Tests;
