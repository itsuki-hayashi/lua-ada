with Lua.Sessions;
with Lua_CLI;

procedure Lua_Ada is
   procedure Configure (Universe : in out Lua.Sessions.Session);
   procedure Configure (Universe : in out Lua.Sessions.Session) is
      pragma Unreferenced (Universe);
   begin
      null;
   end Configure;
   procedure Run is new Lua_CLI (Configure);
begin
   Run;
end Lua_Ada;
