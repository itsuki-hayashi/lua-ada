package Lua.Storage.Conformance is
   function Allocation_Ceiling (Self : Owner) return Byte_Count;
   --  Inspect the actual independent managed ceiling for launcher handshakes.
   procedure Verify (Self : Owner);
   --  Test-only inspection of actual allocator headers, backlinks, alignment
   --  and live accounting. Does not allocate, free or change fault controls.
end Lua.Storage.Conformance;
