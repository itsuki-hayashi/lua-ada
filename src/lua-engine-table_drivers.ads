private package Lua.Engine.Table_Drivers is
   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action;
   --  Resume table helpers whose reads, writes, or length can invoke Lua.
   --  Captures own all intermediate objects across requested VM calls.
end Lua.Engine.Table_Drivers;
