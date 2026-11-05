package Lua.Engine.Compiler is
   function Compile
     (State : in out World; Source, Name : String) return Prototype_Access;
   --  Produce resolved private register code or record a located error.
   --  Compiler allocations are owned by State and collected on failed input.
end Lua.Engine.Compiler;
