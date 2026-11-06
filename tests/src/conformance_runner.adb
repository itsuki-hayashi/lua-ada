with Lua.Sessions.Conformance;
with Ada.Command_Line;
with Lua_CLI;

procedure Conformance_Runner is
   procedure Run is new Lua_CLI
     (Lua.Sessions.Conformance.Configure, Lua.Sessions.Conformance.Finish);
begin
   if Ada.Command_Line.Argument_Count = 1 and then
     Ada.Command_Line.Argument (1) = "--conformance-config"
   then
      Lua.Sessions.Conformance.Print_Configuration;
   else
      Run;
   end if;
end Conformance_Runner;
