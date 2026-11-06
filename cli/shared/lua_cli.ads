with Lua.Sessions;

generic
   with procedure Configure (Universe : in out Lua.Sessions.Session);
procedure Lua_CLI;
--  Shared process driver. Configure runs after selecting process streams
--  and before publishing arguments or executing source. Production supplies
--  a null hook; the test launcher installs its own adapter and limits.
