package Lua.Sessions.Conformance is
   procedure Configure (Universe : in out Session);
   --  Test executable only: install the actual adapter in upstream-test
   --  builds and enforce the independent managed allocation ceiling.
   procedure Finish;
   --  Verify provider balance and emit requested telemetry after disposal.
end Lua.Sessions.Conformance;
