with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Finalizers;
with Test_Support;

package body Lua.Finalizer_Queue_Tests is
   package F renames Lua.Engine.Finalizers;
   function Dead (Item : Object_Access) return Boolean;
   function Dead (Item : Object_Access) return Boolean is
     (not Item.Marked);

   function Target (State : in out World) return Value;
   function Target (State : in out World) return Value is
      Meta : constant Value := New_Table (State);
      Item : constant Value := New_Table (State);
   begin
      Set (State, Meta, New_String (State, "__gc"),
           New_Native (State, "base.print"));
      --  Raw fixture setup leaves enrollment timing to each component case.
      --  Public metatable assignment is exercised by integration tests.
      Item.Reference.Metatable := Meta.Reference;
      return Item;
   end Target;

   generic
      with procedure Behavior (State : in out World);
   procedure Fixture;
   procedure Fixture is
      State : World;
   begin
      --  Queue-component fixtures own only their explicitly enrolled objects;
      --  standard stream finalizers belong to the integration fixtures.
      State.Open_Standard_Libraries := False;
      Initialize (State, (others => <>));
      Begin_Operation (State);
      begin
         --  These component cases test intrusive ownership transitions.
         --  The collector/scheduler integration has separate Lua cases; no
         --  direct callback or simulated public collection success is used.
         Behavior (State);
      exception
         when others => End_Operation (State); Finalize (State); raise;
      end;
      End_Operation (State);
      Finalize (State);
   end Fixture;

   procedure Nil_Handler_Not_Registered (State : in out World);
   procedure Nil_Handler_Not_Registered (State : in out World) is
      Item : Value;
      Meta : Value;
   begin
      --  Assign a metatable without __gc to an ordinary table.
      --  Attempt enrollment through the internal ownership component.
      --  No finalizer obligation or list link is created.
      Meta := New_Table (State);
      Item := New_Table (State);
      Set_Metatable (State, Item, Meta.Reference);
      F.Register (State, Item);
      Assert (not Item.Reference.Finalizer_Registered and then
                State.Finalizable_Head = null, "nil event enrolled object");
   end Nil_Handler_Not_Registered;
   procedure Run_Nil_Handler_Not_Registered is new Fixture
     (Nil_Handler_Not_Registered);

   procedure Noncallable_Handler_Is_Registered (State : in out World);
   procedure Noncallable_Handler_Is_Registered (State : in out World) is
      Item : Value;
      Meta : Value;
   begin
      --  Use false as a nonnil raw __gc event.
      --  Register the metatable-assignment obligation without calling it.
      --  Callable validation is deferred to the real scheduler call.
      Meta := New_Table (State);
      Set (State, Meta, New_String (State, "__gc"), (Boolean_Kind, False));
      Item := New_Table (State);
      Set_Metatable (State, Item, Meta.Reference);
      F.Register (State, Item);
      Assert (Item.Reference.Finalizer_Registered,
              "false is nonnil and must enroll for later callable dispatch");
   end Noncallable_Handler_Is_Registered;
   procedure Run_Noncallable_Handler_Is_Registered is new Fixture
     (Noncallable_Handler_Is_Registered);

   procedure Reverse_Enrollment_Order (State : in out World);
   procedure Reverse_Enrollment_Order (State : in out World) is
      Item, Other : Value;
   begin
      --  Create two objects, then bless the younger before the older.
      --  Separate both and consume the queued targets.
      --  Finalization order follows reverse enrollment rather than creation.
      Item := Target (State);
      Other := Target (State);
      F.Register (State, Other);
      F.Register (State, Item);
      F.Queue_Unreachable (State, Dead'Access);
      F.Begin_Next (State);
      Assert (F.Current_Target (State) = Item, "creation order used");
      F.Finish_Current (State);
      F.Begin_Next (State);
      Assert (F.Current_Target (State) = Other, "enrollment tail lost");
      F.Finish_Current (State);
      Assert (not F.Has_Pending (State), "pending queue retained tail");
   end Reverse_Enrollment_Order;
   procedure Run_Reverse_Enrollment_Order is new Fixture
     (Reverse_Enrollment_Order);

   procedure Duplicate_Enrollment (State : in out World);
   procedure Duplicate_Enrollment (State : in out World) is
      Item, Other : Value;
   begin
      --  Enroll two targets and repeat assignment for the first.
      --  Separate the outstanding obligations and inspect the first target.
      --  An already registered object is not linked twice or reordered.
      Item := Target (State);
      Other := Target (State);
      F.Register (State, Item);
      F.Register (State, Other);
      F.Register (State, Item);
      F.Queue_Unreachable (State, Dead'Access);
      F.Begin_Next (State);
      Assert (F.Current_Target (State) = Other,
              "duplicate enrollment moved an existing obligation");
      F.Finish_Current (State);
   end Duplicate_Enrollment;
   procedure Run_Duplicate_Enrollment is new Fixture
     (Duplicate_Enrollment);

   procedure Pending_Batch_Append (State : in out World);
   procedure Pending_Batch_Append (State : in out World) is
      Item, Other : Value;
   begin
      --  Leave one separated target pending before enrolling another.
      --  Separate the new batch without executing either handler.
      --  Previously queued work stays ahead of the new batch.
      Item := Target (State);
      F.Register (State, Item);
      F.Queue_Unreachable (State, Dead'Access);
      Other := Target (State);
      F.Register (State, Other);
      F.Queue_Unreachable (State, Dead'Access);
      F.Begin_Next (State);
      Assert (F.Current_Target (State) = Item, "new batch overtook pending");
      F.Finish_Current (State);
      F.Begin_Next (State);
      Assert (F.Current_Target (State) = Other, "new batch was dropped");
      F.Finish_Current (State);
   end Pending_Batch_Append;
   procedure Run_Pending_Batch_Append is new Fixture
     (Pending_Batch_Append);

   procedure Predicate_Preserves_Live (State : in out World);
   procedure Predicate_Preserves_Live (State : in out World) is
      Item, Other : Value;
   begin
      --  Mark one registered target as live in the component fixture.
      --  Supply the collector predicate when separating the other target.
      --  Color/generation policy remains outside the finalizer component.
      Item := Target (State);
      Other := Target (State);
      F.Register (State, Item);
      F.Register (State, Other);
      Item.Reference.Marked := True;
      F.Queue_Unreachable (State, Dead'Access);
      Assert (State.Finalizable_Head = Item.Reference,
              "reachable registration left its ownership list");
      F.Begin_Next (State);
      Assert (F.Current_Target (State) = Other,
              "collector reachability predicate was ignored");
      F.Finish_Current (State);
   end Predicate_Preserves_Live;
   procedure Run_Predicate_Preserves_Live is new Fixture
     (Predicate_Preserves_Live);

   procedure Removed_Handler (State : in out World);
   procedure Removed_Handler (State : in out World) is
      Item : Value;
   begin
      --  Separate a target and remove its metatable before invocation.
      --  Prepare the next finalizer from its actual current metatable.
      --  Enrollment survives, while a nil handler requests no invented close.
      Item := Target (State);
      F.Register (State, Item);
      F.Queue_Unreachable (State, Dead'Access);
      Set_Metatable (State, Item, null);
      F.Begin_Next (State);
      Assert (F.Current_Target (State) = Item and then
                F.Current_Handler (State).Kind = Nil_Kind,
              "removed __gc was snapshotted or replaced by a fallback");
      F.Finish_Current (State);
   end Removed_Handler;
   procedure Run_Removed_Handler is new Fixture
     (Removed_Handler);

   procedure Replaced_Handler (State : in out World);
   procedure Replaced_Handler (State : in out World) is
      Item : Value;
      Meta : Value;
   begin
      --  Queue a target, then replace its metatable/event.
      --  Prepare the callback without invoking Lua from this component.
      --  The chosen handler is the replacement, not an old snapshot.
      Item := Target (State);
      F.Register (State, Item);
      F.Queue_Unreachable (State, Dead'Access);
      Meta := New_Table (State);
      Set (State, Meta, New_String (State, "__gc"), (Integer_Kind, 42));
      Set_Metatable (State, Item, Meta.Reference);
      F.Begin_Next (State);
      Assert (F.Current_Handler (State) = Value'(Integer_Kind, 42),
              "queued handler was captured before actual invocation");
      F.Finish_Current (State);
   end Replaced_Handler;
   procedure Run_Replaced_Handler is new Fixture
     (Replaced_Handler);

   procedure Current_Reenrollment (State : in out World);
   procedure Current_Reenrollment (State : in out World) is
      Item : Value;
   begin
      --  Begin a finalizer and emulate its explicit metatable re-assignment.
      --  Enroll the current object again, then finish the earlier invocation.
      --  Finishing releases current roots without removing the new obligation.
      Item := Target (State);
      F.Register (State, Item);
      F.Queue_Unreachable (State, Dead'Access);
      F.Begin_Next (State);
      F.Register (State, Item);
      F.Finish_Current (State);
      Assert (Item.Reference.Finalizer_Registered and then
                State.Finalizable_Head = Item.Reference,
              "finish overwrote callback re-enrollment");
      F.Queue_Unreachable (State, Dead'Access);
      F.Begin_Next (State);
      Assert (F.Current_Target (State) = Item, "renewed target lost");
      F.Finish_Current (State);
   end Current_Reenrollment;
   procedure Run_Current_Reenrollment is new Fixture
     (Current_Reenrollment);

   procedure Closing_Disables_Enrollment (State : in out World);
   procedure Closing_Disables_Enrollment (State : in out World) is
      Item, Other : Value;
   begin
      --  Keep an enrolled reachable object when explicit state close starts.
      --  Attempt another enrollment, then queue all existing obligations.
      --  Close includes prior live targets but prevents an endless new list.
      Item := Target (State);
      F.Register (State, Item);
      State.State_Close_Phase := True;
      Other := Target (State);
      F.Register (State, Other);
      Assert (not Other.Reference.Finalizer_Registered,
              "state-close callback enrolled another target");
      Item.Reference.Marked := True;
      F.Queue_Unreachable (State, Dead'Access, All_Objects => True);
      F.Begin_Next (State);
      Assert (F.Current_Target (State) = Item,
              "state close omitted an existing reachable obligation");
      F.Finish_Current (State);
   end Closing_Disables_Enrollment;
   procedure Run_Closing_Disables_Enrollment is new Fixture
     (Closing_Disables_Enrollment);

   procedure Queue_Is_Not_Execution (State : in out World);
   procedure Queue_Is_Not_Execution (State : in out World) is
      Item : Value;
   begin
      --  Enroll a target whose handler still needs normal callable dispatch.
      --  Separate it using only the allocation-free ownership helper.
      --  Collection publishes pending work without invoking or entering Lua.
      Item := Target (State);
      F.Register (State, Item);
      F.Queue_Unreachable (State, Dead'Access);
      Assert (F.Has_Pending (State) and then
                not State.Finalizer_Active and then
                State.Finalizing_Object = null,
              "collection entered a callback phase");
   end Queue_Is_Not_Execution;
   procedure Run_Queue_Is_Not_Execution is new Fixture
     (Queue_Is_Not_Execution);

   procedure Pending_Roots_Only (State : in out World);
   procedure Pending_Roots_Only (State : in out World) is
      Item : constant Value := Target (State);
      Other : constant Value := Target (State);
      procedure Mark (Node : Object_Access);
      procedure Mark (Node : Object_Access) is
      begin
         if Node /= null then Node.Marked := True; end if;
      end Mark;
   begin
      --  One target is pending and another merely registered/reachable.
      --  Visit only the component's actual strong ownership roots.
      --  Registered obligations must not become immortal strong references.
      F.Register (State, Item);
      F.Queue_Unreachable (State, Dead'Access);
      F.Register (State, Other);
      F.Trace_Roots (State, Mark'Access);
      Assert (Item.Reference.Marked and then not Other.Reference.Marked,
              "registration list was treated as a strong root");
   end Pending_Roots_Only;
   procedure Run_Pending_Roots_Only is new Fixture
     (Pending_Roots_Only);

   procedure Current_Handler_Root (State : in out World);
   procedure Current_Handler_Root (State : in out World) is
      Item : constant Value := Target (State);
      Handler : Value;
      procedure Mark (Node : Object_Access);
      procedure Mark (Node : Object_Access) is
      begin
         if Node /= null then Node.Marked := True; end if;
      end Mark;
   begin
      --  Prepare a selected handler, then replace its metatable edge.
      --  Trace the current callback while its argument holder can allocate.
      --  The chosen callable and target remain independently rooted.
      --  A stateless builtin is a scalar and requires no object root. This
      --  ownership witness deliberately selects a real captured closure so
      --  replacing the metatable edge still leaves collectable handler data.
      Set (State, (Table_Kind, Item.Reference.Metatable),
           New_String (State, "__gc"), New_Native
             (State, "base.print", One_Value (State, Nil_Value)));
      F.Register (State, Item);
      F.Queue_Unreachable (State, Dead'Access);
      F.Begin_Next (State);
      Handler := F.Current_Handler (State);
      Item.Reference.Metatable := null;
      F.Trace_Roots (State, Mark'Access);
      Assert (Item.Reference.Marked and then Handler.Reference.Marked,
              "current finalizer lost its independent handler root");
      F.Finish_Current (State);
      Item.Reference.Marked := False;
      Handler.Reference.Marked := False;
      F.Trace_Roots (State, Mark'Access);
      Assert (not Item.Reference.Marked and then not Handler.Reference.Marked,
              "finished callback kept hidden roots");
   end Current_Handler_Root;
   procedure Run_Current_Handler_Root is new Fixture
     (Current_Handler_Root);

   procedure Invalid_Current_Transition (State : in out World);
   procedure Invalid_Current_Transition (State : in out World) is
      Item : constant Value := Target (State);
      Other : constant Value := Target (State);
      Rejected : Boolean := False;
   begin
      --  Keep one current target with a second target still queued.
      --  Attempt to begin another without finishing the current borrow.
      --  Reject before consuming either list link or replacing a root.
      F.Register (State, Other);
      F.Register (State, Item);
      F.Queue_Unreachable (State, Dead'Access);
      F.Begin_Next (State);
      begin
         F.Begin_Next (State);
      exception
         when Program_Error => Rejected := True;
      end;
      Assert (Rejected and then F.Current_Target (State) = Item and then
                State.Finalizer_Head = Other.Reference,
              "invalid transition mutated finalizer ownership");
      F.Finish_Current (State);
   end Invalid_Current_Transition;
   procedure Run_Invalid_Current_Transition is new Fixture
     (Invalid_Current_Transition);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "finalizer queues: nil event is not registered",
         Run_Nil_Handler_Not_Registered'Access);
      Test_Support.Add
        (Suite, "finalizer queues: noncallable event still enrolls",
         Run_Noncallable_Handler_Is_Registered'Access);
      Test_Support.Add
        (Suite, "finalizer queues: reverse enrollment order",
         Run_Reverse_Enrollment_Order'Access);
      Test_Support.Add
        (Suite, "finalizer queues: repeated assignment preserves order",
         Run_Duplicate_Enrollment'Access);
      Test_Support.Add
        (Suite, "finalizer queues: pending batches append",
         Run_Pending_Batch_Append'Access);
      Test_Support.Add
        (Suite, "finalizer queues: collector predicate controls separation",
         Run_Predicate_Preserves_Live'Access);
      Test_Support.Add
        (Suite, "finalizer queues: removed handler has no fallback",
         Run_Removed_Handler'Access);
      Test_Support.Add
        (Suite, "finalizer queues: replacement handler is selected late",
         Run_Replaced_Handler'Access);
      Test_Support.Add
        (Suite, "finalizer queues: current target can enroll again",
         Run_Current_Reenrollment'Access);
      Test_Support.Add
        (Suite, "finalizer queues: state close stops new registrations",
         Run_Closing_Disables_Enrollment'Access);
      Test_Support.Add
        (Suite, "finalizer queues: separation never invokes Lua",
         Run_Queue_Is_Not_Execution'Access);
      Test_Support.Add
        (Suite, "finalizer queues: pending roots only",
         Run_Pending_Roots_Only'Access);
      Test_Support.Add
        (Suite, "finalizer queues: current handler root",
         Run_Current_Handler_Root'Access);
      Test_Support.Add
        (Suite, "finalizer queues: invalid transition preserves roots",
         Run_Invalid_Current_Transition'Access);
   end Register;
end Lua.Finalizer_Queue_Tests;
