with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with Test_Support;

package body Lua.GC_Control_Tests is
   use type Lua.Storage.Byte_Count;

   generic
      with procedure Behavior (State : in out World);
   procedure Fixture;
   procedure Fixture is
      State : World;
   begin
      Initialize (State, (others => <>));
      begin
         Behavior (State);
      exception
         when others => Finalize (State); raise;
      end;
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "GC control fixture released all actual managed storage");
   end Fixture;

   procedure Check (State : in out World; Source : String);
   procedure Check (State : in out World; Source : String) is
   begin
      Assert (Execute (State, Source, "gc-control"),
              To_String (State.Current.Failure_Text));
   end Check;

   procedure Stop_And_Restart (State : in out World);
   procedure Actual_Count (State : in out World);
   procedure Mode_Results (State : in out World);
   procedure Parameter_Roundtrip (State : in out World);
   procedure C_Integer_Parameter (State : in out World);
   procedure C_String_Options (State : in out World);
   procedure Invalid_Options (State : in out World);
   procedure Lua_Step_Debt (State : in out World);
   procedure Finalizer_Drains_Before_Return (State : in out World);
   procedure Controls_Inside_Finalizer (State : in out World);
   procedure Finalizer_Resurrection (State : in out World);
   procedure Reenrollment (State : in out World);
   procedure Protected_Recovery (State : in out World);
   procedure Pattern_Callback_Roots (State : in out World);
   procedure Format_Callback_Roots (State : in out World);
   procedure Sorting_Callback_Roots (State : in out World);
   procedure Table_Callback_Roots (State : in out World);
   procedure Loading_Callback_Roots (State : in out World);
   procedure Leaving_Generation_Does_Not_Collect (State : in out World);

   procedure Stop_And_Restart (State : in out World) is
   begin
      --  Exercise real exported controls, including an explicit manual step
      --  while stopped. Manual work must not silently restart auto policy.
      Check (State,
        "assert(collectgarbage('isrunning')) " &
        "assert(collectgarbage('stop')==0) " &
        "assert(not collectgarbage('isrunning')) " &
        "assert(type(collectgarbage('step'))=='boolean') " &
        "assert(not collectgarbage('isrunning')) " &
        "assert(collectgarbage('restart')==0) " &
        "assert(collectgarbage('isrunning'))");
   end Stop_And_Restart;

   procedure Actual_Count (State : in out World) is
   begin
      --  Count is a real provider-byte observation. Large owned objects make
      --  it rise; reclaiming them must lower it despite retained registry
      --  capacity. No fabricated C byte-size or semantic stack estimate fits.
      Check (State,
        "local before=collectgarbage('count');local t={} " &
        "for i=1,300 do t[i]={i,string.rep('x',100)} end " &
        "local peak=collectgarbage('count');assert(peak>before) " &
        "t=nil;collectgarbage();assert(collectgarbage('count')<peak)");
   end Actual_Count;

   procedure Mode_Results (State : in out World) is
   begin
      --  Each call returns its actual preceding mode, even when unchanged.
      --  The code executes after real old/color normalization in both ways.
      Check (State,
        "assert(collectgarbage('incremental')=='incremental') " &
        "assert(collectgarbage('generational')=='incremental') " &
        "assert(collectgarbage('generational')=='generational') " &
        "assert(collectgarbage('incremental')=='generational') " &
        "assert(collectgarbage('incremental')=='incremental')");
   end Mode_Results;

   procedure Parameter_Roundtrip (State : in out World) is
   begin
      --  Lua5.5 owns six named encoded parameters, not Lua5.4's mode argument
      --  bundles. Set returns the previous decoded value; query is unchanged.
      Check (State,
        "local p=collectgarbage('param','stepmul',100);assert(p==200) " &
        "assert(collectgarbage('param','stepmul',255)==100) " &
        "assert(collectgarbage('param','stepmul')==250) " &
        "assert(collectgarbage('param','stepmul','100')==250) " &
        "for _,n in ipairs{'minormul','majorminor','minormajor'," &
        "'pause','stepmul','stepsize'} do " &
        "assert(type(collectgarbage('param',n))=='number') end");
   end Parameter_Roundtrip;

   procedure C_Integer_Parameter (State : in out World) is
   begin
      --  The pinned base wrapper narrows a Lua integer to native C int. Test
      --  its actual modulo/sign boundary without disabling Ada range checks.
      Check (State,
        "collectgarbage('param','stepmul',255) " &
        "assert(collectgarbage('param','stepmul',4294967396)==250) " &
        "assert(collectgarbage('param','stepmul')==100) " &
        "assert(collectgarbage('param','stepmul',2147483648)==100) " &
        "assert(collectgarbage('param','stepmul')==100)");
   end C_Integer_Parameter;

   procedure C_String_Options (State : in out World) is
   begin
      --  Option comparison has Lua's C-string boundary, while the source and
      --  ordinary Lua values remain binary safe. A complete prefix before
      --  NUL matches; truncating in the middle remains an ordinary error.
      Check (State,
        "assert(collectgarbage('stop\0ignored')==0) " &
        "assert(not collectgarbage('isrunning\0tail')) " &
        "assert(collectgarbage('param','pause\0tail')==250) " &
        "assert(not pcall(collectgarbage,'co\0unt')) " &
        "collectgarbage('restart')");
   end C_String_Options;

   procedure Invalid_Options (State : in out World) is
   begin
      --  Invalid names/types/integers are catchable language errors, rather
      --  than a status manufactured from an ignored option or Ada exception.
      Check (State,
        "local ok,e=pcall(collectgarbage,'unknown') " &
        "assert(not ok and string.find(e,'invalid option',1,true)) " &
        "assert(not pcall(collectgarbage,'param','unknown')) " &
        "assert(not pcall(collectgarbage,'step',1.5)) " &
        "assert(not pcall(collectgarbage,true))");
   end Invalid_Options;

   procedure Lua_Step_Debt (State : in out World) is
   begin
      --  Derived behavior from unchanged gc.lua53-74 (Lua5.5.1 MIT notice).
      --  Run the genuine Lua loop under the CLI-equivalent quota policy;
      --  separate bounded-session defaults remain covered by existing tests.
      Set_Policy (State, Lua_Compatible);
      Check (State,
        "collectgarbage('stop') " &
        "local function steps(n) collectgarbage();local a={} " &
        "for i=1,100 do a[i]={{}};local b={} end " &
        "local peak=collectgarbage('count');local count=0 " &
        "repeat count=count+1 until collectgarbage('step',n) " &
        "assert(collectgarbage('count')<peak);return count end " &
        "local fast=steps(10);local slow=steps(2);assert(fast<slow) " &
        "collectgarbage('restart')");
   end Lua_Step_Debt;

   procedure Finalizer_Drains_Before_Return (State : in out World) is
   begin
      --  Production setmetatable enrollment plus actual collector atomic
      --  separation must reach the scheduler and finish before this exported
      --  collectgarbage returns. No private queue injection is used here.
      Check (State,
        "local n=0;do local t=setmetatable({}," &
        "{__gc=function()n=n+1 end}) end " &
        "assert(collectgarbage()==0);assert(n==1)");
   end Finalizer_Drains_Before_Return;

   procedure Controls_Inside_Finalizer (State : in out World) is
   begin
      --  Internal collection controls are invalid inside a real finalizer.
      --  The pinned param base arm uniquely returns -1; validation still
      --  rejects an invalid spelling before the internal-stop result.
      Check (State,
        "local seen={};local pause=collectgarbage('param','pause') " &
        "do local t=setmetatable({}, {__gc=function() " &
        "seen[1]=collectgarbage('count')==nil " &
        "seen[2]=collectgarbage('param','pause',100)==-1 " &
        "seen[3]=not pcall(collectgarbage,'unknown') end}) end " &
        "collectgarbage();assert(seen[1] and seen[2] and seen[3]) " &
        "assert(collectgarbage('param','pause')==pause)");
   end Controls_Inside_Finalizer;

   procedure Finalizer_Resurrection (State : in out World) is
   begin
      --  A handler publishes its actual object into a global strong root.
      --  Releasing that resurrection does not enroll the handler a second
      --  time unless a later metatable operation deliberately requests it.
      Check (State,
        "local n=0;do local t=setmetatable({x=17},{__gc=function(o) " &
        "n=n+1;anchor=o end}) end;collectgarbage() " &
        "assert(n==1 and anchor.x==17);anchor=nil;collectgarbage() " &
        "assert(n==1)");
   end Finalizer_Resurrection;

   procedure Reenrollment (State : in out World) is
   begin
      --  Begin_Next clears enrollment before invocation. Reassigning the
      --  real metatable inside the first handler creates one new obligation;
      --  finishing the old callback must not erase that independent link.
      Check (State,
        "local n=0;do local t=setmetatable({}, {__gc=function(o) " &
        "n=n+1;if n==1 then setmetatable(o,getmetatable(o)) end " &
        "end}) end;collectgarbage();assert(n==1) " &
        "collectgarbage();assert(n==2)");
   end Reenrollment;

   procedure Protected_Recovery (State : in out World) is
   begin
      --  A failed native control call leaves normal session state usable for
      --  both later operations in the same chunk and another public execute.
      Check (State,
        "saved=37;assert(not pcall(collectgarbage,'param','bad')) " &
        "collectgarbage();assert(saved==37)");
      Check (State, "assert(saved==37);collectgarbage('step')");
   end Protected_Recovery;

   procedure Pattern_Callback_Roots (State : in out World) is
   begin
      --  Pattern captures and pending replacement results cross a real Lua
      --  callback safe point. Force collector work before each replacement
      --  result; the driver's owned capture packet must keep every byte value.
      Check (State,
        "local s=string.gsub('aba','(.)',function(c) " &
        "collectgarbage('step');return c..c end);assert(s=='aabbaa')");
   end Pattern_Callback_Roots;

   procedure Format_Callback_Roots (State : in out World) is
   begin
      --  The format specification survives its __tostring continuation while
      --  collector work runs inside the handler. Native result publication
      --  must retain both the specification and returned managed byte string.
      Check (State,
        "local t=setmetatable({}, {__tostring=function() " &
        "collectgarbage('step');return 'kept' end}) " &
        "assert(string.format('[%s]',t)=='[kept]')");
   end Format_Callback_Roots;

   procedure Sorting_Callback_Roots (State : in out World) is
   begin
      --  Sorting retains pivots and exchanged table identities outside their
      --  current source slots. A Lua comparator forcing GC must not invalidate
      --  those saved values or corrupt their stable identities/order.
      Check (State,
        "local t={{n=4},{n=1},{n=3},{n=2}} " &
        "table.sort(t,function(a,b) collectgarbage('step');" &
        "return a.n<b.n end) for i=1,4 do assert(t[i].n==i) end");
   end Sorting_Callback_Roots;

   procedure Table_Callback_Roots (State : in out World) is
   begin
      --  Table concat's __len/__index continuations retain the table and
      --  prior string results across subsequent lookups and collector work.
      Check (State,
        "local t=setmetatable({}, {__len=function()return 2 end," &
        "__index=function(_,i) collectgarbage('step');" &
        "return i==1 and 'a' or 'b' end}) " &
        "assert(table.concat(t,':')=='a:b')");
   end Table_Callback_Roots;

   procedure Loading_Callback_Roots (State : in out World) is
   begin
      --  A custom searcher/loader pair and a load reader suspend with live
      --  module data/source fragments. Real GC work inside each callback must
      --  preserve those owning continuation roots and the compiled closure.
      Check (State,
        "package.searchers[1]=function(name)collectgarbage('step');" &
        "return function(n,d)collectgarbage('step');" &
        "return {name=n,data=d} end,'kept' end " &
        "local m,d=require('fixture');assert(m.name=='fixture' " &
        "and m.data=='kept' and d=='kept') " &
        "local n=0;local f=assert(load(function()n=n+1;" &
        "collectgarbage('step');if n==1 then return 'return 17' end " &
        "end));assert(f()==17)");
   end Loading_Callback_Roots;

   procedure Leaving_Generation_Does_Not_Collect (State : in out World) is
   begin
      --  Leaving nursery mode repairs ages/colors; it does not secretly do
      --  a new full mark/separation or eagerly finalize otherwise deferred
      --  garbage. Explicit collect remains the real finalization trigger.
      Check (State,
        "collectgarbage('generational');local n=0 " &
        "do local t=setmetatable({}, {__gc=function()n=n+1 end}) end " &
        "collectgarbage('incremental');assert(n==0) " &
        "collectgarbage();assert(n==1)");
   end Leaving_Generation_Does_Not_Collect;

   procedure Stop_Case is new Fixture (Stop_And_Restart);
   procedure Count_Case is new Fixture (Actual_Count);
   procedure Mode_Case is new Fixture (Mode_Results);
   procedure Parameter_Case is new Fixture (Parameter_Roundtrip);
   procedure Integer_Case is new Fixture (C_Integer_Parameter);
   procedure Option_Case is new Fixture (C_String_Options);
   procedure Invalid_Case is new Fixture (Invalid_Options);
   procedure Debt_Case is new Fixture (Lua_Step_Debt);
   procedure Drain_Case is new Fixture (Finalizer_Drains_Before_Return);
   procedure Internal_Case is new Fixture (Controls_Inside_Finalizer);
   procedure Resurrection_Case is new Fixture (Finalizer_Resurrection);
   procedure Reenroll_Case is new Fixture (Reenrollment);
   procedure Recovery_Case is new Fixture (Protected_Recovery);
   procedure Pattern_Case is new Fixture (Pattern_Callback_Roots);
   procedure Format_Case is new Fixture (Format_Callback_Roots);
   procedure Sorting_Case is new Fixture (Sorting_Callback_Roots);
   procedure Table_Case is new Fixture (Table_Callback_Roots);
   procedure Loading_Case is new Fixture (Loading_Callback_Roots);
   procedure Leave_Case is new Fixture (Leaving_Generation_Does_Not_Collect);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "GC controls: stop restart manual policy",
                        Stop_Case'Access);
      Test_Support.Add (Suite, "GC controls: actual provider memory count",
                        Count_Case'Access);
      Test_Support.Add (Suite, "GC controls: previous real mode results",
                        Mode_Case'Access);
      Test_Support.Add (Suite, "GC controls: encoded parameter roundtrips",
                        Parameter_Case'Access);
      Test_Support.Add (Suite, "GC controls: C integer parameter narrowing",
                        Integer_Case'Access);
      Test_Support.Add (Suite, "GC controls: C-string option boundaries",
                        Option_Case'Access);
      Test_Support.Add (Suite, "GC controls: controlled argument failures",
                        Invalid_Case'Access);
      Test_Support.Add (Suite, "GC controls: real Lua byte-debt loop",
                        Debt_Case'Access);
      Test_Support.Add (Suite, "GC controls: scheduler drains before return",
                        Drain_Case'Access);
      Test_Support.Add (Suite, "GC controls: actual finalizer restrictions",
                        Internal_Case'Access);
      Test_Support.Add (Suite, "GC controls: real resurrection lifetime",
                        Resurrection_Case'Access);
      Test_Support.Add (Suite, "GC controls: handler reenrollment lifetime",
                        Reenroll_Case'Access);
      Test_Support.Add (Suite, "GC controls: protected session recovery",
                        Recovery_Case'Access);
      Test_Support.Add (Suite, "GC controls: actual pattern callback roots",
                        Pattern_Case'Access);
      Test_Support.Add (Suite, "GC controls: format callback continuation",
                        Format_Case'Access);
      Test_Support.Add (Suite, "GC controls: saved sorting callback values",
                        Sorting_Case'Access);
      Test_Support.Add (Suite, "GC controls: table callback continuation",
                        Table_Case'Access);
      Test_Support.Add (Suite, "GC controls: loading callback ownership",
                        Loading_Case'Access);
      Test_Support.Add (Suite, "GC controls: leaving minor repairs no full GC",
                        Leave_Case'Access);
   end Register;
end Lua.GC_Control_Tests;
