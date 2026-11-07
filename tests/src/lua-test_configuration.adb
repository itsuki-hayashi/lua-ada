with Lua.Runtime_Configuration;

package body Lua.Test_Configuration is
   function Compatible_Global return Boolean is
     (Lua.Runtime_Configuration.Compatible_Global);
end Lua.Test_Configuration;
