with AUnit.Test_Suites;

package Lua.Sessions.CLI_Interrupt_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register real SIGINT, protected recovery, hook/closing/targeting and
   --  disposition-lifetime checks as separately named CLI regressions.
end Lua.Sessions.CLI_Interrupt_Tests;
