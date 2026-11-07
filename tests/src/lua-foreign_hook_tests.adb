with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Test_Support;

package body Lua.Foreign_Hook_Tests is
   use type Interfaces.C.int;

   function Contract (Which : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_hook_contract";

   procedure Reflection;
   procedure Line_Events;
   procedure Count_Events;
   procedure Remove_Inside_Hook;
   procedure Independent_States;
   procedure Inactive_Frame;
   procedure C_Return_Close;
   procedure C_Error_Close;
   procedure C_Continuation_Close;
   procedure C_Error_Location;
   procedure Combined_Yield_Events;
   procedure C_Set_Top_Close;
   procedure C_Explicit_Close;
   procedure C_Refusal_Reuse;
   procedure C_Suspended_Indexing;

   procedure Reflection is
   begin
      --  Install a real C callback and inspect its identity, mask and signed
      --  count. The C consumer reports any mismatch to this separate case.
      Assert (Contract (1) = 0, "real C hook reflection");
   end Reflection;

   procedure Line_Events is
   begin
      --  Execute a multiline loop. Each actual line callback verifies that
      --  querying its interrupted frame reports the same positive line.
      Assert (Contract (2) = 0, "C line events and frame line metadata");
   end Line_Events;

   procedure Count_Events is
   begin
      --  Enable only instruction-count events with an interval of two.
      --  Multiple deliveries protect the numeric mask path from a nil mask.
      Assert (Contract (3) = 0, "count-only C hook dispatch");
   end Count_Events;

   procedure Remove_Inside_Hook is
   begin
      --  The first callback removes itself while the loop is still running.
      --  Require exactly one delivery and cleared public callback/mask data.
      Assert (Contract (4) = 0, "C hook removes itself before next event");
   end Remove_Inside_Hook;

   procedure Independent_States is
   begin
      --  Run two simultaneously live C-created states. Only the one with an
      --  installed hook may deliver that callback with its own state pointer.
      Assert (Contract (5) = 0, "independent C state hook ownership");
   end Independent_States;

   procedure Inactive_Frame is
   begin
      --  Retain a line hook's real frame token until after return. Querying
      --  it must fail safely instead of reading recycled activation storage.
      Assert (Contract (6) = 0, "inactive C debug frame token rejected");
   end Inactive_Frame;

   procedure C_Return_Close is
   begin
      --  A marked C slot closes on normal return. Its handler collects while
      --  the outgoing string must remain rooted in the unwind continuation.
      Assert (Contract (7) = 0, "C return closes and retains its result");
   end C_Return_Close;

   procedure C_Error_Close is
   begin
      --  Raise an arbitrary table through a marked C frame. The close
      --  callback and protected caller must see the same error identity.
      Assert (Contract (8) = 0, "C error closes with its actual error object");
   end C_Error_Close;

   procedure C_Continuation_Close is
   begin
      --  A Lua callee yields beneath a K-aware marked C frame. Closing waits
      --  for K to return and cannot replace its retained result under GC.
      Assert (Contract (9) = 0, "C continuation closes after resumed return");
   end C_Continuation_Close;

   procedure C_Error_Location is
   begin
      --  Calling base.error from a real C callback has no Lua caller source.
      --  Internal protection frames cannot fabricate a '(native)' location.
      Assert (Contract (10) = 0, "C caller has no fabricated Lua location");
   end C_Error_Location;
   procedure Combined_Yield_Events is
   begin
      --  Count and line callbacks can both request a yield for one opcode.
      --  They must observe the same real host-resume generation.
      Assert (Contract (14) = 0, "count and line precede one hook yield");
   end Combined_Yield_Events;

   procedure C_Set_Top_Close is
   begin
      --  Shrinking the C stack must close now, allowing the same lower slot
      --  to be marked again before return. Collection runs in both handlers.
      Assert (Contract (11) = 0, "C settop closes before slot reuse");
   end C_Set_Top_Close;

   procedure C_Explicit_Close is
   begin
      --  Explicit closeslot invokes the handler immediately and replaces the
      --  actual stack value with nil, without scheduling another return close.
      Assert (Contract (12) = 0, "C closeslot retires and clears the slot");
   end C_Explicit_Close;

   procedure C_Refusal_Reuse is
   begin
      --  Sweep real provider refusal points during resume. The healthy parent
      --  supports protected calls; the failed child still permits stack
      --  access. Physical close balances all counted provider allocations.
      Assert (Contract (13) = 0, "C resume refusal restores reusable owners");
   end C_Refusal_Reuse;

   procedure C_Suspended_Indexing is
   begin
      --  Read/write handlers run above a suspended Lua thread, including GC.
      --  Its old frame, public table and resume result must all remain intact.
      Assert (Contract (15) = 0, "C indexing retains suspended execution");
   end C_Suspended_Indexing;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "C hooks: callback mask and count reflection",
                        Reflection'Access);
      Test_Support.Add (Suite, "C hooks: actual line events and inspection",
                        Line_Events'Access);
      Test_Support.Add (Suite, "C hooks: count-only instruction events",
                        Count_Events'Access);
      Test_Support.Add (Suite, "C hooks: callback removes itself",
                        Remove_Inside_Hook'Access);
      Test_Support.Add (Suite, "C hooks: independent state ownership",
                        Independent_States'Access);
      Test_Support.Add (Suite, "C hooks: inactive frame token rejected",
                        Inactive_Frame'Access);
      Test_Support.Add (Suite, "C close: normal return retains result",
                        C_Return_Close'Access);
      Test_Support.Add (Suite, "C close: error preserves object identity",
                        C_Error_Close'Access);
      Test_Support.Add (Suite, "C close: continuation retains slot and result",
                        C_Continuation_Close'Access);
      Test_Support.Add (Suite, "C errors: logical caller location",
                        C_Error_Location'Access);
      Test_Support.Add (Suite, "C hooks: combined events before yield",
                        Combined_Yield_Events'Access);
      Test_Support.Add (Suite, "C close: settop closes before slot reuse",
                        C_Set_Top_Close'Access);
      Test_Support.Add (Suite, "C close: explicit slot becomes nil",
                        C_Explicit_Close'Access);
      Test_Support.Add (Suite, "C resume: refusal restores reusable owners",
                        C_Refusal_Reuse'Access);
      Test_Support.Add (Suite, "C indexing: suspended thread retains frames",
                        C_Suspended_Indexing'Access);
   end Register;
end Lua.Foreign_Hook_Tests;
