with AUnit.Test_Suites;

package Lua.Managed_Runtime_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register runtime allocator, payload lifetime and compaction cases.
end Lua.Managed_Runtime_Tests;
