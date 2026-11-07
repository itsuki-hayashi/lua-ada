package Lua.Engine.Operating_System is
   function Open_Module (State : in out World) return Value;
   --  Return a pinned, freshly created os export table. Publication into
   --  globals or the loaded-module registry belongs to the caller.

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action;
   --  Execute the standard os exports. os.time table gets/sets use explicit
   --  native continuations; the VM must mark this operation nonyieldable.
   --  @param State Owning interpreter, execution budget and exit transfer.
   --  @param Activation Traced arguments, normalized date fields and phase.
   --  @return Completed values or one VM callback request; never a recursive
   --  execution. os.exit requests the approved explicit process-exit transfer.
end Lua.Engine.Operating_System;
