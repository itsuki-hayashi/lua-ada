with AUnit.Test_Suites;

package Lua.Collector_Stack_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Atomic stack rescans retain real roots without eagerly rescuing dead
   --  scalar temporaries during incremental propagation.
end Lua.Collector_Stack_Tests;
