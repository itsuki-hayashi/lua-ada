package Lua.Engine.Pattern_Drivers is
   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action;
   --  Resume string pattern iterators/replacements. Pending Lua calls are
   --  returned to the VM; this driver never recursively enters the executor.
end Lua.Engine.Pattern_Drivers;
