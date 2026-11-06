with AUnit.Test_Suites;

package Lua.Table_Reservation_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Real allocation, capacity reuse and atomic-failure invariants.
end Lua.Table_Reservation_Tests;
