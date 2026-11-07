with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.C_Operator_Tests is
   use type Lua.Storage.Byte_Count;
   function Add_Callback return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_operator_add";
   function Less_Callback return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_operator_less";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Arithmetic_Budget;
   procedure Comparison_Budget;
   procedure Check_Budget (Callback : Foreign.C_Function; Handler : String);

   procedure Check_Budget (Callback : Foreign.C_Function; Handler : String) is
      State : World;
      Item : Value;
   begin
      --  A real C function calls the public operator API. Its Lua handler
      --  must consume the same bounded driver's work; neither the private
      --  operator phase nor C lua_call may replace that budget or expose a
      --  catchable result when the host stops the handler.
      Initialize (State, (Instructions => 1_000, others => <>));
      Begin_Operation (State);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Callback);
      Set (State, Global_Environment (State), New_String (State, "operate"),
           Item);
      End_Operation (State);
      Assert (not Execute (State,
        "local a=setmetatable({},{" & Handler & "=function() " &
        "for i=1,100000 do end;return 37 end});" &
        "pcall(operate,a,1);error('operator quota was caught')",
        "C-operator-budget"), "public C handler shares host work quota");
      Assert (State.Current.Failure_Class = Host_Abort,
              "operator host abort remains uncatchable across C portal");
      Assert (Execute (State, "return 37", "C-operator-recovery"),
              To_String (State.Current.Failure_Text));
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "operator abort retires helper/guard/driver owners");
   exception
      when others => Finalize (State); raise;
   end Check_Budget;

   procedure Arithmetic_Budget is
   begin
      Check_Budget (Add_Callback, "__add");
   end Arithmetic_Budget;

   procedure Comparison_Budget is
   begin
      Check_Budget (Less_Callback, "__lt");
   end Comparison_Budget;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "C arithmetic: same-driver handler quota",
                        Arithmetic_Budget'Access);
      Test_Support.Add (Suite, "C comparison: same-driver handler quota",
                        Comparison_Budget'Access);
   end Register;
end Lua.C_Operator_Tests;
