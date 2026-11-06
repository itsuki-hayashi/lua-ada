with AUnit.Test_Suites;

package Lua.Chunk_Tests is
   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite);
   --  Standalone canonical model/codec tests, independent of VM execution.
end Lua.Chunk_Tests;
