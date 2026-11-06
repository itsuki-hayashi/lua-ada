with Lua.Number_Parsing;
with Lua.Storage;

package body Lua.Numbers is
   use type Real_Value;
   use type Integer_Value;

   function Read (Text : String; Base : Natural := 0) return Number is
      Memory : Lua.Storage.Owner;
   begin
      --  Host callers keep the original small interface. Runtime and scanner
      --  code call the same parser with their own explicit universe owner.
      return Lua.Number_Parsing.Read
        (Text, Lua.Storage.Reference (Memory), Base);
   exception
      when Lua.Storage.Allocation_Error =>
         raise Storage_Error with "numeric conversion storage exhausted";
      when Program_Error =>
         --  A failed controlled limb copy can be wrapped by Ada. Only the
         --  explicit provider witness identifies that as storage exhaustion;
         --  unrelated invariant failures retain their original exception.
         if Lua.Storage.Refusal_Pending (Memory) then
            raise Storage_Error with "numeric conversion storage exhausted";
         end if;
         raise;
   end Read;

   function To_Real (Item : Number) return Real_Value is
     (if Item.Kind = Integer_Number then Real_Value (Item.Integer_Item)
      else Item.Real_Item);

   function Equal (Left, Right : Number) return Boolean is
      I : Integer_Value;
      F : Real_Value;
   begin
      if Left.Kind = Integer_Number and then Right.Kind = Integer_Number then
         return Left.Integer_Item = Right.Integer_Item;
      elsif Left.Kind = Real_Number and then Right.Kind = Real_Number then
         return Left.Real_Item = Right.Real_Item;
      end if;
      I := (if Left.Kind = Integer_Number then Left.Integer_Item else
              Right.Integer_Item);
      F := (if Left.Kind = Real_Number then Left.Real_Item
            else Right.Real_Item);
      --  Above 2**53 integer-to-float conversion loses information. Compare
      --  only after checking that the float denotes an in-range exact int.
      if F /= F or else F < -2.0 ** 63 or else F >= 2.0 ** 63 or else
        Real_Value'Truncation (F) /= F
      then
         return False;
      end if;
      return I = Integer_Value (F);
   end Equal;

   function Less (Left, Right : Number) return Boolean is
      I : Integer_Value;
      F : Real_Value;
      Integer_First : constant Boolean := Left.Kind = Integer_Number;
   begin
      if Left.Kind = Integer_Number and then Right.Kind = Integer_Number then
         return Left.Integer_Item < Right.Integer_Item;
      elsif Left.Kind = Real_Number and then Right.Kind = Real_Number then
         return Left.Real_Item < Right.Real_Item;
      end if;
      I := (if Integer_First then Left.Integer_Item else Right.Integer_Item);
      F := (if Integer_First then Right.Real_Item else Left.Real_Item);
      if F /= F then
         return False;
      elsif F >= 2.0 ** 63 then
         return Integer_First;
      elsif F < -2.0 ** 63 then
         return not Integer_First;
      end if;
      if Integer_First then
         return I < Integer_Value (Real_Value'Ceiling (F));
      else
         return Integer_Value (Real_Value'Floor (F)) < I;
      end if;
   end Less;
end Lua.Numbers;
