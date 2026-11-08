with AUnit.Test_Suites;

package Lua.Sessions.CLI_Argument_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register selected-script values, callbacks, ordering, lifetime, exit
   --  and actual refusal/recovery as separately named session regressions.
end Lua.Sessions.CLI_Argument_Tests;
