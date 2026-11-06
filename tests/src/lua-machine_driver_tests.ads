with AUnit.Test_Suites;

package Lua.Machine_Driver_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register incremental progress, packet rooting, quota, ownership and
   --  misuse-boundary cases for the explicit internal VM driver.
end Lua.Machine_Driver_Tests;
