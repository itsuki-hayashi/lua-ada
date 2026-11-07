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
