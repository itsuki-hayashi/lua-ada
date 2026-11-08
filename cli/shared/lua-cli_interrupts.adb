with Interfaces.C;

package body Lua.CLI_Interrupts is
   use type Interfaces.C.int;
   use type Lua.Engine.World_Access;

   function Control (Operation : Lua.Engine.Interrupt_Operation)
                     return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_cli_interrupt_control";

   procedure Start
     (Self : in out Lease; State : not null Lua.Engine.World_Access)
   is
   begin
      if Self.Owner /= null then
         raise Program_Error with "active CLI interrupt lease";
      elsif Control (Lua.Engine.Arm_Interrupt) /= 1 then
         raise Program_Error with "cannot install CLI SIGINT disposition";
      end if;
      --  All writes below are scalar and cannot allocate. A signal arriving
      --  between installation and publication only sets the C pending flag;
      --  no handler can inspect this world or its partially published lease.
      Self.Previous_Controller := State.Interrupt_Controller;
      Self.Previous_Target := State.Interrupt_Target;
      Self.Owner := State;
      State.Interrupt_Controller := Control'Access;
      State.Interrupt_Target := State.Current;
   end Start;

   procedure Finish (Self : in out Lease) is
      Restored : Interfaces.C.int;
   begin
      if Self.Owner /= null then
         Restored := Control (Lua.Engine.Restore_Interrupt);
         --  Restore both scalar borrows even if the OS reports failure.
         --  Clear Owner before raising so scope finalization cannot retry a
         --  completed/failed restore against a released or replaced world.
         Self.Owner.Interrupt_Controller := Self.Previous_Controller;
         Self.Owner.Interrupt_Target := Self.Previous_Target;
         Self.Owner := null;
         Self.Previous_Controller := null;
         Self.Previous_Target := null;
         if Restored /= 1 then
            raise Program_Error with "cannot restore CLI SIGINT disposition";
         end if;
      end if;
   end Finish;

   overriding procedure Finalize (Self : in out Lease) is
   begin
      Finish (Self);
   end Finalize;
end Lua.CLI_Interrupts;
