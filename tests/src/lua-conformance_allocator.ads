with Lua.Storage;

private package Lua.Conformance_Allocator is
   procedure Attach (Memory : not null Lua.Storage.Owner_Access);
   --  Interpose on the actual provider of the test launcher's one universe.
   --  Existing raw blocks are counted before interposition and remain owned
   --  by the original provider. No interpreter allocations are substituted.
   procedure Finish;
   --  Verify physical cleanup and optionally write a PID-specific sidecar.
   --  Call only after session disposal. Idempotent, including after failure;
   --  it never dereferences the expired owner. Test executable only.
end Lua.Conformance_Allocator;
