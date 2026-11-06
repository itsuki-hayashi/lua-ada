with AUnit.Test_Suites;

package Lua.Stack_Policy_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register exact inclusive-bound, overflow/error-stack, nonthrowing API
   --  growth and protected-recovery latch cases for the shared scalar stack.
end Lua.Stack_Policy_Tests;
