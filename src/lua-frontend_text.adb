package body Lua.Frontend_Text is
   procedure Check (Self : Arena; Item : Text_Ref);
   procedure Check (Self : Arena; Item : Text_Ref) is
   begin
      --  Subtraction before addition keeps even malformed private references
      --  from overflowing during validation. Published refs are immutable.
      if Item.First - 1 > Self.Data.Length or else
        Item.Length > Self.Data.Length - (Item.First - 1)
      then
         raise Constraint_Error with "frontend text outside its arena";
      end if;
   end Check;

   procedure Set_Owner
     (Self : in out Arena; Memory : not null Lua.Storage.Owner_Access) is
   begin
      Self.Data.Set_Owner (Memory);
   end Set_Owner;

   function Owner_Of (Self : Arena) return Lua.Storage.Owner_Access is
     (Self.Data.Owner_Of);

   procedure Clear (Self : in out Arena) is
   begin
      Self.Data.Clear;
   end Clear;

   function Store (Self : in out Arena; Text : String) return Text_Ref is
      Start : Positive;
   begin
      if Text'Length = 0 then
         return Empty_Text;
      elsif Self.Data.Length = Natural'Last then
         raise Lua.Storage.Allocation_Error;
      end if;
      Start := Self.Data.Length + 1;
      --  Append validates the complete size before changing length. A refused
      --  growth therefore publishes neither bytes nor a dangling reference.
      Self.Data.Append (Text);
      return (Start, Text'Length);
   end Store;

   function Store
     (Self : in out Arena; Text : in out Lua.Storage.Buffers.Buffer)
      return Text_Ref
   is
      Result : Text_Ref;
      procedure Save (Bytes : String);
      procedure Save (Bytes : String) is
      begin
         Result := Store (Self, Bytes);
      end Save;
   begin
      Text.Query (Save'Access);
      return Result;
   end Store;

   function Text (Self : Arena; Item : Text_Ref) return String is
   begin
      Check (Self, Item);
      return Self.Data.Slice (Item.First, Item.First - 1 + Item.Length);
   end Text;

   procedure Query
     (Self : in out Arena; Item : Text_Ref;
      Process : not null access procedure (Text : String))
   is
      procedure Inspect (Bytes : String);
      procedure Inspect (Bytes : String) is
      begin
         Process (Bytes (Item.First .. Item.First - 1 + Item.Length));
      end Inspect;
   begin
      Check (Self, Item);
      Self.Data.Query (Inspect'Access);
   end Query;

   function Equal (Self : Arena; Left, Right : Text_Ref) return Boolean is
   begin
      Check (Self, Left);
      Check (Self, Right);
      if Left.Length /= Right.Length then
         return False;
      end if;
      for Index in 1 .. Left.Length loop
         if Element (Self, Left, Index) /= Element (Self, Right, Index) then
            return False;
         end if;
      end loop;
      return True;
   end Equal;

   function Equal (Self : Arena; Left : Text_Ref; Right : String)
                  return Boolean is
   begin
      Check (Self, Left);
      if Left.Length /= Right'Length then
         return False;
      end if;
      for Index in 1 .. Left.Length loop
         if Element (Self, Left, Index) /= Right (Right'First + Index - 1) then
            return False;
         end if;
      end loop;
      return True;
   end Equal;

   function Element
     (Self : Arena; Item : Text_Ref; Index : Positive) return Character is
   begin
      Check (Self, Item);
      if Index > Item.Length then
         raise Constraint_Error with "frontend text element outside length";
      end if;
      return Self.Data.Element (Item.First + (Index - 1));
   end Element;
end Lua.Frontend_Text;
