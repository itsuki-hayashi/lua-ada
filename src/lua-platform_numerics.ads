private package Lua.Platform_Numerics is
   function Power (Left, Right : Long_Float) return Long_Float
     with Import, Convention => C, External_Name => "pow";
   --  Use the host binary64 pow primitive used by the pinned C oracle.
   --  GNAT's generic real exponentiation has a different negative-domain
   --  contract and can round differently even for positive operands. This
   --  narrow libm adapter contains no language logic; see ADR 0005.
end Lua.Platform_Numerics;
