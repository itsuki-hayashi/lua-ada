with Interfaces;
with Lua.Storage.Buffers;
with Lua.Storage.Vectors;

private package Lua.Big_Naturals is
   --  Exact nonnegative integers for binary64 conversion/formatting scratch.
   --  There is no implicit allocator and no signed or general-purpose numeric
   --  API. Limbs are little endian; zero owns no live limbs, and every other
   --  value has a nonzero highest limb. Copies retain their explicit owner.
   subtype Small is Interfaces.Unsigned_32;
   subtype Wide is Interfaces.Unsigned_64;
   subtype Power_Base is Small range 1 .. Small'Last;
   type Ordering is (Less_Than, Equal_To, Greater_Than);
   type Number is private;
   procedure Set_Owner
     (Self : in out Number; Memory : not null Lua.Storage.Owner_Access);
   function Owner_Of (Self : Number) return Lua.Storage.Owner_Access;
   procedure Set_Value (Self : in out Number; Value : Wide);
   function From_Unsigned
     (Memory : not null Lua.Storage.Owner_Access; Value : Wide) return Number;
   function Is_Zero (Self : Number) return Boolean;
   function Is_Odd (Self : Number) return Boolean;
   function Bit_Length (Self : Number) return Natural;
   function Compare (Left, Right : Number) return Ordering;
   --  Inspect normalized magnitudes without temporary strings/allocations.

   procedure Add (Self : in out Number; Value : Small);
   procedure Multiply (Self : in out Number; Factor : Small);
   procedure Multiply_Power
     (Self : in out Number; Base : Power_Base; Exponent : Natural);
   procedure Shift_Left (Self : in out Number; Count : Natural);
   procedure Shift_Right (Self : in out Number; Count : Natural);
   procedure Subtract (Self : in out Number; Value : Number);
   --  Mutations reserve all required growth before changing existing limbs.
   --  Subtract requires Self >= Value; violation raises Constraint_Error.

   procedure Divide
     (Numerator, Denominator : Number;
      Quotient, Remainder : in out Number);
   --  Exact Euclidean division; zero divisor raises Constraint_Error. Build
   --  both results before publication. Inputs can alias outputs, but the two
   --  outputs must be distinct. Returned buffers inherit Numerator's owner.
   function To_Unsigned (Self : Number) return Wide;
   --  @exception Constraint_Error The magnitude exceeds 64 bits.
   function Decimal_Digits (Self : Number) return Positive;
   procedure Decimal
     (Self : Number; Output : in out Lua.Storage.Buffers.Buffer);
   --  Render decimal bytes through the same explicit owner. The output owns
   --  no sign or Ada based-literal decoration, including the zero case.

private
   package Limb_Lists is new Lua.Storage.Vectors (Small, Interfaces."=");
   type Number is record
      Limbs : Limb_Lists.Vector;
   end record;
end Lua.Big_Naturals;
