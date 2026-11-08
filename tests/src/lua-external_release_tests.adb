with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.External_Release_Tests is
   use type Interfaces.C.unsigned;
   use type Lua.Storage.Byte_Count;
   function Callback return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_make_external";
   function Release_Count return Interfaces.C.unsigned
     with Import, Convention => C,
          External_Name => "lua_ada_test_external_releases";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Install (State : in out World);
   procedure Release_Uses_Shared_Budget;
   procedure Disposal_After_Abort;

   procedure Install (State : in out World) is
      Item : Value;
   begin
      Begin_Operation (State);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Callback);
      Set (State, Global_Environment (State),
           New_String (State, "make_external"), Item);
      End_Operation (State);
   end Install;

   procedure Release_Uses_Shared_Budget is
      State : World;
      Before : constant Interfaces.C.unsigned := Release_Count;
   begin
      --  An actual C allocator frees its external payload, then calls a Lua
      --  closure. Its loop shares the original driver's quota and returns a
      --  typed host abort above the live C guard, never across Ada frames.
      Initialize (State, (Instructions => 1_000, others => <>));
      Install (State);
      Assert (not Execute (State,
        "function onrelease()for i=1,100000 do end end;" &
        "local x=make_external();x=nil;collectgarbage('collect')",
        "external-release-budget"), "release callback consumes host quota");
      Assert (State.Current.Failure_Class = Host_Abort and then
              Release_Count = Before + 1,
              "one actual free precedes an uncatchable shared-budget abort");
      Assert (Execute (State, "return 37", "external-release-recovery"),
              Failure_Image (State.Current));
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "guard abort releases detached headers and driver records");
   exception
      when others => Finalize (State); raise;
   end Release_Uses_Shared_Budget;

   procedure Disposal_After_Abort is
      State : World;
      Before : constant Interfaces.C.unsigned := Release_Count;
   begin
      --  The payload remains strongly reachable when ordinary Lua exhausts
      --  its quota. Physical disposal must still invoke its actual C free;
      --  attempted Lua reentry cannot restart the exhausted budget or stop
      --  the remaining context/header/provider teardown.
      Initialize (State, (Instructions => 1_000, others => <>));
      Install (State);
      Assert (not Execute (State,
        "function onrelease()return 1 end;kept=make_external();" &
        "for i=1,100000 do end", "external-disposal-budget"),
        "ordinary execution exhausts the original host quota");
      Assert (Release_Count = Before, "rooted payload remains owned");
      Finalize (State);
      Assert (Release_Count = Before + 1 and then
              Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "disposal frees exactly once despite stopped Lua reentry");
   exception
      when others => Finalize (State); raise;
   end Disposal_After_Abort;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "external release: reentry shares host work budget",
         Release_Uses_Shared_Budget'Access);
      Test_Support.Add
        (Suite, "external release: physical disposal after host abort",
         Disposal_After_Abort'Access);
   end Register;
end Lua.External_Release_Tests;
