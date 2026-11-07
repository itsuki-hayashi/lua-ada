with Interfaces.C;
with Lua.Storage;

package Lua.Engine.Garbage_Collection is
   function Control
     (State : in out World; Operation : Interfaces.C.int;
      Step_Bytes : Lua.Storage.Byte_Count := 0;
      Parameter : Interfaces.C.int := 0;
      Setting : Interfaces.C.int := Interfaces.C.int'Pred (0);
      Drain : out Boolean) return Interfaces.C.int;
   --  Shared allocation-free control interface using pinned lua_gc codes.
   --  Collection itself may reclaim storage but never invokes Lua here.
   --  Drain requests a separate scheduler opportunity for queued finalizers.
   --  Unknown operations return -1; invalid parameter indices are API errors.

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
