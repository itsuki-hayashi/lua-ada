with AUnit.Test_Suites;

package Lua.Stack_Inspection_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Test-only inspection of actual Ada stack and activation ownership.
end Lua.Stack_Inspection_Tests;
