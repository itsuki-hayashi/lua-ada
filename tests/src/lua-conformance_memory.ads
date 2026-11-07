with Lua.Engine;

private package Lua.Conformance_Memory is
   procedure Verify (State : Lua.Engine.World);
   --  Inspect real heap edges, code ownership, finalizer queues and live
   --  activation roots without collecting, allocating or repairing state.
   --  Raises Program_Error for inconsistent ownership or dangling edges.
end Lua.Conformance_Memory;
