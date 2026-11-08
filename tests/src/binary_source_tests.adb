with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Binary_Source_Tests is
   Prelude : constant String :=
     "local function check(name,short)" & ASCII.LF &
     "  local original=assert(load('math.sin({})',name))" & ASCII.LF &
     "  local changed=name:gsub('X','\0')" & ASCII.LF &
     "  local bytes,n=string.dump(original):gsub(name,changed,1)" & ASCII.LF &
     "  assert(n==1)" & ASCII.LF &
     "  local f=assert(load(bytes))" & ASCII.LF &
     "  local info=debug.getinfo(f,'S')" & ASCII.LF &
     "  assert(info.source==changed)" & ASCII.LF &
     "  assert(info.short_src==short," & ASCII.LF &
     "         string.format('%q',info.short_src))" & ASCII.LF &
     "  local ok,e=pcall(f)" & ASCII.LF &
     "  local expected=short.."":1: bad argument #1 to 'sin' """ & ASCII.LF &
     "  expected=expected..'(number expected, got table)'" & ASCII.LF &
     "  assert(not ok and e==expected,string.format('%q',e))" & ASCII.LF &
     "end" & ASCII.LF;
   procedure Literal_Name;
   procedure File_Name;
   procedure Snippet_Name;
   procedure Long_File_Tail;
   procedure Check (Expression : String);

   procedure Check (Expression : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        (Prelude & Expression);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   --  Binary patching preserves counted source bytes but display is C text.
   procedure Literal_Name is
   begin
      Check ("check('=aXb','a')");
   end Literal_Name;

   procedure File_Name is
   begin
      Check ("check('@aXb','a')");
   end File_Name;

   procedure Snippet_Name is
   begin
      Check ("check('aXb','[string ""a')");
   end Snippet_Name;

   --  Select the native file tail before applying C-prefix termination.
   procedure Long_File_Tail is
   begin
      Check ("check('@aXb'..string.rep('z',100)," &
             "'...'..string.rep('z',56))");
   end Long_File_Tail;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "binary source: literal NUL display",
                        Literal_Name'Access);
      Test_Support.Add (Suite, "binary source: file NUL display",
                        File_Name'Access);
      Test_Support.Add (Suite, "binary source: snippet NUL display",
                        Snippet_Name'Access);
      Test_Support.Add (Suite, "binary source: long file NUL tail",
                        Long_File_Tail'Access);
   end Register;
end Binary_Source_Tests;
