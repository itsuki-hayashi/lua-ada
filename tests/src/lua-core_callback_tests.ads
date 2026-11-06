with AUnit.Test_Suites;

package Lua.Core_Callback_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register focused comparison, pairs, arithmetic and callback-lifetime
   --  regressions. Each case uses a fresh independently owned Lua session.
end Lua.Core_Callback_Tests;

