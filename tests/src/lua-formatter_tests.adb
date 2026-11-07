with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.Formatter_Tests is
   use type Lua.Storage.Byte_Count;
   function Callback (Choice : Interfaces.C.int) return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_formatter";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Install (State : in out World; Choice : Interfaces.C.int);
   procedure Dispose (State : in out World);
   procedure Shared_Work_Quota;
   procedure String_Extent_Quota;

   procedure Install (State : in out World; Choice : Interfaces.C.int) is
      Item : Value;
   begin
      Begin_Operation (State);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Callback (Choice));
      Set (State, Global_Environment (State), New_String (State, "format"),
           Item);
      End_Operation (State);
   end Install;

   procedure Dispose (State : in out World) is
   begin
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "format buffer and C guard release all owned storage");
   end Dispose;

   procedure Shared_Work_Quota is
      State : World;
   begin
      --  A C callback scans a long foreign string through the real va_list
      --  export. Its work belongs to this driver; Lua pcall cannot catch the
      --  configured abort, and the temporary must be released before C jumps.
      Initialize (State, (Instructions => 200, others => <>));
      Install (State, 1);
      Assert (not Execute (State,
        "pcall(format); error('work abort was caught')", "format-work"),
        "foreign scanning must consume the original instruction budget");
      Assert (State.Current.Failure_Class = Host_Abort,
              "format work limit remains a host abort");
      Assert (Execute (State, "return 19", "format-work-recovery"),
              "raw guard restores the host after a formatter work abort");
      Dispose (State);
   exception
      when others => Finalize (State); raise;
   end Shared_Work_Quota;

   procedure String_Extent_Quota is
      State : World;
   begin
      --  The variadic export must enforce the same explicit per-string
      --  policy as Lua-created strings. A protected Lua caller cannot turn
      --  this configured limit into a catchable semantic allocation refusal.
      Initialize (State, (String_Bytes => 64, others => <>));
      Install (State, 2);
      Assert (not Execute (State,
        "pcall(format); error('size abort was caught')", "format-size"),
        "format output must obey the existing string extent policy");
      Assert (State.Current.Failure_Class = Host_Abort,
              "format extent limit remains a host abort");
      Assert (Execute (State, "return 23", "format-size-recovery"),
              "raw guard restores the host after a formatter extent abort");
      Dispose (State);
   exception
      when others => Finalize (State); raise;
   end String_Extent_Quota;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "C formatter: foreign scanning shares bounded work quota",
         Shared_Work_Quota'Access);
      Test_Support.Add
        (Suite, "C formatter: output obeys bounded string extent quota",
         String_Extent_Quota'Access);
   end Register;
end Lua.Formatter_Tests;
