package Lua.Engine.Stacks is
   --  One context-owned scalar arena is shared by Lua registers and public
   --  C stack windows. Absolute indices survive vector growth; no operation
   --  returns an element reference whose address could become stale.

   procedure Reserve
     (State : in out World; Context : not null Context_Access;
      Last : Natural);
   --  Initialize both parallel arenas through Last, preserving their logical
   --  lengths if either growth is refused. Physical capacity
   --  already obtained from the owner may remain larger after a failed pair.
   --  The caller roots Context/inputs and checks semantic stack quotas before
   --  requesting storage. Retry through one allocation-free emergency GC.
   --  This is physical-only: callers publish/restore current-frame ci.top
   --  in Stack_Used after success; it need not cover ancestor reservations.

   function Read
     (State : in out World; Context : not null Context_Access;
      Index : Positive) return Value;
   function Read
     (Context : not null Context_Access; Index : Positive) return Value;
   --  Allocation-free internal read for already validated foreign indices.
   --  Invalid ownership/initialized bounds raises Program_Error, never Lua.
   --  API index validity and frame-window policy belong to each caller.
   procedure Write
     (State : in out World; Context : not null Context_Access;
      Index : Positive; Item : Value);
   --  Cell_Value is authoritative while a slot has an open capture. Writes
   --  synchronize its cached scalar and actual individually owned cell.

   function Capture
     (State : in out World; Context : not null Context_Access;
      Index : Positive) return Object_Access;
   --  Create at most one actual cell for this live slot. Its current value
   --  and context must stay traced across the possible allocation safe point.

   procedure Detach
     (Context : not null Context_Access; First : Positive; Last : Natural);
   --  Copy authoritative cell values back, then remove only the open-slot
   --  associations. Closures retain their existing cells and identities.
   procedure Clear_Range
     (Context : not null Context_Access; First : Positive; Last : Natural);
   --  Detach and clear an initialized inclusive interval without allocation.
   --  First > Last is empty. The caller owns the complete interval; clearing
   --  a parent's dead tail is invalid when a child window overlaps it.
   procedure Trim (Context : not null Context_Access; Last : Natural);
   --  Clear initialized slots above Last, retaining arena capacity/length.
   --  Do not change any semantic/API top; the caller owns those transitions.

   procedure Trace
     (Context : not null Context_Access;
      Mark_Value : not null access procedure (Item : Value);
      Mark_Cell : not null access procedure (Item : Object_Access));
   --  Validate ordered live windows, then mark their union and the host
   --  prefix. Clear only gaps/tail, never an overlapping child's live data.
   --  Native packet roots remain the collector's separate responsibility.
   --  Callbacks must not allocate, change windows, or execute Lua code.
end Lua.Engine.Stacks;
