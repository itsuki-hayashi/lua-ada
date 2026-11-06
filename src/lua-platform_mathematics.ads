with Interfaces.C;

private package Lua.Platform_Mathematics is
   pragma Linker_Options ("-lm");
   --  These are host binary64 primitives, not an imported Lua implementation.
   --  Ada elementary functions have exception-based domain contracts and may
   --  round differently from the host C library. Lua requires the latter's
   --  NaNs, infinities, signed zeros and rounding for all operations below.
   --  Language argument conversion and every RNG operation remain in Ada.

   function Sine (Item : Interfaces.C.double) return Interfaces.C.double
     with Import, Convention => C, External_Name => "sin";
   function Cosine (Item : Interfaces.C.double) return Interfaces.C.double
     with Import, Convention => C, External_Name => "cos";
   function Tangent (Item : Interfaces.C.double) return Interfaces.C.double
     with Import, Convention => C, External_Name => "tan";
   function Arc_Sine (Item : Interfaces.C.double) return Interfaces.C.double
     with Import, Convention => C, External_Name => "asin";
   function Arc_Cosine (Item : Interfaces.C.double) return Interfaces.C.double
     with Import, Convention => C, External_Name => "acos";
   function Arc_Tangent (Y, X : Interfaces.C.double)
                         return Interfaces.C.double
     with Import, Convention => C, External_Name => "atan2";
   function Logarithm (Item : Interfaces.C.double) return Interfaces.C.double
     with Import, Convention => C, External_Name => "log";
   function Logarithm_2 (Item : Interfaces.C.double)
                         return Interfaces.C.double
     with Import, Convention => C, External_Name => "log2";
   function Logarithm_10 (Item : Interfaces.C.double)
                          return Interfaces.C.double
     with Import, Convention => C, External_Name => "log10";
   function Exponential (Item : Interfaces.C.double)
                          return Interfaces.C.double
     with Import, Convention => C, External_Name => "exp";
   function Square_Root (Item : Interfaces.C.double)
                          return Interfaces.C.double
     with Import, Convention => C, External_Name => "sqrt";
   function Hyperbolic_Sine (Item : Interfaces.C.double)
                              return Interfaces.C.double
     with Import, Convention => C, External_Name => "sinh";
   function Hyperbolic_Cosine (Item : Interfaces.C.double)
                                return Interfaces.C.double
     with Import, Convention => C, External_Name => "cosh";
   function Hyperbolic_Tangent (Item : Interfaces.C.double)
                                 return Interfaces.C.double
     with Import, Convention => C, External_Name => "tanh";
   function Power (Left, Right : Interfaces.C.double)
                     return Interfaces.C.double
     with Import, Convention => C, External_Name => "pow";
   function Fraction
     (Item : Interfaces.C.double; Exponent : access Interfaces.C.int)
      return Interfaces.C.double
     with Import, Convention => C, External_Name => "frexp";
   --  The borrowed exponent pointer lives only for this synchronous call.
   function Scale
     (Item : Interfaces.C.double; Exponent : Interfaces.C.int)
      return Interfaces.C.double
     with Import, Convention => C, External_Name => "ldexp";
end Lua.Platform_Mathematics;
