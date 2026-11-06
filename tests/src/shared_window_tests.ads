with AUnit.Test_Suites;

package Shared_Window_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register observable regressions for overlapping Lua/native windows,
   --  precise protected prefixes, native tails and vararg preparation.
end Shared_Window_Tests;
