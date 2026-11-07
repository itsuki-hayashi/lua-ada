package Lua.Engine.External_Releases is
   procedure Enqueue
     (State : in out World; Item : not null Object_Access);
   --  Transfer the existing header into an intrusive pending-release queue.
   --  No allocation, callback or payload read occurs here. Requeue is inert.
   function Pending (State : World) return Boolean;
   procedure Prepare_Close (State : in out World);
   --  Queue all owned external payloads while globals/contexts remain live.
   --  Registered close headers remain GC roots until physical finalization.
   function Begin_Callback (State : in out World) return Object_Access;
   --  Pop one pending header, borrow the actual stack window and push a LIFO
   --  active-release record. Caller invokes its C allocator after Ada returns.
   procedure Complete
     (State : in out World; Token : Callback_Identity);
   --  Restore the borrowed view, clear callback ownership, and release only
   --  an actually detached header. Token rejects stale/nested acknowledgments.
end Lua.Engine.External_Releases;
