with AUnit.Test_Suites;

package Lua.Condition_Root_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Consumed statement guards release temporaries while actual expression
   --  results and closing locals retain their required ownership.
end Lua.Condition_Root_Tests;
