with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Hook_Registry_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Empty_Removal_Creates_Map;
   procedure Empty_Removal_Creates_Map is
   begin
      --  Even an initial removal initializes the real hook registry table.
      --  Its weak-key mode lives on the table used as its own metatable.
      Check
        ("assert(debug.getregistry()._HOOKKEY==nil);debug.sethook()" &
         ";local t=debug.getregistry()._HOOKKEY;assert(type(t)=='ta" &
         "ble' and getmetatable(t)==t and t.__mode=='k')");
   end Empty_Removal_Creates_Map;

   procedure Thread_Mapping;
   procedure Thread_Mapping is
   begin
      --  The registry entry is the actual callback for the addressed thread.
      --  Reflection returns that identity, and removal clears the entry.
      Check
        ("local co=coroutine.create(function()end);local h=function" &
         "()end;debug.sethook(co,h,'l');local t=debug.getregistry()" &
         "._HOOKKEY;assert(t[co]==h and debug.gethook(co)==h);debug" &
         ".sethook(co);assert(t[co]==nil and select('#',debug.getho" &
         "ok(co))==1)");
   end Thread_Mapping;

   procedure Replace_Callback;
   procedure Replace_Callback is
   begin
      --  A raw entry replacement takes effect without another sethook call.
      --  The next event and gethook both use the new actual function.
      Check
        ("local n=0;local co=coroutine.create(function()local x=1 e" &
         "nd);local old=function()error('stale hook')end;local new=" &
         "function()n=n+1 end;debug.sethook(co,old,'l');debug.getre" &
         "gistry()._HOOKKEY[co]=new;assert(debug.gethook(co)==new);" &
         "assert(coroutine.resume(co));assert(n>0)");
   end Replace_Callback;

   procedure Remove_Callback_Entry;
   procedure Remove_Callback_Entry is
   begin
      --  Removing an entry leaves the installed mask and count intact.
      --  No Lua callback runs, while gethook still returns its full triple.
      Check
        ("local co=coroutine.create(function()local x=1 end);debug." &
         "sethook(co,function()error('removed hook')end,'l',3);debu" &
         "g.getregistry()._HOOKKEY[co]=nil;local t=table.pack(debug" &
         ".gethook(co));assert(t.n==3 and t[1]==nil and t[2]=='l' a" &
         "nd t[3]==3);assert(coroutine.resume(co))");
   end Remove_Callback_Entry;

   procedure Nonfunction_Callback;
   procedure Nonfunction_Callback is
   begin
      --  A callable table is not a Lua function for the hook dispatcher.
      --  Reflect its real entry but ignore it instead of invoking __call.
      Check
        ("local co=coroutine.create(function()local x=1 end);debug." &
         "sethook(co,function()end,'l');local value=setmetatable({}" &
         ",{__call=function()error('called table')end});debug.getre" &
         "gistry()._HOOKKEY[co]=value;local t=table.pack(debug.geth" &
         "ook(co));assert(t.n==3 and t[1]==value and t[2]=='l');ass" &
         "ert(coroutine.resume(co))");
   end Nonfunction_Callback;

   procedure Disabled_Callback_Retention;
   procedure Disabled_Callback_Retention is
   begin
      --  A valid empty-mask installation retains its registry value.
      --  The actual dispatcher is disabled, so gethook returns one nil.
      Check
        ("local co=coroutine.create(function()end);local h=function" &
         "()end;debug.sethook(co,h,'');assert(debug.getregistry()._" &
         "HOOKKEY[co]==h);local t=table.pack(debug.gethook(co));ass" &
         "ert(t.n==1 and t[1]==nil)");
   end Disabled_Callback_Retention;

   procedure Replaced_Closure_Collection;
   procedure Replaced_Closure_Collection is
   begin
      --  A live coroutine cannot retain a hidden copy of its old hook.
      --  Replace its registry callback and collect the removed closure.
      Check
        ("local weak=setmetatable({},{__mode='v'});local co=corouti" &
         "ne.create(function()end);do local old=function()end;weak[" &
         "1]=old;debug.sethook(co,old,'l')end;local new=function()e" &
         "nd;debug.getregistry()._HOOKKEY[co]=new;collectgarbage();" &
         "collectgarbage();assert(weak[1]==nil and debug.gethook(co" &
         ")==new)");
   end Replaced_Closure_Collection;

   procedure Thread_Callback_Ephemeron;
   procedure Thread_Callback_Ephemeron is
   begin
      --  The callback captures its own thread, forming an ephemeron cycle.
      --  With no external owner, neither the thread nor callback may survive.
      Check
        ("local weak=setmetatable({},{__mode='v'});do local co=coro" &
         "utine.create(function()end);local h=(function(t)return fu" &
         "nction()return t end end)(co);weak[1]=co;weak[2]=h;debug." &
         "sethook(co,h,'l')end;collectgarbage();collectgarbage();as" &
         "sert(weak[1]==nil and weak[2]==nil)");
   end Thread_Callback_Ephemeron;

   procedure Active_Callback_Root;
   procedure Active_Callback_Root is
   begin
      --  A hook replaces its own entry and collects before returning.
      --  Its active frame roots the former callback until return, after
      --  which collection releases it and subsequent events use the new one.
      Check
        ("local weak=setmetatable({},{__mode='v'});local n=0;local " &
         "co=coroutine.create(assert(load('local x=1\nx=2\nx=3')));" &
         "local next=function()n=n+1 end;do local h=function()debug" &
         ".getregistry()._HOOKKEY[coroutine.running()]=next;collect" &
         "garbage();assert(weak[1]~=nil)end;weak[1]=h;debug.sethook" &
         "(co,h,'l')end;assert(coroutine.resume(co));collectgarbage" &
         "();collectgarbage();assert(n>0 and weak[1]==nil)");
   end Active_Callback_Root;

   procedure Inherited_Controls;
   procedure Inherited_Controls is
   begin
      --  New threads inherit the parent's Lua dispatcher, mask and count.
      --  They receive no callback entry, so reflection returns nil with
      --  those controls and resumption does not invoke the parent's hook.
      Check
        ("local h=function()end;debug.sethook(h,'c',7);local co=cor" &
         "outine.create(function()local x=1 end);debug.sethook();lo" &
         "cal t=table.pack(debug.gethook(co));assert(t.n==3 and t[1" &
         "]==nil and t[2]=='c' and t[3]==7);assert(debug.getregistr" &
         "y()._HOOKKEY[co]==nil);assert(coroutine.resume(co))");
   end Inherited_Controls;

   procedure Inherited_Callback_Entry;
   procedure Inherited_Callback_Entry is
   begin
      --  Populate only the new child's inherited dispatcher mapping.
      --  It must deliver events with the inherited controls without a
      --  second sethook that would conceal missing inheritance.
      Check
        ("local n=0;debug.sethook(function()end,'l');local co=corou" &
         "tine.create(assert(load('local x=1\nx=2')));debug.sethook" &
         "();debug.getregistry()._HOOKKEY[co]=function()n=n+1 end;a" &
         "ssert(coroutine.resume(co));assert(n>0)");
   end Inherited_Callback_Entry;

   procedure Invalid_Replacement_Preserves;
   procedure Invalid_Replacement_Preserves is
   begin
      --  Invalid replacement arguments must preserve the prior installation.
      --  Inspect both its reflected controls and actual registry identity.
      Check
        ("local co=coroutine.create(function()end);local h=function" &
         "()end;debug.sethook(co,h,'cr',5);assert(not pcall(debug.s" &
         "ethook,co,{},'l'));local f,m,c=debug.gethook(co);assert(f" &
         "==h and m=='cr' and c==5);assert(debug.getregistry()._HOO" &
         "KKEY[co]==h)");
   end Invalid_Replacement_Preserves;

   procedure Independent_Thread_Entries;
   procedure Independent_Thread_Entries is
   begin
      --  Sibling coroutines have separate registry keys and callbacks.
      --  Replacing one entry cannot change the other's reflected function.
      Check
        ("local a=coroutine.create(function()end);local b=coroutine" &
         ".create(function()end);local x,y,z=function()end,function" &
         "()end,function()end;debug.sethook(a,x,'l');debug.sethook(" &
         "b,y,'c');debug.getregistry()._HOOKKEY[a]=z;assert(debug.g" &
         "ethook(a)==z and debug.gethook(b)==y)");
   end Independent_Thread_Entries;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "hook registry: Empty_Removal_Creates_Map",
         Empty_Removal_Creates_Map'Access);
      Test_Support.Add
        (Suite, "hook registry: Thread_Mapping",
         Thread_Mapping'Access);
      Test_Support.Add
        (Suite, "hook registry: Replace_Callback",
         Replace_Callback'Access);
      Test_Support.Add
        (Suite, "hook registry: Remove_Callback_Entry",
         Remove_Callback_Entry'Access);
      Test_Support.Add
        (Suite, "hook registry: Nonfunction_Callback",
         Nonfunction_Callback'Access);
      Test_Support.Add
        (Suite, "hook registry: Disabled_Callback_Retention",
         Disabled_Callback_Retention'Access);
      Test_Support.Add
        (Suite, "hook registry: Replaced_Closure_Collection",
         Replaced_Closure_Collection'Access);
      Test_Support.Add
        (Suite, "hook registry: Thread_Callback_Ephemeron",
         Thread_Callback_Ephemeron'Access);
      Test_Support.Add
        (Suite, "hook registry: Active_Callback_Root",
         Active_Callback_Root'Access);
      Test_Support.Add
        (Suite, "hook registry: Inherited_Controls",
         Inherited_Controls'Access);
      Test_Support.Add
        (Suite, "hook registry: Inherited_Callback_Entry",
         Inherited_Callback_Entry'Access);
      Test_Support.Add
        (Suite, "hook registry: Invalid_Replacement_Preserves",
         Invalid_Replacement_Preserves'Access);
      Test_Support.Add
        (Suite, "hook registry: Independent_Thread_Entries",
         Independent_Thread_Entries'Access);
   end Register;
end Hook_Registry_Tests;
