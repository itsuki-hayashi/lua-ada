with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Hook_Transition_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Lua_Same_Line;
   procedure Lua_Same_Line is
   begin
      --  A real Lua hook return restores the interrupted trace PC.
      Check
        ("do" & ASCII.LF &
         "  local t={}" & ASCII.LF &
         "  local function line(e,n)t[#t+1]=e;t[#t" &
         "+1]=n end" & ASCII.LF &
         "  local origin=debug.getinfo(1,'l').curr" &
         "entline" & ASCII.LF &
         "  debug.sethook(function()debug.sethook(" &
         "line,'l')end,'',2)" & ASCII.LF &
         "  local a=1;a=1;a=1;a=1;a=1" & ASCII.LF &
         "  a=2" & ASCII.LF &
         "  debug.sethook()" & ASCII.LF &
         "  assert(t[1]=='line' and t[2]==origin+3" &
         ")" & ASCII.LF &
         "  assert(t[3]=='line' and t[4]==origin+4" &
         " and t[5]==nil)" & ASCII.LF &
         "end");
   end Lua_Same_Line;

   procedure Lua_Count_Removes_Line;
   procedure Lua_Count_Removes_Line is
   begin
      --  A pending old line phase uses the newly installed hook.
      Check
        ("do" & ASCII.LF &
         "  local event" & ASCII.LF &
         "  local function replacement(e)debug.set" &
         "hook();event=e end" & ASCII.LF &
         "  debug.sethook(function(e)" & ASCII.LF &
         "    if e=='count' then debug.sethook(rep" &
         "lacement,'',1000)end" & ASCII.LF &
         "  end,'l',2)" & ASCII.LF &
         "  local a=1" & ASCII.LF &
         "  a=2" & ASCII.LF &
         "  debug.sethook()" & ASCII.LF &
         "  assert(event=='line')" & ASCII.LF &
         "end");
   end Lua_Count_Removes_Line;

   procedure Literal_Count;
   procedure Literal_Count is
   begin
      --  Each single local constant store executes one actual word.
      Check
        ("do" & ASCII.LF &
         "  local counts={}" & ASCII.LF &
         "  local origin=debug.getinfo(1,'l').curr" &
         "entline" & ASCII.LF &
         "  debug.sethook(function(e)" & ASCII.LF &
         "    if e=='count' then local n=debug.get" &
         "info(2,'l').currentline" & ASCII.LF &
         "      counts[n]=(counts[n]or 0)+1" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end,'',1)" & ASCII.LF &
         "  local a=1" & ASCII.LF &
         "  a=2" & ASCII.LF &
         "  a=3" & ASCII.LF &
         "  a=4" & ASCII.LF &
         "  a=5" & ASCII.LF &
         "  debug.sethook()" & ASCII.LF &
         "  for n=origin+6,origin+10 do assert(cou" &
         "nts[n]==1)end" & ASCII.LF &
         "  assert(a==5)" & ASCII.LF &
         "end");
   end Literal_Count;

   procedure Integer_Cell;
   procedure Integer_Cell is
   begin
      --  A direct integer literal store updates an existing captured cell.
      Check
        ("do" & ASCII.LF &
         "  local a=0;local function read()return " &
         "a end" & ASCII.LF &
         "  a=37;assert(read()==37 and math.type(r" &
         "ead())=='integer')" & ASCII.LF &
         "end");
   end Integer_Cell;

   procedure Float_Cell;
   procedure Float_Cell is
   begin
      --  Direct literal placement preserves the Lua numeric kind.
      Check
        ("do" & ASCII.LF &
         "  local a=0;local function read()return " &
         "a end" & ASCII.LF &
         "  a=3.0;assert(read()==3 and math.type(r" &
         "ead())=='float')" & ASCII.LF &
         "end");
   end Float_Cell;

   procedure Binary_String_Cell;
   procedure Binary_String_Cell is
   begin
      --  A counted string literal retains its embedded NUL bytes.
      Check
        ("do" & ASCII.LF &
         "  local a=0;local function read()return " &
         "a end" & ASCII.LF &
         "  a='x\0y';assert(read()=='x\0y' and #re" &
         "ad()==3)" & ASCII.LF &
         "end");
   end Binary_String_Cell;

   procedure Boolean_Cell;
   procedure Boolean_Cell is
   begin
      --  A boolean constant store updates the shared cell without coercion.
      Check
        ("do" & ASCII.LF &
         "  local a=0;local function read()return " &
         "a end" & ASCII.LF &
         "  a=false;assert(read()==false)" & ASCII.LF &
         "  a=true;assert(read()==true)" & ASCII.LF &
         "end");
   end Boolean_Cell;

   procedure Nil_Cell;
   procedure Nil_Cell is
   begin
      --  A nil constant retires the old captured value.
      Check
        ("do" & ASCII.LF &
         "  local a={};local function read()return" &
         " a end" & ASCII.LF &
         "  a=nil;assert(read()==nil)" & ASCII.LF &
         "end");
   end Nil_Cell;

   procedure Callback_RHS;
   procedure Callback_RHS is
   begin
      --  Nonliteral evaluation cannot overwrite the local before callbacks.
      Check
        ("do" & ASCII.LF &
         "  local a={37}" & ASCII.LF &
         "  local function rhs()assert(type(a)=='t" &
         "able' and a[1]==37);return 5 end" & ASCII.LF &
         "  a=a[1]+rhs();assert(a==42)" & ASCII.LF &
         "end");
   end Callback_RHS;

   procedure Multiple_RHS;
   procedure Multiple_RHS is
   begin
      --  Multiple stores still wait until every RHS has been evaluated.
      Check
        ("do" & ASCII.LF &
         "  local a,b=1,2" & ASCII.LF &
         "  a,b=3,(function()assert(a==1 and b==2)" &
         ";return 4 end)()" & ASCII.LF &
         "  assert(a==3 and b==4)" & ASCII.LF &
         "end");
   end Multiple_RHS;

   procedure Indexed_Store;
   procedure Indexed_Store is
   begin
      --  A literal RHS keeps its ordinary metamethod store behavior.
      Check
        ("do" & ASCII.LF &
         "  local calls=0" & ASCII.LF &
         "  local t=setmetatable({},{__newindex=fu" &
         "nction(self,k,v)" & ASCII.LF &
         "    calls=calls+1;assert(k=='value' and " &
         "v==41);rawset(self,k,v)" & ASCII.LF &
         "  end})" & ASCII.LF &
         "  t.value=41;assert(t.value==41 and call" &
         "s==1)" & ASCII.LF &
         "end");
   end Indexed_Store;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "hook transition: lua same line",
         Lua_Same_Line'Access);
      Test_Support.Add
        (Suite, "hook transition: lua count removes line",
         Lua_Count_Removes_Line'Access);
      Test_Support.Add
        (Suite, "hook transition: literal count",
         Literal_Count'Access);
      Test_Support.Add
        (Suite, "hook transition: integer cell",
         Integer_Cell'Access);
      Test_Support.Add
        (Suite, "hook transition: float cell",
         Float_Cell'Access);
      Test_Support.Add
        (Suite, "hook transition: binary string cell",
         Binary_String_Cell'Access);
      Test_Support.Add
        (Suite, "hook transition: boolean cell",
         Boolean_Cell'Access);
      Test_Support.Add
        (Suite, "hook transition: nil cell",
         Nil_Cell'Access);
      Test_Support.Add
        (Suite, "hook transition: callback rhs",
         Callback_RHS'Access);
      Test_Support.Add
        (Suite, "hook transition: multiple rhs",
         Multiple_RHS'Access);
      Test_Support.Add
        (Suite, "hook transition: indexed store",
         Indexed_Store'Access);
   end Register;
end Hook_Transition_Tests;
