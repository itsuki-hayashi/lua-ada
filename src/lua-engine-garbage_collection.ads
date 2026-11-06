package Lua.Engine.Garbage_Collection is
   procedure Advance
     (State : in out World; Activation : Frame_Access;
      Result : out Native_Action);
   --  Implement Lua5.5 collectgarbage controls over the real collector.
   --  Count uses actual selected-provider raw bytes. A manual step performs
   --  marking/sweeping even while automatic collection is user-stopped.
   --  Pending finalizers request scheduler drainage through a typed action;
   --  this driver never invokes Lua or recursively enters an executor.
   --  Results are moved into caller-owned storage: returning a controlled
   --  packet by value would allocate even after deliberately deferred GC.
end Lua.Engine.Garbage_Collection;
