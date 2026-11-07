with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Collector_Error_Tests is
   procedure Check (Source : String);
   procedure Unknown_Origin;
   procedure Boolean_Argument;
   procedure Named_Argument;
   procedure Default_Option;

   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   --  Native-paired Lua source checks exact type/origin or default results.
   procedure Unknown_Origin is
   begin
      Check
        ("    local f=assert(load('(collectgarbage or pr" &
         "int){}','=collector'))" & ASCII.LF &
         "    local ok,e=pcall(f)" & ASCII.LF &
         "    assert(not ok and e==""collector:1: bad arg" &
         "ument #1 to 'collectgarbage' (string expected," &
         " got table)"",e)");
   end Unknown_Origin;

   --  Native-paired Lua source checks exact type/origin or default results.
   procedure Boolean_Argument is
   begin
      Check
        ("    local f=assert(load('collectgarbage(false)" &
         "','=collector'))" & ASCII.LF &
         "    local ok,e=pcall(f)" & ASCII.LF &
         "    assert(not ok and e==""collector:1: bad arg" &
         "ument #1 to 'collectgarbage' (string expected," &
         " got boolean)"",e)");
   end Boolean_Argument;

   --  Native-paired Lua source checks exact type/origin or default results.
   procedure Named_Argument is
   begin
      Check
        ("    _G.badmode=setmetatable({},{__name='Collec" &
         "tor Box\0suffix'})" & ASCII.LF &
         "    local f=assert(load('collectgarbage(badmod" &
         "e)','=collector'))" & ASCII.LF &
         "    local ok,e=pcall(f);_G.badmode=nil" & ASCII.LF &
         "    assert(not ok and e==""collector:1: bad arg" &
         "ument #1 to 'collectgarbage' (string expected," &
         " got Collector Box)"",e)");
   end Named_Argument;

   --  Native-paired Lua source checks exact type/origin or default results.
   procedure Default_Option is
   begin
      Check
        ("    local a,b=collectgarbage(),collectgarbage(" &
         "nil)" & ASCII.LF &
         "    assert(a==0 and b==0 and math.type(a)=='in" &
         "teger' and math.type(b)=='integer')");
   end Default_Option;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "collector argument: unknown call origin",
                        Unknown_Origin'Access);
      Test_Support.Add (Suite, "collector argument: boolean option type",
                        Boolean_Argument'Access);
      Test_Support.Add (Suite, "collector argument: raw named option type",
                        Named_Argument'Access);
      Test_Support.Add (Suite, "collector argument: nil and absent default",
                        Default_Option'Access);
   end Register;
end Collector_Error_Tests;
