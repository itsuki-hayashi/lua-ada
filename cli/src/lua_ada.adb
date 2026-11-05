with Ada.Command_Line;
with Ada.Text_IO;
with Lua;

procedure Lua_Ada is
   use Ada.Command_Line;
begin
   if Argument_Count = 1 and then Argument (1) = "--version" then
      Ada.Text_IO.Put_Line
        ("Lua Ada " & Lua.Implementation_Version &
         " (target " & Lua.Reference_Release & ")");
   elsif Argument_Count = 0 or else
     (Argument_Count = 1 and then Argument (1) = "--help")
   then
      Ada.Text_IO.Put_Line ("Usage: lua_ada [--help | --version]");
      Ada.Text_IO.Put_Line ("Script execution is not implemented yet.");
   else
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "lua_ada: script execution is not implemented yet");
      Set_Exit_Status (Failure);
   end if;
end Lua_Ada;
