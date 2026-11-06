with Interfaces.C;

private package Lua.Platform_Numerics is
   pragma Linker_Options ("-lm");
   --  Carry the math dependency to static Ada consumers as well as shared
   --  builds. It cannot be inferred from this foreign symbol's declaration.

   function Divide (Left, Right : Interfaces.C.double)
                    return Interfaces.C.double
     with Import, Convention => C, External_Name => "lua_ada_host_divide";
   --  Preserve native IEEE exceptional results without disabling Ada checks.
   --  The tiny host adapter performs one arithmetic operation; all Lua
   --  conversion and dispatch remain in Ada. See ADR 0011.

   function Remainder (Left, Right : Interfaces.C.double)
                       return Interfaces.C.double
     with Import, Convention => C, External_Name => "fmod";
   --  Host truncated-quotient remainder, before Lua's sign correction.
   --  Unlike an Ada remainder attribute, this preserves host domain NaNs.

   function Power (Left, Right : Interfaces.C.double)
                   return Interfaces.C.double
     with Import, Convention => C, External_Name => "pow";
   --  Use the host binary64 pow primitive used by the pinned C oracle.
   --  GNAT's generic real exponentiation has a different negative-domain
   --  contract and can round differently even for positive operands. This
   --  narrow libm adapter contains no language logic; see ADR 0005.
end Lua.Platform_Numerics;
