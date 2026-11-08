with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Test_Support;

package body Lua.C_Allocator_Tests is
   use type Interfaces.C.int;
   function Check (Which : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_allocator";
   procedure Null_Old_Size;
   procedure Free_Null;
   procedure Growth_Prefix;
   procedure Shrink_Prefix;
   procedure Fresh_After_Free;
   procedure Numeric_Alignment;
   procedure Refusal_Preserves;
   procedure Allocator_Identity;
   procedure Default_Identity;
   procedure Live_Seed;
   procedure Null_Seed;
   procedure State_Cleanup;
   procedure Live_Stack_Cleanup;

   --  The shared C case documents setup/action/expected results and owns
   --  its fresh state or allocation; the native default/T oracle runs it too.
   procedure Null_Old_Size is
   begin
      Assert (Check (0) = 1, "null old size ignored");
   end Null_Old_Size;

   --  The shared C case documents setup/action/expected results and owns
   --  its fresh state or allocation; the native default/T oracle runs it too.
   procedure Free_Null is
   begin
      Assert (Check (1) = 1, "zero size frees");
   end Free_Null;

   --  The shared C case documents setup/action/expected results and owns
   --  its fresh state or allocation; the native default/T oracle runs it too.
   procedure Growth_Prefix is
   begin
      Assert (Check (2) = 1, "growth preserves prefix");
   end Growth_Prefix;

   --  The shared C case documents setup/action/expected results and owns
   --  its fresh state or allocation; the native default/T oracle runs it too.
   procedure Shrink_Prefix is
   begin
      Assert (Check (3) = 1, "shrink preserves prefix");
   end Shrink_Prefix;

   --  The shared C case documents setup/action/expected results and owns
   --  its fresh state or allocation; the native default/T oracle runs it too.
   procedure Fresh_After_Free is
   begin
      Assert (Check (4) = 1, "fresh after free");
   end Fresh_After_Free;

   --  The shared C case documents setup/action/expected results and owns
   --  its fresh state or allocation; the native default/T oracle runs it too.
   procedure Numeric_Alignment is
   begin
      Assert (Check (5) = 1, "numeric alignment");
   end Numeric_Alignment;

   --  The shared C case documents setup/action/expected results and owns
   --  its fresh state or allocation; the native default/T oracle runs it too.
   procedure Refusal_Preserves is
   begin
      Assert (Check (6) = 1, "refusal preserves old bytes");
   end Refusal_Preserves;

   --  The shared C case documents setup/action/expected results and owns
   --  its fresh state or allocation; the native default/T oracle runs it too.
   procedure Allocator_Identity is
   begin
      Assert (Check (7) = 1, "public allocator identity");
   end Allocator_Identity;

   --  The shared C case documents setup/action/expected results and owns
   --  its fresh state or allocation; the native default/T oracle runs it too.
   procedure Default_Identity is
   begin
      Assert (Check (8) = 1, "default state allocator identity");
   end Default_Identity;

   --  The shared C case documents setup/action/expected results and owns
   --  its fresh state or allocation; the native default/T oracle runs it too.
   procedure Live_Seed is
   begin
      Assert (Check (9) = 1, "live seed leaves state intact");
   end Live_Seed;

   --  The shared C case documents setup/action/expected results and owns
   --  its fresh state or allocation; the native default/T oracle runs it too.
   procedure Null_Seed is
   begin
      Assert (Check (10) = 1, "null seed accepted");
   end Null_Seed;

   --  The shared C case documents setup/action/expected results and owns
   --  its fresh state or allocation; the native default/T oracle runs it too.
   procedure State_Cleanup is
   begin
      Assert (Check (11) = 1, "counted state cleanup");
   end State_Cleanup;

   --  The shared C case documents setup/action/expected results and owns
   --  its fresh state or allocation; the native default/T oracle runs it too.
   procedure Live_Stack_Cleanup is
   begin
      Assert (Check (12) = 1, "live stack cleanup");
   end Live_Stack_Cleanup;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "C allocator: null old size ignored",
                        Null_Old_Size'Access);
      Test_Support.Add (Suite, "C allocator: zero size frees",
                        Free_Null'Access);
      Test_Support.Add (Suite, "C allocator: growth preserves prefix",
                        Growth_Prefix'Access);
      Test_Support.Add (Suite, "C allocator: shrink preserves prefix",
                        Shrink_Prefix'Access);
      Test_Support.Add (Suite, "C allocator: fresh after free",
                        Fresh_After_Free'Access);
      Test_Support.Add (Suite, "C allocator: numeric alignment",
                        Numeric_Alignment'Access);
      Test_Support.Add (Suite, "C allocator: refusal preserves old bytes",
                        Refusal_Preserves'Access);
      Test_Support.Add (Suite, "C allocator: public allocator identity",
                        Allocator_Identity'Access);
      Test_Support.Add (Suite, "C allocator: default state allocator identity",
                        Default_Identity'Access);
      Test_Support.Add (Suite, "C allocator: live seed leaves state intact",
                        Live_Seed'Access);
      Test_Support.Add (Suite, "C allocator: null seed accepted",
                        Null_Seed'Access);
      Test_Support.Add (Suite, "C allocator: counted state cleanup",
                        State_Cleanup'Access);
      Test_Support.Add (Suite, "C allocator: live stack cleanup",
                        Live_Stack_Cleanup'Access);
   end Register;
end Lua.C_Allocator_Tests;
