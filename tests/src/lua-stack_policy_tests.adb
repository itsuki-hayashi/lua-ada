with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Machine;
with Lua.Runtime_Configuration;
with Lua.Storage; use Lua.Storage;
with Test_Support;

package body Lua.Stack_Policy_Tests is
   package VM renames Lua.Engine.Machine;
   use type Byte_Count;

   generic
      with procedure Behavior (State : in out World);
   procedure Fixture;
   procedure Fixture is
      State : World;
   begin
      Initialize (State, (others => <>));
      begin
         Behavior (State);
      exception
         when others => Finalize (State); raise;
      end;
      Finalize (State);
      Assert (Statistics (State.Memory).Live_Blocks = 0,
              "stack-policy fixture retained managed storage");
   end Fixture;

   procedure Inclusive_Boundary (State : in out World);
   procedure Error_Reserve_Latch (State : in out World);
   procedure Nonthrowing_Growth (State : in out World);
   procedure Recovery_Resets_Latch (State : in out World);

   procedure Inclusive_Boundary (State : in out World) is
      Maximum : constant Positive := Lua.Runtime_Configuration.Maximum_Stack;
      Available : Boolean;
   begin
      --  Our row offsets omit native dummy slot zero. Last=MAXSTACK-1 is
      --  legal; Last=MAXSTACK would require an exclusive top above the bound.
      Available := VM.Ensure_Stack (State, State.Current, Maximum - 1);
      Assert (Available and then
              State.Current.Stack_Allocated_Bound = Maximum and then
              State.Current.Stack_Error_Phase = Normal_Stack,
              "last valid inclusive slot was rejected");
      begin
         Available := VM.Ensure_Stack (State, State.Current, Maximum);
         Assert (False, "exclusive top above MAXSTACK was accepted");
      exception
         when Language_Error => null;
      end;
      Assert (State.Current.Failure_Class = Language_Failure,
              "first stack overflow was not an ordinary Lua failure");
   end Inclusive_Boundary;

   procedure Error_Reserve_Latch (State : in out World) is
      Maximum : constant Positive := Lua.Runtime_Configuration.Maximum_Stack;
      Available : Boolean;
   begin
      --  Closing alone does not grant extra slots. The first real overflow
      --  installs exactly the pinned 200-row error bound; another request
      --  beyond it bypasses recursive handling with the stable ERRERR object.
      State.Current.Cleanup_Depth := 1;
      begin
         Available := VM.Ensure_Stack (State, State.Current, Maximum + 1);
         Assert (False, "ordinary closing received an overflow allowance");
      exception
         when Language_Error => null;
      end;
      State.Current.Cleanup_Depth := 0;
      Assert (State.Current.Stack_Error_Phase = Error_Stack and then
              State.Current.Stack_Allocated_Bound =
                Maximum + Error_Stack_Reserve,
              "first overflow did not install its exact error bound");
      Available := VM.Ensure_Stack
        (State, State.Current, Maximum + Error_Stack_Reserve - 1);
      Assert (Available, "last legal error-reserve slot was rejected");
      begin
         Available := VM.Ensure_Stack
           (State, State.Current, Maximum + Error_Stack_Reserve);
         Assert (False, "error stack was allowed to grow again");
      exception
         when Language_Error => null;
      end;
      Assert (State.Current.Failure_Class = Handling_Failure and then
              Equal (State.Current.Failure, State.Handling_Error_Value),
              "recursive overflow did not use the stable ERRERR object");
   end Error_Reserve_Latch;

   procedure Nonthrowing_Growth (State : in out World) is
      Available : Boolean;
   begin
      --  lua_checkstack can refuse an impossible request without raising a
      --  language error, yet pinned growstack still installs its error bound.
      Available := VM.Ensure_Stack
        (State, State.Current, Natural'Last, Raise_Error => False);
      Assert (not Available and then
              State.Current.Failure_Class = No_Failure and then
              State.Current.Stack_Error_Phase = Error_Stack,
              "nonthrowing growth raised or lost the overflow latch");
      Available := VM.Ensure_Stack
        (State, State.Current, Minimum_C_Stack, Raise_Error => False);
      Assert (Available, "failed checkstack damaged an existing small window");
   end Nonthrowing_Growth;

   procedure Recovery_Resets_Latch (State : in out World) is
      Available : Boolean;
      Before : Byte_Count;
   begin
      --  Protected recovery must leave error-stack mode once every retained
      --  real window fits normally. Resetting the semantic bound is separate
      --  from retained geometric capacity and cannot allocate under refusal.
      Available := VM.Ensure_Stack
        (State, State.Current, Natural'Last, Raise_Error => False);
      Assert (not Available, "oversized setup request unexpectedly fit");
      State.Current.Stack_Used := Minimum_C_Stack;
      State.Current.Foreign_Top := 0;
      Before := Statistics (State.Memory).Growth_Attempts;
      Set_Failure_Countdown (State.Memory, 0);
      VM.Shrink_Error_Stack (State, State.Current);
      Assert (State.Current.Stack_Error_Phase = Normal_Stack and then
              State.Current.Stack_Allocated_Bound =
                2 * (Minimum_C_Stack + 2),
              "recovery retained an exhausted error-stack phase");
      Assert (Statistics (State.Memory).Growth_Attempts = Before,
              "semantic recovery allocated while growth was refused");
      Clear_Failures (State.Memory);
   end Recovery_Resets_Latch;

   procedure Case_Boundary is new Fixture (Inclusive_Boundary);
   procedure Case_Reserve is new Fixture (Error_Reserve_Latch);
   procedure Case_Nonthrowing is new Fixture (Nonthrowing_Growth);
   procedure Case_Recovery is new Fixture (Recovery_Resets_Latch);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "stack policy: exact inclusive maximum",
                        Case_Boundary'Access);
      Test_Support.Add (Suite, "stack policy: overflow reserve then ERRERR",
                        Case_Reserve'Access);
      Test_Support.Add (Suite, "stack policy: nonthrowing checkstack overflow",
                        Case_Nonthrowing'Access);
      Test_Support.Add (Suite, "stack policy: recovery resets error latch",
                        Case_Recovery'Access);
   end Register;
end Lua.Stack_Policy_Tests;
