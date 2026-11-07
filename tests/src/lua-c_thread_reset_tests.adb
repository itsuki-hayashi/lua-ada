with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.C_Thread_Reset_Tests is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Lua.Storage.Byte_Count;
   function Run_Case (Name : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_reset_case";
   function Reader_Callback return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_reset_reader";
   function Self_Callback return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_reset_self";
   function Install_Warning return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_reset_warn_install";
   function Clear_Warning return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_reset_warn_clear";
   procedure Reset_Counters
     with Import, Convention => C,
          External_Name => "lua_ada_test_reset_counters";
   function Returned return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_reset_returned";
   function Reader_Calls return Interfaces.C.unsigned
     with Import, Convention => C,
          External_Name => "lua_ada_test_reset_reads";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Check (Name : String);
   procedure Suspended_Lua;
   procedure Original_Error;
   procedure Close_Error;
   procedure Weak_Prefix;
   procedure Self_Nested;
   procedure Self_Reader;
   procedure Self_Warning;
   procedure Refused_C_Closer;
   procedure Refused_Multiple_Closers;
   procedure Refused_Closer_Error;
   procedure Recursive_Self_Close;
   procedure Reset_Memory_Recovery;
   procedure Borrowed_Reader;
   procedure Borrowed_Warning;
   procedure Shared_Close_Quota;
   procedure Borrowed (Mode : Positive);

   procedure Check (Name : String) is
      C_Name : aliased constant Interfaces.C.char_array :=
        Interfaces.C.To_C (Name);
   begin
      --  Each named protocol creates a real C-owned world, uses the selected
      --  counted provider and closes with zero blocks/bytes. The exact same
      --  fixture is also compiled against native Lua's two configurations.
      Assert (Run_Case (C_Name'Address) = 0, Name);
   end Check;

   procedure Suspended_Lua is
   begin
      Check ("suspended-lua");
   end Suspended_Lua;
   procedure Original_Error is
   begin
      Check ("original-error");
   end Original_Error;
   procedure Close_Error is
   begin
      Check ("closing-error");
   end Close_Error;
   procedure Weak_Prefix is
   begin
      Check ("weak-prefix-lifetime");
   end Weak_Prefix;
   procedure Self_Nested is
   begin
      Check ("self-close-nested");
   end Self_Nested;
   procedure Self_Reader is
   begin
      Check ("self-reader");
   end Self_Reader;
   procedure Self_Warning is
   begin
      Check ("self-warning");
   end Self_Warning;
   procedure Refused_C_Closer is
   begin
      Check ("c-closer-refusal");
   end Refused_C_Closer;

   procedure Refused_Multiple_Closers is
   begin
      Check ("multiple-closers-refusal");
   end Refused_Multiple_Closers;
   procedure Refused_Closer_Error is
   begin
      Check ("closer-error-refusal");
   end Refused_Closer_Error;
   procedure Recursive_Self_Close is
   begin
      Check ("recursive-self-close");
   end Recursive_Self_Close;
   procedure Reset_Memory_Recovery is
   begin
      Check ("reset-memory-recovery");
   end Reset_Memory_Recovery;

   procedure Borrowed (Mode : Positive) is
      State : World;
      Item : Value;
      procedure Install (Name : String; Callback : Foreign.C_Function);
      procedure Install (Name : String; Callback : Foreign.C_Function) is
      begin
         Item := New_Native (State, "foreign.callback");
         Item.Reference.Foreign_Handler := Address (Callback);
         Set (State, Global_Environment (State), New_String (State, Name),
              Item);
      end Install;
      Success : Boolean;
   begin
      Initialize
        (State, (Instructions => (if Mode = 3 then 1_000 else 100_000),
                 others => <>));
      Reset_Counters;
      Begin_Operation (State);
      Install ("reader_self", Reader_Callback);
      Install ("close_self", Self_Callback);
      Install ("install_warning", Install_Warning);
      Install ("clear_warning", Clear_Warning);
      End_Operation (State);
      if Mode = 1 then
         --  The reader's C guard sits above suspended Ada frontend owners.
         --  Self-close must finalize those owners and then resume the actual
         --  parent, while the C reader and its enclosing C body never return.
         Success := Execute (State,
           "local co=coroutine.create(function()reader_self();" &
           "error('C body returned')end);local ok,e=coroutine.resume(co);" &
           "assert(ok and e==nil and coroutine.status(co)=='dead')",
           "=borrowed-reader-self-close");
      elsif Mode = 2 then
         --  A queued warning has no fabricated foreign call frame. Its
         --  typed ACK restores the real borrowed window before resetting and
         --  running the pending Lua closer on this same Ada-owned driver.
         Success := Execute (State,
           "local closed=0;local co=coroutine.create(function()" &
           "local c <close> =setmetatable({},{__close=function()" &
           "closed=closed+1 end});install_warning();warn('close');" &
           "error('warning returned')end);local ok,e=coroutine.resume(co);" &
           "clear_warning();assert(ok and e==nil and closed==1)",
           "=borrowed-warning-self-close");
      else
         --  Closing executes ordinary Lua work on the original host budget.
         --  Its protected reset controller must not catch a host quota or
         --  replace that budget when the C body requests self termination.
         Success := Execute (State,
           "local co=coroutine.create(function()local c <close> =" &
           "setmetatable({},{__close=function()for i=1,100000 do end end});" &
           "close_self()end);pcall(coroutine.resume,co);" &
           "error('close quota was caught')", "=reset-close-quota");
      end if;
      if Mode = 3 then
         Assert (not Success and State.Current.Failure_Class = Host_Abort,
                 "reset closer bypassed or caught the original host quota");
      else
         Assert (Success, To_String (State.Current.Failure_Text));
      end if;
      if Mode = 1 then
         Assert (Reader_Calls = 2,
                 "partial reader did not refill before its self transfer");
      end if;
      Assert (Returned = 0, "an abandoned C body resumed after self close");
      Assert (Execute (State, "return 37", "=reset-recovery"),
              To_String (State.Current.Failure_Text));
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "borrowed reset leaked callback/frontend/frame ownership");
   exception
      when others => Finalize (State); raise;
   end Borrowed;

   procedure Borrowed_Reader is
   begin
      Borrowed (1);
   end Borrowed_Reader;
   procedure Borrowed_Warning is
   begin
      Borrowed (2);
   end Borrowed_Warning;
   procedure Shared_Close_Quota is
   begin
      Borrowed (3);
   end Shared_Close_Quota;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "C reset: suspended Lua", Suspended_Lua'Access);
      Test_Support.Add (Suite, "C reset: incoming error",
                        Original_Error'Access);
      Test_Support.Add (Suite, "C reset: closing error", Close_Error'Access);
      Test_Support.Add (Suite, "C reset: actual weak prefix",
                        Weak_Prefix'Access);
      Test_Support.Add (Suite, "C reset: nested C guards", Self_Nested'Access);
      Test_Support.Add (Suite, "C reset: reader cleanup", Self_Reader'Access);
      Test_Support.Add (Suite, "C reset: warning ACK", Self_Warning'Access);
      Test_Support.Add (Suite, "C reset: C closer refusal",
                        Refused_C_Closer'Access);
      Test_Support.Add (Suite, "C reset: repeated closer refusal",
                        Refused_Multiple_Closers'Access);
      Test_Support.Add (Suite, "C reset: error closer refusal",
                        Refused_Closer_Error'Access);
      Test_Support.Add (Suite, "C reset: recursive self close",
                        Recursive_Self_Close'Access);
      Test_Support.Add (Suite, "C reset: memory refusal recovery",
                        Reset_Memory_Recovery'Access);
      Test_Support.Add (Suite, "C reset: borrowed reader",
                        Borrowed_Reader'Access);
      Test_Support.Add (Suite, "C reset: borrowed warning",
                        Borrowed_Warning'Access);
      Test_Support.Add (Suite, "C reset: original close quota",
                        Shared_Close_Quota'Access);
   end Register;
end Lua.C_Thread_Reset_Tests;
