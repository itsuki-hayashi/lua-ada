with AUnit.Test_Suites;

package Lua.GC_Control_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register real Lua GC controls, scheduled finalization and recovery.
end Lua.GC_Control_Tests;
