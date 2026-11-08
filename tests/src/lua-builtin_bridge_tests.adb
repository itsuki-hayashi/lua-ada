with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.Builtin_Bridge_Tests is
   use type Lua.Storage.Byte_Count;
   function Callback return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_builtin_bridge";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Install (State : in out World);
   procedure Dispose (State : in out World);
   procedure Shared_Work_Quota;
   procedure Catchable_Callback_Error;

   procedure Install (State : in out World) is
      Item : Value;
   begin
      Begin_Operation (State);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Callback);
      Set (State, Global_Environment (State), New_String (State, "forward"),
           Item);
      End_Operation (State);
   end Install;

   procedure Dispose (State : in out World) is
   begin
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "direct builtin frames/call records release selected storage");
   end Dispose;

   procedure Shared_Work_Quota is
      State : World;
   begin
      --  A real C body obtains pairs through lua_tocfunction and calls that
      --  pointer directly. Its Lua __pairs loop must consume the original
      --  bounded driver's work; Lua pcall cannot catch a configured abort.
      Initialize (State, (Instructions => 200, others => <>));
      Install (State);
      Assert (not Execute (State,
        "local t=setmetatable({},{__pairs=function() " &
        "for i=1,10000 do end; return next,{},nil end});" &
        "pcall(forward,t); error('quota was caught')", "builtin-budget"),
        "direct builtin must share the actual host work counter");
      Assert (State.Current.Failure_Class = Host_Abort,
              "direct builtin work is an uncatchable host quota");
      Assert (Execute (State, "return 37", "builtin-recovery"),
              "typed C abort restores the existing host for its next chunk");
      Dispose (State);
   exception
      when others => Finalize (State); raise;
   end Shared_Work_Quota;

   procedure Catchable_Callback_Error is
      State : World;
   begin
      --  An arbitrary callback error is ordinary Lua behavior. It must keep
      --  table identity through the hidden phase and C guard, unlike quota
      --  failure, and leave no driver or prefix owner after successful pcall.
      Initialize (State, (others => <>));
      Install (State);
      Assert (Execute (State,
        "local marker={};local t=setmetatable({}," &
        "{__pairs=function()error(marker)end});" &
        "local ok,e=pcall(forward,t);assert(not ok and e==marker)",
        "builtin-table-error"), Failure_Image (State.Current));
      Dispose (State);
   exception
      when others => Finalize (State); raise;
   end Catchable_Callback_Error;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "builtin C bridge: direct callback shares host budget",
         Shared_Work_Quota'Access);
      Test_Support.Add
        (Suite, "builtin C bridge: arbitrary callback error identity",
         Catchable_Callback_Error'Access);
   end Register;
end Lua.Builtin_Bridge_Tests;
