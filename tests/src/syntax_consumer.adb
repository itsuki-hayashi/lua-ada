with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Lua.Syntax;
with Lua.Sessions;

procedure Syntax_Consumer is
   --  A real Ada host links the public checker and persistent session API.
   --  The same executable is exercised against static/shared library builds.
   use type Lua.Syntax.Check_Status;
   use type Lua.Sessions.Execution_Status;
   Session : Lua.Sessions.Session;
   Setup : constant Lua.Sessions.Execution_Result :=
     Session.Execute ("answer = 41");
   Checked : constant Lua.Syntax.Check_Result :=
     Lua.Syntax.Check ("answer = 99; local x<close>; ::done::");
   Output : constant Lua.Sessions.Execution_Result :=
     Session.Execute ("print(answer + 1)");
begin
   --  Checking accepts deferred syntax without mutating the host's universe.
   --  Captured output verifies both persistence and subsequent execution.
   if Setup.Status /= Lua.Sessions.Succeeded or else
     Checked.Status /= Lua.Syntax.Success or else
     Output.Status /= Lua.Sessions.Succeeded or else
     Output.Output /= "42" & Character'Val (10)
   then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      Ada.Text_IO.Put_Line ("FAIL: Ada syntax/session consumer");
   else
      Ada.Text_IO.Put_Line ("PASS: Ada syntax/session consumer");
   end if;
end Syntax_Consumer;
