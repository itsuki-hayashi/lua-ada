package Lua is
   pragma Pure;

   Language_Version : constant String := "Lua 5.5";
   --  Lua's language version string, distinct from the implementation version.

   Reference_Release : constant String := "5.5.1";
   --  Pinned reference release used for differential compatibility tests.

   Implementation_Version : constant String := "0.1.0-dev";
   --  Development version; this does not imply full Lua compatibility.
end Lua;
