with Ada.Unchecked_Deallocation;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Conformance_Adapter;
with Lua.Conformance_Allocator;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Compiler;
with Lua.Engine.Machine;
with Lua.Engine.Stacks;
with Lua.Storage;
with Test_Support;

package body Lua.Scalar_Closing_Tests is
   use type Lua.Storage.Byte_Count;
   package VM renames Lua.Engine.Machine;
   procedure Free_World is new Ada.Unchecked_Deallocation
     (World, World_Access);
   procedure Uncaptured_Slot;
   procedure Liveness_Independent_Root;
   procedure Invalid_Link_Recovery;
   procedure Wrong_Frame_Head;
   procedure Outside_Context_Head;
   procedure Check_Mutation (Name : String);
   procedure Nil_Mutation;
   procedure False_Mutation;
   procedure False_Type_Closer;
   procedure Outer_Error_GC_Recovery;

   generic
      with procedure Behavior (State : World_Access; Item : Frame_Access);
   procedure Slot_Fixture;
   procedure Slot_Fixture is
      State : World_Access := new World;
      Driver : VM.Driver;
      Code : Prototype_Access;
      Item : Frame_Access;
   begin
      Initialize (State.all, (others => <>));
      State.Canonical_Compilation := True;
      Code := Compiler.Compile
        (State.all, "local x <close> =setmetatable({}," &
         "{__close=function()end});return 37", "=scalar-close-owner");
      VM.Start (Driver, State, Code);
      for Step in 1 .. 200 loop
         Item := State.Current.Stack.Last_Element;
         exit when not Item.Is_Native and then Item.C_Closing_Level /= 0;
         Assert (not VM.Is_Complete (Driver), "closer marked too late");
         VM.Step (Driver);
      end loop;
      Assert (not Item.Is_Native and then Item.C_Closing_Level /= 0,
              "missing actual scalar closing declaration");
      Behavior (State, Item);
      VM.Cancel (Driver);
      VM.Clear_Frames (State.all);
      Finalize (State.all);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "scalar closing owner retained physical storage");
      Free_World (State);
   exception
      when others =>
         if State /= null then
            VM.Cancel (Driver);
            Finalize (State.all);
            Free_World (State);
         end if;
         raise;
   end Slot_Fixture;

   procedure Check_Uncaptured (State : World_Access; Item : Frame_Access);
   procedure Check_Uncaptured (State : World_Access; Item : Frame_Access) is
   begin
      --   A real TBC opcode alone must create neither an upvalue cell nor a
      --   private closer record. Its initialized scalar/link rows already own
      --   the marked declaration; the first predecessor terminates the chain.
      Assert (State.Current.Stack_Cells.Element (Item.C_Closing_Level) = null
              and then Item.Closers.Is_Empty,
              "marking a scalar closer created an artificial capture");
      Assert (Stacks.Closing_Predecessor (Item, Item.C_Closing_Level) = 0,
              "single closer has a foreign predecessor");
   end Check_Uncaptured;

   procedure Check_Root (State : World_Access; Item : Frame_Access);
   procedure Check_Root (State : World_Access; Item : Frame_Access) is
      Target : constant Object_Access :=
        Stacks.Read (State.Current, Item.C_Closing_Level).Reference;
      Top : constant Natural := Item.Canonical_GC_Top;
   begin
      --   Simulate an exhausted debug/compiler live interval. A genuine
      --   pending closer remains a scalar root independently of that extent.
      Item.Canonical_GC_Top := 0;
      Collect (State.all);
      Assert (State.Heap.Contains (Target) and then
              Stacks.Read (State.Current, Item.C_Closing_Level).Reference =
                Target, "liveness clearing destroyed a pending closer");
      Item.Canonical_GC_Top := Top;
   end Check_Root;

   procedure Check_Invalid (State : World_Access; Item : Frame_Access);
   procedure Check_Invalid (State : World_Access; Item : Frame_Access) is
      Level : constant Natural := Item.C_Closing_Level;
      Previous : Natural;
      Rejected : Boolean := False;
   begin
      --   A cycle must fail a checked query without traversing indefinitely
      --   or clearing the actual value. Restore the real chain and collect
      --   again to prove that rejection leaves ownership recoverable.
      State.Current.C_Close_Links.Replace_Element
        (Level, (Previous => Level));
      begin
         Previous := Stacks.Closing_Predecessor (Item, Level);
      exception
         when Program_Error => Rejected := True;
      end;
      State.Current.C_Close_Links.Replace_Element (Level, (Previous => 0));
      Assert (Rejected, "non-descending scalar closing link was accepted");
      Previous := Stacks.Closing_Predecessor (Item, Level);
      Assert (Previous = 0, "rejected closing link was not recoverable");
      Collect (State.all);
   end Check_Invalid;

   procedure Check_Wrong_Frame (State : World_Access; Item : Frame_Access);
   procedure Check_Wrong_Frame (State : World_Access; Item : Frame_Access) is
      Child : constant Frame_Access := New_Frame (State.all);
      Original : constant Natural := Item.C_Closing_Level;
      Level, Previous : Natural;
      Rejected : Boolean := False;
   begin
      --  Publish a genuine initialized child window above the marked owner.
      --  Its value is valid context storage but must not become this parent's
      --  head merely because a parallel link exists at the same index.
      Child.Is_Native := True;
      Child.Stack_Base := Item.Stack_Base + Item.Stack_Window_Length + 1;
      Child.Call_Base := Child.Stack_Base;
      Child.Stack_Live_Top := Child.Stack_Base + 1;
      State.Current.Stack.Append (Child);
      VM.Resize_Stack_Window (State.all, Child, 1);
      Level := Child.Stack_Base + 1;
      Stacks.Write
        (State.all, State.Current, Level,
         Stacks.Read (State.Current, Original));
      State.Current.C_Close_Links.Replace_Element (Level, (Previous => 0));
      Item.C_Closing_Level := Level;
      begin
         Previous := Stacks.Closing_Predecessor (Item, Level);
      exception
         when Program_Error => Rejected := True;
      end;
      Item.C_Closing_Level := Original;
      Assert (Rejected, "closing head accepted another frame's actual slot");
      Previous := Stacks.Closing_Predecessor (Item, Original);
      Assert (Previous = 0, "wrong-frame rejection damaged the actual chain");
      Collect (State.all);
   end Check_Wrong_Frame;

   procedure Check_Outside (State : World_Access; Item : Frame_Access);
   procedure Check_Outside (State : World_Access; Item : Frame_Access) is
      Original : constant Natural := Item.C_Closing_Level;
      Level : constant Natural :=
        Natural (State.Current.Foreign_Stack.Length) + 1;
      Previous : Natural;
      Rejected : Boolean := False;
   begin
      --  Unlike the child-window case, this index has no initialized context
      --  row at all. Query rejection must happen before dereferencing it.
      Item.C_Closing_Level := Level;
      begin
         Previous := Stacks.Closing_Predecessor (Item, Level);
      exception
         when Program_Error => Rejected := True;
      end;
      Item.C_Closing_Level := Original;
      Assert (Rejected, "closing head accepted an uninitialized context row");
      Previous := Stacks.Closing_Predecessor (Item, Original);
      Assert (Previous = 0, "out-of-context rejection damaged actual links");
      Collect (State.all);
   end Check_Outside;

   procedure Uncaptured_Case is new Slot_Fixture (Check_Uncaptured);
   procedure Root_Case is new Slot_Fixture (Check_Root);
   procedure Invalid_Case is new Slot_Fixture (Check_Invalid);
   procedure Wrong_Frame_Case is new Slot_Fixture (Check_Wrong_Frame);
   procedure Outside_Case is new Slot_Fixture (Check_Outside);

   procedure Uncaptured_Slot is
   begin
      Uncaptured_Case;
   end Uncaptured_Slot;

   procedure Liveness_Independent_Root is
   begin
      Root_Case;
   end Liveness_Independent_Root;

   procedure Invalid_Link_Recovery is
   begin
      Invalid_Case;
   end Invalid_Link_Recovery;

   procedure Wrong_Frame_Head is
   begin
      Wrong_Frame_Case;
   end Wrong_Frame_Head;

   procedure Outside_Context_Head is
   begin
      Outside_Case;
   end Outside_Context_Head;

   procedure Check (Name : String; Require_Refusal : Boolean := False);
   procedure Original_Failure;
   procedure Multiple_Failure;
   procedure Closer_Failure;
   procedure Cold_True;
   procedure Nil_Entry;
   procedure False_Entry;
   procedure Closed_Upvalue;
   procedure Mutable_Stack;
   procedure Suspended_Roots;
   procedure Captured_Suspended;
   procedure Generic_For_Scope;
   procedure Jump_Scope;

   procedure Check (Name : String; Require_Refusal : Boolean := False) is
      State : World;
      Success : Boolean;
   begin
      Initialize (State, (others => <>));
      Conformance_Allocator.Attach (Lua.Storage.Reference (State.Memory));
      Conformance_Adapter.Install (State);
      Success := Execute
        (State, "_SCALAR_CLOSING_CASE='" & Name &
         "';dofile('tests/lua/scalar_closing_refusal.lua')",
         "=scalar-closing");
      --   Reset only after the application has completed. A missing callback
      --   remains a failure; teardown must still release actual provider data.
      Conformance_Allocator.Clear_Count_Limit;
      Conformance_Allocator.Set_Byte_Limit (0);
      Assert (Success, Failure_Image (State.Current));
      if Require_Refusal then
         Assert (Lua.Storage.Statistics (State.Memory).Refusals > 0,
                 "closing fixture did not refuse actual provider growth");
      end if;
      Finalize (State);
      Conformance_Allocator.Finish;
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "scalar closing retained selected provider blocks");
   exception
      when others =>
         Conformance_Allocator.Clear_Count_Limit;
         Conformance_Allocator.Set_Byte_Limit (0);
         Lua.Storage.Clear_Failures (State.Memory);
         Finalize (State);
         Conformance_Allocator.Finish;
         raise;
   end Check;

   procedure Original_Failure is
   begin
      --  Mark a real closer after enter disables growth; its callback must
      --  lift the limit after the actual body allocation fails.
      Check ("Original_Failure", Require_Refusal => True);
   end Original_Failure;

   procedure Multiple_Failure is
   begin
      --  An inner memory failure reaches every lower closer and a genuine
      --  later error replaces it.
      Check ("Multiple_Failure", Require_Refusal => True);
   end Multiple_Failure;

   procedure Closer_Failure is
   begin
      --  A refusal inside one closer does not prevent the lower closer from
      --  lifting the limit.
      Check ("Closer_Failure", Require_Refusal => True);
   end Closer_Failure;

   procedure Cold_True is
   begin
      --  A cold TBC function can mark its existing truthy slot without fresh
      --  metadata under permanent refusal.
      Check ("Cold_True");
   end Cold_True;

   procedure Nil_Entry is
   begin
      --  A cold nil closing declaration adds no metadata allocation or
      --  callback.
      Check ("Nil_Entry");
   end Nil_Entry;

   procedure False_Entry is
   begin
      --  A cold false closing declaration adds no metadata allocation or
      --  callback.
      Check ("False_Entry");
   end False_Entry;

   procedure Closed_Upvalue is
   begin
      --  A handler can change a detached captured cell without replacing a
      --  lower pending scalar.
      Check ("Closed_Upvalue");
   end Closed_Upvalue;

   procedure Mutable_Stack is
   begin
      --  A handler changing the actual lower stack slot changes its eventual
      --  closing object.
      Check ("Mutable_Stack");
   end Mutable_Stack;

   procedure Suspended_Roots is
   begin
      --  Pending scalar closers survive suspension and collection, then
      --  disappear after genuine close.
      Check ("Suspended_Roots");
   end Suspended_Roots;

   procedure Captured_Suspended is
   begin
      --  Real lexical captures remain independent owned cells after
      --  suspended close.
      Check ("Captured_Suspended");
   end Captured_Suspended;

   procedure Generic_For_Scope is
   begin
      --  The iterator fourth closing value uses relative canonical scope
      --  depth and closes before the outer local.
      Check ("Generic_For_Scope");
   end Generic_For_Scope;

   procedure Jump_Scope is
   begin
      --  A goto closes only departing locals before the surviving outer
      --  closing scope.
      Check ("Jump_Scope");
   end Jump_Scope;

   procedure Check_Mutation (Name : String) is
      State : World;
      Success : Boolean;
   begin
      --  Ordinary public cases have no T installation or provider override.
      Initialize (State, (others => <>));
      Success := Execute
        (State, "_SCALAR_MUTATION_CASE='" & Name &
         "';dofile('tests/lua/scalar_closing_mutation.lua')",
         "=scalar-closing-mutation");
      Assert (Success, Failure_Image (State.Current));
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "mutated closing slot retained physical ownership");
   exception
      when others => Finalize (State); raise;
   end Check_Mutation;

   procedure Nil_Mutation is
   begin
      --  A truthily marked slot replaced by nil still dispatches its close
      --  and raises the native closing call error.
      Check_Mutation ("Nil_Mutation");
   end Nil_Mutation;

   procedure False_Mutation is
   begin
      --  A truthily marked slot replaced by false still dispatches its
      --  close and raises the native closing call error.
      Check_Mutation ("False_Mutation");
   end False_Mutation;

   procedure False_Type_Closer is
   begin
      --  A replaced false value uses its real type closer, while initial
      --  false stays unmarked; normal/error argument counts remain real.
      Check_Mutation ("False_Type_Closer");
   end False_Type_Closer;

   procedure Outer_Error_GC_Recovery is
   begin
      --  An outer closer sees the replacement error, discarded old values
      --  die during GC, and a healthy new closing call succeeds.
      Check_Mutation ("Outer_Error_GC_Recovery");
   end Outer_Error_GC_Recovery;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "scalar closing: no artificial capture",
         Uncaptured_Slot'Access);
      Test_Support.Add
        (Suite, "scalar closing: independent live root",
         Liveness_Independent_Root'Access);
      Test_Support.Add
        (Suite, "scalar closing: invalid link recovery",
         Invalid_Link_Recovery'Access);
      Test_Support.Add
        (Suite, "scalar closing: reject another frame head",
         Wrong_Frame_Head'Access);
      Test_Support.Add
        (Suite, "scalar closing: reject uninitialized head",
         Outside_Context_Head'Access);
      Test_Support.Add
        (Suite, "scalar closing: Original_Failure",
         Original_Failure'Access);
      Test_Support.Add
        (Suite, "scalar closing: Multiple_Failure",
         Multiple_Failure'Access);
      Test_Support.Add
        (Suite, "scalar closing: Closer_Failure",
         Closer_Failure'Access);
      Test_Support.Add
        (Suite, "scalar closing: Cold_True",
         Cold_True'Access);
      Test_Support.Add
        (Suite, "scalar closing: Nil_Entry",
         Nil_Entry'Access);
      Test_Support.Add
        (Suite, "scalar closing: False_Entry",
         False_Entry'Access);
      Test_Support.Add
        (Suite, "scalar closing: Closed_Upvalue",
         Closed_Upvalue'Access);
      Test_Support.Add
        (Suite, "scalar closing: Mutable_Stack",
         Mutable_Stack'Access);
      Test_Support.Add
        (Suite, "scalar closing: Suspended_Roots",
         Suspended_Roots'Access);
      Test_Support.Add
        (Suite, "scalar closing: Captured_Suspended",
         Captured_Suspended'Access);
      Test_Support.Add
        (Suite, "scalar closing: Generic_For_Scope",
         Generic_For_Scope'Access);
      Test_Support.Add
        (Suite, "scalar closing: Jump_Scope",
         Jump_Scope'Access);
      Test_Support.Add
        (Suite, "scalar mutation: Nil_Mutation",
         Nil_Mutation'Access);
      Test_Support.Add
        (Suite, "scalar mutation: False_Mutation",
         False_Mutation'Access);
      Test_Support.Add
        (Suite, "scalar mutation: False_Type_Closer",
         False_Type_Closer'Access);
      Test_Support.Add
        (Suite, "scalar mutation: Outer_Error_GC_Recovery",
         Outer_Error_GC_Recovery'Access);
   end Register;
end Lua.Scalar_Closing_Tests;
