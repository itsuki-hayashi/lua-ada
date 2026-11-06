with Lua.Sessions;

generic
   with procedure Configure (Universe : in out Lua.Sessions.Session);
   with procedure Finish is null;
procedure Lua_CLI;
--  Shared process driver. Configure runs after selecting process streams
--  and before publishing arguments or executing source. Production supplies
--  a null hook; the test launcher installs its own adapter and limits.
--  Finish runs after physical session disposal, before honoring a typed exit.
--  Test launchers can verify allocator balance without observing freed state.
