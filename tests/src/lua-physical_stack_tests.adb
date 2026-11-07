with Ada.Containers;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Stacks;
with Lua.Runtime_Configuration;
with Lua.Storage; use Lua.Storage;
with Test_Support;

package body Lua.Physical_Stack_Tests is
   use type Ada.Containers.Count_Type;
   use type Integer_Value;
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
         when others =>
            Clear_Failures (State.Memory);
            Finalize (State);
            raise;
      end;
      Clear_Failures (State.Memory);
      Finalize (State);
      Assert (Statistics (State.Memory).Live_Blocks = 0,
              "physical stack fixture released all actual managed blocks");
   end Fixture;

   procedure Prefix_Copy (State : in out World);
   procedure Prefix_Bounds (State : in out World);
   procedure Actual_Stack_Release (State : in out World);
   procedure First_Copy_Refusal (State : in out World);
   procedure Second_Copy_Refusal (State : in out World);
   procedure Alternate_Cache_Release (State : in out World);
   procedure Emergency_Keeps_Storage (State : in out World);
   procedure Ancestor_Reservation (State : in out World);
   procedure Error_Latch_Recovery (State : in out World);
   procedure Borrowed_Warning_Prefix (State : in out World);
   procedure Suspended_Thread_Shrink (State : in out World);

   procedure Prefix_Copy (State : in out World) is
      Source : Values.Vector := Owned_Values (State);
   begin
      --  Exact prefix copying is the typed alternative to raw realloc of a
      --  controlled buffer. It inherits the real owner, chooses no geometric
      --  excess, and leaves the source independent of subsequent mutations.
      Source.Reserve_Capacity (128);
      for Index in 1 .. 5 loop
         Source.Append (Value'(Integer_Kind, Integer_Value (Index)));
      end loop;
      declare
         Target : Values.Vector := Values.Copy_Prefix (Source, 3, 3);
      begin
         Assert (Target.Length = 3 and Target.Capacity = 3 and
                 Target.Owner_Of = Source.Owner_Of,
                 "exact prefix copied real length/capacity/allocator");
         Target.Replace_Element (1, Value'(Integer_Kind, 99));
         Assert (Source.Element (1).Integer_Data = 1 and Source.Length = 5,
                 "prefix copy retained independent controlled ownership");
      end;
   end Prefix_Copy;

   procedure Prefix_Bounds (State : in out World) is
      Source : constant Values.Vector :=
        One_Value (State, Value'(Integer_Kind, 7));
      Rejected : Boolean := False;
      Before : constant Byte_Count := Statistics (State.Memory).Raw_Bytes;
   begin
      --  An impossible copy cannot expose uninitialized slots or silently
      --  allocate through a default owner. Reject before altering the source.
      begin
         declare
            Target : constant Values.Vector :=
              Values.Copy_Prefix (Source, 2, 2);
         begin
            Assert (Target.Is_Empty, "invalid prefix unexpectedly returned");
         end;
      exception
         when Constraint_Error => Rejected := True;
      end;
      Assert (Rejected and Source.Length = 1 and
              Statistics (State.Memory).Raw_Bytes = Before,
              "invalid exact copy preserved source and allocator state");
      Rejected := False;
      begin
         declare
            Target : constant Values.Vector :=
              Values.Copy_Prefix (Values.Empty_Vector, 0, 1);
         begin
            Assert (Target.Is_Empty, "unowned copy unexpectedly returned");
         end;
      exception
         when Program_Error => Rejected := True;
      end;
      Assert (Rejected, "positive exact capacity required an explicit owner");
   end Prefix_Bounds;

   procedure Actual_Stack_Release (State : in out World) is
      Context : constant Context_Access := State.Current;
      Item : constant Value := New_Table (State);
      Cell : Object_Access;
      Before : Byte_Count;
   begin
      --  Reserve real scalar/cell arrays, capture one live binding, then
      --  shrink. Stable indices/cells survive while both actual capacities
      --  and the selected provider's live raw bytes decrease together.
      Lua.Engine.Stacks.Reserve (State, Context, 1_024);
      Context.Stack_Allocated_Bound := 1_024 - Extra_Stack;
      Context.Foreign_Top := 1;
      Lua.Engine.Stacks.Write (State, Context, 1, Item);
      Cell := Lua.Engine.Stacks.Capture (State, Context, 1);
      Before := Statistics (State.Memory).Raw_Bytes;
      Collect (State);
      Assert (Context.Foreign_Stack.Length = 49 and
              Context.Foreign_Stack.Capacity = 49 and
              Context.Stack_Cells.Length = 49 and
              Context.Stack_Cells.Capacity = 49,
              "physical pair used exact 44+5 rows after real shrink");
      Assert (Statistics (State.Memory).Raw_Bytes < Before and
              Context.Stack_Cells (1) = Cell and
              Lua.Engine.Stacks.Read (Context, 1) = Item and
              Context.Foreign_Top = 1 and Context.Stack_Used = 20,
              "shrinking preserved live identity and semantic/API tops");
   end Actual_Stack_Release;

   procedure First_Copy_Refusal (State : in out World) is
      Context : constant Context_Access := State.Current;
      Before : Byte_Count;
   begin
      --  Refuse the first replacement arena. Optional shrinking must retain
      --  both original lengths/capacities/bound and acknowledge only the
      --  real provider-refusal witness, allowing a later operation to retry.
      Lua.Engine.Stacks.Reserve (State, Context, 512);
      Context.Stack_Allocated_Bound := 512 - Extra_Stack;
      Before := Statistics (State.Memory).Raw_Bytes;
      Set_Failure_Countdown (State.Memory, 0);
      Shrink_Context_Storage (State, Context);
      Assert (Context.Foreign_Stack.Length = 512 and
              Context.Stack_Cells.Length = 512 and
              Context.Stack_Allocated_Bound = 512 - Extra_Stack and
              Statistics (State.Memory).Raw_Bytes = Before and
              not Refusal_Pending (State.Memory),
              "refused first copy retained actual paired storage");
      Clear_Failures (State.Memory);
   end First_Copy_Refusal;

   procedure Second_Copy_Refusal (State : in out World) is
      Context : constant Context_Access := State.Current;
      Before : Byte_Count;
   begin
      --  Permit one replacement allocation, then refuse the second. The
      --  first temporary must finalize while neither original is published
      --  away; this protects the two-array transaction under sustained OOM.
      Lua.Engine.Stacks.Reserve (State, Context, 512);
      Context.Stack_Allocated_Bound := 512 - Extra_Stack;
      Lua.Engine.Stacks.Write (State, Context, 1, Value'(Integer_Kind, 77));
      Before := Statistics (State.Memory).Raw_Bytes;
      Set_Failure_Countdown (State.Memory, 1);
      Shrink_Context_Storage (State, Context);
      Assert (Context.Foreign_Stack.Length = 512 and
              Context.Stack_Cells.Length = 512 and
              Statistics (State.Memory).Raw_Bytes = Before and
              Lua.Engine.Stacks.Read (Context, 1).Integer_Data = 77 and
              not Refusal_Pending (State.Memory),
              "second-copy failure retained both old arenas and contents");
      Clear_Failures (State.Memory);
   end Second_Copy_Refusal;

   procedure Alternate_Cache_Release (State : in out World) is
      type Frame_Array is array (1 .. 7) of Frame_Access;
      Frames : Frame_Array;
      Before_Blocks, Before_Bytes : Byte_Count;
   begin
      --  Allocate seven distinct CallInfos before returning any to cache.
      --  Their real retained builders make physical release measurable;
      --  pinned shrinkCI keeps the first and frees each alternate successor.
      for Index in Frames'Range loop
         Frames (Index) := New_Frame (State);
         Frames (Index).Native_Buffer.Append (String'(1 .. 100 => 'x'));
      end loop;
      for Index in Frames'Range loop
         Return_Frame (Frames (Index));
      end loop;
      Before_Blocks := Statistics (State.Memory).Live_Blocks;
      Before_Bytes := Statistics (State.Memory).Raw_Bytes;
      Shrink_Context_Storage (State, State.Current);
      Assert (State.Current.Cache_Count = 4 and
              Statistics (State.Memory).Live_Blocks <= Before_Blocks - 3 and
              Statistics (State.Memory).Raw_Bytes < Before_Bytes,
              "alternate cached records and their buffers were really freed");
   end Alternate_Cache_Release;

   procedure Emergency_Keeps_Storage (State : in out World) is
      Context : constant Context_Access := State.Current;
      First, Second, Third : Frame_Access;
      Attempts : Byte_Count;
   begin
      --  Build oversized storage/cache, then forbid every allocation. The
      --  actual emergency collector must skip optional typed shrink copies
      --  and cache trimming, rather than merely suppressing a public option.
      Lua.Engine.Stacks.Reserve (State, Context, 1_024);
      Context.Stack_Allocated_Bound := 1_024 - Extra_Stack;
      First := New_Frame (State);
      Second := New_Frame (State);
      Third := New_Frame (State);
      Return_Frame (First);
      Return_Frame (Second);
      Return_Frame (Third);
      Begin_Operation (State);
      Set_Failure_Countdown (State.Memory, 0);
      Attempts := Statistics (State.Memory).Growth_Attempts;
      Collect (State, Emergency => True);
      Assert (Context.Foreign_Stack.Length = 1_024 and
              Context.Stack_Cells.Length = 1_024 and
              Context.Cache_Count = 3 and
              Statistics (State.Memory).Growth_Attempts = Attempts,
              "emergency GC preserved physical reserves without growth");
      Clear_Failures (State.Memory);
      End_Operation (State);
   end Emergency_Keeps_Storage;

   procedure Ancestor_Reservation (State : in out World) is
      Context : constant Context_Access := State.Current;
      Parent : Frame_Access := New_Frame (State);
      Child : Frame_Access := New_Frame (State);
   begin
      --  A tiny child runs below a wide parent's reserved end. Optional
      --  shrinking must scan all real ancestors; using only current ci.top
      --  would discard rows the parent legitimately reuses after return.
      Lua.Engine.Stacks.Reserve (State, Context, 2_048);
      Context.Stack_Allocated_Bound := 2_048 - Extra_Stack;
      Parent.Has_Stack_Window := True;
      Parent.Stack_Window_Length := 400;
      Parent.Canonical_GC_Top := 1;
      Child.Has_Stack_Window := True;
      Child.Stack_Base := 2;
      Child.Stack_Window_Length := 8;
      Child.Canonical_GC_Top := 1;
      Context.Stack.Append (Parent);
      Context.Stack.Append (Child);
      Context.Stack_Used := 10;
      Shrink_Context_Storage (State, Context);
      Assert (Context.Foreign_Stack.Length = 809 and
              Context.Stack_Allocated_Bound = 804 and
              Context.Stack_Used = 10,
              "physical shrink retained actual wide-ancestor reservation");
      Context.Stack.Delete_Last;
      Context.Stack.Delete_Last;
      Return_Frame (Child);
      Return_Frame (Parent);
   end Ancestor_Reservation;

   procedure Error_Latch_Recovery (State : in out World) is
      Context : constant Context_Access := State.Current;
      Error_Bound : constant Positive :=
        Lua.Runtime_Configuration.Maximum_Stack + Error_Stack_Reserve;
   begin
      --  Reserve the real selected MAX+200 error stack, not a fake capacity.
      --  Refusal cannot clear its overflow phase; a successful smaller typed
      --  pair releases actual bytes and only then restores normal semantics.
      Lua.Engine.Stacks.Reserve (State, Context, Error_Bound + Extra_Stack);
      Context.Stack_Allocated_Bound := Error_Bound;
      Context.Stack_Error_Phase := Error_Stack;
      Set_Failure_Countdown (State.Memory, 0);
      Shrink_Context_Storage (State, Context);
      Assert (Context.Stack_Error_Phase = Error_Stack and
              Context.Stack_Allocated_Bound = Error_Bound and
              Natural (Context.Foreign_Stack.Length) =
                Error_Bound + Extra_Stack,
              "refused physical release retained exact overflow reserve");
      Clear_Failures (State.Memory);
      Shrink_Context_Storage (State, Context);
      Assert (Context.Stack_Error_Phase = Normal_Stack and
              Context.Stack_Allocated_Bound = 44 and
              Context.Foreign_Stack.Length = 49,
              "successful real shrink repaired overflow phase and bound");
   end Error_Latch_Recovery;

   procedure Borrowed_Warning_Prefix (State : in out World) is
      Context : constant Context_Access := State.Current;
      Activation : Frame_Access := New_Frame (State);
   begin
      --  A C warning callback can push onto its borrowed Lua window. Retain
      --  that actual live prefix as well as the ordinary frame reservation;
      --  the temporary C API top is not an inactive saved reservation.
      Lua.Engine.Stacks.Reserve (State, Context, 2_048);
      Context.Stack_Allocated_Bound := 2_048 - Extra_Stack;
      Activation.Has_Stack_Window := True;
      Activation.Stack_Window_Length := 20;
      Activation.Warning_Borrow_Depth := 1;
      Activation.Stack_Live_Top := 500;
      Context.Stack.Append (Activation);
      Context.Foreign_Top := 500;
      Shrink_Context_Storage (State, Context);
      Assert (Context.Foreign_Stack.Length = 1_009 and
              Context.Foreign_Top = 500,
              "borrowed warning prefix survived physical resize");
      Context.Stack.Delete_Last;
      Return_Frame (Activation);
   end Borrowed_Warning_Prefix;

   procedure Suspended_Thread_Shrink (State : in out World) is
      Thread : constant Value := New_Thread (State, Nil_Value);
      Context : constant Context_Access :=
        State.Contexts (Thread.Reference.Context_Index);
   begin
      --  A reachable Lua-owned inactive thread is discovered through a
      --  normal graph edge, not an active scheduler root. Atomic revisiting
      --  must still release its oversized actual scalar/cell storage.
      Pin (State, Thread);
      Lua.Engine.Stacks.Reserve (State, Context, 1_024);
      Context.Stack_Allocated_Bound := 1_024 - Extra_Stack;
      Collect (State);
      Assert (Context.Foreign_Stack.Length = 49 and
              Context.Stack_Cells.Length = 49 and
              Context.Stack_Allocated_Bound = 44,
              "atomic maintained reachable inactive thread storage");
   end Suspended_Thread_Shrink;

   procedure Prefix_Case is new Fixture (Prefix_Copy);
   procedure Bounds_Case is new Fixture (Prefix_Bounds);
   procedure Release_Case is new Fixture (Actual_Stack_Release);
   procedure First_Case is new Fixture (First_Copy_Refusal);
   procedure Second_Case is new Fixture (Second_Copy_Refusal);
   procedure Cache_Case is new Fixture (Alternate_Cache_Release);
   procedure Emergency_Case is new Fixture (Emergency_Keeps_Storage);
   procedure Ancestor_Case is new Fixture (Ancestor_Reservation);
   procedure Latch_Case is new Fixture (Error_Latch_Recovery);
   procedure Warning_Case is new Fixture (Borrowed_Warning_Prefix);
   procedure Suspended_Case is new Fixture (Suspended_Thread_Shrink);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "physical stack: exact ownerful prefix copy",
                        Prefix_Case'Access);
      Test_Support.Add (Suite, "physical stack: invalid prefix preserved",
                        Bounds_Case'Access);
      Test_Support.Add (Suite, "physical stack: actual paired memory release",
                        Release_Case'Access);
      Test_Support.Add (Suite, "physical stack: first-copy refusal",
                        First_Case'Access);
      Test_Support.Add (Suite, "physical stack: second-copy transaction",
                        Second_Case'Access);
      Test_Support.Add (Suite, "physical stack: alternate cache release",
                        Cache_Case'Access);
      Test_Support.Add (Suite, "physical stack: emergency skips maintenance",
                        Emergency_Case'Access);
      Test_Support.Add (Suite, "physical stack: wide ancestor reservation",
                        Ancestor_Case'Access);
      Test_Support.Add (Suite, "physical stack: real overflow reserve release",
                        Latch_Case'Access);
      Test_Support.Add (Suite, "physical stack: borrowed warning live prefix",
                        Warning_Case'Access);
      Test_Support.Add (Suite, "physical stack: inactive thread atomic shrink",
                        Suspended_Case'Access);
   end Register;
end Lua.Physical_Stack_Tests;
