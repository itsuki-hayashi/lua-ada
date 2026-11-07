with AUnit.Test_Suites;

package Lua.IO_Abort_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register actual descriptor-lifetime checks around host quota aborts
   --  and ordinary finalizer failures. This requires the test-only C witness.
end Lua.IO_Abort_Tests;
