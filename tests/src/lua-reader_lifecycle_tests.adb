with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.Reader_Lifecycle_Tests is
   use type Lua.Storage.Byte_Count;
   function Close_Self (State : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_reader_self_close";
   function Direct_Load (State : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_reader_direct_load";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);

   procedure Check (Partial : Boolean; Direct : Boolean := False);
   procedure Check (Partial : Boolean; Direct : Boolean := False) is
      State : World;
      Item : Value;
      Success : Boolean;
   begin
      Initialize (State, (others => <>));
      Begin_Operation (State);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Close_Self'Access);
      Set (State, Global_Environment (State),
           New_String (State, "reader_close_self"), Item);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Direct_Load'Access);
      Set (State, Global_Environment (State),
           New_String (State, "reader_direct_load"), Item);
      Set (State, Global_Environment (State),
           New_String (State, "reader_partial"), (Boolean_Kind, Partial));
      Set (State, Global_Environment (State),
           New_String (State, "reader_direct"), (Boolean_Kind, Direct));
      End_Operation (State);
      --  Unlike a native default-allocator semantic trial, this owner counts
      --  every selected byte. A real C callback resets the active coroutine
      --  while its Lua load reader/parser and optional direct-C view wait.
      Success := Execute (State,
        "local closed=0;local co=coroutine.create(function()" &
        "local guard<close> = setmetatable({}," &
        "{__close=function()closed=closed+1 end});local n=0;" &
        "local loader=reader_direct and reader_direct_load or load;" &
        "return loader(function()n=n+1;" &
        "if reader_partial and n==1 then return 'local value = ' end;" &
        "reader_close_self();error('self-closed reader resumed')end)end);" &
        "local result=table.pack(coroutine.resume(co));" &
        "assert(result.n==1 and result[1]==true and closed==1);" &
        "assert(coroutine.status(co)=='dead');" &
        "assert(assert(load('return 79'))()==79)", "=reader-self-close");
      Assert (Success, Failure_Image (State.Current));
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0 and then
              Lua.Storage.Statistics (State.Memory).Raw_Bytes = 0,
              "self-close retained reader/parser/guard storage");
   exception
      when others =>
         End_Operation (State);
         Finalize (State);
         raise;
   end Check;

   procedure Empty_Reader;
   procedure Empty_Reader is
   begin
      --  Reset before any source arrives; neither the C nor Lua body resumes.
      Check (Partial => False);
   end Empty_Reader;

   procedure Partial_Reader;
   procedure Partial_Reader is
   begin
      --  Reset with an owned source prefix and partially constructed grammar.
      Check (Partial => True);
   end Partial_Reader;

   procedure Direct_Reader;
   procedure Direct_Reader is
   begin
      --  A saved builtin's hidden phase releases its actual borrowed C view.
      Check (Partial => True, Direct => True);
   end Direct_Reader;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "reader lifecycle: empty source self close",
         Empty_Reader'Access);
      Test_Support.Add
        (Suite, "reader lifecycle: partial source self close",
         Partial_Reader'Access);
      Test_Support.Add
        (Suite, "reader lifecycle: direct saved builtin self close",
         Direct_Reader'Access);
   end Register;
end Lua.Reader_Lifecycle_Tests;
