with AUnit.Test_Suites;

package Return_Hook_Mutation_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Actual result edits, weak lifetime, protected status and close order.
end Return_Hook_Mutation_Tests;
