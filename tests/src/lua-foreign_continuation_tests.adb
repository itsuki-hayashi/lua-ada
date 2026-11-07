with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Test_Support;

package body Lua.Foreign_Continuation_Tests is
   use type Interfaces.C.int;
   function Contract (Which : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_continuation_contract";

   procedure Check (Which : Interfaces.C.int);
   procedure Check (Which : Interfaces.C.int) is
      Result : constant Interfaces.C.int := Contract (Which);
   begin
      Assert (Result = 0, "real C contract result" & Result'Image);
   end Check;

   --  Each C contract creates, exercises and closes its own real state. A
   --  separate AUnit registration keeps one failed boundary from hiding the
   --  other behaviors and gives the conformance ledger a stable case name.
   procedure Synchronous_Call;
   procedure Synchronous_Error;
   procedure Full_Context;
   procedure Repeated_Yield;
   procedure Fixed_Result;
   procedure Zero_Results;
   procedure Multiple_Results;
   procedure Protected_Error;
   procedure Forbidden_Yield;
   procedure Dead_Resume;
   procedure Captured_Root;
   procedure Module_Identity;
   procedure False_Module;
   procedure Preload_Mask;
   procedure Open_Precedence;
   procedure Metamethod_Indexing;
   procedure Immediate_Protected_Error;
   procedure Yieldable_Synchronous_Call;
   procedure Independent_Resume_Source;
   procedure Nested_Continuation_Boundaries;
   procedure Unprotected_Error_After_Yield;
   procedure Child_Yield_Without_K;
   procedure Lua_To_C_Resume;
   procedure Suspended_Dead_Temporaries;
   procedure Hook_Discards_Resume_Arguments;

   procedure Synchronous_Call is
   begin
      Check (1);
   end Synchronous_Call;
   procedure Synchronous_Error is
   begin
      Check (2);
   end Synchronous_Error;
   procedure Full_Context is
   begin
      Check (3);
   end Full_Context;
   procedure Repeated_Yield is
   begin
      Check (4);
   end Repeated_Yield;
   procedure Fixed_Result is
   begin
      Check (5);
   end Fixed_Result;
   procedure Zero_Results is
   begin
      Check (6);
   end Zero_Results;
   procedure Multiple_Results is
   begin
      Check (7);
   end Multiple_Results;
   procedure Protected_Error is
   begin
      Check (8);
   end Protected_Error;
   procedure Forbidden_Yield is
   begin
      Check (9);
   end Forbidden_Yield;
   procedure Dead_Resume is
   begin
      Check (10);
   end Dead_Resume;
   procedure Captured_Root is
   begin
      Check (11);
   end Captured_Root;
   procedure Module_Identity is
   begin
      Check (12);
   end Module_Identity;
   procedure False_Module is
   begin
      Check (13);
   end False_Module;
   procedure Preload_Mask is
   begin
      Check (14);
   end Preload_Mask;
   procedure Open_Precedence is
   begin
      Check (15);
   end Open_Precedence;
   procedure Metamethod_Indexing is
   begin
      Check (16);
   end Metamethod_Indexing;
   procedure Immediate_Protected_Error is
   begin
      Check (17);
   end Immediate_Protected_Error;
   procedure Yieldable_Synchronous_Call is
   begin
      Check (18);
   end Yieldable_Synchronous_Call;
   procedure Independent_Resume_Source is
   begin
      --  The from pointer contributes depth only. Actual results and stack
      --  ownership remain in the resumed state's independent universe.
      Check (19);
   end Independent_Resume_Source;
   procedure Nested_Continuation_Boundaries is
   begin
      --  One yield abandons three nested C pumps. Each continuation must
      --  retain its own result prefix and append34 exactly once on resume.
      Check (20);
   end Nested_Continuation_Boundaries;
   procedure Unprotected_Error_After_Yield is
   begin
      --  An abandoned unprotected C caller cannot turn a later error into
      --  success by receiving the protected-call continuation status.
      Check (21);
   end Unprotected_Error_After_Yield;
   procedure Child_Yield_Without_K is
   begin
      --  The suspended boundary belongs to the callk owner even when the
      --  deepest C callee has no continuation of its own.
      Check (22);
   end Child_Yield_Without_K;
   procedure Lua_To_C_Resume is
   begin
      --  Hand a Lua-resumed suspended context to the real C API. Public
      --  arguments must preserve its retained scalar registers and locals.
      Check (23);
   end Lua_To_C_Resume;
   procedure Suspended_Dead_Temporaries is
   begin
      --  An actual full collection while C has suspended a Lua frame must
      --  reclaim its dead locals despite the public window's high address.
      Check (24);
   end Suspended_Dead_Temporaries;
   procedure Hook_Discards_Resume_Arguments is
   begin
      --  A weak table observes that an argument passed to a suspended hook
      --  is discarded rather than retained on the interrupted Lua frame.
      Check (25);
   end Hook_Discards_Resume_Arguments;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "C K: synchronous call ignores continuation",
                        Synchronous_Call'Access);
      Test_Support.Add (Suite, "C K: synchronous protected error ignores K",
                        Synchronous_Error'Access);
      Test_Support.Add (Suite, "C K: full-width yielded context",
                        Full_Context'Access);
      Test_Support.Add (Suite, "C K: repeated yielding continuation",
                        Repeated_Yield'Access);
      Test_Support.Add (Suite, "C K: fixed result after suspension",
                        Fixed_Result'Access);
      Test_Support.Add (Suite, "C K: zero results after suspension",
                        Zero_Results'Access);
      Test_Support.Add (Suite, "C K: multiple results after suspension",
                        Multiple_Results'Access);
      Test_Support.Add (Suite, "C K: protected error after suspension",
                        Protected_Error'Access);
      Test_Support.Add
        (Suite, "C K: noncontinuation boundary rejects yield",
         Forbidden_Yield'Access);
      Test_Support.Add (Suite, "C resume: completed coroutine is dead",
                        Dead_Resume'Access);
      Test_Support.Add
        (Suite, "C K: closure root survives suspended collection",
         Captured_Root'Access);
      Test_Support.Add (Suite, "C libraries: requiref module identity",
                        Module_Identity'Access);
      Test_Support.Add
        (Suite, "C libraries: false loaded entry reopens module",
         False_Module'Access);
      Test_Support.Add (Suite, "C libraries: selected preload is lazy",
                        Preload_Mask'Access);
      Test_Support.Add (Suite, "C libraries: opening wins over preload",
                        Open_Precedence'Access);
      Test_Support.Add (Suite, "C indexing: handlers and raw bypass",
                        Metamethod_Indexing'Access);
      Test_Support.Add (Suite, "C K: immediate error in yieldable frame",
                        Immediate_Protected_Error'Access);
      Test_Support.Add (Suite, "C K: yieldable synchronous call ignores K",
                        Yieldable_Synchronous_Call'Access);
      Test_Support.Add (Suite, "C resume: independent from state",
                        Independent_Resume_Source'Access);
      Test_Support.Add (Suite, "C K: three nested continuation boundaries",
                        Nested_Continuation_Boundaries'Access);
      Test_Support.Add (Suite, "C K: unprotected error after yield",
                        Unprotected_Error_After_Yield'Access);
      Test_Support.Add (Suite, "C K: child yields without continuation",
                        Child_Yield_Without_K'Access);
      Test_Support.Add (Suite, "C resume: Lua to C ownership transfer",
                        Lua_To_C_Resume'Access);
      Test_Support.Add (Suite, "C resume: suspended dead temporaries collect",
                        Suspended_Dead_Temporaries'Access);
      Test_Support.Add (Suite, "C hooks: resume arguments are discarded",
                        Hook_Discards_Resume_Arguments'Access);
   end Register;
end Lua.Foreign_Continuation_Tests;
