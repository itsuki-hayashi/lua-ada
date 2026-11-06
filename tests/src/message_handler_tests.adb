with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Message_Handler_Tests is
   procedure Check (Source : String);
   procedure Before_Closing;
   procedure Failing_Frame_Inspection;
   procedure Finite_Recursion;
   procedure Recursive_Overflow;
   procedure Infinite_Recursion;
   procedure Nil_Input;
   procedure Collection_During_Handler;
   procedure Nested_Pcall_Shadowing;
   procedure Close_Error_Transformation;
   procedure Failed_Handler_Closing;
   procedure Host_Abort_Bypasses_Handler;

   procedure Check (Source : String) is
      State : Session;
      Result : Execution_Result := State.Execute (Source, "=message-handler");
   begin
      Assert (Result.Status = Succeeded,
              "message-handler fixture failed: " &
              To_String (Result.Error.Message));
      --  Every scenario also verifies that no handler, hook suppression or
      --  non-yieldable charge remains attached to the next public execution.
      Result := State.Execute ("assert(true)", "=handler-recovery");
      Assert (Result.Status = Succeeded, "handler damaged session recovery");
   end Check;

   procedure Before_Closing is
   begin
      --  Keep a live closer in the failing target. The handler must precede
      --  it, and the closer must receive the transformed error rather than
      --  the original text or a post-unwind approximation.
      Check
        ("local order='';local function f()" &
         "local x <close> = setmetatable({}, {__close=function(_,e)" &
         "assert(e=='handled:body');order=order..'close' end});" &
         "error('body',0) end;local ok,e=xpcall(f,function(e)" &
         "order=order..'handler,';return 'handled:'..e end);" &
         "assert(not ok and e=='handled:body' and order=='handler,close')");
   end Before_Closing;

   procedure Failing_Frame_Inspection is
   begin
      --  The original Lua local and error frame must still exist while the
      --  handler queries real metadata. Running it after pcall unwound would
      --  lose both the local and the traceback's failing-function frame.
      Check
        ("local function f()local secret=42;error('body',0) end;" &
         "local ok,e=xpcall(f,function(e)local found=false;" &
         "for level=2,10 do local info=debug.getinfo(level,'f');" &
         "if info and info.func==f then " &
         "local name,value=debug.getlocal(level,1);" &
         "assert(name=='secret' and value==42);found=true end end;" &
         "assert(found);local trace=debug.traceback(e);" &
         "assert(string.find(trace,'message%-handler'));return e end);" &
         "assert(not ok and e=='body')");
   end Failing_Frame_Inspection;

   procedure Finite_Recursion is
   begin
      --  Derived from pinned testes/errors.lua:624-637 (Lua MIT notice in
      --  docs/licenses/lua.md). Each raised number recursively reenters the
      --  same handler until it returns END; no intermediate pcall succeeds.
      Check
        ("local function h(n)if type(n)~='number' then return n " &
         "elseif n==0 then return 'END' else error(n-1,0) end end;" &
         "local ok,e=xpcall(error,h,170);assert(not ok and e=='END')");
   end Finite_Recursion;

   procedure Recursive_Overflow is
   begin
      --  The companion pinned case errors.lua:639-640 exceeds the native
      --  error-entry limit. A handler can return the stack-overflow string;
      --  it must not immediately become generic error-in-error-handling.
      Check
        ("local function h(n)if type(n)~='number' then return n " &
         "elseif n==0 then return 'END' else error(n-1,0) end end;" &
         "local ok,e=xpcall(error,h,300);" &
         "assert(not ok and e=='C stack overflow')");
   end Recursive_Overflow;

   procedure Infinite_Recursion is
   begin
      --  A handler which always raises exhausts the extra error reserve. The
      --  fixed error object must propagate normally and leave a usable state.
      Check
        ("local ok,e=xpcall(error,error);" &
         "assert(not ok and e=='error in error handling')");
   end Infinite_Recursion;

   procedure Nil_Input is
   begin
      --  Lua 5.5 replaces nil only after message handling (ldebug.c:840-853).
      --  The handler must see the original nil, not an eagerly made string.
      Check
        ("local ok,e=xpcall(function()error(nil,0) end," &
         "function(v)assert(v==nil);return 'saw nil' end);" &
         "assert(not ok and e=='saw nil')");
   end Nil_Input;

   procedure Collection_During_Handler is
   begin
      --  A handler explicitly collects while the failed frame owns a local
      --  capture and table error. Their real identities must remain rooted.
      Check
        ("local marker={};local function f()local kept=marker;" &
         "local capture=function()return kept end;error(capture(),0) end;" &
         "local ok,e=xpcall(f,function(v)collectgarbage();return v end);" &
         "assert(not ok and e==marker)");
   end Collection_During_Handler;

   procedure Nested_Pcall_Shadowing is
   begin
      --  Explicit pcall installs a boundary with no message handler. It must
      --  shadow an outer xpcall handler while retaining its normal false/error
      --  result as successful return values of the surrounding target.
      Check
        ("local called=0;local ok,a,b=xpcall(function()" &
         "return pcall(error,'inner',0) end,function(e)called=called+1;" &
         "return e end);assert(ok and a==false and b=='inner' and called==0)");
   end Nested_Pcall_Shadowing;

   procedure Close_Error_Transformation is
   begin
      --  Raw internal close protection inherits the active handler. A new
      --  closer error is transformed once; an already transformed error must
      --  not run the same handler a third time when unwinding continues.
      Check
        ("local seen='';local ok,e=xpcall(function()" &
         "local x <close> = setmetatable({}, {__close=function(_,e)" &
         "assert(e=='body!');error('closer',0) end});error('body',0) end," &
         "function(e)seen=seen..e..',';return e..'!' end);" &
         "assert(not ok and e=='closer!' and seen=='body,closer,')");
   end Close_Error_Transformation;

   procedure Failed_Handler_Closing is
   begin
      --  Failed handler activations retain their own closing declarations.
      --  After the final handler succeeds they close once, inner to outer,
      --  with the final transformed error; the successful handler closes nil.
      Check
        ("local seen='';local function h(n)" &
         "local x <close> = setmetatable({}, {__close=function(_,e)" &
         "assert((n==0 and e==nil) or (n>0 and e=='END'));" &
         "seen=seen..n end});if n==0 then return 'END' end;error(n-1,0) end;" &
         "local ok,e=xpcall(error,h,3);" &
         "assert(not ok and e=='END' and seen=='0123')");
   end Failed_Handler_Closing;

   procedure Host_Abort_Bypasses_Handler is
      State : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      --  An explicit instruction quota is a host abort, never a Lua error
      --  which xpcall can transform or use to restart the execution budget.
      Bounds.Instructions := 100;
      State.Set_Limits (Bounds);
      Result := State.Execute
        ("called=false;xpcall(function()while true do end end," &
         "function()called=true;return 'caught' end)", "=handler-quota");
      Assert (Result.Status = Resource_Error, "quota became catchable");
      Result := State.Execute ("assert(called==false)", "=quota-recovery");
      Assert (Result.Status = Succeeded,
              "host abort invoked message handler");
   end Host_Abort_Bypasses_Handler;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "handler: runs before closing",
                        Before_Closing'Access);
      Test_Support.Add (Suite, "handler: inspects intact failing frames",
                        Failing_Frame_Inspection'Access);
      Test_Support.Add (Suite, "handler: finite recursive errors",
                        Finite_Recursion'Access);
      Test_Support.Add (Suite, "handler: recursive stack overflow",
                        Recursive_Overflow'Access);
      Test_Support.Add (Suite, "handler: infinite recursion failure",
                        Infinite_Recursion'Access);
      Test_Support.Add (Suite, "handler: receives original nil",
                        Nil_Input'Access);
      Test_Support.Add (Suite, "handler: collection keeps error identities",
                        Collection_During_Handler'Access);
      Test_Support.Add (Suite, "handler: pcall shadows outer handler",
                        Nested_Pcall_Shadowing'Access);
      Test_Support.Add (Suite, "handler: transforms new close errors once",
                        Close_Error_Transformation'Access);
      Test_Support.Add (Suite, "handler: closes failed handler activations",
                        Failed_Handler_Closing'Access);
      Test_Support.Add (Suite, "handler: bypassed by host abort",
                        Host_Abort_Bypasses_Handler'Access);
   end Register;
end Message_Handler_Tests;
