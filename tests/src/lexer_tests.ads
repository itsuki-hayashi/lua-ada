with AUnit.Test_Fixtures;

package Lexer_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;
   --  Stateless cases; every scan owns its complete result.

   procedure Keywords_And_Operators (Self : in out Fixture);
   --  Exercise Lua 5.5 keywords and maximal-munch punctuation.

   procedure Strings_And_Locations (Self : in out Fixture);
   --  Exercise decoded byte strings and newline normalization.

   procedure Rejected_Input (Self : in out Fixture);
   --  Invalid escapes, unfinished input, token budgets, and recovery.

   procedure Arbitrary_Bytes (Self : in out Fixture);
   --  Arbitrary source bytes must not escape as unchecked scanner failures.
end Lexer_Tests;
