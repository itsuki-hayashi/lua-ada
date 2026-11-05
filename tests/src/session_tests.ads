with AUnit.Test_Suites;

package Session_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register one case per independently observable Lua/session behavior.
end Session_Tests;
