package Lua.Sessions.Conformance is
   procedure Configure (Universe : in out Session);
   --  Test executable only: install the actual adapter in upstream-test
   --  builds and enforce the independent managed allocation ceiling.
end Lua.Sessions.Conformance;
