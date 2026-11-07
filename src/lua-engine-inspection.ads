private package Lua.Engine.Inspection is
   function Short_Source (Source : String) return String;
   --  Format the pinned bounded Lua chunk identifier used by debug metadata
   --  and error prefixes. The result owns at most 59 display bytes.
   function Visible_Local_Top
     (Context : not null Context_Access; Item : not null Frame_Access)
      return Natural
     with Pre => Item.Context = Context;
   --  Return the actual visible local/temporary register count. A caller's
   --  temporaries stop before its child's function slot; the collector's
   --  rooted extent intentionally includes that slot. This allocation-free
   --  query borrows the addressed context's active physical-window chain.

   function Logical_Frame
     (State : in out World; Context : not null Context_Access; Level : Natural)
      return Frame_Access;
   --  Borrow an actual public frame, excluding scheduler transport and
   --  owners already unwound to protection/the base but retained for closing
   --  cells. Normal scope/return owners retain their actual source frames.
   --  Lua and C inspection share this allocation-free, budgeted traversal.

   function Caller_Frame
     (State : in out World; Context : not null Context_Access;
      Callee : not null Frame_Access) return Frame_Access
     with Pre => Callee.Context = Context;
   --  Borrow the public caller of this validated active frame. Unwound
   --  ownership records cannot contribute a misleading source call name.

   function Inspect
     (State : in out World; Activation : Frame_Access;
      Target_Frame : Frame_Access := null) return Values.Vector;
   --  Implement synchronous debug queries over owned logical activations.
   --  Returned identities refer to real stable cells, never movable vectors.
   --  A C debug query may provide its already-validated active frame instead
   --  of resolving a Lua stack level. The caller must establish membership
   --  in the addressed context before passing Target_Frame; it is borrowed
   --  for this synchronous operation and never becomes a new activation.
end Lua.Engine.Inspection;
