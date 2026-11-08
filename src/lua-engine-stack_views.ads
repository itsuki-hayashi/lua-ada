private package Lua.Engine.Stack_Views is
   function Physical_Owner (Context : not null Context_Access)
                            return Frame_Access;
   --  Borrow the actual scalar owner independently of a C guard identity.
   --  Null denotes the host's base C prefix without a published frame.

   procedure Prepare_Hook (State : in out World; Window : not null
                           Frame_Access);
   --  Charge packet transitions before the transport window retires. This
   --  may report a budget failure; Borrow and Restore then need no quota.

   procedure Borrow
     (State : in out World; Context : not null Context_Access;
      Window : Frame_Access; Lease : in out Stack_View_Lease;
      Kind : Stack_View_Kind := Callback_View);
   --  Publish one synchronous view without executing callbacks or allocating.
   --  Window is null or the current real stack window. Hook_View preserves
   --  the actual C guard owner while exposing the interrupted scalar cells.
   --  The owner must Restore after the corresponding C guard acknowledges
   --  every normal/error/yield/host-abort transfer, before frame retirement.

   procedure Restore
     (State : in out World; Lease : in out Stack_View_Lease;
      Abandon : Boolean := False);
   --  Release exactly this embedded lease. Inactive leases are harmless.
   --  Hook-only temporary reservations are restored allocation-free; a real
   --  child error/closing window is never retired or cleared by this helper.
   --  Abandon suppresses execution-packet reconstruction after a genuinely
   --  transferred error/host stop; only normal return may resume that body.
end Lua.Engine.Stack_Views;
