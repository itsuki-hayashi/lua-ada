with Lua.Conformance_Adapter;
with Lua.Runtime_Configuration;
with Lua.Storage;

package body Lua.Sessions.Conformance is
   procedure Configure (Universe : in out Session) is
      procedure Install (Configuration : String);
      procedure Install (Configuration : String) is
      begin
         if Configuration = "upstream-test" then
            Lua.Conformance_Adapter.Install (Universe.State.all);
            declare
               Result : constant Execution_Result := Universe.Execute
                 ("T._installwarning(); T._installwarning=nil",
                  "(test warning setup)");
            begin
               if Result.Status /= Succeeded then
                  raise Program_Error with "test warning installation failed";
               end if;
            end;
         end if;
      end Install;
   begin
      Lua.Storage.Set_Ceiling (Universe.State.Memory, 2_147_483_648);
      Install (Lua.Runtime_Configuration.Name);
   end Configure;
end Lua.Sessions.Conformance;
