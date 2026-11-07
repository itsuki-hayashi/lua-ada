with AUnit.Test_Suites;

package IO_Runtime_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register independent file, iterator, formatting, failure and ownership
   --  behaviors. Native host probes are separate from these actual Lua cases.
end IO_Runtime_Tests;
