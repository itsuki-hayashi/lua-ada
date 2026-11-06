with AUnit.Test_Suites;

package Lua.Stack_Storage_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Exercise physical arena ownership, real captures, refusal recovery and
   --  collector unions independently of opcode allocation decisions.
end Lua.Stack_Storage_Tests;
