package Lua.Engine.Compiler is
   function Compile
     (State : in out World; Source, Name : String) return Prototype_Access;
   --  Parse/resolve owned syntax, then lower it to private register code.
   --  Syntax validation is shared with Lua.Syntax.Check; deferred features
   --  are rejected only after complete validation and before runtime effects.
   --  Compiler allocations are owned by State and collected on failed input.
end Lua.Engine.Compiler;
