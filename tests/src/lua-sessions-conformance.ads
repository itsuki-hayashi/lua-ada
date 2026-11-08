package Lua.Sessions.Conformance is
   procedure Print_Configuration;
   --  Initialize/configure a real session and report its measured ABI,
   --  installed adapter, selected behavior and independent allocation limit.
   procedure Configure (Universe : in out Session);
   --  Test executable only: install the actual adapter in upstream-test
   --  builds and enforce the independent managed allocation ceiling. The
   --  optional LUA_ADA_CONFORMANCE_ALLOCATOR selects exactly67108864 (heavy)
   --  or2147483648 (ordinary/default); another value rejects configuration.
   procedure Finish;
   --  Verify provider balance and emit requested telemetry after disposal.
end Lua.Sessions.Conformance;
