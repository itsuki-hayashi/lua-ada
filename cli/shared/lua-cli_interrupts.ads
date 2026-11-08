with Ada.Finalization;
with Lua.Engine;

private package Lua.CLI_Interrupts is
   type Lease is new Ada.Finalization.Limited_Controlled with private;
   --  One serialized CLI docall region owns its process signal disposition
   --  and fixed Lua context. No Lua values, frame or C-stack address escapes.
   --  The owning world must remain alive until Finish or scope finalization;
   --  in particular, finalize before Apply_Exit can physically release it.

   procedure Start
     (Self : in out Lease; State : not null Lua.Engine.World_Access);
   --  Call only after successful load and argument lookup, immediately before
   --  the actual protected drive. Generic Driver.Start, compiler and argument
   --  callbacks do not arm SIGINT. No allocation or Lua callback occurs here.
   --  An overlapping lease or failing signal installation raises
   --  Program_Error before publishing any controller into the world.

   procedure Finish (Self : in out Lease);
   --  Restore the exact prior process disposition and world controller/target.
   --  Idempotent after success; failed OS restoration raises Program_Error
   --  after removing the world borrow. No Lua code or executor is invoked.

   overriding procedure Finalize (Self : in out Lease);
   --  Covers all exceptional/cancelled/typed-exit paths in the owning helper.
   --  A failing OS restoration is a host failure, not a caught Lua interrupt.

private
   type Lease is new Ada.Finalization.Limited_Controlled with record
      Owner : Lua.Engine.World_Access;
      Previous_Controller : Lua.Engine.Interrupt_Controller_Access;
      Previous_Target : Lua.Engine.Context_Access;
   end record;
end Lua.CLI_Interrupts;
