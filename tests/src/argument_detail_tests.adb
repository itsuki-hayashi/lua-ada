with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Argument_Detail_Tests is
   Prelude : constant String :=
     "local function check(raw,label)" & ASCII.LF &
     "  local registry=debug.getregistry()" & ASCII.LF &
     "  local loaded=registry._LOADED" & ASCII.LF &
     "  local oldmeta=getmetatable(registry)" & ASCII.LF &
     "  local target=math.sin" & ASCII.LF &
     "  local bad=setmetatable({},{__name=raw})" & ASCII.LF &
     "  _G.detailbad=bad" & ASCII.LF &
     "  local count=0" & ASCII.LF &
     "  local detail='number expected, got '..(label or 'table')" & ASCII.LF &
     "  registry._LOADED=nil" & ASCII.LF &
     "  setmetatable(registry,{__index=function(r,k)" & ASCII.LF &
     "    assert(r==registry and k=='_LOADED')" & ASCII.LF &
     "    count=count+1" & ASCII.LF &
     "    local name,v=debug.getlocal(2,1)" & ASCII.LF &
     "    assert(name and rawequal(v,bad))" & ASCII.LF &
     "    name,v=debug.getlocal(2,2)" & ASCII.LF &
     "    assert(name and rawequal(v,raw))" & ASCII.LF &
     "    name,v=debug.getlocal(2,3)" & ASCII.LF &
     "    assert(name and v==detail)" & ASCII.LF &
     "    name,v=debug.getlocal(2,4)" & ASCII.LF &
     "    assert(name and v==target)" & ASCII.LF &
     "    name,v=debug.getlocal(2,5)" & ASCII.LF &
     "    assert(name and v=='_LOADED')" & ASCII.LF &
     "    return {alias=target}" & ASCII.LF &
     "  end})" & ASCII.LF &
     "  local f=assert(load('(math.sin or print)(detailbad)'," & ASCII.LF &
     "                      '=detail'))" & ASCII.LF &
     "  local ok,e=pcall(f)" & ASCII.LF &
     "  setmetatable(registry,oldmeta)" & ASCII.LF &
     "  rawset(registry,'_LOADED',loaded)" & ASCII.LF &
     "  _G.detailbad=nil" & ASCII.LF &
     "  assert(count==1 and not ok,e)" & ASCII.LF &
     "  local expected=""detail:1: bad argument #1 to 'alias' (""" & ASCII.LF &
     "  assert(e==expected..detail.."")"",e)" & ASCII.LF &
     "end" & ASCII.LF;
   procedure Number_Name;
   procedure Boolean_Name;
   procedure Table_Name;
   procedure Nul_Suffix;
   procedure Name_Scan_Quota;
   procedure Check (Expression : String);

   procedure Check (Expression : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        (Prelude & Expression);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   --  Each native-paired case inspects the real raw value before the detail.
   procedure Number_Name is
   begin
      Check ("check(27)");
   end Number_Name;

   procedure Boolean_Name is
   begin
      Check ("check(false)");
   end Boolean_Name;

   procedure Table_Name is
   begin
      Check ("check({})");
   end Table_Name;

   --  A short C prefix must not process or copy the large counted suffix.
   procedure Nul_Suffix is
   begin
      Check ("check('Small\0'..string.rep('z',30000),'Small')");
   end Nul_Suffix;

   procedure Name_Scan_Quota is
      Universe : Session;
   begin
      --  Prepare a retained long prefix before reducing the host budget.
      Assert (Universe.Execute
        ("bad=setmetatable({},{__name=string.rep('x',30000)})").Status =
          Succeeded, "prepare owned named argument");
      Universe.Set_Limits ((Instructions => 1_000, others => <>));
      declare
         Result : constant Execution_Result := Universe.Execute
           ("pcall(math.sin,bad);error('name quota was caught')");
      begin
         Assert (Result.Status = Resource_Error,
                 To_String (Result.Error.Message));
      end;
      Assert (Universe.Execute ("return 37").Status = Succeeded,
              "name scan host stop damaged reusable session");
   end Name_Scan_Quota;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "argument detail: raw number temporary",
                        Number_Name'Access);
      Test_Support.Add (Suite, "argument detail: raw boolean temporary",
                        Boolean_Name'Access);
      Test_Support.Add (Suite, "argument detail: raw table temporary",
                        Table_Name'Access);
      Test_Support.Add (Suite, "argument detail: short NUL prefix",
                        Nul_Suffix'Access);
      Test_Support.Add (Suite, "argument detail: owning name scan budget",
                        Name_Scan_Quota'Access);
   end Register;
end Argument_Detail_Tests;
