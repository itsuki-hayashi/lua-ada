with Lua.Conformance_Adapter;
with Ada.Text_IO;
with Ada.Characters.Handling;
with Ada.Environment_Variables;
with Interfaces.C;
with Interfaces.C.Strings;
with Lua_Ada_Config;
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
      --  These test-only C strings have static lifetime. The launcher GPR
      --  records its own profile and link mode; the runtime profile below
      --  comes from the separately built library's generated configuration.
      --  Keeping both measurements catches mismatched dependency builds.
      function Build_Profile return Interfaces.C.Strings.chars_ptr
        with Import, Convention => C,
             External_Name => "lua_ada_test_build_profile";
      function Link_Kind return Interfaces.C.Strings.chars_ptr
        with Import, Convention => C,
             External_Name => "lua_ada_test_link_kind";
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
            ",""runtime_build_profile"":""" &
            Ada.Characters.Handling.To_Lower
              (Lua_Ada_Config.Build_Profile'Image) &
            """,""launcher_build_profile"":""" &
            Interfaces.C.Strings.Value (Build_Profile) &
            """,""launcher_library_type"":""" &
            Interfaces.C.Strings.Value (Link_Kind) & """" &
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
      function Requested_Ceiling return Lua.Storage.Byte_Count;
      function Requested_Ceiling return Lua.Storage.Byte_Count is
      begin
         --  This is the test process's independently enforced host ceiling,
         --  not T.totalmem's reversible fault-injection limit. Accept only
         --  the two canonical decimal limits in the acceptance contract;
         --  malformed/unsupported configuration must not silently use2GiB.
         if not Ada.Environment_Variables.Exists
           ("LUA_ADA_CONFORMANCE_ALLOCATOR")
         then
            return 2_147_483_648;
         end if;
         declare
            Text : constant String := Ada.Environment_Variables.Value
              ("LUA_ADA_CONFORMANCE_ALLOCATOR");
         begin
            if Text = "2147483648" then
               return 2_147_483_648;
            elsif Text = "67108864" then
               return 67_108_864;
            end if;
         end;
         raise Program_Error with "invalid conformance allocator ceiling";
      end Requested_Ceiling;

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
      Lua.Storage.Set_Ceiling (Universe.State.Memory, Requested_Ceiling);
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
