with AUnit.Test_Suites;

package Lua.Runtime_Vector_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register explicit owners, packet lifetime and GC workspace regressions.
end Lua.Runtime_Vector_Tests;
