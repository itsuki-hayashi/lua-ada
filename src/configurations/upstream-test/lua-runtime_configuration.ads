private package Lua.Runtime_Configuration is
   Name : constant String := "upstream-test";
   Compatible_Global : constant Boolean := False;
   Compatibility_Math : constant Boolean := True;
   Random_32_Bits : constant Boolean := True;
   Maximum_Stack : constant Positive := 68_000;
   Maximum_C_Calls : constant Positive := 180;
   Auxiliary_Buffer_Bytes : constant Positive := 23;
   --  Pinned ltests.h deliberately exercises tiny auxiliary buffer growth.
   --  Match the pinned ltests.h build's selected semantic constants. This
   --  does not itself install T, emulate C internals or certify the adapter.
end Lua.Runtime_Configuration;
