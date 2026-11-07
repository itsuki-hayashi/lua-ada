with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Test_Support;

package body Lua.Math_Reopen_Tests is
   use type Interfaces.C.int;

   function Contract (Which : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_math_reopen_contract";

   procedure Opening_Preserves_Stream;
   procedure Independent_Streams;
   procedure Retained_Generator;
   procedure Shared_Userdata_Capture;
   procedure Refusal_Recovery;

   procedure Opening_Preserves_Stream is
   begin
      --  Seed the existing library before opening another through the real
      --  exported luaopen_math. Its next draw must still match that seed.
      Assert (Contract (1) = 0, "opening cannot reseed an existing module");
   end Opening_Preserves_Stream;

   procedure Independent_Streams is
   begin
      --  Equal seeds must produce equal streams even when the first module
      --  advances twice before the second module advances at all.
      Assert (Contract (2) = 0, "reopened RNG streams are independent");
   end Independent_Streams;

   procedure Retained_Generator is
   begin
      --  Retain only the old export closures, replace every old module root,
      --  and collect before drawing/reseeding through the retained pair.
      Assert (Contract (3) = 0, "retained closures keep their owned RNG");
   end Retained_Generator;

   procedure Shared_Userdata_Capture is
   begin
      --  Actual debug upvalue inspection observes shared userdata for the
      --  two exports of one module and another payload for a reopened one.
      Assert (Contract (4) = 0, "module exports share actual RNG userdata");
   end Shared_Userdata_Capture;

   procedure Refusal_Recovery is
   begin
      --  Refuse every growth while a real protected opener runs. Restore
      --  allocation and require the old stream, later opening and physical
      --  allocator cleanup to remain correct after the failed construction.
      Assert (Contract (5) = 0, "refused reopening preserves RNG and cleanup");
   end Refusal_Recovery;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "C math: reopening preserves previous stream",
         Opening_Preserves_Stream'Access);
      Test_Support.Add
        (Suite, "C math: reopened streams advance independently",
         Independent_Streams'Access);
      Test_Support.Add
        (Suite, "C math: retained generator survives collection",
         Retained_Generator'Access);
      Test_Support.Add (Suite, "C math: actual shared RNG userdata capture",
                        Shared_Userdata_Capture'Access);
      Test_Support.Add (Suite, "C math: refused reopening preserves stream",
                        Refusal_Recovery'Access);
   end Register;
end Lua.Math_Reopen_Tests;
