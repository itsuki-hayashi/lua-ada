with Ada.Containers;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Stacks;
with Lua.Storage; use Lua.Storage;
with Test_Support;

package body Lua.Stack_Storage_Tests is
   use type Ada.Containers.Count_Type;
   use type Byte_Count;
   package Arena renames Lua.Engine.Stacks;

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
              "scalar arena teardown retained managed blocks");
   end Fixture;


   function Window
     (State : in out World; Base, Live : Natural;
      Native : Boolean := False) return Frame_Access;
   function Window
     (State : in out World; Base, Live : Natural;
      Native : Boolean := False) return Frame_Access
   is
      Item : constant Frame_Access := New_Frame (State);
   begin
      --  These are metadata-only frames: no opcode or library callback runs.
      --  Their physical windows intentionally overlap, just as CALL windows
      --  do. Fixture teardown owns every published record and its cache.
      Item.Has_Stack_Window := True;
      Item.Is_Native := Native;
      Item.Stack_Base := Base;
      Item.Call_Base := Base;
      Item.Stack_Window_Length :=
        Natural (State.Current.Foreign_Stack.Length) - Base;
      Item.Saved_Stack_Used := State.Current.Stack_Used;
      Item.Previous_Stack_Window := State.Current.Stack_Window;
      Item.Canonical_GC_Top := Live;
      Item.Stack_Live_Top := Base + Live;
      State.Current.Stack.Append (Item);
      State.Current.Stack_Window := Item;
      State.Current.Stack_Used := Base + Item.Stack_Window_Length;
      return Item;
   end Window;

   procedure Parallel_Initialization (State : in out World);
   procedure Stable_Indices (State : in out World);
   procedure Actual_Cell_Detachment (State : in out World);
   procedure Clear_Preserves_Captured_Value (State : in out World);
   procedure Physical_Trim_Retains_Capacity (State : in out World);
   procedure Two_Array_Refusal (State : in out World);
   procedure Emergency_Retry (State : in out World);
   procedure Overlapping_Child_Root (State : in out World);
   procedure Disjoint_Window_Gap (State : in out World);
   procedure Host_Prefix_Without_Frames (State : in out World);
   procedure Host_Prefix_During_Lua (State : in out World);
   procedure Active_C_Top (State : in out World);
   procedure Waiting_C_Prefix (State : in out World);
   procedure Authoritative_Cell_Tracing (State : in out World);
   procedure Hidden_Vararg_Prefix (State : in out World);
   procedure Invalid_Order_Is_Nondestructive (State : in out World);
   procedure Trace_Without_Allocation (State : in out World);
   procedure Current_Top_Below_Parent (State : in out World);
   procedure Independent_Context_Arenas (State : in out World);

   procedure Parallel_Initialization (State : in out World) is
      Context : constant Context_Access := State.Current;
      Last : constant Natural :=
        Natural (Context.Foreign_Stack.Length) + 16;
   begin
      --  Physical reservation initializes both vectors, including cells, but
      --  cannot publish a semantic/API top on behalf of its caller.
      Arena.Reserve (State, Context, 2);
      Context.Stack_Used := 2;
      Context.Foreign_Top := 1;
      Arena.Reserve (State, Context, Last);
      Assert (Natural (Context.Foreign_Stack.Length) = Last and
              Natural (Context.Stack_Cells.Length) = Last and
              Context.Stack_Used = 2 and
              Context.Foreign_Top = 1, "physical reservation changed tops");
      Assert (Context.Foreign_Stack.Owner_Of = Reference (State.Memory) and
              Context.Stack_Cells.Owner_Of = Reference (State.Memory),
              "parallel arenas selected explicit universe owner");
      for Index in 1 .. Last loop
         Assert (Arena.Read (State, Context, Index).Kind = Nil_Kind and
                 Context.Stack_Cells (Index) = null,
                 "fresh scalar/cell slot was not initialized");
      end loop;
   end Parallel_Initialization;

   procedure Stable_Indices (State : in out World) is
      Context : constant Context_Access := State.Current;
      Cell : Object_Access;
   begin
      --  Keep only an absolute slot and an actual heap-cell identity across
      --  both arena reallocations. Debug mutation leaves the scalar stale;
      --  reads must prefer the cell and ordinary writes synchronize both.
      Arena.Reserve (State, Context, 4);
      Arena.Write (State, Context, 2, (Integer_Kind, 42));
      Context.Foreign_Top := 2;
      Cell := Arena.Capture (State, Context, 2);
      Arena.Reserve (State, Context, 1_024);
      Assert (Context.Stack_Cells (2) = Cell, "capture moved with vector");
      Cell.Cell_Value := (Integer_Kind, 81);
      Assert (Arena.Read (Context, 2) = Value'(Integer_Kind, 81),
              "internal read used stale scalar cache");
      Arena.Write (State, Context, 2, (Integer_Kind, 99));
      Assert (Cell.Cell_Value = Value'(Integer_Kind, 99) and
              Context.Foreign_Stack (2) = Value'(Integer_Kind, 99),
              "write did not synchronize actual cell and scalar cache");
   end Stable_Indices;

   procedure Actual_Cell_Detachment (State : in out World) is
      Context : constant Context_Access := State.Current;
      First, Next_Cell : Object_Access;
   begin
      --  Leaving/reentering one declaration keeps old closures' cell values
      --  and creates a new actual identity for the next binding lifetime.
      Arena.Reserve (State, Context, 4);
      Arena.Write (State, Context, 2, (Integer_Kind, 1));
      First := Arena.Capture (State, Context, 2);
      Assert (Arena.Capture (State, Context, 2) = First,
              "one open slot created duplicate cells");
      First.Cell_Value := (Integer_Kind, 17);
      Arena.Detach (Context, 2, 2);
      Assert (Context.Stack_Cells (2) = null and
              Arena.Read (Context, 2) = Value'(Integer_Kind, 17),
              "detachment lost authoritative capture value");
      Arena.Write (State, Context, 2, (Integer_Kind, 43));
      Next_Cell := Arena.Capture (State, Context, 2);
      Assert (Next_Cell /= First and
              First.Cell_Value = Value'(Integer_Kind, 17) and
              Next_Cell.Cell_Value = Value'(Integer_Kind, 43),
              "reentered declaration changed an older captured binding");
   end Actual_Cell_Detachment;

   procedure Clear_Preserves_Captured_Value (State : in out World) is
      Context : constant Context_Access := State.Current;
      Cell : Object_Access;
   begin
      --  A dead stack association is distinct from the independent cell.
      --  Clearing the interval must not write nil into an escaping capture.
      Arena.Reserve (State, Context, 4);
      Arena.Write (State, Context, 3, (Integer_Kind, 7));
      Cell := Arena.Capture (State, Context, 3);
      Cell.Cell_Value := (Integer_Kind, 19);
      Arena.Clear_Range (Context, 2, 4);
      Assert (Context.Stack_Cells (3) = null and
              Arena.Read (Context, 3).Kind = Nil_Kind and
              Cell.Cell_Value = Value'(Integer_Kind, 19),
              "dead interval overwrote actual capture value");
   end Clear_Preserves_Captured_Value;

   procedure Physical_Trim_Retains_Capacity (State : in out World) is
      Context : constant Context_Access := State.Current;
      Value_Capacity, Cell_Capacity : Ada.Containers.Count_Type;
      Attempts : Byte_Count;
   begin
      --  Trimming dead initialized slots is physical cleanup. Restoring a
      --  wider parent later must retain both buffers and preserve its tops.
      Arena.Reserve (State, Context, 64);
      Arena.Write (State, Context, 64, (Integer_Kind, 42));
      Context.Stack_Used := 12;
      Context.Foreign_Top := 2;
      Context.Host_Stack_Top := 1;
      Value_Capacity := Context.Foreign_Stack.Capacity;
      Cell_Capacity := Context.Stack_Cells.Capacity;
      Attempts := Statistics (State.Memory).Growth_Attempts;
      Arena.Trim (Context, 2);
      Arena.Reserve (State, Context, 64);
      Assert (Context.Foreign_Stack.Capacity = Value_Capacity and
              Context.Stack_Cells.Capacity = Cell_Capacity and
              Statistics (State.Memory).Growth_Attempts = Attempts,
              "trim discarded reusable physical capacity");
      Assert (Arena.Read (Context, 64).Kind = Nil_Kind and
              Context.Stack_Used = 12 and Context.Foreign_Top = 2 and
              Context.Host_Stack_Top = 1,
              "physical trim changed semantic/API bounds");
   end Physical_Trim_Retains_Capacity;

   procedure Two_Array_Refusal (State : in out World) is
      Context : constant Context_Access := State.Current;
      Cell : Object_Access;
      Refused : Boolean := False;
      Before_Collections : Natural;
      Before_Length : Natural;
   begin
      --  Permit the value arena to grow, then permanently refuse the cell
      --  arena. Retry can collect once but may not publish either new length
      --  or damage the old live value/cell while only one capacity grew.
      Arena.Reserve (State, Context, 4);
      Arena.Write (State, Context, 1, (Integer_Kind, 77));
      Context.Foreign_Top := 1;
      Context.Stack_Used := 4;
      Cell := Arena.Capture (State, Context, 1);

      Before_Collections := State.Collections;
      Before_Length := Natural (Context.Foreign_Stack.Length);
      Set_Failure_Countdown (State.Memory, 1);
      begin
         Arena.Reserve (State, Context, Before_Length + 128);
      exception
         when Allocation_Error | Program_Error =>
            Refused := Refusal_Pending (State.Memory);
            if not Refused then
               raise;
            end if;
      end;
      Assert (Refused and
              Natural (Context.Foreign_Stack.Length) = Before_Length and
              Natural (Context.Stack_Cells.Length) = Before_Length and
              Context.Stack_Used = 4 and
              Context.Stack_Cells (1) = Cell and
              Arena.Read (Context, 1) = Value'(Integer_Kind, 77),
              "half-reserved arenas changed existing logical state");
      Assert (State.Collections = Before_Collections + 1,
              "arena refusal did not use exactly one emergency collection");
      Clear_Failures (State.Memory);
      Acknowledge_Refusal (State.Memory);
      Arena.Reserve (State, Context, Before_Length + 128);
      Assert (Arena.Read (Context, 1) = Value'(Integer_Kind, 77),
              "arena failed to recover after allocator policy restored");
   end Two_Array_Refusal;

   procedure Emergency_Retry (State : in out World) is
      Context : constant Context_Access := State.Current;
      Garbage : constant Value := New_String
        (State, String'(1 .. 65_536 => 'x'));
      Serial : constant Positive := Garbage.Reference.Serial;
      Before : constant Natural := State.Collections;
      Reclaimed : Boolean := True;
   begin
      --  No headroom remains until an unreachable large string is reclaimed.
      --  The physical reservation owns no half-published Lua window when it
      --  invokes the allocation-free collector and retries both arenas.
      Set_Ceiling (State.Memory, Statistics (State.Memory).Raw_Bytes);
      --  Start after constructing garbage: objects born inside the current
      --  atomic operation are deliberately conservative construction roots.
      Begin_Operation (State);
      begin
         Arena.Reserve (State, Context, 512);
      exception
         when others => End_Operation (State); raise;
      end;
      End_Operation (State);
      --  A successful vector allocation may immediately reuse the freed
      --  payload's raw address. Inspect actual Lua object identity instead
      --  of treating allocator address reuse as a failed reclamation.
      for Item of State.Heap loop
         if Item /= null and then Item.Serial = Serial then
            Reclaimed := False;
         end if;
      end loop;
      Assert (State.Collections = Before + 1,
              "arena retry GC count: before" & Before'Image & " after" &
                State.Collections'Image);
      Assert (Reclaimed, "arena retry retained garbage serial" &
                Serial'Image);
      Assert (Context.Foreign_Stack.Length = 512 and
              Context.Stack_Cells.Length = 512,
              "arena retry lengths: values" &
                Context.Foreign_Stack.Length'Image & " cells" &
                Context.Stack_Cells.Length'Image);
      Set_Ceiling (State.Memory, Byte_Count'Last);
   end Emergency_Retry;

   procedure Overlapping_Child_Root (State : in out World) is
      Context : constant Context_Access := State.Current;
      Kept, Dead : Value;
      Parent, Child : Frame_Access;
   begin
      --  The parent's reserved dead tail overlaps the child's live range.
      --  Per-parent clearing would destroy child slot eight before tracing it.
      Arena.Reserve (State, Context, 16);
      Kept := New_Table (State);
      Dead := New_Table (State);
      Arena.Write (State, Context, 8, Kept);
      Arena.Write (State, Context, 12, Dead);
      Parent := Window (State, 1, 3);
      Child := Window (State, 3, 5);
      Assert (Parent.Context = Child.Context, "test windows lost owner");
      Collect (State);
      Assert (State.Heap.Contains (Kept.Reference) and
              Arena.Read (Context, 8) = Kept and
              not State.Heap.Contains (Dead.Reference) and
              Arena.Read (Context, 12).Kind = Nil_Kind,
              "overlap trace destroyed child or retained parent dead tail");
   end Overlapping_Child_Root;

   procedure Disjoint_Window_Gap (State : in out World) is
      Context : constant Context_Access := State.Current;
      Kept, Dead : Value;
      Parent, Child : Frame_Access;
   begin
      --  A gap between disjoint windows is not an implicit live reservation.
      --  Clear its only reference while preserving the later child's edge.
      Arena.Reserve (State, Context, 12);
      Kept := New_Table (State);
      Dead := New_Table (State);
      Arena.Write (State, Context, 5, Dead);
      Arena.Write (State, Context, 9, Kept);
      Parent := Window (State, 1, 1);
      Child := Window (State, 8, 1);
      Assert (Parent.Stack_Base < Child.Stack_Base, "test window order");
      Collect (State);
      Assert (not State.Heap.Contains (Dead.Reference) and
              Arena.Read (Context, 5).Kind = Nil_Kind and
              State.Heap.Contains (Kept.Reference),
              "gap cleanup retained dead data or lost later live window");
   end Disjoint_Window_Gap;

   procedure Host_Prefix_Without_Frames (State : in out World) is
      Context : constant Context_Access := State.Current;
      Kept, Dead : Value;
   begin
      --  A host-owned C stack outside a drive uses its actual logical top,
      --  not the initialized arena length or an uninitialized saved prefix.
      Arena.Reserve (State, Context, 8);
      Kept := New_Table (State);
      Dead := New_Table (State);
      Arena.Write (State, Context, 1, Kept);
      Arena.Write (State, Context, 6, Dead);
      Context.Foreign_Top := 1;
      Collect (State);
      Assert (State.Heap.Contains (Kept.Reference) and
              not State.Heap.Contains (Dead.Reference),
              "idle host stack was traced through physical capacity");
   end Host_Prefix_Without_Frames;

   procedure Host_Prefix_During_Lua (State : in out World) is
      Context : constant Context_Access := State.Current;
      Host, Lua_Value, Dead : Value;
      Activation : Frame_Access;
   begin
      --  A running Lua window retains the saved host prefix, not the old C
      --  top's dead arguments/temporaries. Both live roots must survive.
      Arena.Reserve (State, Context, 12);
      Host := New_Table (State);
      Lua_Value := New_Table (State);
      Dead := New_Table (State);
      Arena.Write (State, Context, 1, Host);
      Arena.Write (State, Context, 6, Lua_Value);
      Arena.Write (State, Context, 11, Dead);
      Context.Host_Stack_Top := 2;
      Context.Foreign_Top := 11;
      Activation := Window (State, 4, 2);
      Assert (Activation.Stack_Base = 4, "test Lua window base");
      Collect (State);
      Assert (State.Heap.Contains (Host.Reference) and
              State.Heap.Contains (Lua_Value.Reference) and
              not State.Heap.Contains (Dead.Reference),
              "drive traced old C top rather than saved host prefix");
   end Host_Prefix_During_Lua;

   procedure Active_C_Top (State : in out World) is
      Context : constant Context_Access := State.Current;
      Kept, Dead : Value;
      Activation : Frame_Access;
   begin
      --  A currently entered C frame can push beyond its prior saved live
      --  prefix. Its logical API top wins; unused LUA_MINSTACK does not root.
      Arena.Reserve (State, Context, 20);
      Kept := New_Table (State);
      Dead := New_Table (State);
      Arena.Write (State, Context, 8, Kept);
      Arena.Write (State, Context, 17, Dead);
      Activation := Window (State, 4, 2, Native => True);
      Activation.Foreign_Entered := True;
      Context.Foreign_Activation := Activation;
      Context.Foreign_Top := 8;
      Collect (State);
      Assert (State.Heap.Contains (Kept.Reference) and
              not State.Heap.Contains (Dead.Reference),
              "active C frame ignored API top or rooted free reservation");
   end Active_C_Top;

   procedure Waiting_C_Prefix (State : in out World) is
      Context : constant Context_Access := State.Current;
      Prefix, Lua_Value, Dead : Value;
      Parent, Child : Frame_Access;
   begin
      --  Foreign_Activation can still name a waiting C caller under Lua.
      --  Its saved prefix is authoritative; stale logical C top is not live.
      Arena.Reserve (State, Context, 16);
      Prefix := New_Table (State);
      Lua_Value := New_Table (State);
      Dead := New_Table (State);
      Arena.Write (State, Context, 2, Prefix);
      Arena.Write (State, Context, 6, Lua_Value);
      Arena.Write (State, Context, 14, Dead);
      Parent := Window (State, 1, 2, Native => True);
      Parent.Foreign_Entered := True;
      Context.Foreign_Activation := Parent;
      Context.Foreign_Top := 14;
      Child := Window (State, 4, 2);
      Assert (Context.Stack.Last_Element = Child, "test waiting C caller");
      Collect (State);
      Assert (State.Heap.Contains (Prefix.Reference) and
              State.Heap.Contains (Lua_Value.Reference) and
              not State.Heap.Contains (Dead.Reference),
              "waiting C frame incorrectly retained its stale API top");
   end Waiting_C_Prefix;

   procedure Authoritative_Cell_Tracing (State : in out World) is
      Context : constant Context_Access := State.Current;
      Old_Value, New_Value : Value;
      Cell : Object_Access;
   begin
      --  Debug/upvalue writes can change a real cell without updating cached
      --  scalar bits. Trace its actual new value and release the stale table.
      Arena.Reserve (State, Context, 2);
      Old_Value := New_Table (State);
      New_Value := New_Table (State);
      Arena.Write (State, Context, 1, Old_Value);
      Context.Foreign_Top := 1;
      Cell := Arena.Capture (State, Context, 1);
      Cell.Cell_Value := New_Value;
      Collect (State);
      Assert (State.Heap.Contains (Cell) and
              State.Heap.Contains (New_Value.Reference) and
              not State.Heap.Contains (Old_Value.Reference) and
              Arena.Read (Context, 1) = New_Value,
              "collector used stale scalar rather than authoritative cell");
   end Authoritative_Cell_Tracing;

   procedure Hidden_Vararg_Prefix (State : in out World) is
      Context : constant Context_Access := State.Current;
      Kept, Dead : Value;
      Activation : Frame_Access;
   begin
      --  Hidden varargs retain original arguments below the shifted R0 base.
      --  Mark from Call_Base through the current register top, not only R0.
      Arena.Reserve (State, Context, 16);
      Kept := New_Table (State);
      Dead := New_Table (State);
      Arena.Write (State, Context, 4, Kept);
      Arena.Write (State, Context, 15, Dead);
      Activation := Window (State, 8, 3);
      Activation.Call_Base := 2;
      Activation.Hidden_Varargs := True;
      Collect (State);
      Assert (State.Heap.Contains (Kept.Reference) and
              not State.Heap.Contains (Dead.Reference),
              "hidden argument prefix disappeared below shifted base");
   end Hidden_Vararg_Prefix;

   procedure Invalid_Order_Is_Nondestructive (State : in out World) is
      Context : constant Context_Access := State.Current;
      Left, Right : Frame_Access;
      Refused : Boolean := False;
      Calls : Natural := 0;
      procedure Mark_Value (Item : Value);
      procedure Mark_Cell (Item : Object_Access);
      procedure Mark_Value (Item : Value) is
      begin
         Calls := Calls + Boolean'Pos (Item.Kind = Nil_Kind);
      end Mark_Value;
      procedure Mark_Cell (Item : Object_Access) is
      begin
         Calls := Calls + Boolean'Pos (Item /= null);
      end Mark_Cell;
   begin
      --  An invalid later interval cannot justify clearing an earlier gap
      --  first. Validate the complete ordering before any destructive pass.
      Arena.Reserve (State, Context, 12);
      Arena.Write (State, Context, 3, (Integer_Kind, 31));
      Left := Window (State, 8, 2);
      Right := Window (State, 3, 2);
      begin
         Arena.Trace (Context, Mark_Value'Access, Mark_Cell'Access);
      exception
         when Program_Error => Refused := True;
      end;
      Assert (Refused and Calls = 0 and
              Arena.Read (Context, 3) = Value'(Integer_Kind, 31),
              "invalid window order destroyed previously live data");
      --  Restore metadata before ordinary fixture teardown/collection.
      Left.Stack_Base := 1;
      Right.Stack_Base := 3;
   end Invalid_Order_Is_Nondestructive;

   procedure Trace_Without_Allocation (State : in out World) is
      Context : constant Context_Access := State.Current;
      Parent, Child : Frame_Access;
      Before : Byte_Count;
      Calls : Natural := 0;
      procedure Mark_Value (Item : Value);
      procedure Mark_Cell (Item : Object_Access);
      procedure Mark_Value (Item : Value) is
      begin
         Assert (Item.Kind = Nil_Kind, "unexpected synthetic scalar kind");
         Calls := Calls + 1;
      end Mark_Value;
      procedure Mark_Cell (Item : Object_Access) is
      begin
         Assert (Item = null, "synthetic trace unexpectedly captured cell");
      end Mark_Cell;
   begin
      --  Union tracing is allocation-free even with overlapping frames.
      --  Counting each slot once protects its linear high-water algorithm.
      Arena.Reserve (State, Context, 16);
      Parent := Window (State, 1, 3);
      Child := Window (State, 3, 5);
      Assert (Parent.Stack_Base < Child.Stack_Base, "test window order");
      Before := Statistics (State.Memory).Growth_Attempts;
      Set_Failure_Countdown (State.Memory, 0);
      Arena.Trace (Context, Mark_Value'Access, Mark_Cell'Access);
      Assert (Calls = 8 and not Refusal_Pending (State.Memory) and
              Statistics (State.Memory).Growth_Attempts = Before,
              "union trace allocated or visited overlap more than once");
      Clear_Failures (State.Memory);
   end Trace_Without_Allocation;

   procedure Current_Top_Below_Parent (State : in out World) is
      Context : constant Context_Access := State.Current;
      Parent, Child : Frame_Access;
   begin
      --  ci.top belongs to the current real frame, not the maximum reserved
      --  ancestor end. A tiny child can reuse the wide parent's dead tail.
      Arena.Reserve (State, Context, 128);
      Parent := Window (State, 1, 3);
      Parent.Stack_Window_Length := 127;
      Child := Window (State, 4, 2);
      Child.Stack_Window_Length := 4;
      Context.Stack_Used := 8;
      Arena.Reserve (State, Context, 12);
      Collect (State);
      Assert (Context.Stack_Used = 8 and
              Parent.Stack_Base + Parent.Stack_Window_Length = 128 and
              Child.Stack_Base + Child.Stack_Window_Length = 8,
              "ancestor reservation incorrectly raised current-frame top");
   end Current_Top_Below_Parent;

   procedure Independent_Context_Arenas (State : in out World) is
      Other : constant Context_Id := Create_Context (State);
      Context : constant Context_Access := State.Contexts (Positive (Other));
   begin
      --  Two contexts share the provider but not slot or cell identities.
      --  Growing/clearing an inactive host context cannot change main's data.
      Arena.Reserve (State, State.Current, 4);
      Arena.Reserve (State, Context, 64);
      Arena.Write (State, State.Current, 1, (Integer_Kind, 17));
      Arena.Write (State, Context, 1, (Integer_Kind, 29));
      Arena.Trim (Context, 0);
      Assert (Arena.Read (State.Current, 1) = Value'(Integer_Kind, 17) and
              Arena.Read (Context, 1).Kind = Nil_Kind,
              "contexts shared mutable scalar storage");
   end Independent_Context_Arenas;

   procedure Initialization_Case is new Fixture (Parallel_Initialization);
   procedure Indices_Case is new Fixture (Stable_Indices);
   procedure Detachment_Case is new Fixture (Actual_Cell_Detachment);
   procedure Clear_Case is new Fixture (Clear_Preserves_Captured_Value);
   procedure Trim_Case is new Fixture (Physical_Trim_Retains_Capacity);
   procedure Refusal_Case is new Fixture (Two_Array_Refusal);
   procedure Retry_Case is new Fixture (Emergency_Retry);
   procedure Overlap_Case is new Fixture (Overlapping_Child_Root);
   procedure Gap_Case is new Fixture (Disjoint_Window_Gap);
   procedure Host_Case is new Fixture (Host_Prefix_Without_Frames);
   procedure Drive_Case is new Fixture (Host_Prefix_During_Lua);
   procedure Active_Case is new Fixture (Active_C_Top);
   procedure Waiting_Case is new Fixture (Waiting_C_Prefix);
   procedure Cell_Case is new Fixture (Authoritative_Cell_Tracing);
   procedure Vararg_Case is new Fixture (Hidden_Vararg_Prefix);
   procedure Order_Case is new Fixture (Invalid_Order_Is_Nondestructive);
   procedure Allocation_Case is new Fixture (Trace_Without_Allocation);
   procedure Current_Case is new Fixture (Current_Top_Below_Parent);
   procedure Context_Case is new Fixture (Independent_Context_Arenas);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "scalar arena: parallel initialization",
                        Initialization_Case'Access);
      Test_Support.Add (Suite, "scalar arena: stable indices and cells",
                        Indices_Case'Access);
      Test_Support.Add (Suite, "scalar arena: actual cell detachment",
                        Detachment_Case'Access);
      Test_Support.Add (Suite, "scalar arena: clear preserves capture",
                        Clear_Case'Access);
      Test_Support.Add (Suite, "scalar arena: physical trim retains capacity",
                        Trim_Case'Access);
      Test_Support.Add (Suite, "scalar arena: paired refusal and recovery",
                        Refusal_Case'Access);
      Test_Support.Add (Suite, "scalar arena: emergency collection retry",
                        Retry_Case'Access);
      Test_Support.Add (Suite, "scalar arena: child survives parent tail",
                        Overlap_Case'Access);
      Test_Support.Add (Suite, "scalar arena: disjoint dead gap",
                        Gap_Case'Access);
      Test_Support.Add (Suite, "scalar arena: idle host prefix",
                        Host_Case'Access);
      Test_Support.Add (Suite, "scalar arena: saved prefix during drive",
                        Drive_Case'Access);
      Test_Support.Add (Suite, "scalar arena: active C logical top",
                        Active_Case'Access);
      Test_Support.Add (Suite, "scalar arena: waiting C saved prefix",
                        Waiting_Case'Access);
      Test_Support.Add (Suite, "scalar arena: authoritative cell tracing",
                        Cell_Case'Access);
      Test_Support.Add (Suite, "scalar arena: hidden vararg prefix",
                        Vararg_Case'Access);
      Test_Support.Add (Suite, "scalar arena: validate order before clearing",
                        Order_Case'Access);
      Test_Support.Add (Suite, "scalar arena: allocation-free union trace",
                        Allocation_Case'Access);
      Test_Support.Add (Suite, "scalar arena: current top below parent",
                        Current_Case'Access);
      Test_Support.Add (Suite, "scalar arena: independent contexts",
                        Context_Case'Access);
   end Register;
end Lua.Stack_Storage_Tests;
