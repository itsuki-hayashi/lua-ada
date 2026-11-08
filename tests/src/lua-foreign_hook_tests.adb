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
   procedure Hook_Scalar_Cells;
   procedure Hook_Nested_Call;
   procedure Hook_Protected_Error;
   procedure Hook_Unprotected_Error;
   procedure Hook_Blocks_Nested_Yield;
   procedure Hook_Direct_Yield;
   procedure Hook_Argument_Weak_Root;
   procedure Hook_Upvalue_Weak_Root;
   procedure External_Release_Lua_View;
   procedure C_Return_Value_Mutation;
   procedure C_Return_Weak_Root;

   procedure C_Return_Value_Mutation is
   begin
      --  A custom C return hook writes the real first transfer slot. The
      --  protected C caller must receive 37 rather than a stale copy of 11.
      Assert (Contract (25) = 0, "C return hook edits actual delivered cell");
   end C_Return_Value_Mutation;

   procedure C_Return_Weak_Root is
   begin
      --  The C body returns a table referenced only by its real result and
      --  a weak entry. Replacing that cell with nil lets hook GC reclaim it.
      Assert (Contract (26) = 0, "C return hook drops stale result roots");
   end C_Return_Weak_Root;

   procedure External_Release_Lua_View is
   begin
      --  Release an actual external payload during a Lua allocation loop.
      --  The callback borrows that real CI, concatenates with Lua handlers,
      --  mutates an earlier pending operand through debug.setlocal, and sees
      --  each consumed tail disappear at its actual fold boundary.
      Assert (Contract (24) = 0, "external release borrows actual Lua CI");
   end External_Release_Lua_View;

   procedure Hook_Argument_Weak_Root is
   begin
      --  Replace type's real C argument with nil, then collect in the call
      --  hook. No copied packet may retain the former weak table value, and
      --  the resumed builtin must consume nil from its actual edited slot.
      Assert (Contract (22) = 0, "C hook removes stale argument roots");
   end Hook_Argument_Weak_Root;

   procedure Hook_Upvalue_Weak_Root is
   begin
      --  Address the interrupted C closure's real upvalue pseudo-index.
      --  Replacing its sole edge must allow collection before body entry.
      Assert (Contract (23) = 0, "C hook removes stale captured roots");
   end Hook_Upvalue_Weak_Root;

   procedure Hook_Scalar_Cells is
   begin
      --  Raw C indices and debug locals denote the same interrupted cells.
      --  Replacing local x through lua_replace changes the caller's result.
      Assert (Contract (16) = 0, "C hook borrows actual Lua scalar cells");
   end Hook_Scalar_Cells;

   procedure Hook_Nested_Call is
   begin
      --  Remove the hook, call Lua, and inspect its hook origin. The borrow
      --  must survive nested stack growth and restore the original prefix.
      Assert (Contract (17) = 0, "C hook retains cells through nested Lua");
   end Hook_Nested_Call;

   procedure Hook_Protected_Error is
   begin
      --  A nested protected C error returns its real object above the same
      --  prefix, allowing the hook to edit a local and return normally.
      Assert (Contract (18) = 0, "C hook restores view after nested error");
   end Hook_Protected_Error;

   procedure Hook_Unprotected_Error is
   begin
      --  Raising integer 17 abandons the hook guard, releases its borrowed
      --  view on typed acknowledgement, and leaves the universe reusable.
      Assert (Contract (19) = 0, "C hook error releases actual view lease");
   end Hook_Unprotected_Error;

   procedure Hook_Blocks_Nested_Yield is
   begin
      --  Lua called synchronously by a C hook cannot yield across that live
      --  body. Its protected error cannot corrupt the interrupted locals.
      Assert (Contract (20) = 0, "C hook nested yield retains C boundary");
   end Hook_Blocks_Nested_Yield;

   procedure Hook_Direct_Yield is
   begin
      --  A direct zero-result hook yield returns normally from C, suspends
      --  once, then resumes the same instruction with original local cells.
      Assert (Contract (21) = 0, "C hook yield restores interrupted stack");
   end Hook_Direct_Yield;

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
      --  supports protected calls; the failed child retains public ERRMEM
      --  status both while allocation is refused and after scalar stack
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
      Test_Support.Add (Suite, "C hooks: actual scalar cells and mutation",
                        Hook_Scalar_Cells'Access);
      Test_Support.Add (Suite, "C hooks: nested call restores borrowed cells",
                        Hook_Nested_Call'Access);
      Test_Support.Add (Suite, "C hooks: protected error restores view",
                        Hook_Protected_Error'Access);
      Test_Support.Add (Suite, "C hooks: unprotected error releases view",
                        Hook_Unprotected_Error'Access);
      Test_Support.Add (Suite, "C hooks: nested yield is nonyieldable",
                        Hook_Blocks_Nested_Yield'Access);
      Test_Support.Add (Suite, "C hooks: direct yield restores instruction",
                        Hook_Direct_Yield'Access);
      Test_Support.Add (Suite, "C hooks: replaced argument loses weak root",
                        Hook_Argument_Weak_Root'Access);
      Test_Support.Add (Suite, "C hooks: replaced upvalue loses weak root",
                        Hook_Upvalue_Weak_Root'Access);
      Test_Support.Add (Suite, "C release: borrowed Lua cells and concat",
                        External_Release_Lua_View'Access);
      Test_Support.Add (Suite, "C hooks: return mutation reaches C caller",
                        C_Return_Value_Mutation'Access);
      Test_Support.Add (Suite, "C hooks: return replacement drops weak root",
                        C_Return_Weak_Root'Access);
   end Register;
end Lua.Foreign_Hook_Tests;
