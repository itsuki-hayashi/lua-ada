with AUnit.Test_Suites;

package Lua.Userdata_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register payload ownership, uservalue/metatable tracing, stable
   --  identity, collection cycles and first-party cleanup boundary cases.
end Lua.Userdata_Tests;
