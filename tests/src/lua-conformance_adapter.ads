with Lua.Engine;

private package Lua.Conformance_Adapter is
   procedure Install (State : in out Lua.Engine.World);
   --  Install supported T operations into this test-owned universe. C
   --  callbacks borrow State until destruction; never install on a copy.
   --  No adapter code is linked into the production library.
   procedure Verify_Collector_Lists (State : Lua.Engine.World);
   --  Allocation-free inspection of registry, generation, gray and remembered
   --  ownership. Raises Program_Error on corruption; never repairs evidence.
end Lua.Conformance_Adapter;
