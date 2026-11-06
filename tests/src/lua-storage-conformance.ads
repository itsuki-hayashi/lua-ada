package Lua.Storage.Conformance is
   procedure Verify (Self : Owner);
   --  Test-only inspection of actual allocator headers, backlinks, alignment
   --  and live accounting. Does not allocate, free or change fault controls.
end Lua.Storage.Conformance;
