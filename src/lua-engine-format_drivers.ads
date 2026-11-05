package Lua.Engine.Format_Drivers is
   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action;
   --  Format byte strings with resumable __tostring calls. All pending
   --  arguments and the conversion specification remain activation roots.
end Lua.Engine.Format_Drivers;
