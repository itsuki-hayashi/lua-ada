with AUnit.Test_Suites;

package Binary_Runtime_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Exercise real native chunk loading/dumping through the public session
   --  API, including source identity, environments, malformed input and GC.
end Binary_Runtime_Tests;
