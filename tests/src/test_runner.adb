with Ada.Command_Line;
with AUnit.Reporter.Text;
with AUnit.Run;
with AUnit.Test_Suites;
with Integer_Tests;
with Lexer_Tests;
with Number_Tests;
with Session_Tests;
with Lifecycle_Tests;

procedure Test_Runner is
   use type AUnit.Status;
   function Suite return AUnit.Test_Suites.Access_Test_Suite;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        new AUnit.Test_Suites.Test_Suite;
   begin
      --  Each registered procedure is a separate AUnit case, so one failing
      --  boundary does not hide the results of unrelated behavior checks.
      Integer_Tests.Register (Result);
      Lexer_Tests.Register (Result);
      Number_Tests.Register (Result);
      Session_Tests.Register (Result);
      Lifecycle_Tests.Register (Result);
      return Result;
   end Suite;

   function Run is new AUnit.Run.Test_Runner_With_Status (Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
begin
   if Run (Reporter) /= AUnit.Success then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Runner;
