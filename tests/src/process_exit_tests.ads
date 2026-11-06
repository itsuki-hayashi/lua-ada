with AUnit.Test_Suites;

package Process_Exit_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Exercise typed process requests without terminating the Ada test host.
end Process_Exit_Tests;
