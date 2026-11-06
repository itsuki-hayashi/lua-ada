private package Lua.Engine.Inspection is
   function Inspect
     (State : in out World; Activation : Frame_Access) return Values.Vector;
   --  Implement synchronous debug queries over owned logical activations.
   --  Returned identities refer to real stable cells, never movable vectors.
end Lua.Engine.Inspection;
