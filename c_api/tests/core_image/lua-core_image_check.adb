with Ada.Text_IO;
with Interfaces.C;
with Lua.Engine.Foreign;
with Lua.Sessions;
with Lua.Storage;
with System;

procedure Lua.Core_Image_Check is
   use type Interfaces.C.int;
   use type Interfaces.C.long_long;
   use type Lua.Engine.Foreign.Action_Status;
   use type Lua.Sessions.Execution_Status;
   use type System.Address;
   package Bridge renames Lua.Engine.Foreign;

   function Make return System.Address
     with Import, Convention => C, External_Name => "lua_ada_image_make";
   function Check
     (State, Pool : System.Address;
      Allocator : Lua.Storage.Allocation_Function) return Interfaces.C.int
     with Import, Convention => C, External_Name => "lua_ada_image_check";
   procedure Close (State : System.Address)
     with Import, Convention => C, External_Name => "lua_ada_image_close";
   procedure Check_Elaboration
     with Import, Convention => C,
          External_Name => "lua_ada_image_check_elaboration";

   State : System.Address;
   Output : aliased Bridge.Response;
   Input : aliased Bridge.Request :=
     (Operation => Bridge.Get_Top, others => <>);
   Universe : Lua.Sessions.Session;
begin
   --  Setup uses the public Ada host and then an independently constructed C
   --  state. These remain independent worlds inside the same compiled core.
   if Universe.Execute ("local n=40+2;assert(n==42)").Status /=
     Lua.Sessions.Succeeded
   then
      raise Program_Error with "Ada session failed in the core image";
   end if;
   Check_Elaboration;
   State := Make;

   --  Read the real C-created stack and its main-thread object through the
   --  actual Ada dispatcher. A duplicate image cannot own a separate registry
   --  or disguise thread identity merely by satisfying a public C wrapper.
   if Bridge.Dispatch (State, Input'Access, Output'Access) /=
     Bridge.Action_Done or else Output.Integer_Data /= 2
   then
      raise Program_Error with "Ada cannot inspect the C-created state";
   end if;
   Input := (Operation => Bridge.To_Thread, Index => -1, others => <>);
   if Bridge.Dispatch (State, Input'Access, Output'Access) /=
     Bridge.Action_Done or else Output.Pointer /= State
   then
      raise Program_Error with "Ada and C see different thread identities";
   end if;

   --  The opposite direction checks a real mutation, actual allocator-function
   --  identity, the actual private pool object and GNAT elaboration count. No
   --  production probe hook or test-modified interpreter library is needed.
   Input := (Operation => Bridge.Push_Integer, Integer_Data => 42,
             others => <>);
   if Bridge.Dispatch (State, Input'Access, Output'Access) /=
     Bridge.Action_Done
   then
      raise Program_Error with "Ada cannot mutate the C-created stack";
   end if;
   --  Compare the actual callback held by this world through both interfaces.
   --  A host's imported function address can name a Windows import thunk, so
   --  taking Default_Allocator'Access in the executable is not this assertion.
   Input := (Operation => Bridge.Get_Allocator, others => <>);
   if Bridge.Dispatch (State, Input'Access, Output'Access) /=
     Bridge.Action_Done or else
       Check (State, Lua.Storage.Pool'Address,
              Output.Allocator) /= 1
   then
      raise Program_Error with "C cannot observe Ada stack and pool identity";
   end if;
   Close (State);
   Check_Elaboration;
   Ada.Text_IO.Put_Line ("CORE IMAGE ADA+C OK");
end Lua.Core_Image_Check;
