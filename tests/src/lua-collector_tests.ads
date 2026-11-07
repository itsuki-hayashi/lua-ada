with AUnit.Test_Suites;

package Lua.Collector_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register incremental, generational, barrier and weak/finalizer cases.
end Lua.Collector_Tests;
