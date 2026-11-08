with Ada.Containers;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Finalizers;
with Lua.Storage; use Lua.Storage;
with Test_Support;

package body Lua.Collector_Tests is
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
      Collect (State);
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
              "collector fixture released every actual managed block");
   end Fixture;

   function Contains (State : World; Serial : Positive) return Boolean;
   procedure Finish (State : in out World);
   procedure Until_Black (State : in out World; Item : Object_Access);
   procedure Until_Sweep (State : in out World);
   procedure Minor (State : in out World);
   function Finalizable (State : in out World) return Value;

   function Contains (State : World; Serial : Positive) return Boolean is
   begin
      --  Addresses can be reused immediately by the provider. Test immutable
      --  object identity through currently owned slots, never a stale pointer.
      for Item of State.Heap loop
         if Item /= null and then Item.Serial = Serial then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   procedure Finish (State : in out World) is
      Done : Boolean := False;
      Steps : Natural := 0;
   begin
      while not Done loop
         Advance_Collection (State, 8, Done);
         Steps := Steps + 1;
         Assert (Steps < 100_000, "incremental cycle made bounded progress");
      end loop;
   end Finish;

   procedure Until_Black (State : in out World; Item : Object_Access) is
      Done : Boolean;
   begin
      for Attempt in 1 .. 100_000 loop
         Advance_Collection (State, 1, Done);
         exit when Item.Color = Black;
         Assert (not Done, "target was traversed before cycle completion");
      end loop;
      Assert (Item.Color = Black and State.GC.Phase = Propagating,
              "fixture reached a real black owner during propagation");
   end Until_Black;

   procedure Until_Sweep (State : in out World) is
      Done : Boolean;
   begin
      for Attempt in 1 .. 100_000 loop
         Advance_Collection (State, 1, Done);
         exit when State.GC.Phase = Sweeping_Objects;
         Assert (not Done, "real sweep phase preceded cycle completion");
      end loop;
      Assert (State.GC.Phase = Sweeping_Objects,
              "fixture reached persistent object sweeping");
   end Until_Sweep;

   procedure Minor (State : in out World) is
      Done : Boolean;
   begin
      Advance_Collection (State, 1, Done);
      Assert (Done, "one generational step actually finished its nursery");
   end Minor;

   function Finalizable (State : in out World) return Value is
      Item : constant Value := New_Table (State);
      Meta : constant Value := New_Table (State);
   begin
      Set (State, Meta, New_String (State, "__gc"),
           New_Native (State, "collector.fixture"));
      Set_Metatable (State, Item, Meta.Reference);
      Lua.Engine.Finalizers.Register (State, Item);
      return Item;
   end Finalizable;

   procedure Partial_Mark (State : in out World);
   procedure Root_Publication (State : in out World);
   procedure Forward_Cell (State : in out World);
   procedure Backward_Table (State : in out World);
   procedure New_During_Sweep (State : in out World);
   procedure Heap_Slot_Reuse (State : in out World);
   procedure Program_Slot_Reuse (State : in out World);
   procedure Provider_Bytes (State : in out World);
   procedure Refusing_Full (State : in out World);
   procedure Failed_Traversal (State : in out World);
   procedure Enter_Generation (State : in out World);
   procedure Nursery_Ages (State : in out World);
   procedure Young_Only_Sweep (State : in out World);
   procedure Remembered_Table (State : in out World);
   procedure Promoted_Cell_Graph (State : in out World);
   procedure Old_Weak_Values (State : in out World);
   procedure Zero_Major_Threshold (State : in out World);
   procedure Mode_Transition (State : in out World);
   procedure Parameter_Rounding (State : in out World);
   procedure Parameter_Saturation (State : in out World);
   procedure Zero_Step_Size (State : in out World);
   procedure Pending_Finalizer (State : in out World);
   procedure Weak_Before_Finalizer (State : in out World);
   procedure Emergency_Queue (State : in out World);
   procedure Weak_Mode_Change (State : in out World);
   procedure Promotion_And_Major (State : in out World);
   procedure Positive_Step_Debt (State : in out World);
   procedure Zero_Forces_Work (State : in out World);
   procedure Larger_Debt_Payments (State : in out World);
   procedure Stopped_Manual_Step (State : in out World);
   procedure Exact_Allocation_Debt (State : in out World);
   procedure Extreme_Debt_Payment (State : in out World);
   procedure Minor_Multiplier_Debt (State : in out World);

   procedure Partial_Mark (State : in out World) is
      Before : constant Natural := State.Collections;
      Done : Boolean;
   begin
      --  A one-unit request starts a root wave, without secretly running the
      --  old full collector and merely delaying its completion counter.
      Advance_Collection (State, 1, Done);
      Assert (not Done and State.Collections = Before and
              State.GC.Phase = Propagating and State.GC.Gray_Head /= null,
              "small step retained actual gray work between activations");
      Finish (State);
      Assert (State.Collections = Before + 1,
              "only a completed real cycle advanced collection count");
   end Partial_Mark;

   procedure Root_Publication (State : in out World) is
      Done : Boolean;
      Item : Value;
      Serial : Positive;
   begin
      --  Add a host operation root after marking has already started. The
      --  publication barrier must protect its graph in the current cycle.
      Advance_Collection (State, 1, Done);
      Item := New_Table (State);
      Serial := Item.Reference.Serial;
      Pin (State, Item);
      Finish (State);
      Assert (Contains (State, Serial),
              "root acquired during propagation survived that cycle");
   end Root_Publication;

   procedure Forward_Cell (State : in out World) is
      Holder : constant Value := New_Native
        (State, "collector.cell", One_Value (State, Nil_Value));
      Cell : constant Object_Access := Holder.Reference.Captures (1);
      Child : Value;
      Serial : Positive;
   begin
      --  Blacken a rooted native upvalue, then write a new white child into
      --  its actual shared cell. No later root rescan may substitute for the
      --  required forward publication barrier.
      Pin (State, Holder);
      Until_Black (State, Cell);
      Child := New_Table (State);
      Serial := Child.Reference.Serial;
      Store_Cell (State, Cell, Child);
      Assert (Child.Reference.Color = Gray,
              "black cell immediately shaded its new white child");
      Finish (State);
      Assert (Contains (State, Serial) and Cell.Cell_Value = Child,
              "actual upvalue retained the child across incremental sweep");
   end Forward_Cell;

   procedure Backward_Table (State : in out World) is
      Parent : constant Value := New_Table (State);
      Child : Value;
      Serial : Positive;
   begin
      --  A raw table insertion into a black owner must make the owner
      --  revisitable; weak/strong semantics are applied when it is retraced.
      Pin (State, Parent);
      Until_Black (State, Parent.Reference);
      Child := New_Table (State);
      Serial := Child.Reference.Serial;
      Set (State, Parent, (Integer_Kind, 1), Child);
      Assert (Parent.Reference.Gray_List = Revisit_Gray,
              "raw table store queued a real backward barrier");
      Finish (State);
      Assert (Contains (State, Serial) and
              Get (Parent, (Integer_Kind, 1)) = Child,
              "atomic revisiting preserved the newly installed table edge");
   end Backward_Table;

   procedure New_During_Sweep (State : in out World) is
      Item : Value;
      Serial : Positive;
   begin
      --  Start sweeping, then allocate and root a new object. Its current
      --  white must differ from dead old-white objects still ahead of cursor.
      Until_Sweep (State);
      Item := New_Table (State);
      Serial := Item.Reference.Serial;
      Pin (State, Item);
      Finish (State);
      Assert (Contains (State, Serial),
              "allocation between sweep batches was never old garbage");
   end New_During_Sweep;

   procedure Heap_Slot_Reuse (State : in out World) is
      Item : Value := New_Table (State);
      Slot : constant Positive := Item.Reference.Registry_Slot;
      Serial : constant Positive := Item.Reference.Serial;
      Extent : constant Ada.Containers.Count_Type := State.Heap.Length;
      Before : constant Natural := State.Live_Objects;
   begin
      --  Collect one unrooted identity, then allocate another. Stable slot
      --  reuse must not shift surviving identities or equate address reuse
      --  with resurrection of the collected serial.
      Collect (State);
      Assert (not Contains (State, Serial) and State.Heap (Slot) = null,
              "sweep detached the dead ownership slot before release");
      Item := New_Table (State);
      Assert (Item.Reference.Registry_Slot = Slot and
              State.Heap.Length = Extent and State.Live_Objects = Before,
              "new object reused actual free slot without registry growth");
   end Heap_Slot_Reuse;

   procedure Program_Slot_Reuse (State : in out World) is
      Item : Prototype_Access := New_Program (State);
      Slot : constant Positive := Item.Registry_Slot;
      Extent : constant Ada.Containers.Count_Type := State.Programs.Length;
   begin
      --  New_Program publishes its own stable ownership row. A discarded
      --  prototype can be collected and reused without a caller double-add.
      Collect (State);
      Assert (State.Programs (Slot) = null,
              "unrooted prototype released its real registry ownership");
      Item := New_Program (State);
      Assert (Item.Registry_Slot = Slot and State.Programs.Length = Extent,
              "code registry reused stable free slot");
   end Program_Slot_Reuse;

   procedure Provider_Bytes (State : in out World) is
      Before : Byte_Count;
      Count : Natural;
      Item : Value;
   begin
      --  Garbage owns both typed table records and actual auxiliary buffers.
      --  Distinct payload bytes require 200 real short-string headers even
      --  with the ordinary universe-wide weak intern index enabled.
      --  Reclamation must reduce the chosen provider's real live-byte count,
      --  without fabricating bytes from semantic stack or object counters.
      for Index in 1 .. 200 loop
         Item := New_Table (State);
         Set (State, Item, (Integer_Kind, 1),
              New_String (State, "payload" & Index'Image));
      end loop;
      Before := Statistics (State.Memory).Raw_Bytes;
      Count := State.Live_Objects;
      Collect (State);
      Assert (Statistics (State.Memory).Raw_Bytes < Before and
              State.Live_Objects = Count - 400,
              "real table/string blocks and buffers were reclaimed");
   end Provider_Bytes;

   procedure Refusing_Full (State : in out World) is
      Item : constant Value := New_Table (State);
      Serial : constant Positive := Item.Reference.Serial;
      Attempts : Byte_Count;
   begin
      --  Refuse every growth after constructing garbage. Mark queues, weak
      --  processing and stable-slot sweeping must finish allocation-free.
      Begin_Operation (State);
      Set_Failure_Countdown (State.Memory, 0);
      Attempts := Statistics (State.Memory).Growth_Attempts;
      Collect (State, Emergency => True);
      Assert (Statistics (State.Memory).Growth_Attempts = Attempts and
              not Contains (State, Serial),
              "emergency full cycle reclaimed garbage without allocation");
      Clear_Failures (State.Memory);
      End_Operation (State);
   end Refusing_Full;

   procedure Failed_Traversal (State : in out World) is
      Activation : Frame_Access := New_Frame (State);
      Rejected : Boolean := False;
      Done : Boolean;
   begin
      --  A deliberately invalid private fixture forces stack validation to
      --  fail during marking. Queue links/colors must be neutralized so a
      --  later correct collection is safe, rather than retaining stale work.
      --  Frame allocation can advance an earlier cycle under the smaller
      --  instrumented settings. Start from an actual paused collector.
      Finish (State);
      Activation.Has_Stack_Window := True;
      Activation.Stack_Base := Natural (State.Current.Foreign_Stack.Length);
      Activation.Canonical_GC_Top := 1;
      State.Current.Stack.Append (Activation);
      begin
         --  Instrumented libraries add roots, so a fixed work allowance
         --  need not reach the thread in its first propagation slice.
         for Slice in 1 .. 10_000 loop
            Advance_Collection (State, 1_000, Done);
            exit when Done;
         end loop;
      exception
         when Program_Error => Rejected := True;
      end;
      Assert (Rejected and not State.Collector_Active and
              State.GC.Gray_Head = null and State.GC.Code_Gray = null,
              "failed traversal released persistent queue ownership");
      State.Current.Stack.Delete_Last;
      Return_Frame (Activation);
      Collect (State);
   end Failed_Traversal;

   procedure Enter_Generation (State : in out World) is
   begin
      --  Mode entry really traces/sweeps before making survivors old; a mode
      --  label alone would leave stale colors and no old-to-young invariant.
      Set_Collector_Mode (State, Generational_Minor_Mode);
      Assert (State.GC.Mode = Generational_Minor_Mode,
              "generation entry selected a completed real old population");
      for Item of State.Heap loop
         if Item /= null then
            Assert (Item.Age = Old_Age and Item.Color = Black,
                    "surviving object was actually normalized as old");
         end if;
      end loop;
   end Enter_Generation;

   procedure Nursery_Ages (State : in out World) is
      Item : Value;
   begin
      --  Root one new object through three actual minors. Promotion requires
      --  separate survival and OLD1 traversal, preserving children throughout.
      Set_Collector_Mode (State, Generational_Minor_Mode);
      Item := New_Table (State);
      Pin (State, Item);
      Minor (State);
      Assert (Item.Reference.Age = Survival_Age, "first nursery survival");
      Minor (State);
      Assert (Item.Reference.Age = Old_1_Age, "second nursery promotion");
      Minor (State);
      Assert (Item.Reference.Age = Old_Age, "OLD1 was traversed before old");
   end Nursery_Ages;

   procedure Young_Only_Sweep (State : in out World) is
      Old : constant Value := New_Table (State);
      Old_Serial : constant Positive := Old.Reference.Serial;
      Young : Value;
      Young_Serial : Positive;
   begin
      --  Make an object old, then remove its only root and add young garbage.
      --  A real minor frees the nursery but intentionally defers old garbage
      --  to the next major/full cycle; a disguised full GC fails this check.
      Pin (State, Old);
      Set_Collector_Mode (State, Generational_Minor_Mode);
      State.Operation_Roots.Clear;
      Young := New_Table (State);
      Young_Serial := Young.Reference.Serial;
      Minor (State);
      Assert (Contains (State, Old_Serial) and
              not Contains (State, Young_Serial),
              "minor swept nursery without sweeping old population");
      Collect (State);
      Assert (not Contains (State, Old_Serial),
              "full generational cycle reclaimed deferred old garbage");
   end Young_Only_Sweep;

   procedure Remembered_Table (State : in out World) is
      Parent : constant Value := New_Table (State);
      Child : Value;
      Serial : Positive;
   begin
      --  An old table is normally skipped by minors. A raw insertion must
      --  remember it until two traversals age its newly retained child safely.
      Pin (State, Parent);
      Set_Collector_Mode (State, Generational_Minor_Mode);
      Child := New_Table (State);
      Serial := Child.Reference.Serial;
      Set (State, Parent, (Integer_Kind, 1), Child);
      Assert (Parent.Reference.Age = Touched_1_Age and
              Parent.Reference.Color = Gray,
              "old table immediately became touched1/gray between minors");
      Minor (State);
      Assert (Parent.Reference.Age = Touched_2_Age and
              Parent.Reference.Color = Black,
              "first minor advanced touched table to touched2/black");
      Minor (State);
      Assert (Contains (State, Serial) and
              Child.Reference.Age = Old_1_Age,
              "remembered child alive=" & Contains (State, Serial)'Image &
                " mode=" & State.GC.Mode'Image & " age=" &
                (if Contains (State, Serial) then Child.Reference.Age'Image
                 else "RECLAIMED") & " promoted=" &
                State.GC.Promoted_Bytes'Image & " baseline=" &
                State.GC.Major_Baseline_Bytes'Image);
   end Remembered_Table;

   procedure Promoted_Cell_Graph (State : in out World) is
      Holder : constant Value := New_Native
        (State, "collector.cell", One_Value (State, Nil_Value));
      Cell : constant Object_Access := Holder.Reference.Captures (1);
      Child, Grandchild : Value;
      Serial : Positive;
   begin
      --  An old actual upvalue acquires a young parent with a young child.
      --  Forward promotion to OLD0 must still traverse the entire graph in
      --  subsequent minors; making the parent immediately old loses the leaf.
      Pin (State, Holder);
      Set_Collector_Mode (State, Generational_Minor_Mode);
      Child := New_Table (State);
      Grandchild := New_Table (State);
      Serial := Grandchild.Reference.Serial;
      Set (State, Child, (Integer_Kind, 1), Grandchild);
      Store_Cell (State, Cell, Child);
      Assert (Child.Reference.Age = Old_0_Age and
              Child.Reference.Color = Gray,
              "old cell forward barrier produced an actual OLD0 child");
      Minor (State);
      Minor (State);
      Assert (Contains (State, Serial),
              "forward-promoted graph retained its younger descendants");
   end Promoted_Cell_Graph;

   procedure Old_Weak_Values (State : in out World) is
      Weak : constant Value := New_Table (State);
      Meta : constant Value := New_Table (State);
      Item : Value;
      Serial : Positive;
   begin
      --  Weak old tables stay revisitable after ordinary touched aging ends.
      --  Two independent nursery insertions must both clear unrooted values.
      Set (State, Meta, New_String (State, "__mode"), New_String (State, "v"));
      Set_Metatable (State, Weak, Meta.Reference);
      Pin (State, Weak);
      Set_Collector_Mode (State, Generational_Minor_Mode);
      for Pass in 1 .. 2 loop
         Item := New_Table (State);
         Serial := Item.Reference.Serial;
         Set (State, Weak, (Integer_Kind, 1), Item);
         Minor (State);
         Assert (not Contains (State, Serial) and
                 Get (Weak, (Integer_Kind, 1)).Kind = Nil_Kind,
                 "old weak-value table cleared fresh nursery identity");
      end loop;
   end Old_Weak_Values;

   procedure Zero_Major_Threshold (State : in out World) is
      Parent : constant Value := New_Table (State);
      Previous : Integer_Value;
   begin
      --  Lua's zero minormajor parameter disables automatic major switching;
      --  it does not request an immediate major on every minor collection.
      Pin (State, Parent);
      Set_Collector_Mode (State, Generational_Minor_Mode);
      Previous := Collector_Parameter_Value (State, Minor_To_Major, 0);
      Assert (Previous > 0, "fixture observed a nonzero default threshold");
      for Index in 1 .. 200 loop
         Set (State, Parent, (Integer_Kind, Integer_Value (Index)),
              New_Table (State));
      end loop;
      Minor (State);
      Minor (State);
      Assert (State.GC.Mode = Generational_Minor_Mode,
              "zero major threshold preserved real minor mode");
   end Zero_Major_Threshold;

   procedure Mode_Transition (State : in out World) is
      Done : Boolean;
      Before : constant Natural := State.Collections;
   begin
      --  Change mode in the middle of real incremental marking, then return
      --  to incremental mode. Both directions must normalize actual colors.
      Advance_Collection (State, 1, Done);
      Set_Collector_Mode (State, Generational_Minor_Mode);
      Set_Collector_Mode (State, Incremental_Mode);
      Assert (State.GC.Mode = Incremental_Mode and
              State.GC.Phase = Paused and State.Collections > Before,
              "mode transitions completed real ownership normalization");
      Finish (State);
   end Mode_Transition;

   procedure Parameter_Rounding (State : in out World) is
      Previous, Actual : Integer_Value;
   begin
      --  Parameter bytes have a rounded binary mantissa, including Lua5.5's
      --  subnormal values. Setting/querying must use the pinned codec rather
      --  than store arbitrary percentages in a wide integer field.
      Previous := Collector_Parameter_Value (State, Step_Multiplier, 100);
      Assert (Previous = 200, "step multiplier default matched pinned Lua");
      Actual := Collector_Parameter_Value (State, Step_Multiplier, 1);
      Assert (Actual = 100, "set returned the previous decoded parameter");
      Actual := Collector_Parameter_Value (State, Step_Multiplier);
      Assert (Actual = 1, "subnormal parameter decoded as a percentage");
      Previous := Collector_Parameter_Value (State, Step_Multiplier, 255);
      Actual := Collector_Parameter_Value (State, Step_Multiplier);
      Assert (Previous = 1 and Actual = 250,
              "normal mantissa rounding matched pinned parameter codec");
   end Parameter_Rounding;

   procedure Parameter_Saturation (State : in out World) is
      Previous, Actual : Integer_Value;
   begin
      --  Large positive values saturate before multiplying during encoding;
      --  negative values query without mutation, even at Integer64 limits.
      Previous := Collector_Parameter_Value
        (State, Pause_Ratio, Integer_Value'Last);
      Actual := Collector_Parameter_Value
        (State, Pause_Ratio, Integer_Value'First);
      Assert (Previous = 250 and Actual = 396_800,
              "parameter saturation avoided integer overflow");
   end Parameter_Saturation;

   procedure Zero_Step_Size (State : in out World) is
      Previous : Integer_Value;
      Done : Boolean;
      Before : constant Natural := State.Collections;
   begin
      --  Zero stepsize requests a complete real cycle on each manual step.
      --  Completion must remain true on repeated calls without stale phases.
      Previous := Collector_Parameter_Value (State, Step_Size, 0);
      Assert (Previous > 0, "Ada table-derived stepsize was initialized");
      Step_Collection (State, 0, Done);
      Assert (Done and State.Collections = Before + 1,
              "zero-sized step completed its first genuine cycle");
      Step_Collection (State, 0, Done);
      Assert (Done and State.Collections = Before + 2,
              "repeated zero-sized step started a new genuine cycle");
   end Zero_Step_Size;

   procedure Pending_Finalizer (State : in out World) is
      Item : constant Value := Finalizable (State);
      Serial : constant Positive := Item.Reference.Serial;
      Child : constant Value := New_Table (State);
      Child_Serial : constant Positive := Child.Reference.Serial;
   begin
      --  Registration is not a permanent root. Atomic separation keeps only
      --  the genuinely pending target and its strong graph; releasing that
      --  queue ownership permits collection in a following real cycle.
      Set (State, Item, (Integer_Kind, 1), Child);
      Collect (State);
      Assert (State.Finalizer_Head = Item.Reference and
              Contains (State, Serial) and Contains (State, Child_Serial),
              "pending finalizer retained its actual strong object graph");
      Lua.Engine.Finalizers.Begin_Next (State);
      Lua.Engine.Finalizers.Finish_Current (State);
      Collect (State);
      Assert (not Contains (State, Serial) and
              not Contains (State, Child_Serial),
              "finished unresurrected finalizer graph was reclaimed");
   end Pending_Finalizer;

   procedure Weak_Before_Finalizer (State : in out World) is
      Weak : constant Value := New_Table (State);
      Meta : constant Value := New_Table (State);
      Item : constant Value := Finalizable (State);
      Serial : constant Positive := Item.Reference.Serial;
   begin
      --  Weak values clear before unreachable finalizables become pending
      --  roots. Reversing those phases incorrectly preserves this weak edge.
      Set (State, Meta, New_String (State, "__mode"), New_String (State, "v"));
      Set_Metatable (State, Weak, Meta.Reference);
      Set (State, Weak, (Integer_Kind, 1), Item);
      Pin (State, Weak);
      Collect (State);
      Assert (Contains (State, Serial) and
              Get (Weak, (Integer_Kind, 1)).Kind = Nil_Kind,
              "weak edge cleared before pending finalizer graph was marked");
   end Weak_Before_Finalizer;

   procedure Emergency_Queue (State : in out World) is
      Item : constant Value := Finalizable (State);
      Serial : constant Positive := Item.Reference.Serial;
   begin
      --  Pinned emergency atomic still separates finalizable objects. It
      --  must preserve their graph and leave callbacks for the scheduler;
      --  allocator failure must never recursively execute Lua cleanup.
      Begin_Operation (State);
      Set_Failure_Countdown (State.Memory, 0);
      Collect (State, Emergency => True);
      Assert (State.Finalizer_Head = Item.Reference and
              Contains (State, Serial) and not State.Finalizer_Active and
              State.Finalizing_Object = null,
              "emergency queued real finalizer without invoking it");
      Clear_Failures (State.Memory);
      End_Operation (State);
   end Emergency_Queue;

   procedure Weak_Mode_Change (State : in out World) is
      Weak : constant Value := New_Table (State);
      Meta : constant Value := New_Table (State);
      Child : constant Value := New_Table (State);
      Serial : constant Positive := Child.Reference.Serial;
   begin
      --  Traverse a weak-value table, then remove its metatable's __mode
      --  before atomic. Suppressing weak clearing alone is unsafe: its now
      --  strong child must actually become marked before physical sweeping.
      Set (State, Meta, New_String (State, "__mode"), New_String (State, "v"));
      Set_Metatable (State, Weak, Meta.Reference);
      Set (State, Weak, (Integer_Kind, 1), Child);
      Pin (State, Weak);
      Until_Black (State, Weak.Reference);
      Set (State, Meta, New_String (State, "__mode"), Nil_Value);
      Finish (State);
      Assert (Contains (State, Serial) and
              Get (Weak, (Integer_Kind, 1)) = Child,
              "weak-to-strong mode change retained a truly marked child");
   end Weak_Mode_Change;

   procedure Promotion_And_Major (State : in out World) is
      Parent : constant Value := New_Table (State);
      Previous : Integer_Value;
      Garbage : Value;
      Serial : Positive := 1;
      Done : Boolean;
   begin
      --  Promote enough real typed allocations to exceed a 1% major trigger.
      --  The major must then really resume full-heap marking/sweeping; after
      --  reclaiming fresh garbage a zero return threshold permits minors.
      Pin (State, Parent);
      Set_Collector_Mode (State, Generational_Minor_Mode);
      Previous := Collector_Parameter_Value (State, Minor_To_Major, 1);
      Assert (Previous > 0, "nonzero promotion threshold existed");
      Previous := Collector_Parameter_Value (State, Major_To_Minor, 0);
      Assert (Previous > 0, "nonzero return threshold existed");
      for Index in 1 .. 64 loop
         Set (State, Parent, (Integer_Kind, Integer_Value (Index)),
              New_Table (State));
      end loop;
      Minor (State);
      Minor (State);
      Assert (State.GC.Mode = Generational_Major_Mode,
              "actual promoted bytes triggered a real major cycle");
      for Index in 1 .. 200 loop
         Garbage := New_Table (State);
         Serial := Garbage.Reference.Serial;
      end loop;
      Advance_Collection (State, 1, Done);
      Assert (not Done and State.GC.Phase = Propagating,
              "major used resumable full-population marking");
      Finish (State);
      Assert (State.GC.Mode = Generational_Minor_Mode and
              not Contains (State, Serial),
              "major reclaimed real garbage before returning to minors");
   end Promotion_And_Major;

   procedure Positive_Step_Debt (State : in out World) is
      Before : constant Long_Long_Integer := State.GC.Debt_Remaining;
      Work : constant Byte_Count := State.GC.Work_Units;
      Done : Boolean;
   begin
      --  A positive Lua5.5 step argument pays allocation debt in bytes. One
      --  byte cannot start a paused cycle with a genuine positive countdown.
      Assert (Before > 1, "fixture has real post-collection pause debt");
      Step_Collection (State, 1, Done);
      Assert (not Done and State.GC.Phase = Paused and
              State.GC.Work_Units = Work and
              State.GC.Debt_Remaining = Before - 1,
              "positive byte payment did not fabricate traversal work");
   end Positive_Step_Debt;

   procedure Minor_Multiplier_Debt (State : in out World) is
      Previous : Integer_Value;
      Baseline : Byte_Count;
      First_Debt : Long_Long_Integer;
      Before : Natural;
   begin
      --  Keep the same real old population while changing only minormul.
      --  Mode entry must apply the first value, and completing a real minor
      --  cycle must apply the changed value to the next allocation countdown.
      --  A parameter that merely round-trips but never affects scheduling
      --  fails this comparison. The fixture also checks physical cleanup.
      Previous := Collector_Parameter_Value (State, Minor_Multiplier, 100);
      Assert (Previous > 0, "default minor multiplier was positive");
      Set_Collector_Mode (State, Generational_Minor_Mode);
      Baseline := State.GC.Major_Baseline_Bytes;
      First_Debt := State.GC.Debt_Remaining;
      Assert (Baseline > 0 and First_Debt > 0,
              "mode entry established actual live storage and byte debt");
      Previous := Collector_Parameter_Value (State, Minor_Multiplier, 200);
      Assert (Previous = 100, "changed only the minor multiplier");
      Before := State.Collections;
      Minor (State);
      Assert (State.Collections = Before + 1 and
              State.GC.Mode = Generational_Minor_Mode,
              "a real minor collection completed without changing mode");
      Assert (State.GC.Major_Baseline_Bytes = Baseline and
              State.GC.Debt_Remaining = 2 * First_Debt,
              "doubling minormul doubles the next allocation countdown");
   end Minor_Multiplier_Debt;

   procedure Zero_Forces_Work (State : in out World) is
      Work : constant Byte_Count := State.GC.Work_Units;
      Done : Boolean;
   begin
      --  Zero is the force-step spelling even with outstanding pause debt.
      --  The ordinary work budget stops at indivisible atomic rather than
      --  silently sweeping an entire small heap in this same basic step.
      Step_Collection (State, 0, Done);
      Assert (not Done and State.GC.Work_Units > Work and
              State.GC.Phase = Sweeping_Objects,
              "forced basic step performed work and stopped after atomic");
      Finish (State);
   end Zero_Forces_Work;

   procedure Larger_Debt_Payments (State : in out World) is
      Other : World;
      function Count_Steps
        (Subject : in out World; Payment : Byte_Count) return Positive;
      function Count_Steps
        (Subject : in out World; Payment : Byte_Count) return Positive
      is
         Parent : Value;
         Child, Grandchild, Garbage : Value;
         Done : Boolean := False;
         Count : Positive := 1;
      begin
         Collect (Subject);
         Subject.GC_Running := False;
         Parent := New_Table (Subject);
         Pin (Subject, Parent);
         for Index in 1 .. 100 loop
            Child := New_Table (Subject);
            Grandchild := New_Table (Subject);
            Set (Subject, Child, (Integer_Kind, 1), Grandchild);
            Set (Subject, Parent, (Integer_Kind, Integer_Value (Index)),
                 Child);
            Garbage := New_Table (Subject);
         end loop;
         Assert (Garbage.Kind = Table_Kind, "constructed actual garbage");
         while not Done loop
            Step_Collection (Subject, Payment, Done);
            exit when Done;
            Count := Count + 1;
            Assert (Count < 200_000, "byte debt payments made progress");
         end loop;
         return Count;
      end Count_Steps;
      Slow, Fast : Positive;
   begin
      --  Independent equally initialized worlds protect the gc.lua steps
      --  regression: ten-byte payments must finish in fewer calls than two.
      --  This tests real debt/progress; no requested value is a test skip.
      Initialize (Other, (others => <>));
      begin
         Slow := Count_Steps (State, 2);
         Fast := Count_Steps (Other, 10);
         Assert (Fast < Slow,
                 "larger payments: fast" & Fast'Image &
                   " slow" & Slow'Image);
      exception
         when others => Finalize (Other); raise;
      end;
      Finalize (Other);
   end Larger_Debt_Payments;

   procedure Stopped_Manual_Step (State : in out World) is
      Work : constant Byte_Count := State.GC.Work_Units;
      Done : Boolean;
   begin
      --  User-stop suppresses automatic safe-point work, while an explicit
      --  manual request still advances the same collector and preserves stop.
      State.GC_Running := False;
      Restart_Collection (State);
      Poll_Collection (State);
      Assert (State.GC.Work_Units = Work,
              "stopped automatic collector performed no hidden work");
      Step_Collection (State, 0, Done);
      Assert (not State.GC_Running and State.GC.Work_Units > Work,
              "manual step advanced without restarting automatic policy");
      State.GC_Running := True;
      Finish (State);
   end Stopped_Manual_Step;

   procedure Exact_Allocation_Debt (State : in out World) is
      Before : constant Long_Long_Integer := State.GC.Debt_Remaining;
      Sample : constant Byte_Count := State.GC.Last_Sampled_Bytes;
      Item : constant Value := New_Table (State);
      Growth : constant Byte_Count :=
        Statistics (State.Memory).Raw_Bytes - Sample;
      Done : Boolean;
   begin
      --  Sampling charges real provider growth, including the typed record's
      --  compiler/allocator overhead; no C-layout or semantic-slot estimate
      --  can stand in for this measured delta.
      Assert (Item.Reference.Allocation_Bytes > 0 and
              Before > Long_Long_Integer (Growth) + 1,
              "fixture retained enough actual pause debt");
      Step_Collection (State, 1, Done);
      Assert (not Done and State.GC.Debt_Remaining =
                Before - Long_Long_Integer (Growth) - 1,
              "manual step sampled exact managed-allocation byte delta");
   end Exact_Allocation_Debt;

   procedure Extreme_Debt_Payment (State : in out World) is
      Work : constant Byte_Count := State.GC.Work_Units;
      Done : Boolean;
   begin
      --  Saturate the signed countdown near its lower boundary, then pay the
      --  largest representable byte amount. It must force ordinary work and
      --  recover normally, never overflow an Ada scheduling counter.
      State.GC.Debt_Remaining := Long_Long_Integer'First + 5;
      Step_Collection (State, Byte_Count'Last, Done);
      Assert (State.GC.Work_Units > Work,
              "extreme debt payment performed real controlled work");
      Finish (State);
   end Extreme_Debt_Payment;

   procedure Partial_Case is new Fixture (Partial_Mark);
   procedure Root_Case is new Fixture (Root_Publication);
   procedure Cell_Case is new Fixture (Forward_Cell);
   procedure Table_Case is new Fixture (Backward_Table);
   procedure Sweep_Case is new Fixture (New_During_Sweep);
   procedure Heap_Case is new Fixture (Heap_Slot_Reuse);
   procedure Program_Case is new Fixture (Program_Slot_Reuse);
   procedure Bytes_Case is new Fixture (Provider_Bytes);
   procedure Refusal_Case is new Fixture (Refusing_Full);
   procedure Recovery_Case is new Fixture (Failed_Traversal);
   procedure Generation_Case is new Fixture (Enter_Generation);
   procedure Age_Case is new Fixture (Nursery_Ages);
   procedure Young_Case is new Fixture (Young_Only_Sweep);
   procedure Remember_Case is new Fixture (Remembered_Table);
   procedure Graph_Case is new Fixture (Promoted_Cell_Graph);
   procedure Weak_Case is new Fixture (Old_Weak_Values);
   procedure Threshold_Case is new Fixture (Zero_Major_Threshold);
   procedure Mode_Case is new Fixture (Mode_Transition);
   procedure Rounding_Case is new Fixture (Parameter_Rounding);
   procedure Saturation_Case is new Fixture (Parameter_Saturation);
   procedure Step_Case is new Fixture (Zero_Step_Size);
   procedure Finalizer_Case is new Fixture (Pending_Finalizer);
   procedure Ordering_Case is new Fixture (Weak_Before_Finalizer);
   procedure Emergency_Case is new Fixture (Emergency_Queue);
   procedure Weak_Mode_Case is new Fixture (Weak_Mode_Change);
   procedure Major_Case is new Fixture (Promotion_And_Major);
   procedure Payment_Case is new Fixture (Positive_Step_Debt);
   procedure Force_Case is new Fixture (Zero_Forces_Work);
   procedure Larger_Case is new Fixture (Larger_Debt_Payments);
   procedure Stopped_Case is new Fixture (Stopped_Manual_Step);
   procedure Allocation_Case is new Fixture (Exact_Allocation_Debt);
   procedure Extreme_Case is new Fixture (Extreme_Debt_Payment);
   procedure Minor_Debt_Case is new Fixture (Minor_Multiplier_Debt);

   procedure Dead_Context_Cells (State : in out World);
   procedure Dead_Context_Cells (State : in out World) is
   begin
      --  Suspended self-referential coroutines retain captured stack cells.
      --  Churn reused heap slots, then collect both the dead contexts and
      --  their cells. Physical teardown must never read an already swept
      --  cell; closures retained independently must still read live cells.
      Assert (Execute (State,
        "local keep={}; for pass=1,8 do " &
        "for i=1,100 do local co=coroutine.create(function() " &
        "local x={i}; local f=function()return x[1]end; " &
        "coroutine.yield(f) end); local ok,f=coroutine.resume(co); " &
        "assert(ok); if i==100 then keep[pass]=f end end; " &
        "collectgarbage() end; " &
        "for _,f in ipairs(keep) do assert(f()==100) end",
        "dead-context-cells"), "coroutine cell reclamation completed");
      Collect (State);
   end Dead_Context_Cells;
   procedure Dead_Context_Case is new Fixture (Dead_Context_Cells);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "collector: dead context cell sweep order",
                        Dead_Context_Case'Access);
      Test_Support.Add (Suite, "collector: persistent partial marking",
                        Partial_Case'Access);
      Test_Support.Add (Suite, "collector: root publication during marking",
                        Root_Case'Access);
      Test_Support.Add (Suite, "collector: actual cell forward barrier",
                        Cell_Case'Access);
      Test_Support.Add (Suite, "collector: raw table backward barrier",
                        Table_Case'Access);
      Test_Support.Add (Suite, "collector: allocation between sweep batches",
                        Sweep_Case'Access);
      Test_Support.Add (Suite, "collector: stable heap slot reuse",
                        Heap_Case'Access);
      Test_Support.Add (Suite, "collector: stable program slot reuse",
                        Program_Case'Access);
      Test_Support.Add (Suite, "collector: actual provider byte reclamation",
                        Bytes_Case'Access);
      Test_Support.Add (Suite, "collector: refusing allocator emergency GC",
                        Refusal_Case'Access);
      Test_Support.Add (Suite, "collector: failed traversal recovery",
                        Recovery_Case'Access);
      Test_Support.Add (Suite, "collector: actual generational entry",
                        Generation_Case'Access);
      Test_Support.Add (Suite, "collector: separate nursery age transitions",
                        Age_Case'Access);
      Test_Support.Add (Suite, "collector: minor sweeps young objects only",
                        Young_Case'Access);
      Test_Support.Add (Suite, "collector: remembered old table graph",
                        Remember_Case'Access);
      Test_Support.Add (Suite, "collector: forward-promoted cell graph",
                        Graph_Case'Access);
      Test_Support.Add (Suite, "collector: revisitable old weak values",
                        Weak_Case'Access);
      Test_Support.Add (Suite, "collector: zero disables major threshold",
                        Threshold_Case'Access);
      Test_Support.Add (Suite, "collector: interleaved mode transitions",
                        Mode_Case'Access);
      Test_Support.Add (Suite, "collector: pinned parameter rounding",
                        Rounding_Case'Access);
      Test_Support.Add (Suite, "collector: saturated parameter arithmetic",
                        Saturation_Case'Access);
      Test_Support.Add (Suite, "collector: zero stepsize completes cycles",
                        Step_Case'Access);
      Test_Support.Add (Suite, "collector: queued finalizer graph ownership",
                        Finalizer_Case'Access);
      Test_Support.Add (Suite, "collector: weak values before finalization",
                        Ordering_Case'Access);
      Test_Support.Add (Suite, "collector: emergency queues without calls",
                        Emergency_Case'Access);
      Test_Support.Add (Suite, "collector: interleaved weak-mode replacement",
                        Weak_Mode_Case'Access);
      Test_Support.Add (Suite, "collector: real promotion and major cycle",
                        Major_Case'Access);
      Test_Support.Add (Suite, "collector: positive steps pay byte debt",
                        Payment_Case'Access);
      Test_Support.Add (Suite, "collector: zero forces real basic work",
                        Force_Case'Access);
      Test_Support.Add (Suite, "collector: larger byte payments finish sooner",
                        Larger_Case'Access);
      Test_Support.Add (Suite, "collector: stopped automatic/manual policy",
                        Stopped_Case'Access);
      Test_Support.Add (Suite, "collector: exact allocation debt sampling",
                        Allocation_Case'Access);
      Test_Support.Add (Suite, "collector: saturating extreme debt payment",
                        Extreme_Case'Access);
      Test_Support.Add (Suite, "collector: minormul changes minor byte debt",
                        Minor_Debt_Case'Access);
   end Register;
end Lua.Collector_Tests;
