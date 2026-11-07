with AUnit.Test_Suites;

package Hook_Registry_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register actual weak registry, callback and inheritance regressions.
end Hook_Registry_Tests;
