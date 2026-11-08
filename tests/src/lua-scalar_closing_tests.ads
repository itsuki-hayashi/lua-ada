with AUnit.Test_Suites;

package Lua.Scalar_Closing_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Real scalar closing slots, refusal recovery, detached captures,
   --  debugger mutation and suspended/generic-for scope ownership.
end Lua.Scalar_Closing_Tests;
