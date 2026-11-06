with AUnit.Test_Suites;

package Lua.Output_Policy_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Register focused capture, delivery, quota and callback-order cases.
   --  Actual process stdout bytes are checked by the separate API consumer.
end Lua.Output_Policy_Tests;
