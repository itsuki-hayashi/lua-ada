with AUnit.Test_Suites;

package Lua.Foreign_Hook_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register focused public-C hook and active-frame lifetime regressions.
end Lua.Foreign_Hook_Tests;
