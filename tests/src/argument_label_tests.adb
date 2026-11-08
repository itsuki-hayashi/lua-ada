with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Argument_Label_Tests is
   Prelude : constant String :=
     "local function check(modules,label)" & ASCII.LF &
     "  local registry=debug.getregistry()" & ASCII.LF &
     "  local loaded=registry._LOADED" & ASCII.LF &
     "  local oldmeta=getmetatable(registry)" & ASCII.LF &
     "  registry._LOADED=nil" & ASCII.LF &
     "  setmetatable(registry,{__index=function(r,k)" & ASCII.LF &
     "    assert(r==registry and k=='_LOADED')" & ASCII.LF &
     "    return modules" & ASCII.LF &
     "  end})" & ASCII.LF &
     "  local ok,e=pcall(math.sin,{})" & ASCII.LF &
     "  setmetatable(registry,oldmeta)" & ASCII.LF &
     "  rawset(registry,'_LOADED',loaded)" & ASCII.LF &
     "  local expected=""bad argument #1 to '""..label" & ASCII.LF &
     "  expected=expected..""' (number expected, got table)""" & ASCII.LF &
     "  assert(not ok and e==expected,e)" & ASCII.LF &
     "end" & ASCII.LF;
   procedure Nested_Keys;
   procedure First_Nul;
   procedure Global_Prefix;
   procedure Empty_Label;
   procedure Key_Scan_Quota;
   procedure Check (Expression : String);

   procedure Check (Expression : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        (Prelude & Expression);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   --  These identical native-paired bodies use only the actual registry.
   procedure Nested_Keys is
   begin
      Check ("check({lib={member=math.sin}},'lib.member')");
   end Nested_Keys;

   procedure First_Nul is
   begin
      --  The first key ends the C name before either huge counted suffix.
      Check
        ("check({['Alias\0'..string.rep('x',30000)]=" &
         "{[string.rep('y',30000)]=math.sin}},'Alias')");
   end First_Nul;

   procedure Global_Prefix is
   begin
      Check ("check({_G={['sin\0ignored']=math.sin}},'sin')");
   end Global_Prefix;

   procedure Empty_Label is
   begin
      Check ("check({['_G.\0ignored']=math.sin},'')");
   end Empty_Label;

   procedure Key_Scan_Quota is
      Universe : Session;
   begin
      --  Construct the real key and callback before reducing the budget.
      Assert (Universe.Execute
        ("local r=debug.getregistry();saved_loaded=r._LOADED;" &
         "saved_meta=getmetatable(r);local m=" &
         "{[string.rep('n',30000)]=math.sin};r._LOADED=nil;" &
         "setmetatable(r,{__index=function()return m end})").Status =
          Succeeded, "prepare actual long module key");
      Universe.Set_Limits ((Instructions => 1_000, others => <>));
      declare
         Result : constant Execution_Result := Universe.Execute
           ("pcall(math.sin,{});error('key quota was caught')");
      begin
         Assert (Result.Status = Resource_Error,
                 To_String (Result.Error.Message));
      end;
      Assert (Universe.Execute
        ("local r=debug.getregistry();setmetatable(r,saved_meta);" &
         "rawset(r,'_LOADED',saved_loaded);return 37").Status = Succeeded,
              "module key host stop damaged reusable session");
   end Key_Scan_Quota;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "argument label: nested keys",
                        Nested_Keys'Access);
      Test_Support.Add (Suite, "argument label: first key NUL suffixes",
                        First_Nul'Access);
      Test_Support.Add (Suite, "argument label: global prefix removal",
                        Global_Prefix'Access);
      Test_Support.Add (Suite, "argument label: empty stripped label",
                        Empty_Label'Access);
      Test_Support.Add (Suite, "argument label: owning key scan budget",
                        Key_Scan_Quota'Access);
   end Register;
end Argument_Label_Tests;
