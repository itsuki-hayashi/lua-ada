with Ada.Containers;

package body Lua.Engine.Stacks is
   use type Lua.Storage.Owner_Access;

   procedure Check_Owner
     (State : in out World; Context : not null Context_Access);
   procedure Check_Slot
     (State : in out World; Context : not null Context_Access;
      Index : Positive);
   procedure Check_Range
     (Context : not null Context_Access; First : Positive; Last : Natural);

   procedure Check_Owner
     (State : in out World; Context : not null Context_Access) is
   begin
      if Context.Memory /= Lua.Storage.Reference (State.Memory) or else
        Context.Foreign_Stack.Owner_Of /= Context.Memory or else
        Context.Stack_Cells.Owner_Of /= Context.Memory
      then
         raise Program_Error with "scalar arena has another allocator";
      end if;
   end Check_Owner;

   procedure Check_Slot
     (State : in out World; Context : not null Context_Access;
      Index : Positive) is
   begin
      Check_Owner (State, Context);
      if Natural (Context.Foreign_Stack.Length) /=
        Natural (Context.Stack_Cells.Length)
      then
         raise Program_Error with "mismatched scalar arena lengths";
      elsif Index > Natural (Context.Foreign_Stack.Length) then
         Fail (State, "stack index out of range");
      end if;
   end Check_Slot;

   procedure Check_Range
     (Context : not null Context_Access; First : Positive; Last : Natural) is
   begin
      if Context.Memory = null or else
        Context.Foreign_Stack.Owner_Of /= Context.Memory or else
        Context.Stack_Cells.Owner_Of /= Context.Memory or else
        Natural (Context.Foreign_Stack.Length) /=
          Natural (Context.Stack_Cells.Length)
      then
         raise Program_Error with "invalid parallel scalar arena";
      elsif First <= Last and then
        (Last > Natural (Context.Foreign_Stack.Length) or else
         Last > Natural (Context.Stack_Cells.Length))
      then
         raise Program_Error with "uninitialized scalar arena interval";
      end if;
   end Check_Range;

   procedure Reserve
     (State : in out World; Context : not null Context_Access;
      Last : Natural)
   is
      Retried : Boolean := False;
      Needed : constant Natural := Natural'Max
        (Last, Natural'Max (Natural (Context.Foreign_Stack.Length),
                           Natural (Context.Stack_Cells.Length)));
   begin
      Check_Owner (State, Context);
      loop
         begin
            --  Reserve both buffers before publishing either new length.
            --  Value/cell elements are scalar and initialize without further
            --  allocation, so refusal preserves the old logical lengths and
            --  live slots. A successful first reserve may leave spare
            --  physical capacity if the second fails; no semantic top is
            --  published here. Emergency GC may clear already dead slots.
            Context.Foreign_Stack.Reserve_Capacity
              (Ada.Containers.Count_Type (Needed));
            Context.Stack_Cells.Reserve_Capacity
              (Ada.Containers.Count_Type (Needed));
            Context.Foreign_Stack.Set_Length
              (Ada.Containers.Count_Type (Needed));
            Context.Stack_Cells.Set_Length
              (Ada.Containers.Count_Type (Needed));
            return;
         exception
            when Lua.Storage.Allocation_Error =>
               if not Retry_Allocation (State, Retried) then
                  raise;
               end if;
            when Program_Error =>
               --  Ada may wrap failed controlled initialization. A genuine
               --  provider-refusal witness is mandatory; an unrelated
               --  invariant/tampering error must never become a GC retry.
               if not Lua.Storage.Refusal_Pending (State.Memory) or else
                 not Retry_Allocation (State, Retried)
               then
                  raise;
               end if;
         end;
      end loop;
   end Reserve;

   function Read
     (State : in out World; Context : not null Context_Access;
      Index : Positive) return Value
   is
   begin
      Check_Slot (State, Context, Index);
      return Read (Context, Index);
   end Read;

   function Read
     (Context : not null Context_Access; Index : Positive) return Value
   is
      Cell : Object_Access;
   begin
      Check_Range (Context, Index, Index);
      Cell := Context.Stack_Cells.Element (Index);
      return (if Cell = null then Context.Foreign_Stack.Element (Index)
              else Cell.Cell_Value);
   end Read;

   procedure Write
     (State : in out World; Context : not null Context_Access;
      Index : Positive; Item : Value)
   is
      Cell : Object_Access;
   begin
      Check_Slot (State, Context, Index);
      --  No vector reference survives either operation. Cached scalar writes
      --  and cell writes cannot allocate; both describe one Lua binding.
      Cell := Context.Stack_Cells.Element (Index);
      Root_Barrier (State, Item);
      Context.Foreign_Stack.Replace_Element (Index, Item);
      if Cell /= null then
         Store_Cell (State, Cell, Item);
      end if;
   end Write;

   function Capture
     (State : in out World; Context : not null Context_Access;
      Index : Positive) return Object_Access
   is
      Cell : Object_Access;
   begin
      Check_Slot (State, Context, Index);
      Cell := Context.Stack_Cells.Element (Index);
      if Cell = null then
         --  The source slot is already a live collector root. New_Cell may
         --  trigger one emergency collection, so retain only its stable
         --  absolute index rather than borrowing either resizable vector.
         Cell := New_Cell (State, Read (State, Context, Index));
         if Context.Thread = null then
            Root_Barrier (State, Cell);
         else
            Write_Barrier (State, Context.Thread, Cell);
         end if;
         Context.Stack_Cells.Replace_Element (Index, Cell);
      end if;
      return Cell;
   end Capture;

   procedure Detach
     (Context : not null Context_Access; First : Positive; Last : Natural) is
   begin
      Check_Range (Context, First, Last);
      for Index in First .. Last loop
         declare
            Cell : constant Object_Access :=
              Context.Stack_Cells.Element (Index);
         begin
            if Cell /= null then
               Context.Foreign_Stack.Replace_Element
                 (Index, Cell.Cell_Value);
               Context.Stack_Cells.Replace_Element (Index, null);
            end if;
         end;
      end loop;
   end Detach;

   procedure Clear_Range
     (Context : not null Context_Access; First : Positive; Last : Natural) is
   begin
      Check_Range (Context, First, Last);
      for Index in First .. Last loop
         --  The actual cell already owns its latest value. Dropping only the
         --  association preserves closures that survive this stack lifetime;
         --  the cached scalar itself is dead and must not remain a GC edge.
         Context.Stack_Cells.Replace_Element (Index, null);
         Context.Foreign_Stack.Replace_Element (Index, Nil_Value);
      end loop;
   end Clear_Range;

   procedure Trim (Context : not null Context_Access; Last : Natural) is
      Initialized : constant Natural :=
        Natural (Context.Foreign_Stack.Length);
   begin
      Check_Range (Context, 1, Initialized);
      if Last > Initialized then
         raise Program_Error with "scalar arena trim exceeds storage";
      elsif Last < Initialized then
         Clear_Range (Context, Last + 1, Initialized);
      end if;
   end Trim;

   function Try_Shrink
     (Context : not null Context_Access; Last : Natural) return Boolean
   is
      Initialized : constant Natural :=
        Natural (Context.Foreign_Stack.Length);
   begin
      Check_Range (Context, 1, Initialized);
      if Last > Initialized then
         raise Program_Error with "physical stack shrink cannot grow";
      elsif Last = Initialized and then
        Natural (Context.Foreign_Stack.Capacity) = Last and then
        Natural (Context.Stack_Cells.Capacity) = Last
      then
         return True;
      end if;
      declare
         --  Controlled Ada buffers cannot safely use raw realloc: their
         --  discriminants, finalization links and possibly nested elements
         --  belong to typed objects. Exact ownerful prefix copies provide a
         --  safe physical shrink, whose temporary peak/counts remain real.
         New_Values : Values.Vector := Values.Copy_Prefix
           (Context.Foreign_Stack, Ada.Containers.Count_Type (Last),
            Ada.Containers.Count_Type (Last));
         New_Cells : Cell_References.Vector := Cell_References.Copy_Prefix
           (Context.Stack_Cells, Ada.Containers.Count_Type (Last),
            Ada.Containers.Count_Type (Last));
      begin
         Values.Move (Context.Foreign_Stack, New_Values);
         Cell_References.Move (Context.Stack_Cells, New_Cells);
      end;
      return True;
   exception
      when Lua.Storage.Allocation_Error =>
         Lua.Storage.Acknowledge_Refusal (Context.Memory.all);
         return False;
      when Program_Error =>
         if not Lua.Storage.Refusal_Pending (Context.Memory.all) then
            raise;
         end if;
         Lua.Storage.Acknowledge_Refusal (Context.Memory.all);
         return False;
   end Try_Shrink;


   procedure Trace
     (Context : not null Context_Access;
      Mark_Value : not null access procedure (Item : Value);
      Mark_Cell : not null access procedure (Item : Object_Access))
   is
      Prefix : constant Natural :=
        (if Context.Detached_Resume_Window then Context.Resume_Host_Stack_Top
         elsif Context.Stack.Is_Empty then Context.Foreign_Top
         else Context.Host_Stack_Top);
      Initialized : constant Natural :=
        Natural (Context.Foreign_Stack.Length);
      Previous_First, Visited : Natural := 0;
      Public_First : constant Natural := Context.Resume_Stack_Used + 1;
      Public_Last : constant Natural := Context.Host_Stack_Top;
      Public_Visited : Boolean := not Context.Detached_Resume_Window;

      procedure Bounds
        (Activation : not null Frame_Access; First, Last : out Natural);
      procedure Visit (First, Last : Natural);

      procedure Bounds
        (Activation : not null Frame_Access; First, Last : out Natural) is
      begin
         First := Natural'Max
           (1, (if Activation.Hidden_Varargs then Activation.Call_Base
                else Activation.Stack_Base));
         if Activation.Is_Native then
            Last :=
              (if Activation = Context.Foreign_Activation and then
                 Activation.Foreign_Entered and then
                 Activation = Context.Stack.Last_Element
               then Context.Foreign_Top else Activation.Stack_Live_Top);
         else
            if Activation.Canonical_GC_Top >
              Natural'Last - Activation.Stack_Base
            then
               raise Program_Error with "scalar live window overflow";
            end if;
            Last := Activation.Stack_Base + Activation.Canonical_GC_Top;
            if Activation.Warning_Borrow_Depth /= 0 then
               --  A C warning callback borrows this real Lua frame without
               --  adding a logical debug frame. Its API writes are live too.
               Last := Natural'Max (Last, Activation.Stack_Live_Top);
            end if;
         end if;
      end Bounds;

      procedure Visit (First, Last : Natural) is
         Start : Natural;
      begin
         if First > Last or else Last <= Visited then
            return;
         end if;
         if First > Visited + 1 then
            Clear_Range (Context, Visited + 1, First - 1);
         end if;
         Start := Natural'Max (First, Visited + 1);
         for Index in Start .. Last loop
            declare
               Cell : constant Object_Access :=
                 Context.Stack_Cells.Element (Index);
            begin
               if Cell = null then
                  Mark_Value (Context.Foreign_Stack.Element (Index));
               else
                  --  A debug/upvalue write may leave the scalar cache stale.
                  --  Trace the actual cell/value, not both competing copies.
                  Context.Foreign_Stack.Replace_Element
                    (Index, Cell.Cell_Value);
                  Mark_Cell (Cell);
               end if;
            end;
         end loop;
         Visited := Last;
      end Visit;
   begin
      Check_Range (Context, 1, Initialized);
      if Prefix > Initialized then
         raise Program_Error with "host prefix exceeds scalar arena";
      end if;
      if Context.Detached_Resume_Window and then
        (Public_Last < Context.Resume_Stack_Used or else
         Public_Last > Initialized)
      then
         raise Program_Error with "invalid detached public stack window";
      end if;
      --  Validate the complete ordering before clearing anything. Eagerly
      --  clearing a gap and only later discovering an out-of-order window
      --  could destroy a live child value before reporting the invariant.
      for Activation of Context.Stack loop
         if Activation.Has_Stack_Window then
            declare
               First, Last : Natural;
            begin
               Bounds (Activation, First, Last);
               if Activation.Context /= Context or else
                 First < Previous_First or else Last > Initialized
               then
                  raise Program_Error with "invalid ordered scalar windows";
               end if;
               Previous_First := First;
            end;
         end if;
      end loop;
      if Prefix > 0 then
         Visit (1, Prefix);
      end if;
      --  Windows are ordered by their starts, and can overlap arbitrarily.
      --  Visited is the union's high-water mark, so each scalar is traced at
      --  most once and a parent's dead tail cannot clear an active child.
      for Activation of Context.Stack loop
         if Activation.Has_Stack_Window then
            declare
               First, Last : Natural;
            begin
               Bounds (Activation, First, Last);
               if not Public_Visited and then Public_First < First then
                  Visit (Public_First, Public_Last);
                  Public_Visited := True;
               end if;
               Visit (First, Last);
               if not Public_Visited and then Public_First <= Last + 1 then
                  Visit (Public_First, Public_Last);
                  Public_Visited := True;
               end if;
            end;
         end if;
      end loop;
      if not Public_Visited then
         --  A public yield/argument window is a separate live interval. Its
         --  high address cannot turn gaps or dead Lua temporaries below it
         --  into an artificial host prefix retaining weakly reachable data.
         Visit (Public_First, Public_Last);
      end if;
      if Visited < Initialized then
         Clear_Range (Context, Visited + 1, Initialized);
      end if;
   end Trace;
end Lua.Engine.Stacks;
