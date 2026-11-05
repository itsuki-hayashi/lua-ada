with AUnit.Test_Fixtures;

package Integer_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Wrapping (Self : in out Fixture);
   --  Arithmetic at signed representation boundaries.

   procedure Division_And_Shifts (Self : in out Fixture);
   --  Floor/sign rules, zero failures, and extreme shift counts.
end Integer_Tests;
