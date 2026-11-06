package Lua.Engine.Warnings is
   procedure Emit
     (State : in out World; Message : Value;
      To_Continue : Boolean := False);
   procedure Emit
     (State : in out World; Message : Byte_String;
      Root : Value := Nil_Value; To_Continue : Boolean := False);
   --  Borrow a NUL-terminated message. Custom delivery retains Root in the
   --  actual origin frame until its C-owned callback acknowledges the event.
   --  Static views need no Root; neither overload copies the message bytes.

   function Pending (State : World) return Boolean;
   function Identity (State : World) return Callback_Identity;
   procedure Begin_Callback (State : in out World);
   procedure Acknowledge
     (State : in out World; Token : Callback_Identity);
   procedure Discard (State : in out World; Activation : Frame_Access);
   --  Events are embedded in existing native/driver frames, not allocated
   --  warning records. The linked event stack survives nested callbacks.

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action;
   --  Validate every warn argument before emitting its first fragment, then
   --  expose each custom callback as a separate scheduler phase.
end Lua.Engine.Warnings;
