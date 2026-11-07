with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Test_Support;

package body Lua.C_Base_Closing_Tests is
   use type Interfaces.C.int;
   function Check (Which : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_base_closing";
   procedure Set_Top;
   procedure Close_Slot;
   procedure Reverse_Order;
   procedure Actual_Slot;
   procedure Registration_Refusal;
   procedure Grown_Registration;
   procedure Callback_Registration;
   procedure False_Registration;
   procedure Thread_Query;
   procedure Prefix_Collection;
   procedure State_Close;
   procedure Callback_Result;
   procedure Callback_Error;

   --  These exercise the real C entrypoints and selected allocator. The
   --  shared fixture describes each setup/action/observation and is also
   --  compiled unchanged against native Lua's default and T configurations.
   procedure Set_Top is
   begin
      Assert (Check (0) = 1, "host settop closes its actual base slot");
   end Set_Top;
   procedure Close_Slot is
   begin
      Assert (Check (1) = 1, "closeslot closes once and writes nil");
   end Close_Slot;
   procedure Reverse_Order is
   begin
      Assert (Check (2) = 1, "host closing follows reverse registration");
   end Reverse_Order;
   procedure Actual_Slot is
   begin
      Assert (Check (3) = 1, "closing reads the actual replaced scalar");
   end Actual_Slot;
   procedure Registration_Refusal is
   begin
      Assert (Check (4) = 1, "first valid base registration allocates zero");
   end Registration_Refusal;
   procedure Grown_Registration is
   begin
      Assert (Check (5) = 1, "grown base registration allocates zero");
   end Grown_Registration;
   procedure Callback_Registration is
   begin
      Assert (Check (6) = 1, "callback registration allocates zero");
   end Callback_Registration;
   procedure False_Registration is
   begin
      Assert (Check (7) = 1, "false/nil registration allocates zero");
   end False_Registration;
   procedure Thread_Query is
   begin
      Assert (Check (8) = 1, "Lua-created thread query allocates zero");
   end Thread_Query;
   procedure Prefix_Collection is
   begin
      Assert (Check (9) = 1, "close callback traces actual base prefix");
   end Prefix_Collection;
   procedure State_Close is
   begin
      Assert (Check (10) = 1, "state close consumes the live base closer");
   end State_Close;
   procedure Callback_Result is
   begin
      Assert (Check (11) = 1, "C return closes while retaining actual result");
   end Callback_Result;
   procedure Callback_Error is
   begin
      Assert (Check (12) = 1, "C error closes with the arbitrary error value");
   end Callback_Error;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "C base: settop closes", Set_Top'Access);
      Test_Support.Add (Suite, "C base: closeslot clears", Close_Slot'Access);
      Test_Support.Add (Suite, "C base: reverse order", Reverse_Order'Access);
      Test_Support.Add (Suite, "C base: actual scalar", Actual_Slot'Access);
      Test_Support.Add (Suite, "C base: first refusal",
                        Registration_Refusal'Access);
      Test_Support.Add (Suite, "C base: grown refusal",
                        Grown_Registration'Access);
      Test_Support.Add (Suite, "C callback: close registration refusal",
                        Callback_Registration'Access);
      Test_Support.Add (Suite, "C base: false registration",
                        False_Registration'Access);
      Test_Support.Add (Suite, "C thread: query refusal", Thread_Query'Access);
      Test_Support.Add (Suite, "C base: closing GC prefix",
                        Prefix_Collection'Access);
      Test_Support.Add (Suite, "C base: owning state close",
                        State_Close'Access);
      Test_Support.Add (Suite, "C callback: close retains return result",
                        Callback_Result'Access);
      Test_Support.Add (Suite, "C callback: close sees arbitrary error",
                        Callback_Error'Access);
   end Register;
end Lua.C_Base_Closing_Tests;
