with AUnit.Assertions; use AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Characters.Latin_1;
with Interfaces.C;
with Lua.Conformance_Allocator;
with Lua.Engine; use Lua.Engine;
with Lua.Sessions.CLI;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.Sessions.CLI_Interrupt_Tests is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned_long;
   use type Lua.Storage.Byte_Count;
   LF : constant Character := Ada.Characters.Latin_1.LF;

   function Prepare return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_interrupt_prepare";
   function Restore return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_interrupt_restore";
   function Previous return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_interrupt_previous";
   function Active return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_cli_interrupt_test_active";
   function Arm_Count return Interfaces.C.unsigned_long
     with Import, Convention => C,
          External_Name => "lua_ada_cli_interrupt_test_arm_count";
   function Signal_Now (Pointer : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_interrupt_raise";
   function Signal_State (Pointer : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_interrupt_state";
   function Default_Disposition (Pointer : System.Address)
                                return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_interrupt_default";

   procedure Check
     (Source : String; Expected : Execution_Status := Succeeded;
      Setup : String := ""; After : String := "";
      Error : String := "interrupted!";
      Selected : Boolean := False; No_Arm : Boolean := False;
      Repeat : Boolean := False; Bounded_Work : Boolean := False);
   procedure Check
     (Source : String; Expected : Execution_Status := Succeeded;
      Setup : String := ""; After : String := "";
      Error : String := "interrupted!";
      Selected : Boolean := False; No_Arm : Boolean := False;
      Repeat : Boolean := False; Bounded_Work : Boolean := False)
   is
      Self : Session;
      Result : Execution_Result;
      Before : Interfaces.C.unsigned_long;

      procedure Cleanup;
      procedure Cleanup is
         Restored : constant Interfaces.C.int := Restore;
      begin
         Self.Close;
         Conformance_Allocator.Finish;
         Assert (Restored = 1, "failed to restore test signal disposition");
         Assert (Conformance_Allocator.Measurements.Bytes = 0 and then
                 Conformance_Allocator.Measurements.Blocks = 0,
                 "interrupt execution retained provider storage");
      end Cleanup;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Assert (Prepare = 1, "cannot prepare prior signal disposition");
      --  Real C callbacks use the ordinary typed guard, then raise the actual
      --  process SIGINT. The helper refuses to raise if no CLI lease is armed,
      --  so an ordering regression fails a case instead of killing AUnit.
      Set (Self.State.all, Global_Environment (Self.State.all),
           New_String (Self.State.all, "signal_now"),
           (Foreign_Function_Kind, Signal_Now'Address));
      Set (Self.State.all, Global_Environment (Self.State.all),
           New_String (Self.State.all, "signal_state"),
           (Foreign_Function_Kind, Signal_State'Address));
      Set (Self.State.all, Global_Environment (Self.State.all),
           New_String (Self.State.all, "signal_default"),
           (Foreign_Function_Kind, Default_Disposition'Address));
      if Setup'Length /= 0 then
         Result := Self.Execute (Setup, "=interrupt-setup");
         Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      end if;
      if Bounded_Work then
         Self.Set_Limits ((Instructions => 500, others => <>));
      end if;
      Before := Arm_Count;
      for Pass in 1 .. (if Repeat then 2 else 1) loop
         if Selected then
            Result := CLI.Execute_Selected_Script
              (Self, Source, "@interrupt-script.lua");
         else
            Result := CLI.Execute (Self, Source, "=interrupt-case");
         end if;
         Assert (Result.Status = Expected,
                 "unexpected interrupt result: " &
                 To_String (Result.Error.Message));
         Assert (Active = 0, "CLI signal lease survived its host boundary");
         Assert (Previous = 1, "prior SIGINT handler was not restored");
      end loop;
      if No_Arm then
         Assert (Arm_Count = Before,
                 "compilation/argument lookup armed SIGINT before docall");
      end if;
      if Expected = Runtime_Error then
         Assert (Index (Result.Error.Message, Error) > 0,
                 "unhandled interrupt lost its native message");
      end if;
      if After'Length /= 0 then
         Result := Self.Execute (After, "=interrupt-after");
         Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      end if;
      Cleanup;
   exception
      when others => Cleanup; raise;
   end Check;

   procedure Protected_Interrupt;
   procedure Protected_Interrupt is
   begin
      --  The first real signal becomes a normal pcall error at the next Lua
      --  boundary. Code after the interrupted call cannot run, and the process
      --  disposition remains default until this one docall region finishes.
      Check ("local ran=false;local ok,e=pcall(function() " &
        "signal_now();ran=true end);assert(not ok and not ran);" &
        "assert(e:find('interrupted!',1,true));assert(signal_default())");
   end Protected_Interrupt;

   procedure Unhandled_Interrupt;
   procedure Unhandled_Interrupt is
   begin
      Check ("signal_now();error('unreachable')", Runtime_Error);
   end Unhandled_Interrupt;

   procedure Closing_Interrupt;
   procedure Closing_Interrupt is
   begin
      Check ("closed=0;local ok,e=pcall(function() " &
        "local x<close> =setmetatable({},{__close=function(_,err) " &
        "closed=closed+1;assert(err:find('interrupted!',1,true)) end});" &
        "signal_now() end);assert(not ok and closed==1)",
        After => "assert(closed==1);assert(not signal_state())");
   end Closing_Interrupt;

   procedure Count_Hook_Interrupt;
   procedure Count_Hook_Interrupt is
   begin
      Check ("local done=false;local ok,e=pcall(function() " &
        "debug.sethook(function() if not done then signal_now();" &
        "done=true end end,'',1);while true do end end);" &
        "assert(not ok and done and debug.gethook()==nil)");
   end Count_Hook_Interrupt;

   procedure Line_Hook_Interrupt;
   procedure Line_Hook_Interrupt is
   begin
      Check ("local done=false;local ok,e=pcall(function()" & LF &
        "debug.sethook(function() if not done then signal_now();" &
        "done=true end end,'l')" & LF & "while true do end end);" &
        "assert(not ok and done and debug.gethook()==nil)");
   end Line_Hook_Interrupt;

   procedure Return_Hook_Interrupt;
   procedure Return_Hook_Interrupt is
   begin
      Check ("local done=false;local ok,e=pcall(function() " &
        "debug.sethook(function(event) if event=='return' and not done " &
        "then signal_now();done=true end end,'r');" &
        "local function f() return 7 end;local x=f() end);" &
        "assert(not ok and done and debug.gethook()==nil)");
   end Return_Hook_Interrupt;

   procedure Finalizer_Interrupt;
   procedure Finalizer_Interrupt is
   begin
      --  Native collection suppresses hooks while __gc executes. A request
      --  raised there must let that real callback finish before the next
      --  eligible boundary delivers the interrupt to its protected caller.
      Check ("local done=false;local ok,e=pcall(function() do local x=" &
        "setmetatable({},{__gc=function() signal_now();done=true end}) " &
        "end;collectgarbage();error('unreachable') end);" &
        "assert(not ok and done and e:find('interrupted!',1,true))");
   end Finalizer_Interrupt;

   procedure Coroutine_Target;
   procedure Coroutine_Target is
   begin
      --  Native docall's globalL is fixed. A child's own instructions must
      --  finish/yield before the interrupted parent consumes that request.
      Check ("local child=false;local co;local ok,e=pcall(function() " &
        "co=coroutine.create(function() signal_now();child=true;" &
        "coroutine.yield(9) end);coroutine.resume(co);error('unreachable') " &
        "end);assert(not ok and child);" &
        "assert(coroutine.status(co)=='suspended')");
   end Coroutine_Target;

   procedure Repeated_Execution;
   procedure Repeated_Execution is
   begin
      Check ("local ok,e=pcall(signal_now);assert(not ok and " &
        "e:find('interrupted!',1,true))", Repeat => True);
   end Repeated_Execution;

   procedure Syntax_Not_Armed;
   procedure Syntax_Not_Armed is
   begin
      Check ("local =", Syntax_Error, No_Arm => True);
   end Syntax_Not_Armed;

   procedure Arguments_Not_Armed;
   procedure Arguments_Not_Armed is
   begin
      Check ("error('unreachable')", Runtime_Error, Selected => True,
        Setup => "arg=setmetatable({},{__len=function() " &
          "local active=signal_state();assert(not active);" &
          "error('argument witness') end})", Error => "argument witness",
        No_Arm => True);
   end Arguments_Not_Armed;

   procedure Exit_Without_Close;
   procedure Exit_Without_Close is
   begin
      Check ("os.exit(37,false)", Exit_Requested);
   end Exit_Without_Close;

   procedure Exit_With_Close;
   procedure Exit_With_Close is
   begin
      Check ("os.exit(37,true)", Exit_Requested);
   end Exit_With_Close;

   procedure Host_Quota;
   procedure Host_Quota is
   begin
      Check ("pcall(function() while true do end end)", Resource_Error,
             Bounded_Work => True);
   end Host_Quota;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "CLI interrupt: pcall catches first real SIGINT",
         Protected_Interrupt'Access);
      Test_Support.Add
        (Suite, "CLI interrupt: unhandled diagnostic and restore",
         Unhandled_Interrupt'Access);
      Test_Support.Add (Suite, "CLI interrupt: closer sees error exactly once",
                        Closing_Interrupt'Access);
      Test_Support.Add
        (Suite, "CLI interrupt: count hook finishes then clears",
         Count_Hook_Interrupt'Access);
      Test_Support.Add (Suite, "CLI interrupt: line hook finishes then clears",
                        Line_Hook_Interrupt'Access);
      Test_Support.Add
        (Suite, "CLI interrupt: return hook finishes then clears",
         Return_Hook_Interrupt'Access);
      Test_Support.Add (Suite, "CLI interrupt: finalizer finishes first",
                        Finalizer_Interrupt'Access);
      Test_Support.Add (Suite, "CLI interrupt: fixed resumer context",
                        Coroutine_Target'Access);
      Test_Support.Add (Suite, "CLI interrupt: repeated independent regions",
                        Repeated_Execution'Access);
      Test_Support.Add (Suite, "CLI interrupt: syntax failure never arms",
                        Syntax_Not_Armed'Access);
      Test_Support.Add (Suite, "CLI interrupt: argument lookup never arms",
                        Arguments_Not_Armed'Access);
      Test_Support.Add (Suite, "CLI interrupt: no-close exit restores owner",
                        Exit_Without_Close'Access);
      Test_Support.Add (Suite, "CLI interrupt: close exit ends lease first",
                        Exit_With_Close'Access);
      Test_Support.Add (Suite, "CLI interrupt: host quota stays uncatchable",
                        Host_Quota'Access);
   end Register;
end Lua.Sessions.CLI_Interrupt_Tests;
