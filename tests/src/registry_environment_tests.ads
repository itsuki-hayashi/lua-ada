with AUnit.Test_Suites;

package Registry_Environment_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Real registry ownership and independent initial environment bindings.
end Registry_Environment_Tests;
