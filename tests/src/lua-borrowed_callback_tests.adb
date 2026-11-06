with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with System;
with Test_Support;

package body Lua.Borrowed_Callback_Tests is
   use type Interfaces.C.int;
   package C renames Interfaces.C;
   function Callback (Choice : C.int) return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_borrowed_callback";
   function Escaped_Body return C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_borrowed_escaped_body";
   function Entered_Body return C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_borrowed_entered_body";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Free_World is new Ada.Unchecked_Deallocation
     (World, World_Access);

   generic
      with procedure Action (State : World_Access);
   procedure Fixture;

   procedure Fixture is
      State : World_Access := new World;
   begin
      Initialize (State.all, (others => <>));
      begin
         Action (State);
      exception
         when others =>
            Finalize (State.all);
            Free_World (State);
            raise;
      end;
      Finalize (State.all);
      Free_World (State);
   end Fixture;

   procedure Install
     (State : in out World; Name : String; Choice : C.int);
   procedure Simple_Callback (State : World_Access);
   procedure Reentrant_Lua (State : World_Access);
   procedure Protected_Identity (State : World_Access);
   procedure Bounded_Host_Abort (State : World_Access);
   procedure Deferred_Warning_Reentry (State : World_Access);
   procedure Deferred_Warning_Error (State : World_Access);

   procedure Install
     (State : in out World; Name : String; Choice : C.int) is
   begin
      --  The public Ada API intentionally has no host callback registration
      --  surface yet. This private fixture installs an actual C code pointer
      --  into the same globals and driver that ordinary sessions execute.
      Set (State, Global_Environment (State), New_String (State, Name),
           (Foreign_Function_Kind, Address (Callback (Choice))));
   end Install;

   procedure Simple_Callback (State : World_Access) is
   begin
      --  Normal Ada execution must invoke the real C function, retain its
      --  actual argument window and consume its result without another Run.
      Install (State.all, "host", 0);
      Assert (Execute (State.all, "assert(host(20,22)==42)", "borrowed-add"),
              "Ada-owned execution could not call its C function");
   end Simple_Callback;

   procedure Reentrant_Lua (State : World_Access) is
   begin
      --  The C body calls Lua through lua_call. That nested API request must
      --  attach a boundary to the existing driver, retaining the same budget.
      Install (State.all, "host", 1);
      Assert (Execute (State.all,
        "assert(host(function(a,b)return a+b end)==42)", "borrowed-reentry"),
        "C-to-Lua reentry created or lost an interpreter boundary");
   end Reentrant_Lua;

   procedure Protected_Identity (State : World_Access) is
   begin
      --  A C lua_error abandons only C activations above its live guard.
      --  Ordinary Lua pcall receives the same arbitrary table, then recovers.
      Install (State.all, "host", 2);
      Assert (Execute (State.all,
        "local e={};local ok,r=pcall(host,e);assert(not ok and r==e)",
        "borrowed-error"), "C callback error lost protected identity");
      Install (State.all, "host", 0);
      Assert (Execute (State.all, "assert(host(20,22)==42)",
                       "borrowed-error-recovery"), "callback did not recover");
   end Protected_Identity;

   procedure Bounded_Host_Abort (State : World_Access) is
      Succeeded : Boolean;
   begin
      --  Both the Lua caller and C body protect the infinite inner chunk.
      --  A host quota remains uncatchable: neither can continue, and the Ada
      --  host survives with a structured resource failure and usable session.
      Install (State.all, "host", 3);
      State.Bounds.Instructions := 100;
      Succeeded := Execute (State.all,
        "pcall(host,function()while true do end end);error('continued')",
        "borrowed-quota");
      Assert (not Succeeded and then State.Current.Failure_Class = Host_Abort,
              "bounded C-to-Lua execution returned a catchable error");
      Assert (Entered_Body = 1 and then Escaped_Body = 0,
              "C protected body caught or escaped the host abort");
      State.Bounds.Instructions := 10_000;
      Install (State.all, "host", 0);
      Assert (Execute (State.all, "assert(host(20,22)==42)",
                       "borrowed-quota-recovery"),
              "host abort poisoned state");
   end Bounded_Host_Abort;

   procedure Deferred_Warning_Reentry (State : World_Access) is
   begin
      --  This exercises the actual deferred C pump, not a queue simulation.
      --  The outer warnf runs nested Lua warn code while its own string and
      --  argument window remain borrowed and rooted by the original frame.
      Install (State.all, "install_warning", 4);
      Install (State.all, "check_warning", 5);
      Assert (Execute (State.all,
        "install_warning();warn('outer','last');check_warning()",
        "borrowed-warning-reentry"), "deferred warning reentry failed");
   end Deferred_Warning_Reentry;

   procedure Deferred_Warning_Error (State : World_Access) is
   begin
      --  warnf throws a registry-rooted table through its C guard. Its actual
      --  origin then fails through ordinary Lua pcall without a dummy frame.
      Install (State.all, "install_error_warning", 6);
      Assert (Execute (State.all,
        "local e={};install_error_warning(e);" &
        "local ok,r=pcall(warn,'failure');assert(not ok and r==e)",
        "borrowed-warning-error"), "warning error lost its Lua identity");
   end Deferred_Warning_Error;

   procedure Simple_Case is new Fixture (Simple_Callback);
   procedure Reentry_Case is new Fixture (Reentrant_Lua);
   procedure Protection_Case is new Fixture (Protected_Identity);
   procedure Abort_Case is new Fixture (Bounded_Host_Abort);
   procedure Warning_Case is new Fixture (Deferred_Warning_Reentry);
   procedure Warning_Error_Case is new Fixture (Deferred_Warning_Error);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "borrowed C: ordinary Ada execution",
                        Simple_Case'Access);
      Test_Support.Add (Suite, "borrowed C: nested Lua call",
                        Reentry_Case'Access);
      Test_Support.Add (Suite, "borrowed C: protected error identity",
                        Protection_Case'Access);
      Test_Support.Add (Suite, "borrowed C: host abort and recovery",
                        Abort_Case'Access);
      Test_Support.Add (Suite, "borrowed C: deferred warning reentry",
                        Warning_Case'Access);
      Test_Support.Add (Suite, "borrowed C: deferred warning error",
                        Warning_Error_Case'Access);
   end Register;
end Lua.Borrowed_Callback_Tests;
