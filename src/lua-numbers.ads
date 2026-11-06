with Interfaces;
with Lua.Integers;

package Lua.Numbers is
   --  Numeric text is validated before asking Ada to convert it. In
   --  particular, Ada's underscores and based-literal syntax are not Lua
   --  syntax, while Lua's hexadecimal integers wrap at 64 bits.

   subtype Real_Value is Interfaces.IEEE_Float_64;
   subtype Integer_Value is Lua.Integers.Integer_Value;

   type Number_Kind is (Invalid, Integer_Number, Real_Number);
   type Number (Kind : Number_Kind := Invalid) is record
      case Kind is
         when Invalid => null;
         when Integer_Number => Integer_Item : Integer_Value;
         when Real_Number => Real_Item : Real_Value;
      end case;
   end record;
   --  Invalid is an ordinary failed conversion, not an Ada exception.

   function Read (Text : String; Base : Natural := 0) return Number;
   --  Parse Lua numeric text, allowing surrounding ASCII whitespace.
   --  @param Text Decimal/hexadecimal text, optionally signed.
   --  @param Base Zero selects Lua syntax; 2..36 selects integer-only syntax.
   --  @return The integer/real distinction, or Invalid for malformed input.
   --  @exception Storage_Error Temporary conversion storage was exhausted.

   function To_Real (Item : Number) return Real_Value
     with Pre => Item.Kind /= Invalid;
   --  Convert a valid number for operations requiring floating arithmetic.

   function Equal (Left, Right : Number) return Boolean
     with Pre => Left.Kind /= Invalid and then Right.Kind /= Invalid;
   --  Compare exactly across integer/float boundaries, without rounding ints.

   function Less (Left, Right : Number) return Boolean
     with Pre => Left.Kind /= Invalid and then Right.Kind /= Invalid;
   --  Ordered comparison with exact mixed-type boundaries and IEEE NaNs.
end Lua.Numbers;
