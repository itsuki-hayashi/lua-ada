with Lua.Engine;

private package Lua.Conformance_Adapter is
   procedure Install_Platform (State : in out Lua.Engine.World);
   --  Install native counterpart drivers in the test launcher, including its
   --  T-absent configuration. No counterpart is an unchanged execution.
   function Has_Failing_Stream return Boolean;
   --  Whether this host provides a native buffered failure counterpart.
   function Has_Nonblocking_Pair return Boolean;
   --  Whether this host provides the Windows native pipe-pair driver.
   procedure Install (State : in out Lua.Engine.World);
   --  Install supported T operations into this test-owned universe. C
   --  callbacks borrow State until destruction; never install on a copy.
   --  No adapter code is linked into the production library.
   procedure Verify_Collector_Lists (State : Lua.Engine.World);
   --  Allocation-free inspection of registry, generation, gray and remembered
   --  ownership. Raises Program_Error on corruption; never repairs evidence.
   procedure Verify_Table_Storage
     (State : Lua.Engine.World; Item : Lua.Engine.Value;
      Member_Rows, Live_Entries : out Natural);
   --  Inspect actual member/index/free-list ownership without allocating,
   --  collecting or repairing. Validate heap membership and value tags before
   --  dereferencing keys. Return retained rows and nonnil values, not C table
   --  geometry. Raise Program_Error on corruption; indexed tombstones and
   --  revived live free-listed rows are legitimate retained storage.
   --  Counts are valid only on successful return. Bounded repeated walks
   --  avoid input-sized scratch storage in this test-only inspector.
end Lua.Conformance_Adapter;
