with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Error_Closing_Tests is
   procedure Check (Source : String);
   procedure Check (Source : String) is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute (Source);
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Check;

   procedure Pcall_Replacement_Yields;
   procedure Pcall_Replacement_Yields is
   begin
      --  Resume each error closer through the real pcall continuation.
      Check
        ("local co=coroutine.wrap(function() return pcall(func" &
         "tion() local outer <close> =setmetatable({},{__close" &
         "=function(_,e) coroutine.yield('outer',e);error(e+20" &
         ") end}) local inner <close> =setmetatable({},{__clos" &
         "e=function(_,e) coroutine.yield('inner',e);error(e+1" &
         ") end}) error(10) end) end) local a,b=co();assert(a=" &
         "='inner' and b==10) a,b=co();assert(a=='outer' and b" &
         "==11) a,b=co();assert(a==false and b==31)");
   end Pcall_Replacement_Yields;

   procedure Abandoned_Tostring_Barrier;
   procedure Abandoned_Tostring_Barrier is
   begin
      --  A failed native tostring no longer owns a C body or caller.
      Check
        ("local co=coroutine.wrap(function() return pcall(func" &
         "tion() return tostring(setmetatable({},{__tostring=f" &
         "unction() local x <close> =setmetatable({},{__close=" &
         "function(_,e) assert(debug.getinfo(2,'f').func==pcal" &
         "l) coroutine.yield('closed',e) end}) error(17) end})" &
         ") end) end) local a,b=co();assert(a=='closed' and b=" &
         "=17) a,b=co();assert(a==false and b==17)");
   end Abandoned_Tostring_Barrier;

   procedure Pre_TBC_Local_Root;
   procedure Pre_TBC_Local_Root is
   begin
      --  The actual scalar prefix below a closing slot survives
      --  collection.
      Check
        ("local weak=setmetatable({},{__mode='v'}) local co=co" &
         "routine.wrap(function() return pcall(function() loca" &
         "l x={};weak[1]=x local c <close> =setmetatable({},{_" &
         "_close=function() collectgarbage();assert(weak[1]~=n" &
         "il);coroutine.yield('alive') end}) error(17) end) en" &
         "d) assert(co()=='alive');local a,b=co();assert(a==fa" &
         "lse and b==17) collectgarbage();assert(weak[1]==nil)");
   end Pre_TBC_Local_Root;

   procedure Post_TBC_Temporary_Release;
   procedure Post_TBC_Temporary_Release is
   begin
      --  Error closing discards abandoned locals above its selected slot.
      Check
        ("local weak=setmetatable({},{__mode='v'}) local co=co" &
         "routine.wrap(function() return pcall(function() loca" &
         "l c <close> =setmetatable({},{__close=function() col" &
         "lectgarbage();assert(weak[1]==nil);coroutine.yield('" &
         "gone') end}) local x={};weak[1]=x;error(17) end) end" &
         ") assert(co()=='gone');local a,b=co();assert(a==fals" &
         "e and b==17)");
   end Post_TBC_Temporary_Release;

   procedure Failed_Return_Result_Release;
   procedure Failed_Return_Result_Release is
   begin
      --  A failed close abandons the old return packet before outer GC.
      Check
        ("local weak=setmetatable({},{__mode='v'}) local co=co" &
         "routine.wrap(function() return pcall(function() loca" &
         "l outer <close> =setmetatable({},{__close=function(_" &
         ",e) assert(e==17);collectgarbage();assert(weak[1]==n" &
         "il) coroutine.yield('gone') end}) local inner <close" &
         "> =setmetatable({},{__close=function()error(17)end})" &
         " local function result()local x={};weak[1]=x;return " &
         "x end return result() end) end) assert(co()=='gone')" &
         ";local a,b=co();assert(a==false and b==17)");
   end Failed_Return_Result_Release;

   procedure Nested_Closing_Floor;
   procedure Nested_Closing_Floor is
   begin
      --  Inner protected closing retains the active outer closer's real
      --  prefix.
      Check
        ("local weak=setmetatable({},{__mode='v'}) local co=co" &
         "routine.wrap(function() return pcall(function() loca" &
         "l x={};weak[1]=x local outer <close> =setmetatable({" &
         "},{__close=function() local a,b=pcall(function() loc" &
         "al y={};weak[2]=y local inner <close> =setmetatable(" &
         "{},{__close=function() collectgarbage();assert(weak[" &
         "1] and weak[2]) coroutine.yield('inner') end}) error" &
         "(23) end) assert(a==false and b==23);collectgarbage(" &
         ") assert(weak[1] and weak[2]==nil);coroutine.yield('" &
         "outer') end}) error(17) end) end) assert(co()=='inne" &
         "r');assert(co()=='outer') local a,b=co();assert(a==f" &
         "alse and b==17) collectgarbage();assert(weak[1]==nil" &
         " and weak[2]==nil)");
   end Nested_Closing_Floor;

   procedure False_Normal_Close_Result;
   procedure False_Normal_Close_Result is
   begin
      --  A normal closer's false result is discarded before return.
      Check
        ("local co=coroutine.wrap(function() return pcall(func" &
         "tion() local c <close> =setmetatable({},{__close=fun" &
         "ction() coroutine.yield('closed');return false,99 en" &
         "d}) return 7 end) end) assert(co()=='closed');local " &
         "a,b=co();assert(a==true and b==7)");
   end False_Normal_Close_Result;

   procedure False_Error_Close_Result;
   procedure False_Error_Close_Result is
   begin
      --  A successful error closer cannot replace the error with its
      --  results.
      Check
        ("local co=coroutine.wrap(function() return pcall(func" &
         "tion() local c <close> =setmetatable({},{__close=fun" &
         "ction(_,e) assert(e==17);coroutine.yield('closed');r" &
         "eturn false,99 end}) error(17) end) end) assert(co()" &
         "=='closed');local a,b=co();assert(a==false and b==17" &
         ")");
   end False_Error_Close_Result;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "error closing: Pcall_Replacement_Yields",
         Pcall_Replacement_Yields'Access);
      Test_Support.Add
        (Suite, "error closing: Abandoned_Tostring_Barrier",
         Abandoned_Tostring_Barrier'Access);
      Test_Support.Add
        (Suite, "error closing: Pre_TBC_Local_Root",
         Pre_TBC_Local_Root'Access);
      Test_Support.Add
        (Suite, "error closing: Post_TBC_Temporary_Release",
         Post_TBC_Temporary_Release'Access);
      Test_Support.Add
        (Suite, "error closing: Failed_Return_Result_Release",
         Failed_Return_Result_Release'Access);
      Test_Support.Add
        (Suite, "error closing: Nested_Closing_Floor",
         Nested_Closing_Floor'Access);
      Test_Support.Add
        (Suite, "error closing: False_Normal_Close_Result",
         False_Normal_Close_Result'Access);
      Test_Support.Add
        (Suite, "error closing: False_Error_Close_Result",
         False_Error_Close_Result'Access);
   end Register;
end Error_Closing_Tests;
