with AUnit.Test_Suites;

package Lua.Call_Metadata_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Actual frame capacity, transactional reservations and C guard lifetime
   --  under provider refusal, shrinking and uncatchable embedding stops.
end Lua.Call_Metadata_Tests;
