private package Lua.Engine.Sorting is
   function Create
     (State : in out World; Arguments : Values.Vector) return Values.Vector;
   --  Validate C-int-sized capacity hints, then reserve actual owned storage.

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action;
   --  Iterative heapsort over real table accesses. Every pending value lives
   --  in traced activation captures before a Lua comparison/access callback.
end Lua.Engine.Sorting;
