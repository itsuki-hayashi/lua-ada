with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Test_Support;

package body Lua.Context_Tests is

   generic
      with procedure Action (State : in out World);
   procedure Fixture;

   procedure Fixture is
      State : World;
   begin
      Initialize (State, (others => <>));
      begin
         Action (State);
      exception
         when others =>
            Finalize (State);
            raise;
      end;
      Finalize (State);
   end Fixture;

   procedure Shared_Globals (State : in out World);
   procedure Isolated_Failures (State : in out World);
   procedure Argument_Root (State : in out World);
   procedure Error_Root (State : in out World);
   procedure Inactive_Frame_Root (State : in out World);
   procedure Selection_Guard (State : in out World);
   procedure Shared_Budget (State : in out World);
   procedure Context_Cleanup (State : in out World);

   procedure Shared_Globals (State : in out World) is
      Other : constant Context_Id := Create_Context (State);
   begin
      --  Execute in two contexts of one universe. Globals must be shared,
      --  while the stacks themselves remain separately owned containers.
      Assert (Execute (State, "answer=42", "first"), "first execution");
      Select_Context (State, Other);
      Assert (Execute (State, "print(answer)", "second"), "second execution");
      Assert (To_String (State.Output) = "42" & ASCII.LF, "shared globals");
      Assert (State.Current /= State.Contexts (1), "distinct context");
   end Shared_Globals;

   procedure Isolated_Failures (State : in out World) is
      Main : constant Context_Access := State.Current;
      Other : constant Context_Id := Create_Context (State);
   begin
      --  A recoverable failure belongs to its execution context. Successful
      --  execution elsewhere must neither inherit nor erase that diagnostic.
      Assert (not Execute (State, "error('retained')", "first"), "Lua error");
      Select_Context (State, Other);
      Assert (Execute (State, "assert(true)", "second"), "other recovery");
      Assert (Length (State.Current.Failure_Text) = 0, "clean other error");
      Assert (Index (Main.Failure_Text, "retained") > 0, "retained error");
      Select_Context (State, 1);
      Assert (Execute (State, "assert(true)", "recovery"), "main recovery");
      Assert (not (Main.Status = Running_Context),
        "driver released after recovery");
   end Isolated_Failures;

   procedure Argument_Root (State : in out World) is
      Other : constant Context_Id := Create_Context (State);
      Item : constant Value := New_Table (State);
   begin
      --  Only the inactive argument packet retains this otherwise unreachable
      --  table. Collect from main, then drop the packet and collect again.
      Select_Context (State, Other);
      State.Current.Arguments.Append (Item);
      Select_Context (State, 1);
      Collect (State);
      Assert (State.Heap.Contains (Item.Reference), "inactive argument root");
      State.Contexts (Positive (Other)).Arguments.Clear;
      Collect (State);
      Assert (not State.Heap.Contains (Item.Reference), "released argument");
   end Argument_Root;

   procedure Error_Root (State : in out World) is
      Other : constant Context_Id := Create_Context (State);
      Item : constant Value := New_Table (State);
   begin
      --  Lua errors may carry arbitrary objects. An inactive error value is
      --  just as much a root as a frame slot; clearing it allows collection.
      State.Contexts (Positive (Other)).Failure := Item;
      State.Contexts (Positive (Other)).Has_Failure_Value := True;
      Collect (State);
      Assert (State.Heap.Contains (Item.Reference), "inactive error root");
      State.Contexts (Positive (Other)).Failure := Nil_Value;
      State.Contexts (Positive (Other)).Has_Failure_Value := False;
      Collect (State);
      Assert (not State.Heap.Contains (Item.Reference), "released error");
   end Error_Root;

   procedure Inactive_Frame_Root (State : in out World) is
      Other : constant Context_Id := Create_Context (State);
      Activation : Frame_Access :=
        New_Frame (State, State.Contexts (Positive (Other)));
      Item : constant Value := New_String (State, "capture");
   begin
      --  Pending native callbacks retain captures even on an inactive stack.
      --  Releasing that activation removes its last root in the shared heap.
      Activation.Native_Captures.Append (Item);
      State.Contexts (Positive (Other)).Stack.Append (Activation);
      Collect (State);
      Assert (State.Heap.Contains (Item.Reference), "inactive frame capture");
      State.Contexts (Positive (Other)).Stack.Clear;
      Return_Frame (Activation);
      Collect (State);
      Assert (not State.Heap.Contains (Item.Reference), "released capture");
   end Inactive_Frame_Root;

   procedure Selection_Guard (State : in out World) is
      Main : constant Context_Access := State.Current;
      Other : constant Context_Id := Create_Context (State);
      Rejected : Boolean := False;
   begin
      --  A driver must never silently change the stack beneath its retained
      --  frame pointers. Rejection preserves both selector and running state.
      Main.Status := Running_Context;
      begin
         Select_Context (State, Other);
      exception
         when Program_Error => Rejected := True;
      end;
      Main.Status := Suspended_Context;
      Assert (Rejected and then State.Current = Main, "active driver guard");
      Rejected := False;
      begin
         Select_Context (State, Other + 1);
      exception
         when Program_Error => Rejected := True;
      end;
      Assert (Rejected and then State.Current = Main, "invalid context ID");
   end Selection_Guard;

   procedure Shared_Budget (State : in out World) is
      Other : constant Context_Id := Create_Context (State);
   begin
      --  Context selection is not a fresh public execution. Retained work
      --  and host limits belong to the universe and cannot be reset by it.
      State.Steps := 19;
      Select_Context (State, Other);
      Assert (State.Steps = 19, "context selection reset budget");
      Assert (State.Current.Stack.Is_Empty, "fresh context stack");
   end Shared_Budget;

   procedure Context_Cleanup (State : in out World) is
      Other : constant Context_Id := Create_Context (State);
   begin
      --  Finalize owns every inactive activation too. Calling it again must
      --  tolerate the empty registry and null borrowed selector.
      State.Contexts (Positive (Other)).Stack.Append
        (New_Frame (State, State.Contexts (Positive (Other))));
      Finalize (State);
      Finalize (State);
      Assert (State.Contexts.Is_Empty and then State.Current = null,
              "context registry released");
      Assert (State.Heap.Is_Empty, "world heap released");
   end Context_Cleanup;

   procedure Shared_Case is new Fixture (Shared_Globals);
   procedure Failure_Case is new Fixture (Isolated_Failures);
   procedure Argument_Case is new Fixture (Argument_Root);
   procedure Error_Case is new Fixture (Error_Root);
   procedure Frame_Case is new Fixture (Inactive_Frame_Root);
   procedure Guard_Case is new Fixture (Selection_Guard);
   procedure Budget_Case is new Fixture (Shared_Budget);
   procedure Cleanup_Case is new Fixture (Context_Cleanup);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "contexts: shared globals", Shared_Case'Access);
      Test_Support.Add
        (Suite, "contexts: isolated errors", Failure_Case'Access);
      Test_Support.Add
        (Suite, "contexts: argument roots", Argument_Case'Access);
      Test_Support.Add (Suite, "contexts: error roots", Error_Case'Access);
      Test_Support.Add (Suite, "contexts: frame roots", Frame_Case'Access);
      Test_Support.Add (Suite, "contexts: selection guard", Guard_Case'Access);
      Test_Support.Add (Suite, "contexts: shared budget", Budget_Case'Access);
      Test_Support.Add (Suite, "contexts: cleanup", Cleanup_Case'Access);
   end Register;
end Lua.Context_Tests;
