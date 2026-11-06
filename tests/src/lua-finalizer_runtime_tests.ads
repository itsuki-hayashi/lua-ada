with AUnit.Test_Suites;

package Lua.Finalizer_Runtime_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Actual queued Lua callbacks, protection, roots and scheduler policies.
end Lua.Finalizer_Runtime_Tests;
