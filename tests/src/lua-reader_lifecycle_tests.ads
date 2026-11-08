with AUnit.Test_Suites;

package Lua.Reader_Lifecycle_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register separately named real C reader self-close cleanup cases.
end Lua.Reader_Lifecycle_Tests;
