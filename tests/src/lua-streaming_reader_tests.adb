with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.Streaming_Reader_Tests is
   use type Lua.Storage.Byte_Count;
   function Callback (Which : Interfaces.C.int) return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_streaming_reader";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Install (State : in out World; Which : Interfaces.C.int);
   procedure Dispose (State : in out World);
   procedure Source_Work_Quota;
   procedure Nested_Work_Quota;
   procedure Semantic_Reader_Error;

   procedure Install (State : in out World; Which : Interfaces.C.int) is
      Item : Value;
   begin
      Begin_Operation (State);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Callback (Which));
      Set (State, Global_Environment (State), New_String (State, "reader"),
           Item);
      End_Operation (State);
   end Install;

   procedure Dispose (State : in out World) is
   begin
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "all reader/frontend/driver storage released");
   end Dispose;

   procedure Source_Work_Quota is
      State : World;
   begin
      --  Acquisition really copies the foreign piece through managed input.
      --  Its work exceeds this host budget, and Lua pcall cannot convert that
      --  configured abort into an ordinary catchable reader error.
      Initialize (State, (Instructions => 200, others => <>));
      Install (State, 1);
      Assert (not Execute
        (State, "pcall(reader); error('quota was caught')", "reader-budget"),
        "source acquisition must stop the bounded host execution");
      Assert (State.Current.Failure_Class = Host_Abort,
              "source work is a host quota, not a Lua memory/error result");
      Assert (Execute (State, "return 17", "reader-recovery"),
              "fresh host chunk recovers after typed reader abort");
      Dispose (State);
   exception
      when others => Finalize (State); raise;
   end Source_Work_Quota;

   procedure Nested_Work_Quota is
      State : World;
   begin
      --  The reader invokes actual Lua through the same borrowed driver.
      --  Its loop must consume this existing budget; beginning a second
      --  executor or resetting steps would let the outer pcall continue.
      Initialize (State, (Instructions => 200, others => <>));
      Install (State, 2);
      Assert (not Execute
        (State, "pcall(reader); error('nested quota was caught')",
         "nested-reader-budget"), "nested reader work must share its budget");
      Assert (State.Current.Failure_Class = Host_Abort,
              "nested C refill returns a typed uncatchable host abort");
      Assert (Execute (State, "return 31", "nested-reader-recovery"),
              "nested protected driver restores the host after abort");
      Dispose (State);
   exception
      when others => Finalize (State); raise;
   end Nested_Work_Quota;

   procedure Semantic_Reader_Error is
      State : World;
   begin
      --  A reader's arbitrary error table is ordinary Lua behavior. It
      --  survives the C guard and frontend cleanup and stays catchable,
      --  distinct from the two explicit quota failures above.
      Initialize (State, (others => <>));
      Install (State, 3);
      Assert (Execute (State,
        "local ok,e=pcall(reader); " &
        "assert(not ok and type(e)=='table' and e.code==99)",
        "reader-table-error"), Failure_Image (State.Current));
      Dispose (State);
   exception
      when others => Finalize (State); raise;
   end Semantic_Reader_Error;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "streaming reader: managed source work budget",
         Source_Work_Quota'Access);
      Test_Support.Add
        (Suite, "streaming reader: nested execution shares budget",
         Nested_Work_Quota'Access);
      Test_Support.Add
        (Suite, "streaming reader: semantic table error remains catchable",
         Semantic_Reader_Error'Access);
   end Register;
end Lua.Streaming_Reader_Tests;
