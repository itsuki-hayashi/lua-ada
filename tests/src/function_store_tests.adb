with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Function_Store_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Field_Store;
   procedure Field_Store is
   begin
      --  A failed function field definition is attributed to its opening
      --  keyword.
      Check
        ("do" & ASCII.LF &
         "  function_store_target={}" & ASCII.LF &
         "  local f=assert(load([=[function functi" &
         "on_store_target.x.y()" & ASCII.LF &
         " return 7" & ASCII.LF &
         "end]=],'=function-store'))" & ASCII.LF &
         "  local ok,e=pcall(f);function_store_tar" &
         "get=nil" & ASCII.LF &
         "  assert(not ok and e==[=[function-store" &
         ":1: attempt to index a nil value (field " &
         "'x')]=],tostring(e))" & ASCII.LF &
         "end");
   end Field_Store;

   procedure Method_Store;
   procedure Method_Store is
   begin
      --  An implicit-self method definition retains the opening store line.
      Check
        ("do" & ASCII.LF &
         "  function_store_target={}" & ASCII.LF &
         "  local f=assert(load([=[function functi" &
         "on_store_target.x:y()" & ASCII.LF &
         " return self" & ASCII.LF &
         "end]=],'=function-store'))" & ASCII.LF &
         "  local ok,e=pcall(f);function_store_tar" &
         "get=nil" & ASCII.LF &
         "  assert(not ok and e==[=[function-store" &
         ":1: attempt to index a nil value (field " &
         "'x')]=],tostring(e))" & ASCII.LF &
         "end");
   end Method_Store;

   procedure Empty_Store;
   procedure Empty_Store is
   begin
      --  An empty function body still stores on the definition's first line.
      Check
        ("do" & ASCII.LF &
         "  function_store_target={}" & ASCII.LF &
         "  local f=assert(load([=[function functi" &
         "on_store_target.x.y()" & ASCII.LF &
         "end]=],'=function-store'))" & ASCII.LF &
         "  local ok,e=pcall(f);function_store_tar" &
         "get=nil" & ASCII.LF &
         "  assert(not ok and e==[=[function-store" &
         ":1: attempt to index a nil value (field " &
         "'x')]=],tostring(e))" & ASCII.LF &
         "end");
   end Empty_Store;

   procedure Keyword_Line;
   procedure Keyword_Line is
   begin
      --  A split keyword and target uses the keyword line rather than target
      --  line.
      Check
        ("do" & ASCII.LF &
         "  function_store_target={}" & ASCII.LF &
         "  local f=assert(load([=[function" & ASCII.LF &
         " function_store_target.x.y()" & ASCII.LF &
         " return 7" & ASCII.LF &
         "end]=],'=function-store'))" & ASCII.LF &
         "  local ok,e=pcall(f);function_store_tar" &
         "get=nil" & ASCII.LF &
         "  assert(not ok and e==[=[function-store" &
         ":1: attempt to index a nil value (field " &
         "'x')]=],tostring(e))" & ASCII.LF &
         "end");
   end Keyword_Line;

   procedure Assignment_End;
   procedure Assignment_End is
   begin
      --  An ordinary anonymous-function assignment retains its closing RHS
      --  line.
      Check
        ("do" & ASCII.LF &
         "  function_store_target={}" & ASCII.LF &
         "  local f=assert(load([=[function_store_" &
         "target.x.y = function()" & ASCII.LF &
         " return 7" & ASCII.LF &
         "end]=],'=function-store'))" & ASCII.LF &
         "  local ok,e=pcall(f);function_store_tar" &
         "get=nil" & ASCII.LF &
         "  assert(not ok and e==[=[function-store" &
         ":3: attempt to index a nil value (field " &
         "'x')]=],tostring(e))" & ASCII.LF &
         "end");
   end Assignment_End;

   procedure Target_Read;
   procedure Target_Read is
   begin
      --  A target-prefix read still fails before closure construction.
      Check
        ("do" & ASCII.LF &
         "  function_store_target=nil" & ASCII.LF &
         "  local f=assert(load([=[function functi" &
         "on_store_target.x.y()" & ASCII.LF &
         " return 7" & ASCII.LF &
         "end]=],'=function-store'))" & ASCII.LF &
         "  local ok,e=pcall(f);function_store_tar" &
         "get=nil" & ASCII.LF &
         "  assert(not ok and e==[=[function-store" &
         ":1: attempt to index a nil value (global" &
         " 'function_store_target')]=],tostring(e)" &
         ")" & ASCII.LF &
         "end");
   end Target_Read;

   procedure Field_Events;
   procedure Field_Events is
   begin
      --  Closure construction stays on end while the actual field store
      --  moves to start.
      Check
        ("do" & ASCII.LF &
         "  local storeline,stored;function_store_" &
         "target={x=setmetatable({},{__newindex=fu" &
         "nction(t,k,v)" & ASCII.LF &
         "    storeline=debug.getinfo(2,'l').curre" &
         "ntline;stored=v;rawset(t,k,v)" & ASCII.LF &
         "  end})}" & ASCII.LF &
         "  local function f()" & ASCII.LF &
         "    function function_store_target.x.y()" & ASCII.LF &
         "      return 7" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local info=debug.getinfo(f,'S');local " &
         "lines={}" & ASCII.LF &
         "  debug.sethook(function(_,line)if debug" &
         ".getinfo(2,'f').func==f then lines[#line" &
         "s+1]=line end end,'l')" & ASCII.LF &
         "  f();debug.sethook();function_store_tar" &
         "get=nil" & ASCII.LF &
         "  assert(storeline==info.linedefined+1 a" &
         "nd stored()==7)" & ASCII.LF &
         "  local expected={info.linedefined+1,inf" &
         "o.linedefined+3,info.linedefined+1,info." &
         "lastlinedefined}" & ASCII.LF &
         "  assert(#lines==#expected);for i,v in i" &
         "pairs(expected)do assert(lines[i]==v,tab" &
         "le.concat(lines,','))end" & ASCII.LF &
         "end");
   end Field_Events;

   procedure Global_Events;
   procedure Global_Events is
   begin
      --  A real global newindex callback observes the opening definition
      --  store.
      Check
        ("do" & ASCII.LF &
         "  local storeline,stored;local env=setme" &
         "tatable({},{__index=_G,__newindex=functi" &
         "on(t,k,v)" & ASCII.LF &
         "    storeline=debug.getinfo(2,'l').curre" &
         "ntline;stored=v;rawset(t,k,v)" & ASCII.LF &
         "  end})" & ASCII.LF &
         "  local f" & ASCII.LF &
         "  do" & ASCII.LF &
         "    local _ENV=env" & ASCII.LF &
         "    f=function()" & ASCII.LF &
         "      function function_store_created()" & ASCII.LF &
         "        return 7" & ASCII.LF &
         "      end" & ASCII.LF &
         "    end" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local info=debug.getinfo(f,'S');local " &
         "lines={}" & ASCII.LF &
         "  debug.sethook(function(_,line)if debug" &
         ".getinfo(2,'f').func==f then lines[#line" &
         "s+1]=line end end,'l')" & ASCII.LF &
         "  f();debug.sethook()" & ASCII.LF &
         "  assert(storeline==info.linedefined+1 a" &
         "nd stored==env.function_store_created an" &
         "d stored()==7)" & ASCII.LF &
         "  local expected={info.linedefined+3,inf" &
         "o.linedefined+1,info.lastlinedefined}" & ASCII.LF &
         "  assert(#lines==#expected);for i,v in i" &
         "pairs(expected)do assert(lines[i]==v,tab" &
         "le.concat(lines,','))end" & ASCII.LF &
         "end");
   end Global_Events;

   procedure Local_Events;
   procedure Local_Events is
   begin
      --  A recursive local definition retains its distinct closing-line
      --  initialization.
      Check
        ("do" & ASCII.LF &
         "  local function f()" & ASCII.LF &
         "    local function created()" & ASCII.LF &
         "      return 7" & ASCII.LF &
         "    end" & ASCII.LF &
         "    return created" & ASCII.LF &
         "  end" & ASCII.LF &
         "  local info=debug.getinfo(f,'S');local " &
         "lines={}" & ASCII.LF &
         "  debug.sethook(function(_,line)if debug" &
         ".getinfo(2,'f').func==f then lines[#line" &
         "s+1]=line end end,'l')" & ASCII.LF &
         "  local stored=f();debug.sethook();asser" &
         "t(stored()==7)" & ASCII.LF &
         "  local expected={info.linedefined+3,inf" &
         "o.linedefined+4}" & ASCII.LF &
         "  assert(#lines==#expected);for i,v in i" &
         "pairs(expected)do assert(lines[i]==v,tab" &
         "le.concat(lines,','))end" & ASCII.LF &
         "end");
   end Local_Events;

   procedure Explicit_Global_Store;
   procedure Explicit_Global_Store is
   begin
      --  A split global directive stores on its GLOBAL keyword line.
      Check
        ("do" & ASCII.LF &
         "  local observed;local env=setmetatable(" &
         "{},{__newindex=function(t,k,v)" & ASCII.LF &
         "    observed=debug.getinfo(2,'l').curren" &
         "tline;rawset(t,k,v)" & ASCII.LF &
         "  end})" & ASCII.LF &
         "  local f=assert(load('global\n function" &
         "\n created\n ()\n return 7\n end','=expl" &
         "icit-global','t',env))" & ASCII.LF &
         "  f();assert(observed==1 and env.created" &
         "()==7)" & ASCII.LF &
         "end");
   end Explicit_Global_Store;

   procedure Explicit_Global_Metadata;
   procedure Explicit_Global_Metadata is
   begin
      --  Global function metadata uses its actual parenthesis line.
      Check
        ("do" & ASCII.LF &
         "  local env={};local f=assert(load('glob" &
         "al\n function\n created\n ()\n return 7\" &
         "n end','=explicit-global','t',env))" & ASCII.LF &
         "  f();local info=debug.getinfo(env.creat" &
         "ed,'S')" & ASCII.LF &
         "  assert(info.linedefined==4 and info.la" &
         "stlinedefined==6 and env.created()==7)" & ASCII.LF &
         "end");
   end Explicit_Global_Metadata;

   procedure Ordinary_Metadata;
   procedure Ordinary_Metadata is
   begin
      --  A split ordinary function retains keyword-based child metadata.
      Check
        ("do" & ASCII.LF &
         "  local env={};local f=assert(load('func" &
         "tion\n created\n ()\n return 7\n end','=" &
         "ordinary-function','t',env))" & ASCII.LF &
         "  f();local info=debug.getinfo(env.creat" &
         "ed,'S')" & ASCII.LF &
         "  assert(info.linedefined==1 and info.la" &
         "stlinedefined==5 and env.created()==7)" & ASCII.LF &
         "end");
   end Ordinary_Metadata;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "function stores: field store",
         Field_Store'Access);
      Test_Support.Add
        (Suite, "function stores: method store",
         Method_Store'Access);
      Test_Support.Add
        (Suite, "function stores: empty store",
         Empty_Store'Access);
      Test_Support.Add
        (Suite, "function stores: keyword line",
         Keyword_Line'Access);
      Test_Support.Add
        (Suite, "function stores: assignment end",
         Assignment_End'Access);
      Test_Support.Add
        (Suite, "function stores: target read",
         Target_Read'Access);
      Test_Support.Add
        (Suite, "function stores: field events",
         Field_Events'Access);
      Test_Support.Add
        (Suite, "function stores: global events",
         Global_Events'Access);
      Test_Support.Add
        (Suite, "function stores: local events",
         Local_Events'Access);
      Test_Support.Add
        (Suite, "function stores: explicit global store",
         Explicit_Global_Store'Access);
      Test_Support.Add
        (Suite, "function stores: explicit global metadata",
         Explicit_Global_Metadata'Access);
      Test_Support.Add
        (Suite, "function stores: ordinary metadata",
         Ordinary_Metadata'Access);
   end Register;
end Function_Store_Tests;
