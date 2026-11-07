with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.C_Buffer_Tests is
   use type Interfaces.C.int;
   use type Lua.Storage.Byte_Count;
   function Check (Which : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_buffer";
   function Callback (Choice : Interfaces.C.int) return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_buffer_budget";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Bounded_Check
     (Choice : Interfaces.C.int; Bounds : Limits;
      Recover_First : Boolean := True);
   procedure Scan_Quota;
   procedure Extent_Quota;
   procedure Heap_Abort_Cleanup;
   procedure Near_Limit_Growth;
   procedure Heap_Disposal_Without_Lua;
   procedure Empty_Result;
   procedure Fixed_Binary_Nul;
   procedure Zero_Null_Add;
   procedure Addstring_Terminator;
   procedure Direct_Prep_Addsize;
   procedure Initial_Small;
   procedure Initial_Heap;
   procedure Addvalue_Collection;
   procedure Growth_Prefix;
   procedure Sub_And_Character;
   procedure Nested_Buffers;
   procedure Callback_Result;
   procedure Callback_Error;
   procedure Abandoned_Close;
   procedure Growth_Refusal;
   procedure Header_Refusal;
   procedure Captured_Provider;

   --  The identical C source documents setup/action/expected results and
   --  runs against native default/T. Every case owns a fresh provider state
   --  and checks cleanup after close; these are real operations, not mocks.
   procedure Empty_Result is
   begin
      Assert (Check (0) = 1, "empty result and placeholder");
   end Empty_Result;

   procedure Fixed_Binary_Nul is
   begin
      Assert (Check (1) = 1, "fixed scratch binary bytes");
   end Fixed_Binary_Nul;

   procedure Zero_Null_Add is
   begin
      Assert (Check (2) = 1, "zero length null append");
   end Zero_Null_Add;

   procedure Addstring_Terminator is
   begin
      Assert (Check (3) = 1, "C string terminator");
   end Addstring_Terminator;

   procedure Direct_Prep_Addsize is
   begin
      Assert (Check (4) = 1, "prepared space and size");
   end Direct_Prep_Addsize;

   procedure Initial_Small is
   begin
      Assert (Check (5) = 1, "initial small space");
   end Initial_Small;

   procedure Initial_Heap is
   begin
      Assert (Check (6) = 1, "initial heap space");
   end Initial_Heap;

   procedure Addvalue_Collection is
   begin
      Assert (Check (7) = 1, "addvalue survives collection");
   end Addvalue_Collection;

   procedure Growth_Prefix is
   begin
      Assert (Check (8) = 1, "growth preserves each prefix");
   end Growth_Prefix;

   procedure Sub_And_Character is
   begin
      Assert (Check (9) = 1, "subtract and append characters");
   end Sub_And_Character;

   procedure Nested_Buffers is
   begin
      Assert (Check (10) = 1, "nested buffer ownership");
   end Nested_Buffers;

   procedure Callback_Result is
   begin
      Assert (Check (11) = 1, "callback result window");
   end Callback_Result;

   procedure Callback_Error is
   begin
      Assert (Check (12) = 1, "callback error closes box");
   end Callback_Error;

   procedure Abandoned_Close is
   begin
      Assert (Check (13) = 1, "explicit abandoned close");
   end Abandoned_Close;

   procedure Growth_Refusal is
   begin
      Assert (Check (14) = 1, "each actual refused growth");
   end Growth_Refusal;

   procedure Header_Refusal is
   begin
      Assert (Check (15) = 1, "publication header refusal");
   end Header_Refusal;

   procedure Captured_Provider is
   begin
      Assert (Check (16) = 1, "published payload retains allocator/data pair");
   end Captured_Provider;

   procedure Bounded_Check
     (Choice : Interfaces.C.int; Bounds : Limits;
      Recover_First : Boolean := True)
   is
      State : World;
      Item : Value;
   begin
      Initialize (State, Bounds);
      Begin_Operation (State);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Callback (Choice));
      Set (State, Global_Environment (State), New_String (State, "buffer"),
           Item);
      End_Operation (State);
      Assert (not Execute (State,
        "pcall(buffer); error('buffer abort was caught')", "buffer-quota"),
        "C buffers share the configured uncatchable host policy");
      Assert (State.Current.Failure_Class = Host_Abort,
              "a host quota must not become a catchable memory error");
      if Recover_First then
         Assert (Execute (State, "return 37", "buffer-quota-recovery"),
                 "the real C guard restores the host after buffer abort");
      end if;
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "physical userdata cleanup releases all buffer ownership");
   exception
      when others => Finalize (State); raise;
   end Bounded_Check;

   procedure Scan_Quota is
   begin
      --  Foreign C text is scanned by the actual auxiliary export; a Lua
      --  protected caller cannot reset the instruction budget or catch it.
      Bounded_Check (1, (Instructions => 200, others => <>));
   end Scan_Quota;

   procedure Extent_Quota is
   begin
      --  Fixed caller scratch must obey the string policy at publication,
      --  even though it has not needed any input-sized managed allocation.
      Bounded_Check (2, (String_Bytes => 64, others => <>));
   end Extent_Quota;

   procedure Heap_Abort_Cleanup is
   begin
      --  A real promoted buffer precedes the failing second request. Host
      --  disposal may not run Lua, so its userdata resource fallback must
      --  release both descriptor and payload and permit later execution.
      Bounded_Check
        (3, (Instructions => 20_000, String_Bytes => 4_096, others => <>));
   end Heap_Abort_Cleanup;

   procedure Heap_Disposal_Without_Lua is
   begin
      --  Do not reset the work epoch or run another Lua collection before
      --  physical teardown. Only the attached native resource fallback can
      --  release this untransferred payload after the host abort.
      Bounded_Check
        (3, (Instructions => 20_000, String_Bytes => 4_096, others => <>),
         Recover_First => False);
   end Heap_Disposal_Without_Lua;

   procedure Near_Limit_Growth is
      State : World;
      Item : Value;
   begin
      --  The default growth proposal exceeds 1,300 bytes, but the requested
      --  content is only 1,224. Optional capacity must be capped rather than
      --  causing an otherwise valid bounded-session string to fail.
      Initialize (State, (String_Bytes => 1_300, others => <>));
      Begin_Operation (State);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Callback (4));
      Set (State, Global_Environment (State), New_String (State, "buffer"),
           Item);
      End_Operation (State);
      Assert (Execute (State,
        "local s=buffer(); assert(#s==1224 and s==string.rep('b',1224))",
        "buffer-near-limit"), "growth slack must not count as string content");
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "capped capacity and adopted payload are released");
   exception
      when others => Finalize (State); raise;
   end Near_Limit_Growth;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "C buffer: empty result and placeholder",
                        Empty_Result'Access);
      Test_Support.Add (Suite, "C buffer: fixed scratch binary bytes",
                        Fixed_Binary_Nul'Access);
      Test_Support.Add (Suite, "C buffer: zero length null append",
                        Zero_Null_Add'Access);
      Test_Support.Add (Suite, "C buffer: C string terminator",
                        Addstring_Terminator'Access);
      Test_Support.Add (Suite, "C buffer: prepared space and size",
                        Direct_Prep_Addsize'Access);
      Test_Support.Add (Suite, "C buffer: initial small space",
                        Initial_Small'Access);
      Test_Support.Add (Suite, "C buffer: initial heap space",
                        Initial_Heap'Access);
      Test_Support.Add (Suite, "C buffer: addvalue survives collection",
                        Addvalue_Collection'Access);
      Test_Support.Add (Suite, "C buffer: growth preserves each prefix",
                        Growth_Prefix'Access);
      Test_Support.Add (Suite, "C buffer: subtract and append characters",
                        Sub_And_Character'Access);
      Test_Support.Add (Suite, "C buffer: nested buffer ownership",
                        Nested_Buffers'Access);
      Test_Support.Add (Suite, "C buffer: callback result window",
                        Callback_Result'Access);
      Test_Support.Add (Suite, "C buffer: callback error closes box",
                        Callback_Error'Access);
      Test_Support.Add (Suite, "C buffer: explicit abandoned close",
                        Abandoned_Close'Access);
      Test_Support.Add (Suite, "C buffer: each actual refused growth",
                        Growth_Refusal'Access);
      Test_Support.Add (Suite, "C buffer: publication header refusal",
                        Header_Refusal'Access);
      Test_Support.Add (Suite, "C buffer: captured allocator and data",
                        Captured_Provider'Access);
      Test_Support.Add (Suite, "C buffer: bounded foreign scan",
                        Scan_Quota'Access);
      Test_Support.Add (Suite, "C buffer: bounded result extent",
                        Extent_Quota'Access);
      Test_Support.Add (Suite, "C buffer: bounded heap abort cleanup",
                        Heap_Abort_Cleanup'Access);
      Test_Support.Add (Suite, "C buffer: bounded near-limit growth",
                        Near_Limit_Growth'Access);
      Test_Support.Add (Suite, "C buffer: heap disposal without Lua",
                        Heap_Disposal_Without_Lua'Access);
   end Register;
end Lua.C_Buffer_Tests;
