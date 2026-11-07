with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.C_Substitution_Tests is
   use type Interfaces.C.int;
   use type Lua.Storage.Byte_Count;
   function Check (Which : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_substitution";
   function Callback (Choice : Interfaces.C.int) return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_substitution_budget";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Bounded_Check
     (Choice : Interfaces.C.int; Bounds : Limits;
      Recover_First : Boolean := True);
   procedure Empty_Pattern_Quota;
   procedure Comparison_Quota;
   procedure Heap_Disposal;
   procedure Literal_Metachars;
   procedure Nonoverlap;
   procedure No_Rescan;
   procedure Shrink;
   procedure Grow;
   procedure Empty_Replacement;
   procedure No_Match;
   procedure Empty_Subject;
   procedure Prefix_Suffix;
   procedure Nul_Subject;
   procedure Nul_Pattern;
   procedure Append_Reuse;
   procedure Large_Prefix;
   procedure Callback_Result;
   procedure Callback_Error;
   procedure Refusal_Recovery;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Literal_Metachars is
   begin
      Assert (Check (0) = 1, "literal metacharacters");
   end Literal_Metachars;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Nonoverlap is
   begin
      Assert (Check (1) = 1, "nonoverlapping matches");
   end Nonoverlap;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure No_Rescan is
   begin
      Assert (Check (2) = 1, "replacement not rescanned");
   end No_Rescan;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Shrink is
   begin
      Assert (Check (3) = 1, "shrinking replacement");
   end Shrink;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Grow is
   begin
      Assert (Check (4) = 1, "growing replacement");
   end Grow;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Empty_Replacement is
   begin
      Assert (Check (5) = 1, "empty replacement");
   end Empty_Replacement;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure No_Match is
   begin
      Assert (Check (6) = 1, "no match");
   end No_Match;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Empty_Subject is
   begin
      Assert (Check (7) = 1, "empty subject");
   end Empty_Subject;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Prefix_Suffix is
   begin
      Assert (Check (8) = 1, "prefix and suffix");
   end Prefix_Suffix;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Nul_Subject is
   begin
      Assert (Check (9) = 1, "NUL subject");
   end Nul_Subject;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Nul_Pattern is
   begin
      Assert (Check (10) = 1, "NUL pattern");
   end Nul_Pattern;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Append_Reuse is
   begin
      Assert (Check (11) = 1, "buffer append reuse");
   end Append_Reuse;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Large_Prefix is
   begin
      Assert (Check (12) = 1, "large growth prefix");
   end Large_Prefix;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Callback_Result is
   begin
      Assert (Check (13) = 1, "callback result");
   end Callback_Result;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Callback_Error is
   begin
      Assert (Check (14) = 1, "callback error cleanup");
   end Callback_Error;

   --  Shared C source documents the actual setup/action/expected contract.
   procedure Refusal_Recovery is
   begin
      Assert (Check (15) = 1, "refusal and recovery");
   end Refusal_Recovery;

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
      Set (State, Global_Environment (State), New_String (State, "substitute"),
           Item);
      End_Operation (State);
      Assert (not Execute (State,
        "pcall(substitute); error('substitution abort was caught')",
        "substitution-quota"),
        "C substitution share the configured uncatchable host policy");
      Assert (State.Current.Failure_Class = Host_Abort,
              "a host quota must not become a catchable memory error");
      if Recover_First then
         Assert (Execute (State, "return 37", "substitution-quota-recovery"),
                 "real C guard restores the host after substitution abort");
      end if;
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "physical userdata cleanup releases all buffer ownership");
   exception
      when others => Finalize (State); raise;
   end Bounded_Check;


   procedure Empty_Pattern_Quota is
   begin
      --  Native empty-pattern behavior does not progress. The bounded
      --  session must still stop the actual exported helper and recover.
      Bounded_Check (0, (Instructions => 2_000, others => <>));
   end Empty_Pattern_Quota;

   procedure Comparison_Quota is
   begin
      --  Initial scans fit; actual common-prefix comparisons exceed quota.
      Bounded_Check (1, (Instructions => 2_000, others => <>));
   end Comparison_Quota;

   procedure Heap_Disposal is
   begin
      --  Do not run Lua again before physical cleanup of the promoted box.
      Bounded_Check
        (2, (Instructions => 20_000, others => <>),
         Recover_First => False);
   end Heap_Disposal;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "C substitution: literal metacharacters",
                        Literal_Metachars'Access);
      Test_Support.Add (Suite, "C substitution: nonoverlapping matches",
                        Nonoverlap'Access);
      Test_Support.Add (Suite, "C substitution: replacement not rescanned",
                        No_Rescan'Access);
      Test_Support.Add (Suite, "C substitution: shrinking replacement",
                        Shrink'Access);
      Test_Support.Add (Suite, "C substitution: growing replacement",
                        Grow'Access);
      Test_Support.Add (Suite, "C substitution: empty replacement",
                        Empty_Replacement'Access);
      Test_Support.Add (Suite, "C substitution: no match",
                        No_Match'Access);
      Test_Support.Add (Suite, "C substitution: empty subject",
                        Empty_Subject'Access);
      Test_Support.Add (Suite, "C substitution: prefix and suffix",
                        Prefix_Suffix'Access);
      Test_Support.Add (Suite, "C substitution: NUL subject",
                        Nul_Subject'Access);
      Test_Support.Add (Suite, "C substitution: NUL pattern",
                        Nul_Pattern'Access);
      Test_Support.Add (Suite, "C substitution: buffer append reuse",
                        Append_Reuse'Access);
      Test_Support.Add (Suite, "C substitution: large growth prefix",
                        Large_Prefix'Access);
      Test_Support.Add (Suite, "C substitution: callback result",
                        Callback_Result'Access);
      Test_Support.Add (Suite, "C substitution: callback error cleanup",
                        Callback_Error'Access);
      Test_Support.Add (Suite, "C substitution: refusal and recovery",
                        Refusal_Recovery'Access);
      Test_Support.Add (Suite, "C substitution: empty pattern quota",
                        Empty_Pattern_Quota'Access);
      Test_Support.Add (Suite, "C substitution: actual comparison quota",
                        Comparison_Quota'Access);
      Test_Support.Add (Suite, "C substitution: heap disposal without Lua",
                        Heap_Disposal'Access);
   end Register;
end Lua.C_Substitution_Tests;
