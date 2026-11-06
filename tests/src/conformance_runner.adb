with Lua.Sessions.Conformance;
with Lua_CLI;

procedure Conformance_Runner is
   procedure Run is new Lua_CLI (Lua.Sessions.Conformance.Configure);
begin
   Run;
end Conformance_Runner;
