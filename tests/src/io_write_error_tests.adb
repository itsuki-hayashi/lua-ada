with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body IO_Write_Error_Tests is
   procedure Check (Source : String);
   procedure Unknown_Origin;
   procedure Direct_Global;
   procedure Method_First;
   procedure Method_Second;
   procedure Named_Type;
   procedure No_Arguments;

   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   --  Native-paired Lua source checks exact errors and observable effects.
   procedure Unknown_Origin is
   begin
      Check
        ("    local f=assert(load('(io.write or print){}" &
         "','=write'))" & ASCII.LF &
         "    local ok,e=pcall(f)" & ASCII.LF &
         "    assert(not ok and e==""write:1: bad argumen" &
         "t #1 to 'io.write' (string expected, got table" &
         ")"",e)");
   end Unknown_Origin;

   --  Native-paired Lua source checks exact errors and observable effects.
   procedure Direct_Global is
   begin
      Check
        ("    local f=assert(load('io.write(false)','=wr" &
         "ite'))" & ASCII.LF &
         "    local ok,e=pcall(f)" & ASCII.LF &
         "    assert(not ok and e==""write:1: bad argumen" &
         "t #1 to 'write' (string expected, got boolean)" &
         """,e)");
   end Direct_Global;

   --  Native-paired Lua source checks exact errors and observable effects.
   procedure Method_First is
   begin
      Check
        ("    _G.writefile=io.stdout" & ASCII.LF &
         "    local f=assert(load(""writefile:write({})""," &
         "'=write'))" & ASCII.LF &
         "    local ok,e=pcall(f);_G.writefile=nil" & ASCII.LF &
         "    assert(not ok and e==""write:1: bad argumen" &
         "t #1 to 'write' (string expected, got table)""," &
         "e)");
   end Method_First;

   --  Native-paired Lua source checks exact errors and observable effects.
   procedure Method_Second is
   begin
      Check
        ("    local file=assert(io.tmpfile());_G.writefi" &
         "le=file" & ASCII.LF &
         "    local f=assert(load(""writefile:write('save" &
         "d',{})"",'=write'))" & ASCII.LF &
         "    local ok,e=pcall(f);file:seek('set');local" &
         " bytes=file:read('a');file:close();_G.writefil" &
         "e=nil" & ASCII.LF &
         "    assert(not ok and e==""write:1: bad argumen" &
         "t #2 to 'write' (string expected, got table)""," &
         "e)" & ASCII.LF &
         "    assert(bytes=='saved')");
   end Method_Second;

   --  Native-paired Lua source checks exact errors and observable effects.
   procedure Named_Type is
   begin
      Check
        ("    local file=assert(io.tmpfile());_G.writefi" &
         "le=file" & ASCII.LF &
         "    _G.writevalue=setmetatable({},{__name='Wri" &
         "te Box\0suffix'})" & ASCII.LF &
         "    local f=assert(load('writefile:write(write" &
         "value)','=write'))" & ASCII.LF &
         "    local ok,e=pcall(f);file:close();_G.writef" &
         "ile=nil;_G.writevalue=nil" & ASCII.LF &
         "    assert(not ok and e==""write:1: bad argumen" &
         "t #1 to 'write' (string expected, got Write Bo" &
         "x)"",e)");
   end Named_Type;

   --  Native-paired Lua source checks exact errors and observable effects.
   procedure No_Arguments is
   begin
      Check
        ("    local file=assert(io.tmpfile())" & ASCII.LF &
         "    assert(file:write()==file);file:close()");
   end No_Arguments;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "I/O write: unknown call origin",
                        Unknown_Origin'Access);
      Test_Support.Add (Suite, "I/O write: direct global call",
                        Direct_Global'Access);
      Test_Support.Add (Suite, "I/O write: method first argument",
                        Method_First'Access);
      Test_Support.Add (Suite, "I/O write: method second preserves bytes",
                        Method_Second'Access);
      Test_Support.Add (Suite, "I/O write: raw named argument type",
                        Named_Type'Access);
      Test_Support.Add (Suite, "I/O write: zero arguments",
                        No_Arguments'Access);
   end Register;
end IO_Write_Error_Tests;
