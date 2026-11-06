package Lua.Engine.Finalizers is
   --  Intrusive ownership for real Lua table/userdata finalization. This
   --  package never allocates, invokes a handler, or recursively collects.
   --  The scheduler owns call protection, warnings and hook/yield policy.

   procedure Register (State : in out World; Item : Value);
   --  Enroll once when a metatable containing a nonnil raw __gc is assigned.
   --  Removal/replacement of that field does not cancel enrollment. Handler
   --  lookup happens at invocation time, as in pinned luaC_checkfinalizer.

   procedure Queue_Unreachable
     (State : in out World;
      Is_Unreachable : not null access function
        (Item : Object_Access) return Boolean;
      All_Objects : Boolean := False);
   --  Transfer unreachable registrations to the pending queue in reverse
   --  enrollment order, appending after any previously pending objects.
   --  Call after clearing initially dead weak values and before remarking
   --  pending finalizable graphs. Emergency cycles can queue, never execute.
   --  All_Objects is the explicit state-close path; registration is disabled
   --  by its caller before running any state-close callback.

   function Has_Pending (State : World) return Boolean;
   procedure Begin_Next (State : in out World);
   --  Move the next queued object into the rooted current slot and read its
   --  actual current __gc. Clear enrollment before calling, so a callback may
   --  deliberately re-enroll it by assigning another metatable. The caller
   --  must finish or abandon the current finalizer before beginning another.
   function Current_Target (State : World) return Value;
   function Current_Handler (State : World) return Value;
   procedure Finish_Current (State : in out World);
   --  Release only the current roots. Never overwrite a callback's renewed
   --  enrollment or its intrusive link. Host aborts abandon the callback;
   --  this operation itself does not execute Lua cleanup.

   procedure Abandon_Current (State : in out World);
   --  A host abort cannot execute a Lua destructor. Remember that disposition
   --  on attached owned userdata, then release current roots. Native disposal
   --  occurs only when the object really dies, preserving resurrected aliases.

   procedure Trace_Roots
     (State : World;
      Mark : not null access procedure (Item : Object_Access));
   --  Pending/current objects are roots. Merely registered objects are not:
   --  their otherwise unreachable graphs must reach finalization normally.
end Lua.Engine.Finalizers;
