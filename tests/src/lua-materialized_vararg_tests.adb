with AUnit.Assertions; use AUnit.Assertions;
with Lua.Conformance_Adapter;
with Lua.Conformance_Allocator;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with Test_Support;

package body Lua.Materialized_Vararg_Tests is
   use type Lua.Storage.Byte_Count;
   procedure Check (Name : String; Faults : Boolean := False);
   procedure Payload_Types;
   procedure Nil_Holes;
   procedure Fresh_Aliases;
   procedure Captured_Table;
   procedure Count_Faults;
   procedure Byte_Faults;
   procedure Partial_Release;
   procedure Retained_Recovery;

   procedure Check (Name : String; Faults : Boolean := False) is
      State : World;
      Success : Boolean;
   begin
      Initialize (State, (others => <>));
      if Faults then
         Conformance_Allocator.Attach (Lua.Storage.Reference (State.Memory));
         Conformance_Adapter.Install (State);
      end if;
      Success := Execute
        (State, "_MATERIALIZED_VARARG_CASE='" & Name &
         "';dofile('tests/lua/materialized_vararg" &
         (if Faults then "_refusal" else "") & ".lua')",
         "=materialized-vararg");
      if Faults then
         Conformance_Allocator.Clear_Count_Limit;
         Conformance_Allocator.Set_Byte_Limit (0);
      end if;
      Assert (Success, Failure_Image (State.Current));
      if Faults then
         Assert (Lua.Storage.Statistics (State.Memory).Refusals > 0,
                 "vararg fault fixture did not refuse actual growth");
      end if;
      Finalize (State);
      if Faults then Conformance_Allocator.Finish; end if;
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "materialized varargs retained selected provider blocks");
   exception
      when others =>
         if Faults then
            Conformance_Allocator.Clear_Count_Limit;
            Conformance_Allocator.Set_Byte_Limit (0);
         end if;
         Lua.Storage.Clear_Failures (State.Memory);
         Finalize (State);
         if Faults then Conformance_Allocator.Finish; end if;
         raise;
   end Check;

   procedure Payload_Types is
   begin
      --  Return the original five arguments as a real table with their
      --  integer/string types and exact length.
      Check ("Payload_Types");
   end Payload_Types;

   procedure Nil_Holes is
   begin
      --  Preserve leading, interior and trailing nils plus empty and
      --  one-nil lengths.
      Check ("Nil_Holes");
   end Nil_Holes;

   procedure Fresh_Aliases is
   begin
      --  Create a fresh table per invocation while preserving
      --  argument-object aliases.
      Check ("Fresh_Aliases");
   end Fresh_Aliases;

   procedure Captured_Table is
   begin
      --  Keep the materialized table alive through a real escaped closure,
      --  then release its weak edge.
      Check ("Captured_Table");
   end Captured_Table;

   procedure Count_Faults is
   begin
      --  Increase actual allocation allowance one by one until success;
      --  every earlier outcome must be a real memory error.
      Check ("Count_Faults", Faults => True);
   end Count_Faults;

   procedure Byte_Faults is
   begin
      --  Increase actual provider bytes by seven until success; verify
      --  recovery and the full original payload.
      Check ("Byte_Faults", Faults => True);
   end Byte_Faults;

   procedure Partial_Release is
   begin
      --  Drop every failed partial construction and source closure, then
      --  prove the payload weak edge dies.
      Check ("Partial_Release", Faults => True);
   end Partial_Release;

   procedure Retained_Recovery is
   begin
      --  Keep an earlier successful result rooted through refusal, then
      --  recover with a distinct fresh result.
      Check ("Retained_Recovery", Faults => True);
   end Retained_Recovery;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "materialized vararg: Payload_Types",
         Payload_Types'Access);
      Test_Support.Add
        (Suite, "materialized vararg: Nil_Holes",
         Nil_Holes'Access);
      Test_Support.Add
        (Suite, "materialized vararg: Fresh_Aliases",
         Fresh_Aliases'Access);
      Test_Support.Add
        (Suite, "materialized vararg: Captured_Table",
         Captured_Table'Access);
      Test_Support.Add
        (Suite, "materialized vararg: Count_Faults",
         Count_Faults'Access);
      Test_Support.Add
        (Suite, "materialized vararg: Byte_Faults",
         Byte_Faults'Access);
      Test_Support.Add
        (Suite, "materialized vararg: Partial_Release",
         Partial_Release'Access);
      Test_Support.Add
        (Suite, "materialized vararg: Retained_Recovery",
         Retained_Recovery'Access);
   end Register;
end Lua.Materialized_Vararg_Tests;
