with Lua.Conformance_Adapter;
with Ada.Text_IO;
with Interfaces.C;
with Lua.Engine;
with Lua.Storage.Conformance;
with System;
with Lua.Runtime_Configuration;
with Lua.Storage;
with Lua.Conformance_Allocator;

package body Lua.Sessions.Conformance is
   procedure Print_Configuration is
      use type Lua.Engine.Value_Kind;
      function Extra_Space return Interfaces.C.size_t
        with Import, Convention => C, External_Name => "lua_ada_extra_space";
      function Flag (Item : Boolean) return String is
        (if Item then "true" else "false");
   begin
      declare
         Universe : Session;
         Adapter : Lua.Engine.Value;
      begin
         Configure (Universe);
         Adapter := Lua.Engine.Get
           (Lua.Engine.Global_Environment (Universe.State.all),
            Lua.Engine.New_String (Universe.State.all, "T"));
         Ada.Text_IO.Put_Line
           ("{""schema_version"":1,""implementation"":""Lua Ada""," &
            """lua_release"":""Lua 5.5.1"",""configuration"":""" &
            Lua.Runtime_Configuration.Name & """,""test_adapter"":" &
            Flag (Adapter.Kind = Lua.Engine.Table_Kind) &
            ",""integer_bytes"":" &
            Natural'Image (Lua.Engine.Integer_Value'Size / 8) &
            ",""number_bytes"":" &
            Natural'Image (Lua.Engine.Real_Value'Size / 8) &
            ",""pointer_bytes"":" & Natural'Image (System.Address'Size / 8) &
            ",""extra_space_bytes"":" & Extra_Space'Image &
            ",""expected_extra_space_bytes"":" &
            Natural'Image (System.Address'Size / 8) &
            ",""max_stack"":" &
            Positive'Image (Lua.Runtime_Configuration.Maximum_Stack) &
            ",""max_c_calls"":" &
            Positive'Image (Lua.Runtime_Configuration.Maximum_C_Calls) &
            ",""aux_buffer_bytes"":" &
            Positive'Image (Lua.Runtime_Configuration.Auxiliary_Buffer_Bytes) &
            ",""compat_global"":" &
            Boolean'Pos (Lua.Runtime_Configuration.Compatible_Global)'Image &
            ",""rand32"":" & Flag (Universe.State.Random_Use_32_Bits) &
            ",""compat_math"":" & Flag (Universe.State.Math_Compatibility) &
            ",""allocator_accounting"":""managed-provider-raw-bytes""," &
            """allocator_limit_bytes"":" &
            Lua.Storage.Conformance.Allocation_Ceiling
              (Universe.State.Memory)'Image & "}");
         Universe.Close;
      end;
      Finish;
   end Print_Configuration;

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
