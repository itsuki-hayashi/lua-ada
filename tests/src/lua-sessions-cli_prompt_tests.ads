with AUnit.Test_Suites;

package Lua.Sessions.CLI_Prompt_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register separately named prompt value, callback, policy and ownership
   --  regressions. The CLI-only child is exercised on the actual session.
end Lua.Sessions.CLI_Prompt_Tests;
