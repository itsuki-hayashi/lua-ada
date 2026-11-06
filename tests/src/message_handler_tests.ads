with AUnit.Test_Suites;

package Message_Handler_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register message-handler timing, recursive transformation, dynamic
   --  protection, closing, collection and resource-boundary regressions.
end Message_Handler_Tests;
