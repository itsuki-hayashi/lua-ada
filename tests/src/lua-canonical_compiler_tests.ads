with AUnit.Test_Suites;

package Lua.Canonical_Compiler_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Owned lowering contracts; separate C execution supplies semantic parity.
end Lua.Canonical_Compiler_Tests;
