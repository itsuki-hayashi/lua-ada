with AUnit.Test_Suites;

package OS_Runtime_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register focused native-time, table-callback, locale and process cases.
   --  Process exit has a separate typed-result/child-process acceptance owner.
end OS_Runtime_Tests;
