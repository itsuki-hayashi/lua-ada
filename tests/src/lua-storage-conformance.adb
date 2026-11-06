with System.Address_To_Access_Conversions;

package body Lua.Storage.Conformance is
   function Allocation_Ceiling (Self : Owner) return Byte_Count is
     (Self.Ceiling);
   use System.Storage_Elements;
   use type System.Address;
   package Headers is new System.Address_To_Access_Conversions (Header);
   package Addresses is new
     System.Address_To_Access_Conversions (System.Address);

   procedure Verify (Self : Owner) is
      Cursor : System.Address := Self.First;
      Previous : System.Address := System.Null_Address;
      Blocks, Raw, Payload : Byte_Count := 0;
      Header_Bytes : constant Byte_Count :=
        (Header'Size + System.Storage_Unit - 1) / System.Storage_Unit;
      Pointer_Bytes : constant Byte_Count :=
        (System.Address'Size + System.Storage_Unit - 1) / System.Storage_Unit;
      procedure Check (Condition : Boolean);
      procedure Check (Condition : Boolean) is
      begin
         if not Condition then
            raise Program_Error with "allocator ownership invariant failed";
         end if;
      end Check;
   begin
      while Cursor /= System.Null_Address loop
         Check (Blocks < Self.Counts.Live_Blocks);
         declare
            Item : Header renames Headers.To_Pointer (Cursor).all;
            Offset : Byte_Count;
         begin
            Check (Item.Parent /= null);
            Check (Item.Parent.all'Address = Self'Address);
            Check (Item.Raw = Cursor and Item.Before = Previous);
            Check (Item.Alignment > 0 and Item.Size > 0);
            Check (Item.User > Item.Raw);
            Offset := Item.User - Item.Raw;
            Check (Offset >= Header_Bytes + Pointer_Bytes);
            Check (Offset <= Item.Raw_Size);
            Check (Item.Size <= Item.Raw_Size - Offset);
            Check (Item.User mod Item.Alignment = 0);
            Check (Item.User mod System.Address'Alignment = 0);
            Check (Addresses.To_Pointer
                     (Item.User - Pointer_Bytes).all = Item.Raw);
            Raw := Raw + Item.Raw_Size;
            Payload := Payload + Item.Size;
            Blocks := Blocks + 1;
            Previous := Cursor;
            Cursor := Item.After;
         end;
      end loop;
      Check (Blocks = Self.Counts.Live_Blocks);
      Check (Raw = Self.Counts.Raw_Bytes);
      Check (Payload = Self.Counts.Payload_Bytes);
      Check (Raw <= Self.Counts.Peak_Raw_Bytes);
   end Verify;
end Lua.Storage.Conformance;
