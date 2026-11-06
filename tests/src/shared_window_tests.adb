with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Shared_Window_Tests is
   procedure Check (Source : String);
   procedure Protected_Wide_Arguments;
   procedure Pcall_Discards_Excess;
   procedure Xpcall_Discards_Excess;
   procedure Native_Tail_Caller;
   procedure Native_Tail_Error_Frame;
   procedure Vararg_Call_Hook;
   procedure Result_Growth_After_Protection;

   procedure Check (Source : String) is
      State : Session;
      Result : Execution_Result;
   begin
      State.Set_Execution_Policy (Lua_Compatible);
      Result := State.Execute (Source, "=shared-window");
      Assert (Result.Status = Succeeded,
              "shared window fixture failed: " &
                To_String (Result.Error.Message));
      Result := State.Execute ("assert(true)", "=window-recovery");
      Assert (Result.Status = Succeeded,
              "window retirement damaged the next execution");
   end Check;

   procedure Protected_Wide_Arguments is
   begin
      --  A pcall target overlaps its native caller's argument suffix. Eighty
      --  nested calls with 500 extras fit the configured upstream 68,000-slot
      --  stack; summing duplicated Lua/native packets would overflow early.
      Check
        ("local a={};for i=1,500 do a[i]=i end;" &
         "local function f(n,...)if n==0 then return select('#',...) end;" &
         "local ok,count=pcall(f,n-1,...);assert(ok,count);return count end;" &
         "assert(f(80,table.unpack(a))==500)");
   end Protected_Wide_Arguments;

   procedure Pcall_Discards_Excess is
   begin
      --  The child ignores its argument. Once its entry slot is reused, a
      --  stale pcall construction packet must not keep that weak value alive.
      Check
        ("local w=setmetatable({}, {__mode='v'});" &
         "local function make()local x={};w[1]=x;return x end;" &
         "local function child()collectgarbage();assert(w[1]==nil) end;" &
         "assert(pcall(child,make()))");
   end Pcall_Discards_Excess;

   procedure Xpcall_Discards_Excess is
   begin
      --  xpcall retains only f/handler/true below its target. Its original
      --  excess-argument snapshot is not another GC root during the callback.
      Check
        ("local w=setmetatable({}, {__mode='v'});" &
         "local function make()local x={};w[1]=x;return x end;" &
         "local function child()collectgarbage();assert(w[1]==nil) end;" &
         "assert(xpcall(child,function(e)return e end,make()))");
   end Xpcall_Discards_Excess;

   procedure Native_Tail_Caller is
   begin
      --  A native tail callee runs while the Lua tail caller remains a real
      --  inspectable activation. The comparator observes its actual identity,
      --  not a fabricated traceback name or an internal continuation frame.
      Check
        ("local f;local seen=false;local function cmp(a,b)" &
         "for level=1,12 do local i=debug.getinfo(level,'f');" &
         "if i and i.func==f then seen=true end end;return a<b end;" &
         "f=function()return table.sort({2,1},cmp) end;f();assert(seen)");
   end Native_Tail_Caller;

   procedure Native_Tail_Error_Frame is
   begin
      --  The same retained caller must be visible before an error handler
      --  unwinds a tail call into a native error function. Its local survives
      --  for inspection even though captured upvalues may already be closed.
      Check
        ("local f;f=function()local secret=42;return error('tail',0) end;" &
         "local ok,e=xpcall(f,function(e)local seen=false;" &
         "for level=2,12 do local i=debug.getinfo(level,'f');" &
         "if i and i.func==f then local n,v=debug.getlocal(level,1);" &
         "assert(n=='secret' and v==42);seen=true end end;" &
         "assert(seen);return e end);assert(not ok and e=='tail')");
   end Native_Tail_Error_Frame;

   procedure Vararg_Call_Hook is
   begin
      --  The call hook runs after VARARGPREP. Negative local indices must
      --  address actual extras, and a mutation there feeds the subsequent ...
      --  expression instead of editing an abandoned argument packet.
      Check
        ("local f;local seen=false;f=function(a,...)return a,... end;" &
         "debug.sethook(function(event)if event=='call' then " &
         "local i=debug.getinfo(2,'f');if i.func==f then " &
         "local n,v=debug.getlocal(2,-1);assert(n and v==20);" &
         "assert(debug.setlocal(2,-1,42));seen=true end end end,'c');" &
         "local a,b,c=f(10,20,30);debug.sethook();" &
         "assert(seen and a==10 and b==42 and c==30)");
   end Vararg_Call_Hook;

   procedure Result_Growth_After_Protection is
   begin
      --  A no-window protected holder must not restore a saved small ci.top
      --  after publishing a much larger open-result sequence into its parent.
      Check
        ("local a={};for i=1,500 do a[i]=i end;" &
         "local function many()return table.unpack(a) end;" &
         "local function check(ok,...)assert(ok and select('#',...)==500);" &
         "assert(select(1,...)==1 and select(500,...)==500) end;" &
         "check(pcall(many));check(xpcall(many,function(e)return e end))");
   end Result_Growth_After_Protection;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "windows: protected wide arguments overlap",
                        Protected_Wide_Arguments'Access);
      Test_Support.Add (Suite, "windows: pcall discards excess argument roots",
                        Pcall_Discards_Excess'Access);
      Test_Support.Add (Suite, "windows: xpcall releases excess roots",
                        Xpcall_Discards_Excess'Access);
      Test_Support.Add (Suite, "windows: native tail retains Lua caller",
                        Native_Tail_Caller'Access);
      Test_Support.Add (Suite, "windows: native tail error keeps locals",
                        Native_Tail_Error_Frame'Access);
      Test_Support.Add (Suite, "windows: vararg prep precedes call hook",
                        Vararg_Call_Hook'Access);
      Test_Support.Add (Suite, "windows: protected open results retain top",
                        Result_Growth_After_Protection'Access);
   end Register;
end Shared_Window_Tests;
