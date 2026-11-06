with AUnit.Test_Suites;

package Lua.Frame_Cache_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Exercise activation identity, ownership, retained capacity and root
   --  removal independently of VM argument/result transport.
end Lua.Frame_Cache_Tests;
