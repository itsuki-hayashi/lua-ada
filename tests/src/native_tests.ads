with AUnit.Test_Suites;

package Native_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Focused public-session regressions for native callback continuations
   --  and core metamethod dispatch. Tests expose no private object handles.
end Native_Tests;
