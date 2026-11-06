with Lua.Conformance_Adapter;
with Lua.Runtime_Configuration;
with Lua.Storage;
with Lua.Conformance_Allocator;

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
      Lua.Conformance_Allocator.Attach
        (Lua.Storage.Reference (Universe.State.Memory));
      Lua.Conformance_Adapter.Install_Platform (Universe.State.all);
      Install (Lua.Runtime_Configuration.Name);
   end Configure;

   procedure Finish is
   begin
      Lua.Conformance_Allocator.Finish;
   end Finish;
end Lua.Sessions.Conformance;
