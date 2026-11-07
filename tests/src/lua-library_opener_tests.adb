with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Test_Support;

package body Lua.Library_Opener_Tests is
   use type Interfaces.C.int;

   function Contract (Which : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_library_opener_contract";

   procedure Debug_Module;
   procedure String_Module;
   procedure Table_Module;
   procedure UTF8_Module;

   procedure Debug_Module is
   begin
      --  Open only debug in a bare C state. Require one returned table,
      --  no implicit global publication and a call exposing its real registry.
      Assert (Contract (1) = 0, "direct debug module is functional");
   end Debug_Module;

   procedure String_Module is
   begin
      --  The direct string opener must support embedded-zero slicing and
      --  install a type metatable indexing that exact returned module table.
      Assert (Contract (2) = 0, "direct string module is functional");
   end String_Module;

   procedure Table_Module is
   begin
      --  Calling the returned pack export must preserve an actual nil hole
      --  and explicit argument count while leaving the table global absent.
      Assert (Contract (3) = 0, "direct table module is functional");
   end Table_Module;

   procedure UTF8_Module is
   begin
      --  The utf8 constructor alone exposes a working decoder in a bare
      --  state, without opening any base/string globals as a side effect.
      Assert (Contract (4) = 0, "direct UTF8 module is functional");
   end UTF8_Module;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "C openers: debug returns actual registry",
                        Debug_Module'Access);
      Test_Support.Add (Suite, "C openers: string bytes and type metatable",
                        String_Module'Access);
      Test_Support.Add (Suite, "C openers: table pack preserves nil holes",
                        Table_Module'Access);
      Test_Support.Add (Suite, "C openers: UTF8 decodes actual bytes",
                        UTF8_Module'Access);
   end Register;
end Lua.Library_Opener_Tests;
