with Lua.Engine.Call_Names;

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

   function Call_Identity
     (State : in out World; Context : not null Context_Access;
      Callee : Frame_Access) return Call_Names.Borrowed_Identity
     with Pre => Callee = null or else Callee.Context = Context;
   --  Borrow an actual activation's explicit or inferred public call origin.
   --  Hook/finalizer priority and tail-call loss follow getinfo semantics;
   --  no Lua objects are allocated. Retain the frame/prototype while using
   --  the immutable name bytes; Name_Image supplies rendered C text.

   function Traceback
     (State : in out World; Context : not null Context_Access;
      Message : Value; Start_Level : Integer_Value) return Value;
   --  Render the addressed context's actual logical frames. All temporary
   --  storage and the returned Lua string belong to State's selected owner.
   --  Context and Message are borrowed during this synchronous operation;
   --  retain their owners throughout. A nil message omits the prefix and
   --  a negative C-int level produces only the prefix and traceback heading.
   --  Lua integer levels undergo the pinned wrapper's explicit C-int cast.
   function Traceback
     (State : in out World; Context : not null Context_Access;
      Message : Byte_String; Has_Message : Boolean;
      Start_Level : Integer_Value) return Value;
   --  Borrow an already measured C message, without an intermediate Lua
   --  string or unmanaged copy. Its bytes must survive this callback-free
   --  query; a zero-length nonnull message still contributes a newline.

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
