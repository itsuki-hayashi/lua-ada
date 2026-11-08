with Interfaces.C;
with System;

private package Lua.Platform_Numerics is
   pragma Linker_Options ("-lm");
   --  Carry the math dependency to static Ada consumers as well as shared
   --  builds. It cannot be inferred from this foreign symbol's declaration.

   function Pointer_Text
     (Pointer, Bytes : System.Address; Capacity : Interfaces.C.size_t;
      Width, Left : Interfaces.C.int)
      return Interfaces.C.size_t
     with Import, Convention => C,
          External_Name => "lua_ada_host_pointer_text";
   --  Native bounded %p spelling only, including the host's null spelling.
   --  No pointer is dereferenced and no Lua value or allocation is involved.

   function Divide (Left, Right : Interfaces.C.double)
                    return Interfaces.C.double
     with Import, Convention => C, External_Name => "lua_ada_host_divide";
   --  Preserve native IEEE exceptional results without disabling Ada checks.
   --  The tiny host adapter performs one arithmetic operation; all Lua
   --  conversion and dispatch remain in Ada. See ADR 0011.

   function General_Carry_Zeroes return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_host_general_carry_zeroes";
   --  Observe whether native alternate %g retains fractional zeroes when
   --  rounding moves fixed notation into scientific notation. This differs
   --  between libc implementations; no operating-system name decides it.
   --  Only spelling is probed; actual values and rounding remain in Ada.

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
