private package Lua.Engine.Debug_Console is
   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action;
   --  Read fixed-size native debug commands and request their execution from
   --  the existing scheduler. Captures/results retain every value across
   --  compilation, protected execution and error-conversion callbacks.
end Lua.Engine.Debug_Console;
