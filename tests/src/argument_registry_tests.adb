with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Argument_Registry_Tests is
   use type Interfaces.C.int;
   function C_Check (Which : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_argument_registry";
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Callback_Loaded;
   procedure Callback_Loaded is
   begin
      --  One actual registry lookup supplies the module graph.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r);local calls=" &
         "0" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=fu" &
         "nction(t,k)assert(t==r and k=='_LOADED');c" &
         "alls=calls+1;return loaded end})" & ASCII.LF &
         "  local ok,e=pcall(math.sin,{})" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and calls==1 and e==""bad a" &
         "rgument #1 to 'math.sin' (number expected," &
         " got table)"",tostring(e))" & ASCII.LF &
         "end");
   end Callback_Loaded;

   procedure Plain_Temporaries;
   procedure Plain_Temporaries is
   begin
      --  The original C frame owns detail, target and getfield key.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r)" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=fu" &
         "nction()" & ASCII.LF &
         "    assert(debug.getinfo(2,'f').func==math" &
         ".sin)" & ASCII.LF &
         "    local n,a=debug.getlocal(2,1);assert(n" &
         "=='(C temporary)' and type(a)=='table')" & ASCII.LF &
         "    local _,detail=debug.getlocal(2,2);loc" &
         "al _,f=debug.getlocal(2,3);local _,key=deb" &
         "ug.getlocal(2,4)" & ASCII.LF &
         "    assert(detail=='number expected, got t" &
         "able' and f==math.sin and key=='_LOADED' a" &
         "nd debug.getlocal(2,5)==nil)" & ASCII.LF &
         "    return loaded" & ASCII.LF &
         "  end})" & ASCII.LF &
         "  local ok,e=pcall(math.sin,{})" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and e==""bad argument #1 to" &
         " 'math.sin' (number expected, got table)""," &
         "tostring(e))" & ASCII.LF &
         "end");
   end Plain_Temporaries;

   procedure Named_Temporaries;
   procedure Named_Temporaries is
   begin
      --  A raw __name precedes the formatted detail in real slots.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r)" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=fu" &
         "nction()" & ASCII.LF &
         "    local _,name=debug.getlocal(2,2);local" &
         " _,detail=debug.getlocal(2,3)" & ASCII.LF &
         "    local _,f=debug.getlocal(2,4);local _," &
         "key=debug.getlocal(2,5)" & ASCII.LF &
         "    assert(name=='Named' and detail=='numb" &
         "er expected, got Named' and f==math.sin an" &
         "d key=='_LOADED' and debug.getlocal(2,6)==" &
         "nil)" & ASCII.LF &
         "    return loaded" & ASCII.LF &
         "  end})" & ASCII.LF &
         "  local ok,e=pcall(math.sin,setmetatable({" &
         "},{__name='Named'}))" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and e==""bad argument #1 to" &
         " 'math.sin' (number expected, got Named)""," &
         "tostring(e))" & ASCII.LF &
         "end");
   end Named_Temporaries;

   procedure Error_Identity;
   procedure Error_Identity is
   begin
      --  A lookup error replaces the pending argument diagnostic.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r);local marker" &
         "={}" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=fu" &
         "nction()error(marker)end})" & ASCII.LF &
         "  local ok,e=pcall(math.sin,{})" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and e==marker)" & ASCII.LF &
         "end");
   end Error_Identity;

   procedure Empty_Result;
   procedure Empty_Result is
   begin
      --  A handler returning no values produces the unknown name.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r);local calls=" &
         "0" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=fu" &
         "nction()calls=calls+1 end})" & ASCII.LF &
         "  local ok,e=pcall(math.sin,{})" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and calls==1 and e==""bad a" &
         "rgument #1 to '?' (number expected, got ta" &
         "ble)"",tostring(e))" & ASCII.LF &
         "end");
   end Empty_Result;

   procedure Nested_Errors;
   procedure Nested_Errors is
   begin
      --  Nested lookups retain independent original types and indices.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r);local calls=" &
         "0" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=fu" &
         "nction()" & ASCII.LF &
         "    calls=calls+1" & ASCII.LF &
         "    if calls==1 then local ok,e=pcall(math" &
         ".cos,false);assert(not ok and e==""bad argu" &
         "ment #1 to 'math.cos' (number expected, go" &
         "t boolean)"",tostring(e))end" & ASCII.LF &
         "    return loaded" & ASCII.LF &
         "  end})" & ASCII.LF &
         "  local ok,e=pcall(math.sin,{})" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and calls==2 and e==""bad a" &
         "rgument #1 to 'math.sin' (number expected," &
         " got table)"",tostring(e))" & ASCII.LF &
         "end");
   end Nested_Errors;

   procedure Table_Forwarding;
   procedure Table_Forwarding is
   begin
      --  The registry can forward the lookup through a table.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r)" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index={_" &
         "LOADED=loaded}})" & ASCII.LF &
         "  local ok,e=pcall(math.sin,{})" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and e==""bad argument #1 to" &
         " 'math.sin' (number expected, got table)""," &
         "tostring(e))" & ASCII.LF &
         "end");
   end Table_Forwarding;

   procedure Cannot_Yield;
   procedure Cannot_Yield is
   begin
      --  Registry callbacks cannot suspend synchronous argument checking.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r)" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=co" &
         "routine.yield})" & ASCII.LF &
         "  local co=coroutine.create(function()retu" &
         "rn pcall(math.sin,{})end)" & ASCII.LF &
         "  local resumed,ok,e=coroutine.resume(co)" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(resumed and not ok and e=='attemp" &
         "t to yield across a C-call boundary' and c" &
         "oroutine.status(co)=='dead',tostring(e))" & ASCII.LF &
         "end");
   end Cannot_Yield;

   procedure Nul_Module_Name;
   procedure Nul_Module_Name is
   begin
      --  The actual returned module name has C string rendering.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r)" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=fu" &
         "nction()return {['A\0B']={f=math.sin}}end}" &
         ")" & ASCII.LF &
         "  local ok,e=pcall(math.sin,{})" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and e==""bad argument #1 to" &
         " 'A' (number expected, got table)"",tostrin" &
         "g(e))" & ASCII.LF &
         "end");
   end Nul_Module_Name;

   procedure Operand_Collection;
   procedure Operand_Collection is
   begin
      --  A callback dropping the actual C argument removes its last edge.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r);local weak=s" &
         "etmetatable({},{__mode='v'})" & ASCII.LF &
         "  local function factory()return math.sin " &
         "end" & ASCII.LF &
         "  local function bad()local a={};weak[1]=a" &
         ";return (factory())(a)end" & ASCII.LF &
         "  local function clear()" & ASCII.LF &
         "    -- A native C tail call can retain its" &
         " Lua caller until the C return." & ASCII.LF &
         "    -- Clear every actual caller slot, the" &
         "n retire this helper's own reads." & ASCII.LF &
         "    for level=3,10 do" & ASCII.LF &
         "      if not debug.getinfo(level,'f')then " &
         "break end" & ASCII.LF &
         "      for index=1,40 do local name,value=d" &
         "ebug.getlocal(level,index)" & ASCII.LF &
         "        if not name then break end" & ASCII.LF &
         "        if value==weak[1]then debug.setloc" &
         "al(level,index,nil)end" & ASCII.LF &
         "      end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=fu" &
         "nction()" & ASCII.LF &
         "    assert(debug.getinfo(2,'f').func==math" &
         ".sin);clear();collectgarbage();assert(weak" &
         "[1]==nil)" & ASCII.LF &
         "    return loaded" & ASCII.LF &
         "  end})" & ASCII.LF &
         "  local ok,e=pcall(bad)" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and e:match(""bad argument " &
         "#1 to 'math.sin' %(number expected, got ta" &
         "ble%)$""),tostring(e))" & ASCII.LF &
         "end");
   end Operand_Collection;

   procedure Known_Name_Bypass;
   procedure Known_Name_Bypass is
   begin
      --  A known Lua call name never searches the registry.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r);local calls=" &
         "0" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=fu" &
         "nction()calls=calls+1;return loaded end})" & ASCII.LF &
         "  local ok,e=pcall(function()math.sin({})e" &
         "nd)" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and calls==0 and e:match(""" &
         ": bad argument #1 to 'sin' %(number expect" &
         "ed, got table%)$""),tostring(e))" & ASCII.LF &
         "end");
   end Known_Name_Bypass;

   procedure Non_Table_Modules;
   procedure Non_Table_Modules is
   begin
      --  A non-table callback result still produces the unknown name.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r);local calls=0" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=fu" &
         "nction()calls=calls+1;return 37 end})" & ASCII.LF &
         "  local ok,e=pcall(math.sin,{})" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and calls==1 and e==""bad " &
         "argument #1 to '?' (number expected, got table)"",tostrin" &
         "g(e))" & ASCII.LF &
         "end");
   end Non_Table_Modules;

   procedure Returned_Modules;
   procedure Returned_Modules is
   begin
      --  Name search uses the callback result even if it rewrites the
      --  registry.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r)" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=fu" &
         "nction()r._LOADED=loaded;return {alias=mat" &
         "h.sin}end})" & ASCII.LF &
         "  local ok,e=pcall(math.sin,{})" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and e==""bad argument #1 to" &
         " 'alias' (number expected, got table)"",tos" &
         "tring(e))" & ASCII.LF &
         "end");
   end Returned_Modules;

   procedure Third_Argument;
   procedure Third_Argument is
   begin
      --  A deferred type error preserves its original third argument
      --  index.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r)" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=fu" &
         "nction()return loaded end})" & ASCII.LF &
         "  local ok,e=pcall(debug.setuservalue,nil," &
         "{},false)" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and e==""bad argument #3 to" &
         " 'debug.setuservalue' (number expected, go" &
         "t boolean)"",tostring(e))" & ASCII.LF &
         "end");
   end Third_Argument;

   procedure Representation_Temporaries;
   procedure Representation_Temporaries is
   begin
      --  Direct argerror retains no invented type-error detail slot.
      Check
        ("do" & ASCII.LF &
         "  local r=debug.getregistry();local loaded" &
         ",mt=r._LOADED,getmetatable(r)" & ASCII.LF &
         "  r._LOADED=nil;setmetatable(r,{__index=fu" &
         "nction()" & ASCII.LF &
         "    assert(debug.getinfo(2,'f').func==debu" &
         "g.setuservalue)" & ASCII.LF &
         "    local _,f=debug.getlocal(2,4);local _," &
         "key=debug.getlocal(2,5)" & ASCII.LF &
         "    assert(f==debug.setuservalue and key==" &
         "'_LOADED' and debug.getlocal(2,6)==nil)" & ASCII.LF &
         "    return loaded" & ASCII.LF &
         "  end})" & ASCII.LF &
         "  local ok,e=pcall(debug.setuservalue,nil," &
         "{},1.5)" & ASCII.LF &
         "  setmetatable(r,mt);r._LOADED=loaded" & ASCII.LF &
         "  assert(not ok and e==""bad argument #3 to" &
         " 'debug.setuservalue' (number has no integ" &
         "er representation)"",tostring(e))" & ASCII.LF &
         "end");
   end Representation_Temporaries;

   procedure Callback_Budget;
   procedure Callback_Budget is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  The lookup is actual user code inside synchronous C argument
      --  checking. It must share the existing host budget, remain outside
      --  Lua pcall recovery, and retire its barrier before the next chunk.
      Universe.Set_Limits ((Instructions => 1_000, others => <>));
      Result := Universe.Execute
        ("local r=debug.getregistry();r._LOADED=nil;" &
         "setmetatable(r,{__index=function()while true do end end});" &
         "pcall(math.sin,{});error('lookup quota was caught')");
      Assert (Result.Status = Resource_Error,
              "registry lookup must share the owning host work budget");
      Result := Universe.Execute ("assert(37+5==42)");
      Assert (Result.Status = Succeeded,
              "argument lookup host abort must retire its live owners");
   end Callback_Budget;

   procedure Direct_C_Owner;
   procedure Direct_C_Owner is
   begin
      --  The saved builtin C pointer adds no public CI: real temporaries
      --  belong to the original C body while its hidden Ada phase waits.
      Assert (C_Check (0) = 1, "actual original C registry lookup owner");
   end Direct_C_Owner;

   procedure Direct_C_Roots;
   procedure Direct_C_Roots is
   begin
      --  A C-created operand has no older Lua local. Clearing its actual
      --  C slot must also release the hidden builtin phase's request copy.
      Assert (C_Check (1) = 1, "actual original C operand collection");
   end Direct_C_Roots;

   procedure Direct_C_Guard;
   procedure Direct_C_Guard is
   begin
      --  The callback throws a table through the actual saved C pointer.
      --  The error is identical and code after that C call never executes.
      Assert (C_Check (2) = 1, "actual original C error guard ownership");
   end Direct_C_Guard;

   procedure Direct_C_Captures;
   procedure Direct_C_Captures is
   begin
      --  Updating the actual C closure's upvalue removes the old sole edge;
      --  a failed hidden builtin phase cannot retain a capture snapshot.
      Assert (C_Check (3) = 1, "actual original C captured value collection");
   end Direct_C_Captures;

   procedure Direct_C_Prefix;
   procedure Direct_C_Prefix is
   begin
      --  Calling a saved C pointer treats the entire live C prefix as its
      --  stack, including temporaries beyond sin's single consumed argument.
      Assert (C_Check (4) = 1, "actual original C extra temporaries survive");
   end Direct_C_Prefix;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "argument registry: callback loaded",
         Callback_Loaded'Access);
      Test_Support.Add
        (Suite, "argument registry: plain temporaries",
         Plain_Temporaries'Access);
      Test_Support.Add
        (Suite, "argument registry: named temporaries",
         Named_Temporaries'Access);
      Test_Support.Add
        (Suite, "argument registry: error identity",
         Error_Identity'Access);
      Test_Support.Add
        (Suite, "argument registry: empty result",
         Empty_Result'Access);
      Test_Support.Add
        (Suite, "argument registry: nested errors",
         Nested_Errors'Access);
      Test_Support.Add
        (Suite, "argument registry: table forwarding",
         Table_Forwarding'Access);
      Test_Support.Add
        (Suite, "argument registry: cannot yield",
         Cannot_Yield'Access);
      Test_Support.Add
        (Suite, "argument registry: nul module name",
         Nul_Module_Name'Access);
      Test_Support.Add
        (Suite, "argument registry: operand collection",
         Operand_Collection'Access);
      Test_Support.Add
        (Suite, "argument registry: known name bypass",
         Known_Name_Bypass'Access);
      Test_Support.Add
        (Suite, "argument registry: non table modules",
         Non_Table_Modules'Access);
      Test_Support.Add
        (Suite, "argument registry: returned modules",
         Returned_Modules'Access);
      Test_Support.Add
        (Suite, "argument registry: third argument",
         Third_Argument'Access);
      Test_Support.Add
        (Suite, "argument registry: representation temporaries",
         Representation_Temporaries'Access);
      Test_Support.Add (Suite, "argument registry: owning host budget",
                        Callback_Budget'Access);
      Test_Support.Add (Suite, "argument registry: direct C owner",
                        Direct_C_Owner'Access);
      Test_Support.Add (Suite, "argument registry: direct C roots",
                        Direct_C_Roots'Access);
      Test_Support.Add (Suite, "argument registry: direct C guard",
                        Direct_C_Guard'Access);
      Test_Support.Add (Suite, "argument registry: direct C captures",
                        Direct_C_Captures'Access);
      Test_Support.Add (Suite, "argument registry: direct C extra temporaries",
                        Direct_C_Prefix'Access);
   end Register;
end Argument_Registry_Tests;
