with AUnit.Test_Suites;

package Lifecycle_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Host ownership, resource boundaries, collection, and recovery cases.
end Lifecycle_Tests;
