with Lua.Engine.Finalizers;

separate (Lua.Engine)
package body Collector is
   type Weak_Flags is record
      Keys, Values : Boolean := False;
   end record;

   function Other (Color : White_Color) return White_Color is
     (if Color = White_0 then White_1 else White_0);
   function White (Item : Object_Access) return Boolean is
     (Item /= null and then Item.Color in White_0 | White_1);
   function Young (Item : Object_Access) return Boolean is
     (Item.Age in New_Age | Survival_Age);

   procedure Shade
     (State : in out World; Item : Object_Access; Force : Boolean := False);
   procedure Shade_Value (State : in out World; Item : Value);
   procedure Shade_Code (State : in out World; Item : Prototype_Access);
   procedure Trace_Context (State : in out World; Context : Context_Access);
   function Weak_Mode (Item : Object_Access) return Weak_Flags;
   function Alive (State : World; Item : Value) return Boolean;
   procedure Trace_Roots (State : in out World);
   procedure Propagate_Object (State : in out World);
   procedure Propagate_Code (State : in out World);
   procedure Propagate_All (State : in out World);
   procedure Converge_Ephemerons (State : in out World);
   procedure Clear_Weak
     (State : in out World; Keys, Values : Boolean);
   procedure Atomic (State : in out World);
   procedure Begin_Cycle (State : in out World);
   procedure Sweep_Object (State : in out World);
   procedure Sweep_Program (State : in out World);
   procedure Reset_After_Failure (State : in out World);
   procedure Remember (State : in out World; Item : not null Object_Access);
   procedure Move_Age
     (State : in out World; Item : not null Object_Access; Age : Object_Age);
   procedure Forget (State : in out World; Item : not null Object_Access);
   procedure Minor (State : in out World);
   procedure Make_All_Old (State : in out World);
   function Bytes (State : World) return Lua.Storage.Byte_Count;
   procedure Initialize_Parameters (State : in out World);
   procedure Finish_Cycle (State : in out World);
   procedure Account (State : in out World);
   procedure Set_Debt
     (State : in out World; Amount : Lua.Storage.Byte_Count);
   procedure Sample_Debt (State : in out World);

   procedure Account (State : in out World) is
   begin
      if State.GC.Work_Units < Lua.Storage.Byte_Count'Last then
         State.GC.Work_Units := State.GC.Work_Units + 1;
      end if;
   end Account;

   procedure Set_Debt
     (State : in out World; Amount : Lua.Storage.Byte_Count)
   is
      Current : constant Lua.Storage.Byte_Count := Bytes (State);
      Limit : constant Lua.Storage.Byte_Count :=
        Lua.Storage.Byte_Count'Last - Current;
   begin
      --  Like luaE_setdebt, keep actual bytes plus the positive countdown
      --  representable. The provider retains the authoritative byte count;
      --  debt is scheduling policy, never another memory-use estimate.
      State.GC.Debt_Remaining := Long_Long_Integer
        (Lua.Storage.Byte_Count'Min (Amount, Limit));
      State.GC.Last_Sampled_Bytes := Current;
   end Set_Debt;

   procedure Sample_Debt (State : in out World) is
      Current : constant Lua.Storage.Byte_Count := Bytes (State);
      Delta_Bytes : Lua.Storage.Byte_Count;
      Change : Long_Long_Integer;
   begin
      --  All managed allocations/frees already update the selected owner.
      --  Sampling their net delta at a VM/API safe point preserves the same
      --  countdown meaning without a global allocator callback or reentry.
      if Current >= State.GC.Last_Sampled_Bytes then
         Delta_Bytes := Current - State.GC.Last_Sampled_Bytes;
         Change := Long_Long_Integer (Delta_Bytes);
         State.GC.Debt_Remaining :=
           (if State.GC.Debt_Remaining < Long_Long_Integer'First + Change
            then Long_Long_Integer'First
            else State.GC.Debt_Remaining - Change);
      else
         Delta_Bytes := State.GC.Last_Sampled_Bytes - Current;
         Change := Long_Long_Integer (Delta_Bytes);
         State.GC.Debt_Remaining :=
           (if State.GC.Debt_Remaining > Long_Long_Integer'Last - Change
            then Long_Long_Integer'Last
            else State.GC.Debt_Remaining + Change);
      end if;
      State.GC.Last_Sampled_Bytes := Current;
   end Sample_Debt;

   function Unreachable (State : World; Item : Object_Access)
                         return Boolean is
   begin
      if Item = null or else
        (State.GC.Cycle_Is_Minor and then not Young (Item))
      then
         return False;
      elsif State.GC.Phase in Sweeping_Objects | Sweeping_Programs |
        Finishing_Sweep | Finalizers_Ready
      then
         return Item.Color = Other (State.GC.Current_White);
      end if;
      return Item.Color = State.GC.Current_White;
   end Unreachable;

   procedure Shade
     (State : in out World; Item : Object_Access; Force : Boolean := False) is
   begin
      Account (State);
      if Item = null or else Item.Gray_List /= Not_Queued or else
        (not White (Item) and then not Force)
      then
         return;
      elsif State.GC.Cycle_Is_Minor and then
        not Young (Item) and then not Force
      then
         return;
      end if;
      --  Persistent links belong to one world's phase machine. Mutator
      --  barriers can add work between Advance calls, without retaining this
      --  Ada activation or allocating another work-list element.
      Item.Color := Gray;
      Item.Gray_List := Primary_Gray;
      Item.Mark_Next := State.GC.Gray_Head;
      State.GC.Gray_Head := Item;
   end Shade;

   procedure Shade_Value (State : in out World; Item : Value) is
   begin
      if Item.Kind in String_Kind | Table_Kind | Closure_Kind |
        Native_Closure_Kind | Thread_Kind | Userdata_Kind
      then
         Shade (State, Item.Reference);
      else
         Account (State);
      end if;
   end Shade_Value;

   procedure Shade_Code (State : in out World; Item : Prototype_Access) is
   begin
      Account (State);
      if Item = null or else Item.Color not in White_0 | White_1 then
         return;
      end if;
      Item.Color := Gray;
      Item.Mark_Next := State.GC.Code_Gray;
      State.GC.Code_Gray := Item;
      --  One immutable canonical owner retains all of its real wrappers.
      --  Queue them once instead of recursively tracing their constants on
      --  the Ada stack; runtime closures/cells remain separate heap objects.
      if Item.Canonical_Owner /= null and then
        Item.Canonical_Owner.Color in White_0 | White_1
      then
         Item.Canonical_Owner.Color := Black;
         for Sibling of Item.Canonical_Owner.Wrappers loop
            Shade_Code (State, Sibling);
         end loop;
      end if;
   end Shade_Code;

   function Weak_Mode (Item : Object_Access) return Weak_Flags is
      Mode : constant Value := Tables.Raw_Field (Item.Metatable, "__mode");
      Result : Weak_Flags;
      Byte : Character;
   begin
      if Mode.Kind = String_Kind then
         for Index in 1 .. Length (Mode.Reference.Bytes) loop
            Byte := Element (Mode.Reference.Bytes, Index);
            exit when Byte = ASCII.NUL;
            Result.Keys := Result.Keys or Byte = 'k';
            Result.Values := Result.Values or Byte = 'v';
            exit when Result.Keys and Result.Values;
         end loop;
      end if;
      return Result;
   end Weak_Mode;

   function Alive (State : World; Item : Value) return Boolean is
     (Item.Kind not in Table_Kind | Closure_Kind | Native_Closure_Kind |
        Thread_Kind | Userdata_Kind or else not Unreachable
          (State, Item.Reference));
   --  Lua weak strings have value semantics; they are not cleared as weak
   --  identities. Their actual objects are nevertheless marked by traversal.

   procedure Propagate_Object (State : in out World) is
      Item : constant Object_Access := State.GC.Gray_Head;
      procedure Mark (Child : Object_Access);
      procedure Mark_Value (Child : Value);
      procedure Mark (Child : Object_Access) is
      begin
         Shade (State, Child);
      end Mark;
      procedure Mark_Value (Child : Value) is
      begin
         Shade_Value (State, Child);
      end Mark_Value;
   begin
      State.GC.Gray_Head := Item.Mark_Next;
      Item.Mark_Next := null;
      Item.Gray_List := Not_Queued;
      case Item.Kind is
         when Thread_Object =>
            Trace_Context (State, State.Contexts (Item.Context_Index));
         when Cell_Object => Mark_Value (Item.Cell_Value);
         when String_Object => null;
         when Userdata_Object =>
            Mark (Item.Userdata_Metatable);
            for Uservalue of Item.Uservalues loop
               Mark_Value (Uservalue);
            end loop;
         when Table_Object =>
            Mark (Item.Metatable);
            declare
               Mode : constant Weak_Flags := Weak_Mode (Item);
            begin
               Item.Weak_Seen := Mode.Keys or Mode.Values;
               for Member of Item.Members loop
                  Account (State);
                  if Member.Item.Kind /= Nil_Kind then
                     if not Mode.Keys or else Member.Key.Kind = String_Kind
                     then
                        Mark_Value (Member.Key);
                     end if;
                     if Member.Item.Kind = String_Kind or else
                       (not Mode.Values and then
                        (not Mode.Keys or else Alive (State, Member.Key)))
                     then
                        Mark_Value (Member.Item);
                     end if;
                  end if;
               end loop;
            end;
         when Environment =>
            Mark (Item.Parent);
            for Local of Item.Locals loop
               Mark (Local.Cell);
            end loop;
         when Closure =>
            Mark (Item.Capture);
            Shade_Code (State, Item.Code);
            for Cell of Item.Upvalues loop
               Mark (Cell);
            end loop;
         when Native_Closure =>
            for Cell of Item.Captures loop
               Mark (Cell);
            end loop;
      end case;
      Item.Color := Black;
      if Item.Kind = Thread_Object and then State.GC.Phase = Propagating
      then
         --  A traversed stack remains revisitable until atomic. Apart from
         --  publication barriers this ensures dead slots/optional stack
         --  maintenance are reconciled for every reachable suspended thread,
         --  not just whichever thread happens to be the active root later.
         Item.Color := Gray;
         Item.Gray_List := Revisit_Gray;
         Item.Mark_Next := State.GC.Gray_Again;
         State.GC.Gray_Again := Item;
      end if;
      if not Young (Item) and then
        (Item.Kind = Thread_Object or else
         (Item.Kind = Table_Object and then
          (Weak_Mode (Item).Keys or else Weak_Mode (Item).Values)))
      then
         --  Old stacks and weak tables contain independently changing live
         --  edges. Keep them in the actual remembered set between minors;
         --  an old ordinary immutable object needs no such repeated scan.
         Remember (State, Item);
      end if;
   end Propagate_Object;

   procedure Propagate_Code (State : in out World) is
      Item : constant Prototype_Access := State.GC.Code_Gray;
   begin
      State.GC.Code_Gray := Item.Mark_Next;
      Item.Mark_Next := null;
      for Constant_Value of Item.Canonical_Constants loop
         Shade_Value (State, Constant_Value);
      end loop;
      for Instruction_Value of Item.Code loop
         Shade_Code (State, Instruction_Value.Nested);
      end loop;
      Item.Color := Black;
   end Propagate_Code;

   procedure Propagate_All (State : in out World) is
   begin
      --  Code traversal can reveal heap strings, and closures can reveal code.
      --  Drain both queues to a fixed point; a one-way ordering would miss
      --  edges first discovered by the second family of work.
      while State.GC.Gray_Head /= null or else State.GC.Code_Gray /= null loop
         if State.GC.Gray_Head /= null then
            Propagate_Object (State);
         else
            Propagate_Code (State);
         end if;
      end loop;
   end Propagate_All;

   procedure Converge_Ephemerons (State : in out World) is
   begin
      loop
         for Item of State.Heap loop
            if Item /= null and then Item.Kind = Table_Object and then
              not Unreachable (State, Item)
            then
               declare
                  Mode : constant Weak_Flags := Weak_Mode (Item);
               begin
                  if Mode.Keys and then not Mode.Values then
                     for Member of Item.Members loop
                        if Alive (State, Member.Key) then
                           Shade_Value (State, Member.Item);
                        end if;
                     end loop;
                  end if;
               end;
            end if;
         end loop;
         exit when State.GC.Gray_Head = null and State.GC.Code_Gray = null;
         Propagate_All (State);
      end loop;
   end Converge_Ephemerons;

   procedure Clear_Weak
     (State : in out World; Keys, Values : Boolean) is
   begin
      for Item of State.Heap loop
         if Item /= null and then Item.Kind = Table_Object and then
           not Unreachable (State, Item)
         then
            declare
               Mode : constant Weak_Flags := Weak_Mode (Item);
            begin
               for Index in Item.Members.First_Index ..
                 Item.Members.Last_Index
               loop
                  declare
                     Member : Table_Entry := Item.Members.Element (Index);
                  begin
                     if (Keys and then Mode.Keys and then
                         not Alive (State, Member.Key)) or else
                       (Values and then Mode.Values and then
                         not Alive (State, Member.Item))
                     then
                        Member.Item := Nil_Value;
                     end if;
                     if Keys and then Member.Item.Kind = Nil_Kind and then
                       Member.Key.Kind in String_Kind | Table_Kind |
                         Closure_Kind | Native_Closure_Kind | Thread_Kind |
                           Userdata_Kind
                       and then Unreachable (State, Member.Key.Reference)
                     then
                        Member.Key := Nil_Value;
                     end if;
                     Item.Members.Replace_Element (Index, Member);
                  end;
               end loop;
               Tables.Rebuild (Item);
            end;
         end if;
      end loop;
   end Clear_Weak;

   procedure Atomic (State : in out World) is
      function Dead (Item : Object_Access) return Boolean;
      procedure Mark (Item : Object_Access);
      function Dead (Item : Object_Access) return Boolean is
        (Unreachable (State, Item));
      procedure Mark (Item : Object_Access) is
      begin
         Shade (State, Item, Force => True);
      end Mark;
   begin
      --  Atomic is deliberately indivisible, as in pinned Lua. Ordinary
      --  propagation/sweep really yielded between previous Advance calls;
      --  this phase reconciles mutator roots, barriers, weak graphs and the
      --  pending finalizer queue before any dead identity can be released.
      Trace_Roots (State);
      while State.GC.Gray_Again /= null loop
         declare
            Item : constant Object_Access := State.GC.Gray_Again;
         begin
            State.GC.Gray_Again := Item.Mark_Next;
            Item.Mark_Next := State.GC.Gray_Head;
            Item.Gray_List := Primary_Gray;
            State.GC.Gray_Head := Item;
         end;
      end loop;
      for Item of State.Heap loop
         if Item /= null and then Item.Weak_Seen and then
           not Unreachable (State, Item)
         then
            --  __mode can be replaced while marking is suspended. Retrace
            --  the actual previously weak table under its current policy,
            --  including a weak-to-strong change; merely suppressing weak
            --  clearing would otherwise leave dangling unmarked values.
            Item.Weak_Seen := False;
            Shade (State, Item, Force => True);
         end if;
      end loop;
      Propagate_All (State);
      Converge_Ephemerons (State);
      Clear_Weak (State, Keys => False, Values => True);
      Lua.Engine.Finalizers.Queue_Unreachable (State, Dead'Access);
      Lua.Engine.Finalizers.Trace_Roots (State, Mark'Access);
      Propagate_All (State);
      Converge_Ephemerons (State);
      Clear_Weak (State, Keys => True, Values => True);
      State.GC.Current_White := Other (State.GC.Current_White);
      State.GC.Atomic_Completed := True;
      State.GC.Sweep_Index := 1;
      State.GC.Sweep_End := State.Heap.Last_Index;
      State.GC.Program_Index := 1;
      State.GC.Program_End := State.Programs.Last_Index;
      State.GC.Phase := Sweeping_Objects;
   end Atomic;

   procedure Sweep_Object (State : in out World) is
      Slot : constant Positive := State.GC.Sweep_Index;
      Item : constant Object_Access := State.Heap.Element (Slot);
   begin
      State.GC.Sweep_Index := State.GC.Sweep_Index + 1;
      if Item = null then
         return;
      elsif Unreachable (State, Item) then
         if Item.Kind = Thread_Object then
            declare
               Context : Context_Access :=
                 State.Contexts.Element (Item.Context_Index);
            begin
               if Context /= null and then not Context.Host_Owned then
                  Destroy_Frames (State, Context);
                  State.Contexts.Replace_Element (Item.Context_Index, null);
                  Release_Foreign_Context (State, Context);
                  Free_Context (Context);
               end if;
            end;
         end if;
         Release_Heap_Object (State, Slot);
      else
         Item.Color := State.GC.Current_White;
         Item.Weak_Seen := False;
      end if;
   end Sweep_Object;

   procedure Sweep_Program (State : in out World) is
      Slot : constant Positive := State.GC.Program_Index;
      Item : Prototype_Access := State.Programs.Element (Slot);
   begin
      State.GC.Program_Index := State.GC.Program_Index + 1;
      if Item = null then
         return;
      elsif Item.Color = Other (State.GC.Current_White) then
         Release_Registered_Program (State, Item);
      else
         Item.Color := State.GC.Current_White;
         if Item.Canonical_Owner /= null then
            Item.Canonical_Owner.Color := State.GC.Current_White;
         end if;
      end if;
   end Sweep_Program;

   function Bytes (State : World) return Lua.Storage.Byte_Count is
     (Lua.Storage.Statistics (State.Memory).Raw_Bytes);

   procedure Trace_Context (State : in out World; Context : Context_Access) is
      procedure Mark (Item : Object_Access);
      procedure Mark_Value (Item : Value);
      procedure Mark (Item : Object_Access) is
      begin
         Shade (State, Item);
      end Mark;
      procedure Mark_Value (Item : Value) is
      begin
         Shade_Value (State, Item);
      end Mark_Value;
      procedure Mark_Activation (Activation : not null Frame_Access);
      procedure Mark_Activation (Activation : not null Frame_Access) is
      begin
         Mark_Value (Activation.Callee);
         Mark_Value (Activation.Message_Handler);
         Mark_Value (Activation.Warning_Root);
         for Item of Activation.Error_Packet loop
            Mark_Value (Item);
         end loop;
         for Closing of Activation.Closers loop
            Mark (Closing.Cell);
            if Closing.Frozen then
               Mark_Value (Closing.Frozen_Value);
            end if;
         end loop;
         Mark_Value (Activation.Unwind_Error);
         for Item of Activation.Unwind_Results loop
            Mark_Value (Item);
         end loop;
         Mark (Activation.Native_Self);
         for Item of Activation.Native_Arguments loop
            Mark_Value (Item);
         end loop;
         for Item of Activation.Native_Results loop
            Mark_Value (Item);
         end loop;
         for Item of Activation.Native_Captures loop
            Mark_Value (Item);
         end loop;
         Mark (Activation.Scope);
         Shade_Code (State, Activation.Code);
         Mark (Activation.Vararg_Table);
         for Index in 1 .. Activation.Active_Registers loop
            for Item of Activation.Slots (Index) loop
               Mark_Value (Item);
            end loop;
         end loop;
         for Item of Activation.Varargs loop
            Mark_Value (Item);
         end loop;
      end Mark_Activation;
   begin
      if Context = null then
         return;
      end if;
      for Item of Context.Boundary_Results loop
         Mark_Value (Item);
      end loop;
      Lua.Engine.Stacks.Trace
        (Context, Mark_Value'Access, Mark'Access);
      if State.GC.Phase = Enter_Atomic and then not State.GC.Emergency then
         --  Mark/clear the actual live union before optional physical copies.
         --  No vector borrow survives Trace; absolute indices and stable
         --  cells remain authoritative after both arrays move together.
         Shrink_Context_Storage (State, Context);
      end if;
      Mark_Value (Context.Hook);
      Mark_Value (Context.Entry_Function);
      Mark_Value (Context.Failure);
      for Item of Context.Transfer.Results loop
         Mark_Value (Item);
      end loop;
      for Item of Context.Arguments loop
         Mark_Value (Item);
      end loop;
      for Activation of Context.Stack loop
         Mark_Activation (Activation);
         declare
            Deferred : Frame_Access := Activation.Deferred_Error_Head;
         begin
            --  A boundary remains on the real context stack while its C
            --  guard owns error transfer. Every detached scope must keep
            --  its frozen cells/closers/prototype traced in that interval.
            while Deferred /= null loop
               Mark_Activation (Deferred);
               Deferred := Deferred.Deferred_Error_Next;
            end loop;
         end;
      end loop;
   end Trace_Context;

   procedure Trace_Roots (State : in out World) is
      String_Root : Object_Access := State.String_Root_Head;
      Release : Object_Access;
      procedure Mark (Item : Object_Access);
      procedure Mark (Item : Object_Access) is
      begin
         Shade (State, Item, Force => Item /= null and then
           Item.Kind = Thread_Object);
      end Mark;
   begin
      Mark (State.Main_Thread);
      Mark (State.Foreign_Registry);
      Shade_Value (State, State.Memory_Error_Value);
      Shade_Value (State, State.Handling_Error_Value);
      Shade_Code (State, State.Entry_Code);
      for Code of State.Operation_Programs loop
         Shade_Code (State, Code);
      end loop;
      for Item of State.Operation_Roots loop
         Shade_Value (State, Item);
      end loop;
      while String_Root /= null loop
         Mark (String_Root);
         String_Root := String_Root.String_Root_Next;
      end loop;
      Release := State.External_Release_Head;
      while Release /= null loop
         if Release.Registry_Slot /= 0 then Mark (Release); end if;
         Release := Release.Release_Next;
      end loop;
      Release := State.External_Release_Active;
      while Release /= null loop
         if Release.Registry_Slot /= 0 then Mark (Release); end if;
         Release := Release.Release_Active_Previous;
      end loop;
      if State.Operation_Active or else State.GC.Emergency then
         for Item of State.Heap loop
            if Item /= null and then Item.Serial >= State.Operation_Start
            then
               Mark (Item);
            end if;
         end loop;
      end if;
      if State.Compiling or else State.GC.Cycle_Is_Minor then
         --  The old lowerer still owns unfinished registry entries. During
         --  a minor, immutable code owners are a conservative root family:
         --  their constant objects cannot become dangling just because an
         --  old closure is deliberately not traversed in this generation.
         --  Heap old-to-young traversal still uses the remembered set.
         for Item of State.Programs loop
            Shade_Code (State, Item);
         end loop;
      end if;
      Mark (State.String_Metatable);
      for Meta of State.Type_Metatables loop
         Mark (Meta);
      end loop;
      Mark (State.Loaded_Modules);
      Mark (State.Preload_Modules);
      Lua.Engine.Finalizers.Trace_Roots (State, Mark'Access);
      for Context of State.Contexts loop
         if Context /= null and then
           (Context.Host_Owned or else Context.Status in
              Running_Context | Normal_Context)
         then
            Mark (Context.Thread);
            if Context.Thread = null then
               Trace_Context (State, Context);
            end if;
         end if;
      end loop;
   end Trace_Roots;

   procedure Forget (State : in out World; Item : not null Object_Access) is
   begin
      if not Item.Remembered then
         return;
      end if;
      if Item.Remembered_Previous = null then
         State.GC.Remembered_Head := Item.Remembered_Next;
      else
         Item.Remembered_Previous.Remembered_Next := Item.Remembered_Next;
      end if;
      if Item.Remembered_Next /= null then
         Item.Remembered_Next.Remembered_Previous := Item.Remembered_Previous;
      end if;
      Item.Remembered := False;
      Item.Remembered_Next := null;
      Item.Remembered_Previous := null;
   end Forget;

   procedure Remember (State : in out World; Item : not null Object_Access) is
   begin
      if Item.Remembered then
         return;
      end if;
      Item.Remembered := True;
      Item.Remembered_Previous := null;
      Item.Remembered_Next := State.GC.Remembered_Head;
      if State.GC.Remembered_Head /= null then
         State.GC.Remembered_Head.Remembered_Previous := Item;
      end if;
      State.GC.Remembered_Head := Item;
   end Remember;

   procedure Move_Age
     (State : in out World; Item : not null Object_Access; Age : Object_Age)
   is
   begin
      if Item.Generation_Previous = null then
         State.GC.Generations (Item.Age) := Item.Generation_Next;
      else
         Item.Generation_Previous.Generation_Next := Item.Generation_Next;
      end if;
      if Item.Generation_Next /= null then
         Item.Generation_Next.Generation_Previous := Item.Generation_Previous;
      end if;
      Item.Age := Age;
      Item.Generation_Previous := null;
      Item.Generation_Next := State.GC.Generations (Age);
      if State.GC.Generations (Age) /= null then
         State.GC.Generations (Age).Generation_Previous := Item;
      end if;
      State.GC.Generations (Age) := Item;
   end Move_Age;

   procedure Register_Object
     (State : in out World; Item : not null Object_Access) is
   begin
      Item.Color := State.GC.Current_White;
      Item.Age := New_Age;
      Item.Generation_Previous := null;
      Item.Generation_Next := State.GC.Generations (New_Age);
      if Item.Generation_Next /= null then
         Item.Generation_Next.Generation_Previous := Item;
      end if;
      State.GC.Generations (New_Age) := Item;
      --  Publication does not imply reachability. The caller must install a
      --  root/store barrier before any subsequent allocation safe point.
   end Register_Object;

   procedure Unregister_Object
     (State : in out World; Item : not null Object_Access) is
   begin
      Forget (State, Item);
      if Item.Generation_Previous = null then
         State.GC.Generations (Item.Age) := Item.Generation_Next;
      else
         Item.Generation_Previous.Generation_Next := Item.Generation_Next;
      end if;
      if Item.Generation_Next /= null then
         Item.Generation_Next.Generation_Previous := Item.Generation_Previous;
      end if;
      Item.Generation_Next := null;
      Item.Generation_Previous := null;
   end Unregister_Object;

   procedure Register_Program
     (State : in out World; Item : not null Prototype_Access) is
   begin
      Item.Color := State.GC.Current_White;
      if Item.Canonical_Owner /= null then
         Item.Canonical_Owner.Color := State.GC.Current_White;
      end if;
   end Register_Program;

   procedure Root_Barrier (State : in out World; Item : Value) is
   begin
      --  At the enter-atomic boundary all running-thread roots are rescanned
      --  before sweep. A transient call argument that has already returned
      --  must not keep a weakly reachable coroutine alive for another cycle.
      --  Heap edges still use their forward/back barriers: only root packets
      --  defer to that mandatory atomic rescan.
      if State.GC.Phase = Propagating then
         Shade_Value (State, Item);
      end if;
   end Root_Barrier;

   procedure Revive_String
     (State : in out World; Item : not null Object_Access) is
   begin
      --  The intern chain can still contain a string whose old-white color
      --  was declared dead at atomic, but whose sweep slot has not run. As
      --  in luaS_internshrstr, finding its bytes makes that same header live
      --  again. Strings have no outgoing edges, so whitening is sufficient
      --  after the marking wave; during propagation use its ordinary queue.
      if State.GC.Phase in Sweeping_Objects | Sweeping_Programs |
        Finishing_Sweep | Finalizers_Ready
      then
         Item.Color := State.GC.Current_White;
      else
         Root_Barrier (State, Item);
      end if;
   end Revive_String;

   procedure Root_Barrier (State : in out World; Item : Object_Access) is
   begin
      if State.GC.Phase = Propagating then
         Shade (State, Item);
      end if;
   end Root_Barrier;

   procedure Code_Barrier (State : in out World; Item : Prototype_Access) is
   begin
      if State.GC.Phase in Propagating | Enter_Atomic then
         Shade_Code (State, Item);
      end if;
   end Code_Barrier;

   procedure Write_Barrier
     (State : in out World; Owner : not null Object_Access;
      Item : Object_Access) is
   begin
      if Item = null then
         return;
      end if;
      if not Young (Owner) and then Young (Item) then
         --  A forward edge makes the child OLD0, preserving it until an
         --  explicit OLD1 traversal has visited all of its own children.
         Move_Age (State, Item, Old_0_Age);
         Remember (State, Owner);
      end if;
      if Owner.Color = Black and then White (Item) then
         if State.GC.Phase in Propagating | Enter_Atomic or else
           State.GC.Mode = Generational_Minor_Mode
         then
            Shade (State, Item, Force => True);
         elsif State.GC.Phase in Sweeping_Objects | Sweeping_Programs then
            --  Sweep no longer has a marking wave. Repair the owner color
            --  rather than appending work to a queue nobody would drain.
            Owner.Color := State.GC.Current_White;
         end if;
      end if;
   end Write_Barrier;

   procedure Write_Barrier
     (State : in out World; Owner : not null Object_Access; Item : Value) is
   begin
      if Item.Kind in String_Kind | Table_Kind | Closure_Kind |
        Native_Closure_Kind | Thread_Kind | Userdata_Kind
      then
         Write_Barrier (State, Owner, Item.Reference);
      end if;
   end Write_Barrier;

   procedure Back_Barrier
     (State : in out World; Owner : not null Object_Access) is
   begin
      if not Young (Owner) then
         Remember (State, Owner);
         if Owner.Age /= Touched_1_Age then
            Move_Age (State, Owner, Touched_1_Age);
         end if;
      end if;
      if Owner.Color = Black then
         if State.GC.Phase in Propagating | Enter_Atomic |
           Sweeping_Objects | Sweeping_Programs or else
           State.GC.Mode = Generational_Minor_Mode
         then
            --  One intrusive mark link cannot belong to two gray lists.
            --  Revisit membership prevents repeated table writes appending
            --  duplicate links or corrupting the persistent work list.
            Owner.Color := Gray;
            Owner.Gray_List := Revisit_Gray;
            Owner.Mark_Next := State.GC.Gray_Again;
            State.GC.Gray_Again := Owner;
         end if;
      end if;
   end Back_Barrier;

   function Encode (Percent : Lua.Storage.Byte_Count)
                    return Interfaces.Unsigned_8
   is
      Scaled, Shift : Lua.Storage.Byte_Count;
   begin
      --  Preserve pinned luaO_codeparam's rounded subnormal/normal boundary.
      --  Saturating before multiplication keeps arbitrary Lua integers safe.
      if Percent >= 396_800 then
         return 255;
      end if;
      Scaled := (Percent * 128 + 99) / 100;
      if Scaled < 16 then
         return Interfaces.Unsigned_8 (Scaled);
      end if;
      Shift := 0;
      while Scaled >= 32 loop
         Scaled := Scaled / 2;
         Shift := Shift + 1;
      end loop;
      return Interfaces.Unsigned_8
        ((Shift + 1) * 16 + Scaled - 16);
   end Encode;

   function Apply
     (Encoded : Interfaces.Unsigned_8; Amount : Lua.Storage.Byte_Count)
      return Lua.Storage.Byte_Count
   is
      Mantissa : Lua.Storage.Byte_Count :=
        Lua.Storage.Byte_Count (Encoded) mod 16;
      Exponent : Integer := Integer (Encoded) / 16;
      Result : Lua.Storage.Byte_Count;
   begin
      if Exponent /= 0 then
         Exponent := Exponent - 1;
         Mantissa := Mantissa + 16;
      end if;
      Exponent := Exponent - 7;
      if Exponent >= 0 then
         if Mantissa /= 0 and then
           Amount > Lua.Storage.Byte_Count'Last / Mantissa
         then
            return Lua.Storage.Byte_Count'Last;
         end if;
         Result := Amount * Mantissa;
         for Index in 1 .. Exponent loop
            if Result > Lua.Storage.Byte_Count'Last / 2 then
               return Lua.Storage.Byte_Count'Last;
            end if;
            Result := Result * 2;
         end loop;
         return Result;
      elsif Amount <= Lua.Storage.Byte_Count'Last / 31 then
         return Amount * Mantissa / 2 ** (-Exponent);
      elsif Amount / 2 ** (-Exponent) <=
        Lua.Storage.Byte_Count'Last / 31
      then
         return Amount / 2 ** (-Exponent) * Mantissa;
      end if;
      return Lua.Storage.Byte_Count'Last;
   end Apply;

   procedure Initialize_Parameters (State : in out World) is
      subtype Table_Header is Heap_Object (Table_Object, 0);
      Header_Bytes : constant Lua.Storage.Byte_Count :=
        (Table_Header'Size + System.Storage_Unit - 1) / System.Storage_Unit;
   begin
      if State.GC.Parameters_Ready then
         return;
      end if;
      State.GC.Parameters :=
        [Minor_Multiplier => Encode (20),
         Major_To_Minor => Encode (50), Minor_To_Major => Encode (70),
         Pause_Ratio => Encode (250), Step_Multiplier => Encode (200),
         Step_Size => Encode (200 * Header_Bytes)];
      --  The step-size default uses the actual Ada table header, not a
      --  fabricated C Table layout. Count/threshold samples use the selected
      --  provider's real raw live bytes, including owned vector capacities.
      State.GC.Parameters_Ready := True;
      Set_Debt (State, 0);
   end Initialize_Parameters;

   function Parameter
     (State : in out World; Name : Collector_Parameter;
      Value : Integer_Value := Integer_Value'First) return Integer_Value
   is
      Result : Integer_Value;
   begin
      Initialize_Parameters (State);
      Result := Integer_Value (Apply (State.GC.Parameters (Name), 100));
      if Value >= 0 then
         State.GC.Parameters (Name) := Encode
           (Lua.Storage.Byte_Count'Min
              (396_800, Lua.Storage.Byte_Count (Value)));
      end if;
      return Result;
   end Parameter;

   procedure Begin_Cycle (State : in out World) is
   begin
      Initialize_Parameters (State);
      State.GC.Cycle_Started_Bytes := Bytes (State);
      State.GC.Cycle_Marked_Bytes := 0;
      State.GC.Atomic_Completed := False;
      State.GC.Cycle_Is_Minor := False;
      State.GC.Phase := Propagating;
      Trace_Roots (State);
   end Begin_Cycle;

   procedure Reset_After_Failure (State : in out World) is
   begin
      --  A propagation callback must never leave intrusive links pointing
      --  through an abandoned local queue. The heap still owns every live
      --  object; rebuilding neutral metadata requires no allocation and does
      --  not invoke user code. Already released sweep slots remain null.
      State.GC.Gray_Head := null;
      State.GC.Gray_Again := null;
      State.GC.Code_Gray := null;
      State.GC.Remembered_Head := null;
      State.GC.Generations := [others => null];
      for Item of State.Heap loop
         if Item /= null then
            Item.Mark_Next := null;
            Item.Gray_List := Not_Queued;
            Item.Remembered := False;
            Item.Remembered_Next := null;
            Item.Remembered_Previous := null;
            Item.Weak_Seen := False;
            Item.Generation_Next := null;
            Item.Generation_Previous := null;
            Register_Object (State, Item);
         end if;
      end loop;
      for Item of State.Programs loop
         if Item /= null then
            Item.Mark_Next := null;
            Register_Program (State, Item);
         end if;
      end loop;
      if State.GC.Mode = Generational_Minor_Mode then
         --  Old colors no longer describe a completed major after recovery.
         --  The next real cycle must rebuild that invariant before minors.
         State.GC.Mode := Generational_Major_Mode;
      end if;
      State.GC.Cycle_Is_Minor := False;
      State.GC.Young_Sweep := null;
      State.GC.Phase := Paused;
      State.Collector_Active := False;
      Set_Debt (State, 0);
   end Reset_After_Failure;

   procedure Make_All_Old (State : in out World) is
   begin
      State.GC.Generations := [others => null];
      State.GC.Remembered_Head := null;
      for Item of State.Heap loop
         if Item /= null then
            Item.Age := Old_Age;
            Item.Color := Black;
            Item.Gray_List := Not_Queued;
            Item.Mark_Next := null;
            Item.Remembered := False;
            Item.Remembered_Next := null;
            Item.Remembered_Previous := null;
            Item.Generation_Previous := null;
            Item.Generation_Next := State.GC.Generations (Old_Age);
            if Item.Generation_Next /= null then
               Item.Generation_Next.Generation_Previous := Item;
            end if;
            State.GC.Generations (Old_Age) := Item;
            if Item.Kind = Thread_Object or else
              (Item.Kind = Table_Object and then
               (Weak_Mode (Item).Keys or else Weak_Mode (Item).Values))
            then
               Remember (State, Item);
            end if;
         end if;
      end loop;
      for Item of State.Programs loop
         if Item /= null then
            Item.Color := Black;
            if Item.Canonical_Owner /= null then
               Item.Canonical_Owner.Color := Black;
            end if;
         end if;
      end loop;
      State.GC.Mode := Generational_Minor_Mode;
      State.GC.Major_Baseline_Bytes := Bytes (State);
      State.GC.Promoted_Bytes := 0;
      Set_Debt (State, Apply
        (State.GC.Parameters (Minor_Multiplier),
         State.GC.Major_Baseline_Bytes));
   end Make_All_Old;

   procedure Finish_Cycle (State : in out World) is
      Current : constant Lua.Storage.Byte_Count := Bytes (State);
      Added : constant Lua.Storage.Byte_Count :=
        (if State.GC.Cycle_Started_Bytes > State.GC.Major_Baseline_Bytes
         then State.GC.Cycle_Started_Bytes - State.GC.Major_Baseline_Bytes
         else 0);
      Reclaimed : constant Lua.Storage.Byte_Count :=
        (if State.GC.Cycle_Started_Bytes > Current
         then State.GC.Cycle_Started_Bytes - Current else 0);
   begin
      --  Backward barriers may enqueue marked owners during incremental
      --  sweep. They must become gray immediately (unlike forward barriers),
      --  then sweep whitens their still-live nodes. No marking wave remains
      --  in this cycle; unlink the completed revisit list before its owners
      --  can become garbage in the next cycle. This never follows dead nodes:
      --  only black, already marked objects enter this list during sweep.
      if not State.GC.Cycle_Is_Minor then
         while State.GC.Gray_Again /= null loop
            declare
               Item : constant Object_Access := State.GC.Gray_Again;
            begin
               State.GC.Gray_Again := Item.Mark_Next;
               Item.Mark_Next := null;
               Item.Gray_List := Not_Queued;
            end;
         end loop;
      end if;
      State.GC.Last_Completed_Bytes := Current;
      State.GC.Last_Sampled_Bytes := Current;
      if State.Collections < Natural'Last then
         State.Collections := State.Collections + 1;
      end if;
      State.Next_GC := Positive'Max
        (256, (if State.Live_Objects > Positive'Last / 2
               then Positive'Last else State.Live_Objects * 2));
      if not State.GC.Cycle_Is_Minor and then
        State.GC.Mode = Generational_Major_Mode and then
        Reclaimed > Apply (State.GC.Parameters (Major_To_Minor), Added)
      then
         Make_All_Old (State);
      elsif State.GC.Mode = Generational_Major_Mode then
         State.GC.Major_Baseline_Bytes := Current;
      end if;
      if State.GC.Mode = Generational_Minor_Mode then
         Set_Debt (State, Apply
           (State.GC.Parameters (Minor_Multiplier),
            State.GC.Major_Baseline_Bytes));
      else
         declare
            Threshold : constant Lua.Storage.Byte_Count :=
              Apply (State.GC.Parameters (Pause_Ratio), Current);
         begin
            Set_Debt
              (State, (if Threshold > Current then Threshold - Current
                       else 0));
         end;
      end if;
      State.GC.Phase := Finalizers_Ready;
      if not State.GC.Emergency then
         --  One ordinary cycle grants one scheduler drain opportunity. If
         --  minimum stack/CI preflight fails, caller code must progress until
         --  a later real cycle requests another attempt; queue presence alone
         --  cannot trigger a helper before every instruction forever.
         State.Finalizers_Requested :=
           Lua.Engine.Finalizers.Has_Pending (State);
      end if;
   end Finish_Cycle;

   procedure Minor (State : in out World) is
      Cursor, Next : Object_Access;
      Size, Limit : Lua.Storage.Byte_Count;

      procedure Age_And_Trace (Age : Object_Age; New_Age : Object_Age);
      procedure Sweep_Young (Age : Object_Age);

      procedure Age_And_Trace (Age : Object_Age; New_Age : Object_Age) is
         Item : Object_Access := State.GC.Generations (Age);
         Following : Object_Access;
      begin
         while Item /= null loop
            Following := Item.Generation_Next;
            Shade (State, Item, Force => True);
            Move_Age (State, Item, New_Age);
            Item := Following;
         end loop;
      end Age_And_Trace;

      procedure Sweep_Young (Age : Object_Age) is
         Item : Object_Access := State.GC.Generations (Age);
         Following : Object_Access;
      begin
         while Item /= null loop
            Following := Item.Generation_Next;
            if Unreachable (State, Item) then
               State.GC.Sweep_Index := Item.Registry_Slot;
               Sweep_Object (State);
            elsif Age = New_Age then
               Move_Age (State, Item, Survival_Age);
               Item.Color := State.GC.Current_White;
            else
               Move_Age (State, Item, Old_1_Age);
               Item.Color := Black;
               --  Promotion work derives from the actual typed allocation,
               --  not C object-size guesses. Global thresholds/counts still
               --  use all real raw provider storage, including auxiliaries.
               Size := Item.Allocation_Bytes;
               State.GC.Promoted_Bytes :=
                 (if Size > Lua.Storage.Byte_Count'Last -
                    State.GC.Promoted_Bytes
                  then Lua.Storage.Byte_Count'Last
                  else State.GC.Promoted_Bytes + Size);
               Remember (State, Item);
            end if;
            Item := Following;
         end loop;
      end Sweep_Young;
   begin
      --  Lua's minor itself is indivisible: OLD1 tracing, atomic convergence
      --  and real nursery sweeping finish in one collector activation.
      --  Major/inc propagation and sweeping remain genuinely resumable.
      Initialize_Parameters (State);
      State.GC.Cycle_Started_Bytes := Bytes (State);
      State.GC.Cycle_Is_Minor := True;
      State.GC.Atomic_Completed := False;
      State.GC.Phase := Propagating;
      Age_And_Trace (Old_1_Age, Old_Age);
      Age_And_Trace (Old_0_Age, Old_1_Age);
      Cursor := State.GC.Remembered_Head;
      while Cursor /= null loop
         Next := Cursor.Remembered_Next;
         Shade (State, Cursor, Force => True);
         Cursor := Next;
      end loop;
      for Code of State.Programs loop
         if Code /= null then
            Code.Color := State.GC.Current_White;
            if Code.Canonical_Owner /= null then
               Code.Canonical_Owner.Color := State.GC.Current_White;
            end if;
         end if;
      end loop;
      Trace_Roots (State);
      State.GC.Phase := Enter_Atomic;
      Atomic (State);
      --  Sweep the pre-existing survival list first: nursery survivors moved
      --  into it below must not become old in the same collection.
      Sweep_Young (Survival_Age);
      Sweep_Young (New_Age);
      Cursor := State.GC.Remembered_Head;
      while Cursor /= null loop
         Next := Cursor.Remembered_Next;
         if Cursor.Age = Touched_1_Age then
            Move_Age (State, Cursor, Touched_2_Age);
         elsif Cursor.Age = Touched_2_Age then
            Move_Age (State, Cursor, Old_Age);
            if Cursor.Kind /= Thread_Object and then not
              (Cursor.Kind = Table_Object and then
               (Weak_Mode (Cursor).Keys or else Weak_Mode (Cursor).Values))
            then
               Forget (State, Cursor);
            end if;
         elsif Cursor.Age = Old_Age and then
           Cursor.Kind /= Thread_Object and then not
           (Cursor.Kind = Table_Object and then
            (Weak_Mode (Cursor).Keys or else Weak_Mode (Cursor).Values))
         then
            Forget (State, Cursor);
         end if;
         Cursor := Next;
      end loop;
      Limit := Apply
        (State.GC.Parameters (Minor_To_Major), State.GC.Major_Baseline_Bytes);
      if Limit /= 0 and then State.GC.Promoted_Bytes >= Limit then
         --  Preparing a major whitens old objects; keeping their black marks
         --  would prevent the next root wave from traversing the full graph.
         Reset_After_Failure (State);
         State.GC.Mode := Generational_Major_Mode;
         State.GC.Cycle_Is_Minor := True;
      end if;
      Finish_Cycle (State);
      State.GC.Cycle_Is_Minor := False;
   end Minor;

   procedure Advance
     (State : in out World; Work : Positive; Finished : out Boolean)
   is
      Remaining : Natural := Work;
      Consumed : Natural;
      Before : Lua.Storage.Byte_Count;
   begin
      if State.Collector_Active then
         Finished := False;
         return;
      end if;
      State.Collector_Active := True;
      Finished := False;
      if State.GC.Phase = Finalizers_Ready then
         State.GC.Phase := Paused;
         --  Completion must survive a work-budget boundary at the end of
         --  sweeping. Starting another cycle here would lose that event.
         State.Collector_Active := False;
         Finished := True;
         return;
      end if;
      if State.GC.Mode = Generational_Minor_Mode then
         Minor (State);
         State.GC.Phase := Paused;
         State.Collector_Active := False;
         Finished := True;
         return;
      end if;
      while Remaining /= 0 loop
         Consumed := 1;
         Before := State.GC.Work_Units;
         case State.GC.Phase is
            when Paused => Begin_Cycle (State);
            when Propagating =>
               if State.GC.Gray_Head /= null then
                  Propagate_Object (State);
               elsif State.GC.Code_Gray /= null then
                  Propagate_Code (State);
               else
                  State.GC.Phase := Enter_Atomic;
               end if;
            when Enter_Atomic =>
               Atomic (State);
               --  A basic incremental step stops at atomic even if that
               --  indivisible work exceeded or left unused its word budget.
               --  Fast zero-work cycles call Advance again to finish sweep.
               exit;
            when Sweeping_Objects =>
               if State.GC.Sweep_Index <= State.GC.Sweep_End then
                  Sweep_Object (State);
               else
                  State.GC.Phase := Sweeping_Programs;
               end if;
            when Sweeping_Programs =>
               if State.GC.Program_Index <= State.GC.Program_End then
                  Sweep_Program (State);
               else
                  State.GC.Phase := Finishing_Sweep;
               end if;
            when Finishing_Sweep => Finish_Cycle (State);
            when Finalizers_Ready =>
               State.GC.Phase := Paused;
               Finished := True;
               exit;
         end case;
         --  Traversal is charged by the actual visited edges/rows, including
         --  already marked targets. Table/thread traversal stays atomic, as
         --  in Lua, but its whole cost reduces this step's remaining work.
         if State.GC.Work_Units > Before then
            Consumed := Natural (Lua.Storage.Byte_Count'Min
              (Lua.Storage.Byte_Count (Natural'Last),
               State.GC.Work_Units - Before));
         end if;
         Remaining := Remaining - Natural'Min (Consumed, Remaining);
      end loop;
      State.Collector_Active := False;
   exception
      when others =>
         Reset_After_Failure (State);
         raise;
   end Advance;

   procedure Step
     (State : in out World; Extra_Bytes : Lua.Storage.Byte_Count;
      Finished : out Boolean)
   is
      Size, Work : Lua.Storage.Byte_Count;
      Word_Bytes : constant Positive :=
        (System.Address'Size + System.Storage_Unit - 1) /
          System.Storage_Unit;
   begin
      Finished := False;
      if State.Collector_Active then
         return;
      end if;
      Initialize_Parameters (State);
      if Extra_Bytes = 0 then
         --  A zero request forces a basic step. Positive requests instead
         --  pay allocation debt and can legitimately perform no work yet.
         Set_Debt (State, 0);
      else
         Sample_Debt (State);
         declare
            Payment : constant Long_Long_Integer :=
              Long_Long_Integer (Extra_Bytes);
         begin
            State.GC.Debt_Remaining :=
              (if State.GC.Debt_Remaining <
                 Long_Long_Integer'First + Payment
               then Long_Long_Integer'First
               else State.GC.Debt_Remaining - Payment);
         end;
      end if;
      if State.GC.Debt_Remaining > 0 then
         return;
      end if;
      Size := Apply (State.GC.Parameters (Step_Size), 100);
      Work := Apply
        (State.GC.Parameters (Step_Multiplier),
         Size / Lua.Storage.Byte_Count (Word_Bytes));
      if Work = 0 then
         --  A zero work budget (stepsize or stepmul) finishes one real cycle.
         --  Repeated Advance calls still perform real separate phases;
         --  this is not a fake completion flag around old full collection.
         while not Finished loop
            Advance (State, 256, Finished);
         end loop;
         return;
      end if;
      Advance
        (State, Positive'Max
           (1, Positive (Lua.Storage.Byte_Count'Min
              (Lua.Storage.Byte_Count (Positive'Last),
               Lua.Storage.Byte_Count'Max (1, Work)))),
         Finished);
      if not Finished then
         --  Sweeping/marking is genuinely unfinished. As in incstep, the
         --  next basic step waits for stepsize further bytes, irrespective
         --  of any extra payment discarded by this single manual request.
         Set_Debt (State, Size);
      end if;
   end Step;

   procedure Poll (State : in out World) is
      Completed : Boolean;
   begin
      if not State.GC_Running or else State.Collector_Active or else
        State.State_Close_Phase or else State.Finalizer_Active
      then
         return;
      end if;
      Initialize_Parameters (State);
      Sample_Debt (State);
      --  A bounded host can run out of object slots before its byte debt
      --  expires. At this instruction safe point all temporaries are rooted;
      --  reclaim before the next opcode needs a small batch of new objects.
      if State.Live_Objects >= State.Bounds.Heap_Objects -
        Natural'Min (64, State.Bounds.Heap_Objects / 4)
      then
         Full (State);
         return;
      end if;
      if State.GC.Debt_Remaining <= 0 then
         Step (State, 0, Completed);
      end if;
   end Poll;

   procedure Restart (State : in out World) is
   begin
      Initialize_Parameters (State);
      Set_Debt (State, 0);
   end Restart;

   procedure Full (State : in out World; Emergency : Boolean := False) is
      Saved_Mode : constant Collector_Mode := State.GC.Mode;
      Completed : Boolean := False;
   begin
      if State.Collector_Active then
         return;
      end if;
      --  Restart neutrally so emergency collection never trusts a partial
      --  earlier root snapshot. Persistent construction roots are re-read.
      Reset_After_Failure (State);
      State.GC.Mode := Incremental_Mode;
      State.GC.Emergency := Emergency;
      while not Completed loop
         Advance (State, 256, Completed);
      end loop;
      if Saved_Mode /= Incremental_Mode then
         Make_All_Old (State);
      end if;
      State.GC.Emergency := False;
   exception
      when others =>
         State.GC.Emergency := False;
         Reset_After_Failure (State);
         raise;
   end Full;

   procedure Change_Mode
     (State : in out World; Mode : Collector_Mode) is
   begin
      if State.Collector_Active or else
        (State.GC.Mode = Incremental_Mode and then Mode = Incremental_Mode)
        or else (State.GC.Mode = Generational_Minor_Mode and then
                 Mode /= Incremental_Mode)
      then
         return;
      end if;
      if Mode = Incremental_Mode then
         if State.GC.Mode = Generational_Minor_Mode then
            --  Leaving minors repairs the color/age invariant without
            --  collecting otherwise unreachable objects or creating a new
            --  finalization opportunity. This owned backend performs that
            --  allocation-free neutralization synchronously; Lua's allgc
            --  representation schedules its corresponding whitening sweep.
            Reset_After_Failure (State);
            Set_Debt (State, Apply (State.GC.Parameters (Step_Size), 100));
         end if;
         State.GC.Mode := Incremental_Mode;
      else
         --  In particular GENMAJOR -> GENMINOR is not a no-op: the public
         --  generational request must complete actual normalization before
         --  the next nursery-only cycle can omit old population traversal.
         Full (State);
         Make_All_Old (State);
      end if;
   end Change_Mode;
end Collector;
