with AUnit.Test_Suites;

package Lua.Canonical_Runtime_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register actual canonical-word execution through the shared iterative
   --  scheduler, including callbacks, cells, closing and controlled failures.
end Lua.Canonical_Runtime_Tests;
