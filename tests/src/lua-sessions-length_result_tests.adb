with AUnit.Assertions; use AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Lua.Conformance_Adapter;
with Lua.Conformance_Allocator;
with Lua.Storage;
with Test_Support;

package body Lua.Sessions.Length_Result_Tests is
   use type Lua.Storage.Byte_Count;

   procedure Check (Name : String; Refusal : Boolean := False);
   procedure Check (Name : String; Refusal : Boolean := False) is
      Self : Session;
      Result : Execution_Result;

      procedure Close_Checked;
      procedure Close_Checked is
      begin
         Conformance_Allocator.Clear_Count_Limit;
         Conformance_Allocator.Set_Byte_Limit (0);
         Self.Close;
         Conformance_Allocator.Finish;
         Assert (Conformance_Allocator.Measurements.Bytes = 0 and then
                 Conformance_Allocator.Measurements.Blocks = 0,
                 "length result retained selected provider storage");
      end Close_Checked;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      if Refusal then Conformance_Adapter.Install (Self.State.all); end if;
      Result := Self.Execute
        ((if Name = "empty-refusal" then
             "assert(loadfile('tests/lua/length_empty_result_refusal.lua'))()"
          elsif Refusal then
             "assert(loadfile('tests/lua/length_result_refusal.lua'))()"
          else "assert(loadfile('tests/lua/length_result_semantics.lua'))('" &
            Name & "')"), "=length-result");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Assert (Index
                (Result.Output,
                 (if Name = "empty-refusal" then
                     "PASS: length-empty-result-refusal"
                  else "PASS: length-result-" & Name)) > 0,
              "length result did not complete its actual fixture");
      Close_Checked;
   exception
      when others => Close_Checked; raise;
   end Check;

   procedure First_Result;
   procedure First_Result is
   begin
      --  Extra handler returns never escape a single-result length operator.
      Check ("first");
   end First_Result;

   procedure Empty_Result;
   procedure Empty_Result is
   begin
      --  A handler with no values still supplies exactly one nil result.
      Check ("empty");
   end Empty_Result;

   procedure Error_Recovery;
   procedure Error_Recovery is
   begin
      Check ("failure");
   end Error_Recovery;

   procedure Actual_Refusal;
   procedure Actual_Refusal is
   begin
      --  The handler leaves actual M0 armed until the caller gets its value.
      --  No empty table, frame or result arena may be created on that path.
      Check ("refusal", Refusal => True);
   end Actual_Refusal;

   procedure Empty_Refusal;
   procedure Empty_Refusal is
   begin
      --  No returned value means a real nil result, even when the consumed
      --  argument arena is the only already allocated empty packet available.
      Check ("empty-refusal", Refusal => True);
   end Empty_Refusal;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "length result: first only",
                        First_Result'Access);
      Test_Support.Add (Suite, "length result: empty becomes nil",
                        Empty_Result'Access);
      Test_Support.Add (Suite, "length result: error recovery",
                        Error_Recovery'Access);
      Test_Support.Add (Suite, "length result: callback leaves M0",
                        Actual_Refusal'Access);
      Test_Support.Add (Suite, "length result: empty callback leaves M0",
                        Empty_Refusal'Access);
   end Register;
end Lua.Sessions.Length_Result_Tests;
