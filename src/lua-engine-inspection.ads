private package Lua.Engine.Inspection is
   function Short_Source (Source : String) return String;
   --  Format the pinned bounded Lua chunk identifier used by debug metadata
   --  and error prefixes. The result owns at most 59 display bytes.
   function Inspect
     (State : in out World; Activation : Frame_Access) return Values.Vector;
   --  Implement synchronous debug queries over owned logical activations.
   --  Returned identities refer to real stable cells, never movable vectors.
end Lua.Engine.Inspection;
