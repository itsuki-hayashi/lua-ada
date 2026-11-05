with AUnit.Test_Suites;

package Test_Support is
   type Test_Action is access procedure;
   --  Each action is one independently named behavior, not a hidden suite.

   procedure Add
     (Suite : AUnit.Test_Suites.Access_Test_Suite;
      Title : String; Action : Test_Action);
   --  Register an ordinary library-level procedure as one AUnit test case.
   --  @param Suite Suite which takes ownership of the allocated case.
   --  @param Title Human-readable behavior reported in test output.
   --  @param Action Procedure containing the test's setup/action/assertions.
end Test_Support;
