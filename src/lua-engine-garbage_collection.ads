package Lua.Engine.Garbage_Collection is
   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action;
   --  Implement Lua5.5 collectgarbage controls over the real collector.
   --  Count uses actual selected-provider raw bytes. A manual step performs
   --  marking/sweeping even while automatic collection is user-stopped.
   --  Pending finalizers request scheduler drainage through a typed action;
   --  this driver never invokes Lua or recursively enters an executor.
end Lua.Engine.Garbage_Collection;
