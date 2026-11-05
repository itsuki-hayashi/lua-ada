package Lua.Engine.Machine is
   procedure Run (State : in out World; Code : Prototype_Access);
   --  Execute on an explicit frame stack; collection occurs at safe points.

   procedure Clear_Frames (State : in out World);
   --  Release all frame-owned packets after success or failed execution.
end Lua.Engine.Machine;
