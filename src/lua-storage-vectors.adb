with Ada.Unchecked_Deallocation;
with System.Address_To_Access_Conversions;

package body Lua.Storage.Vectors is
   use type Count_Type;
   use type System.Address;

   package Elements is new
     System.Address_To_Access_Conversions (Element_Type);

   procedure Free_Buffer is new Ada.Unchecked_Deallocation
     (Buffer, Buffer_Access);

   procedure Check_Index (Self : Vector; Index : Positive);
   procedure Check_Tampering (Self : Vector);
   procedure Borrow (Data : Buffer_Access);
   procedure Unborrow (Counter : in out Counter_Access);
   function Checked_Count (Count : Count_Type) return Natural;
   function Default_Slot return Slot;
   procedure Make_Space (Self : in out Vector; Extra : Count_Type);
   function Pointer
     (Data : Buffer_Access; Index : Positive) return Elements.Object_Pointer;

   function Pointer
     (Data : Buffer_Access; Index : Positive) return Elements.Object_Pointer
   is
   begin
      --  A slot's discriminant is mutable, so Ada does not permit a direct
      --  Access attribute for its dependent component. The reference guards
      --  below prevent all discriminant-changing structural operations while
      --  this pointer is borrowed. The address names the actual typed item.
      return Elements.To_Pointer (Data.Items (Index).Item'Address);
   end Pointer;

   procedure Check_Index (Self : Vector; Index : Positive) is
   begin
      if Index > Self.Used then
         raise Constraint_Error with "vector index outside live elements";
      end if;
   end Check_Index;

   procedure Check_Tampering (Self : Vector) is
   begin
      if Self.Data /= null and then Self.Data.Borrows /= 0 then
         raise Program_Error with "vector buffer is borrowed";
      end if;
   end Check_Tampering;

   procedure Borrow (Data : Buffer_Access) is
   begin
      if Data /= null then
         if Data.Borrows = Natural'Last then
            raise Program_Error with "vector borrow count overflow";
         end if;
         Data.Borrows := Data.Borrows + 1;
      end if;
   end Borrow;

   procedure Unborrow (Counter : in out Counter_Access) is
   begin
      if Counter /= null then
         Counter.all := Counter.all - 1;
         Counter := null;
      end if;
   end Unborrow;

   function Checked_Count (Count : Count_Type) return Natural is
   begin
      return Natural (Count);
   exception
      when Constraint_Error =>
         raise Allocation_Error;
   end Checked_Count;

   function Default_Slot return Slot is
   begin
      return (Present => True, Item => <>);
   end Default_Slot;

   procedure Set_Owner
     (Self : in out Vector; Memory : not null Owner_Access)
   is
   begin
      if Self.Memory = Memory then
         return;
      elsif Self.Data /= null then
         raise Program_Error with "cannot rebind allocated vector";
      end if;
      Self.Memory := Memory;
   end Set_Owner;

   function Owner_Of (Self : Vector) return Owner_Access is (Self.Memory);
   function Length (Self : Vector) return Count_Type is
     (Count_Type (Self.Used));
   function Capacity (Self : Vector) return Count_Type is
     (if Self.Data = null then 0 else Count_Type (Self.Data.Capacity));
   function Is_Empty (Self : Vector) return Boolean is (Self.Used = 0);
   function First_Index (Self : Vector) return Positive is
      pragma Unreferenced (Self);
   begin
      return 1;
   end First_Index;
   function Last_Index (Self : Vector) return Extended_Index is (Self.Used);

   function Element (Self : Vector; Index : Positive) return Element_Type is
   begin
      Check_Index (Self, Index);
      return Self.Data.Items (Index).Item;
   end Element;

   function Has_Element (Position : Cursor) return Boolean is
     (Position.Storage /= null and then Position.Index > 0 and then
      Position.Index <= Position.Storage.Capacity and then
      Position.Storage.Items (Position.Index).Present);

   function Element (Position : Cursor) return Element_Type is
   begin
      if not Has_Element (Position) then
         raise Constraint_Error with "vector cursor has no element";
      end if;
      return Position.Storage.Items (Position.Index).Item;
   end Element;

   function First_Element (Self : Vector) return Element_Type is
     (Element (Self, 1));
   function Last_Element (Self : Vector) return Element_Type is
     (Element (Self, Positive (Self.Used)));

   function Constant_Reference
     (Self : aliased Vector; Index : Positive) return Constant_Reference_Type
   is
   begin
      Check_Index (Self, Index);
      Borrow (Self.Data);
      return Result : Constant_Reference_Type
        (Pointer (Self.Data, Index))
      do
         Result.Guard.Counter := Self.Data.Borrows'Access;
      end return;
   end Constant_Reference;

   function Constant_Reference
     (Self : aliased Vector; Position : Cursor) return Constant_Reference_Type
   is
   begin
      if Position.Storage /= Self.Data then
         raise Program_Error with "cursor belongs to another vector";
      end if;
      return Constant_Reference (Self, Positive (Position.Index));
   end Constant_Reference;

   function Reference
     (Self : aliased in out Vector; Index : Positive) return Reference_Type
   is
   begin
      Check_Index (Self, Index);
      Borrow (Self.Data);
      return Result : Reference_Type (Pointer (Self.Data, Index)) do
         Result.Guard.Counter := Self.Data.Borrows'Access;
      end return;
   end Reference;

   function Reference
     (Self : aliased in out Vector; Position : Cursor) return Reference_Type
   is
   begin
      if Position.Storage /= Self.Data then
         raise Program_Error with "cursor belongs to another vector";
      end if;
      return Reference (Self, Positive (Position.Index));
   end Reference;

   overriding procedure Finalize (Self : in out Borrow_Guard) is
   begin
      Unborrow (Self.Counter);
   end Finalize;

   overriding procedure Finalize (Self : in out Buffer) is
   begin
      --  Subpool finalization can reach a buffer before its owning vector.
      --  Empty each discriminated slot before automatic component cleanup,
      --  making a later owner-driven Unchecked_Deallocation idempotent even
      --  when Element_Type has a non-idempotent user finalizer.
      for Index in Self.Items'Range loop
         if Self.Items (Index).Present then
            Self.Items (Index) := (Present => False);
         end if;
      end loop;
   end Finalize;

   function Iterate
     (Self : Vector) return Iterator_Interfaces.Reversible_Iterator'Class
   is
   begin
      Borrow (Self.Data);
      return Result : Iterator do
         Result.Storage := Self.Data;
         Result.Length := Self.Used;
      end return;
   end Iterate;

   overriding function First (Self : Iterator) return Cursor is
     (if Self.Length = 0 then No_Element else (Self.Storage, 1));
   overriding function Next
     (Self : Iterator; Position : Cursor) return Cursor
   is
   begin
      if Position.Storage /= Self.Storage or else
        Position.Index >= Self.Length
      then
         return No_Element;
      end if;
      return (Self.Storage, Position.Index + 1);
   end Next;

   overriding function Last (Self : Iterator) return Cursor is
     (if Self.Length = 0 then No_Element else (Self.Storage, Self.Length));
   overriding function Previous
     (Self : Iterator; Position : Cursor) return Cursor
   is
   begin
      if Position.Storage /= Self.Storage or else Position.Index <= 1 then
         return No_Element;
      end if;
      return (Self.Storage, Position.Index - 1);
   end Previous;

   overriding procedure Finalize (Self : in out Iterator) is
   begin
      if Self.Storage /= null then
         Self.Storage.Borrows := Self.Storage.Borrows - 1;
         Self.Storage := null;
      end if;
   end Finalize;

   procedure Reserve_Capacity (Self : in out Vector; Capacity : Count_Type) is
      Required : constant Natural := Checked_Count (Capacity);
      Current : constant Natural :=
        (if Self.Data = null then 0 else Self.Data.Capacity);
      Desired : Natural;
      Fresh, Old : Buffer_Access;
   begin
      if Required <= Current then
         return;
      end if;
      Check_Tampering (Self);
      if Self.Memory = null then
         raise Program_Error with "vector allocation requires an owner";
      end if;
      Desired := Natural'Max (Required,
        (if Current > Natural'Last / 2 then Natural'Last
         else Natural'Max (4, Current * 2)));
      Fresh := new (Handle (Self.Memory.all)) Buffer (Desired);
      begin
         --  Build a complete replacement before publishing it. Nested owned
         --  vectors copy through Adjust, and failure finalizes only the fresh
         --  slots; the original buffer remains reachable and unchanged.
         for Index in 1 .. Self.Used loop
            Fresh.Items (Index) := Self.Data.Items (Index);
         end loop;
      exception
         when others =>
            Free_Buffer (Fresh);
            raise;
      end;
      Old := Self.Data;
      Self.Data := Fresh;
      Free_Buffer (Old);
   end Reserve_Capacity;

   procedure Make_Space (Self : in out Vector; Extra : Count_Type) is
   begin
      if Extra > Count_Type (Natural'Last - Self.Used) then
         raise Allocation_Error;
      end if;
      Reserve_Capacity (Self, Count_Type (Self.Used) + Extra);
   end Make_Space;

   procedure Set_Length (Self : in out Vector; Length : Count_Type) is
      Desired : constant Natural := Checked_Count (Length);
   begin
      if Desired = Self.Used then
         return;
      end if;
      Check_Tampering (Self);
      if Desired < Self.Used then
         Delete_Last (Self, Count_Type (Self.Used - Desired));
      else
         Reserve_Capacity (Self, Length);
         while Self.Used < Desired loop
            Self.Data.Items (Self.Used + 1) := Default_Slot;
            Self.Used := Self.Used + 1;
         end loop;
      end if;
   end Set_Length;

   procedure Append
     (Self : in out Vector; New_Item : Element_Type; Count : Count_Type := 1)
   is
   begin
      if Count = 0 then
         return;
      end if;
      Check_Tampering (Self);
      declare
         --  Snapshot before growth: New_Item may be an element of Self, whose
         --  old buffer growth will release. This also protects nested values.
         Saved : constant Slot := (True, New_Item);
      begin
         Make_Space (Self, Count);
         for Index in 1 .. Checked_Count (Count) loop
            Self.Data.Items (Self.Used + 1) := Saved;
            Self.Used := Self.Used + 1;
         end loop;
      end;
   end Append;

   procedure Append (Self : in out Vector; New_Item : Vector) is
      Count : constant Natural := New_Item.Used;
      Start : constant Natural := Self.Used;
   begin
      if Count = 0 then
         return;
      end if;
      Check_Tampering (Self);
      Make_Space (Self, Count_Type (Count));
      --  Self-append is safe: growth preserves the old prefix, and writes
      --  begin after that prefix. Capture Count before increasing Used.
      for Index in 1 .. Count loop
         Self.Data.Items (Start + Index) := New_Item.Data.Items (Index);
         Self.Used := Self.Used + 1;
      end loop;
   end Append;

   procedure Insert
     (Self : in out Vector; Before : Positive;
      New_Item : Element_Type; Count : Count_Type := 1)
   is
      Extra : constant Natural := Checked_Count (Count);
   begin
      if Before - 1 > Self.Used then
         raise Constraint_Error with "vector insertion index";
      elsif Extra = 0 then
         return;
      end if;
      Check_Tampering (Self);
      declare
         Saved : constant Slot := (True, New_Item);
      begin
         Make_Space (Self, Count);
         for Index in reverse Before .. Self.Used loop
            Self.Data.Items (Index + Extra) := Self.Data.Items (Index);
         end loop;
         for Index in Before .. Before + Extra - 1 loop
            Self.Data.Items (Index) := Saved;
         end loop;
         Self.Used := Self.Used + Extra;
      end;
   end Insert;

   procedure Delete
     (Self : in out Vector; Index : Positive; Count : Count_Type := 1)
   is
      Removed : Natural;
   begin
      if Index - 1 > Self.Used then
         raise Constraint_Error with "vector deletion index";
      end if;
      Removed := Natural (Count_Type'Min
        (Count, Count_Type (Self.Used - (Index - 1))));
      if Removed = 0 then
         return;
      end if;
      Check_Tampering (Self);
      for Position in Index .. Self.Used - Removed loop
         Self.Data.Items (Position) := Self.Data.Items (Position + Removed);
      end loop;
      for Position in Self.Used - Removed + 1 .. Self.Used loop
         Self.Data.Items (Position) := (Present => False);
      end loop;
      Self.Used := Self.Used - Removed;
   end Delete;

   procedure Delete_Last (Self : in out Vector; Count : Count_Type := 1) is
      Removed : constant Natural := Natural
        (Count_Type'Min (Count, Count_Type (Self.Used)));
   begin
      if Removed /= 0 then
         Delete (Self, Self.Used - Removed + 1, Count_Type (Removed));
      end if;
   end Delete_Last;

   procedure Clear (Self : in out Vector) is
   begin
      Delete_Last (Self, Count_Type (Self.Used));
   end Clear;

   procedure Replace_Element
     (Self : in out Vector; Index : Positive; New_Item : Element_Type)
   is
   begin
      Check_Index (Self, Index);
      Self.Data.Items (Index).Item := New_Item;
   end Replace_Element;

   procedure Update_Element
     (Self : in out Vector; Index : Positive;
      Process : not null access procedure (Item : in out Element_Type))
   is
   begin
      Check_Index (Self, Index);
      declare
         Guard : constant Reference_Type := Reference (Self, Index);
      begin
         Process (Guard.Element.all);
      end;
   end Update_Element;

   function Find_Index
     (Self : Vector; Item : Element_Type) return Extended_Index
   is
   begin
      for Index in 1 .. Self.Used loop
         if Self.Data.Items (Index).Item = Item then
            return Index;
         end if;
      end loop;
      return No_Index;
   end Find_Index;

   function Contains (Self : Vector; Item : Element_Type) return Boolean is
     (Find_Index (Self, Item) /= No_Index);

   function Copy (Self : Vector) return Vector is (Self);

   procedure Move (Target, Source : in out Vector) is
   begin
      if Target'Address = Source'Address then
         return;
      end if;
      --  Check both operands before releasing anything. A rejected move must
      --  leave existing references valid and both ownership graphs untouched.
      Check_Tampering (Target);
      Check_Tampering (Source);
      Finalize (Target);
      --  Cleanup may invoke user element finalizers. Publish the transfer only
      --  after it succeeds, so a raising finalizer cannot orphan Source. These
      --  scalar assignments cannot allocate, adjust or finalize any element.
      Target.Memory := Source.Memory;
      Target.Data := Source.Data;
      Target.Used := Source.Used;
      Source.Memory := null;
      Source.Data := null;
      Source.Used := 0;
   end Move;

   function "=" (Left, Right : Vector) return Boolean is
   begin
      if Left.Used /= Right.Used then
         return False;
      end if;
      for Index in 1 .. Left.Used loop
         if Left.Data.Items (Index).Item /= Right.Data.Items (Index).Item then
            return False;
         end if;
      end loop;
      return True;
   end "=";

   function To_Vector
     (Memory : not null Owner_Access; New_Item : Element_Type;
      Length : Count_Type) return Vector
   is
   begin
      return Result : Vector do
         Set_Owner (Result, Memory);
         Append (Result, New_Item, Length);
      end return;
   end To_Vector;

   overriding procedure Adjust (Self : in out Vector) is
      Original : constant Buffer_Access := Self.Data;
      Count : constant Natural := Self.Used;
   begin
      --  The shallow controlled copy initially points into its source. Clear
      --  that borrowed pointer before anything that may fail, so cleanup of
      --  a failed Adjust can never deallocate the source's storage.
      Self.Data := null;
      Self.Used := 0;
      if Count = 0 then
         return;
      end if;
      Reserve_Capacity (Self, Count_Type (Count));
      begin
         for Index in 1 .. Count loop
            Self.Data.Items (Index) := Original.Items (Index);
            Self.Used := Self.Used + 1;
         end loop;
      exception
         when others =>
            Finalize (Self);
            raise;
      end;
   end Adjust;

   overriding procedure Finalize (Self : in out Vector) is
      Old : Buffer_Access := Self.Data;
   begin
      Check_Tampering (Self);
      Self.Data := null;
      Self.Used := 0;
      Free_Buffer (Old);
   end Finalize;
end Lua.Storage.Vectors;
