with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.C_Conversion_Tests is
   use type Lua.Storage.Byte_Count;
   function Callback return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_convert_number";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Shared_Scan_Budget;

   procedure Shared_Scan_Budget is
      State : World;
      Function_Value, Source : Value;
   begin
      --  Set up the long immutable payload outside execution. An actual C
      --  callback then asks lua_stringtonumber to parse it. Fixed scratch
      --  removes allocator growth, but cannot acquire a fresh work counter
      --  or turn the host's scan limit into a catchable pcall result.
      Initialize (State, (Instructions => 1_000, others => <>));
      Begin_Operation (State);
      Function_Value := New_Native (State, "foreign.callback");
      Function_Value.Reference.Foreign_Handler := Address (Callback);
      Set (State, Global_Environment (State),
           New_String (State, "convert_number"), Function_Value);
      Source := New_String (State, "1" & String'(1 .. 10_000 => '0') &
                            ".0e-10000");
      Set (State, Global_Environment (State), New_String (State, "source"),
           Source);
      End_Operation (State);
      Assert (not Execute (State,
        "pcall(convert_number,source);error('scan quota was caught')",
        "numeric-C-scan-budget"), "C conversion shares original work quota");
      Assert (State.Current.Failure_Class = Host_Abort,
              "fixed numeric scratch does not bypass host scan limits");
      Assert (Execute (State, "return 37", "numeric-C-scan-recovery"),
              To_String (State.Current.Failure_Text));
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "quota recovery retires real C records and numeric scratch");
   exception
      when others => Finalize (State); raise;
   end Shared_Scan_Budget;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "C numeric conversion: shared scan work budget",
         Shared_Scan_Budget'Access);
   end Register;
end Lua.C_Conversion_Tests;
