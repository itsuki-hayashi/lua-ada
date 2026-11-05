with Ada.Command_Line;
with AUnit.Reporter.Text;
with AUnit.Run;
with AUnit.Test_Caller;
with AUnit.Test_Suites;
with Lexer_Tests;
with Integer_Tests;

procedure Test_Runner is
   use type AUnit.Status;
   package Cases is new AUnit.Test_Caller (Lexer_Tests.Fixture);
   package Integer_Cases is new AUnit.Test_Caller (Integer_Tests.Fixture);

   function Suite return AUnit.Test_Suites.Access_Test_Suite;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        new AUnit.Test_Suites.Test_Suite;
   begin
      Result.Add_Test
        (Integer_Cases.Create ("integer wrapping",
                               Integer_Tests.Wrapping'Access));
      Result.Add_Test
        (Integer_Cases.Create ("division and shifts",
                               Integer_Tests.Division_And_Shifts'Access));
      Result.Add_Test
        (Cases.Create ("keywords and operators",
                       Lexer_Tests.Keywords_And_Operators'Access));
      Result.Add_Test
        (Cases.Create ("strings and locations",
                       Lexer_Tests.Strings_And_Locations'Access));
      Result.Add_Test
        (Cases.Create ("invalid source and budgets",
                       Lexer_Tests.Rejected_Input'Access));
      Result.Add_Test
        (Cases.Create ("arbitrary source bytes",
                       Lexer_Tests.Arbitrary_Bytes'Access));
      return Result;
   end Suite;

   function Run is new AUnit.Run.Test_Runner_With_Status (Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
begin
   if Run (Reporter) /= AUnit.Success then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Runner;
