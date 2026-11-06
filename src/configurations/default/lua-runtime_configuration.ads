private package Lua.Runtime_Configuration is
   Name : constant String := "default";
   Compatible_Global : constant Boolean := True;
   Compatibility_Math : constant Boolean := False;
   Random_32_Bits : constant Boolean := False;
   Maximum_Stack : constant Positive := 1_000_000;
   Maximum_C_Calls : constant Positive := 200;
   --  Pinned ordinary Lua 5.5.1 build policy. These are semantic/runtime
   --  configuration constants, independent of bounded host session quotas.
end Lua.Runtime_Configuration;
