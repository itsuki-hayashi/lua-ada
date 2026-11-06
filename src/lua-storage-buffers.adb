with System.Address_To_Access_Conversions;
with System.Storage_Elements;

package body Lua.Storage.Buffers is
   use System.Storage_Elements;
   use type System.Address;
   package Characters is new
     System.Address_To_Access_Conversions (Character);

   procedure Check_Mutation (Self : Buffer);
   procedure Copy_Bytes
     (Source, Target : System.Address; Count : Natural);
   procedure Write
     (Self : in out Buffer; Text : String; At_End : Boolean);

   procedure Check_Mutation (Self : Buffer) is
   begin
      if Self.Borrows /= 0 then
         raise Program_Error with "byte buffer is borrowed";
      end if;
   end Check_Mutation;

   procedure Copy_Bytes
     (Source, Target : System.Address; Count : Natural)
   is
   begin
      if Count = 0 or else Source = Target then
         return;
      elsif To_Integer (Target) < To_Integer (Source) then
         for Offset in
           Storage_Offset range 0 .. Storage_Offset (Count) - 1
         loop
            Characters.To_Pointer (Target + Offset).all :=
              Characters.To_Pointer (Source + Offset).all;
         end loop;
      else
         for Offset in reverse
           Storage_Offset range 0 .. Storage_Offset (Count) - 1
         loop
            Characters.To_Pointer (Target + Offset).all :=
              Characters.To_Pointer (Source + Offset).all;
         end loop;
      end if;
   end Copy_Bytes;

   procedure Set_Owner
     (Self : in out Buffer; Memory : not null Owner_Access)
   is
   begin
      if Self.Memory = Memory then
         return;
      elsif Self.Data /= System.Null_Address then
         raise Program_Error with "cannot rebind allocated byte buffer";
      end if;
      Self.Memory := Memory;
   end Set_Owner;

   function Owner_Of (Self : Buffer) return Owner_Access is (Self.Memory);
   function Length (Self : Buffer) return Natural is (Self.Used);
   function Capacity (Self : Buffer) return Natural is (Self.Reserved);
   function Is_Empty (Self : Buffer) return Boolean is (Self.Used = 0);
   function Address (Self : Buffer) return System.Address is (Self.Data);

   procedure Reserve_Capacity (Self : in out Buffer; Capacity : Natural) is
      Desired : Natural;
   begin
      if Capacity <= Self.Reserved then
         return;
      end if;
      Check_Mutation (Self);
      if Self.Memory = null then
         raise Program_Error with "byte buffer allocation requires an owner";
      end if;
      Desired := Natural'Max (Capacity,
        (if Self.Reserved > Natural'Last / 2 then Natural'Last
         else Natural'Max (64, Self.Reserved * 2)));
      --  The managed block includes a terminator; this is distinct from the
      --  logical byte length, so embedded NUL never truncates Lua strings.
      Reallocate (Self.Memory.all, Self.Data, Byte_Count (Desired) + 1);
      Self.Reserved := Desired;
      Characters.To_Pointer (Self.Data + Storage_Offset (Self.Used)).all :=
        Character'Val (0);
   end Reserve_Capacity;

   procedure Write
     (Self : in out Buffer; Text : String; At_End : Boolean)
   is
      Start : constant Natural := (if At_End then Self.Used else 0);
      Source : System.Address;
      Offset : Storage_Offset := 0;
      Aliased_Source : Boolean := False;
   begin
      Check_Mutation (Self);
      if Text'Length > Natural'Last - Start then
         raise Allocation_Error;
      end if;
      if Text'Length = 0 then
         if not At_End then
            Clear (Self);
         end if;
         return;
      end if;
      Source := Text (Text'First)'Address;
      if Self.Data /= System.Null_Address and then
        To_Integer (Source) >= To_Integer (Self.Data) and then
        To_Integer (Source) <=
          To_Integer (Self.Data) + Integer_Address (Self.Used)
      then
         --  Capture an offset, not an old pointer: realloc may release the
         --  previous payload before this operation copies its aliased source.
         --  The complete source must lie within initialized bytes plus NUL.
         Offset := Source - Self.Data;
         Aliased_Source := Text'Length - 1 <= Self.Used - Natural (Offset);
      end if;
      Reserve_Capacity (Self, Start + Text'Length);
      if Aliased_Source then
         Source := Self.Data + Offset;
      end if;
      Copy_Bytes (Source, Self.Data + Storage_Offset (Start), Text'Length);
      Self.Used := Start + Text'Length;
      Characters.To_Pointer (Self.Data + Storage_Offset (Self.Used)).all :=
        Character'Val (0);
   end Write;

   procedure Append (Self : in out Buffer; Text : String) is
   begin
      Write (Self, Text, At_End => True);
   end Append;

   procedure Append (Self : in out Buffer; Item : Character) is
   begin
      Append (Self, String'(1 => Item));
   end Append;

   procedure Append (Self : in out Buffer; Source : in out Buffer) is
      procedure Add (Text : String);
      procedure Add (Text : String) is
      begin
         Append (Self, Text);
      end Add;
   begin
      if Source.Used = 0 then
         return;
      elsif Self'Address = Source'Address then
         declare
            View : constant String (1 .. Source.Used)
              with Import, Address => Source.Data;
         begin
            Append (Self, View);
         end;
      else
         Query (Source, Add'Access);
      end if;
   end Append;

   procedure Insert
     (Self : in out Buffer; Before : Positive; Text : String)
   is
      Saved : Buffer;
      Source : System.Address;
      Offset : constant Natural := Before - 1;
   begin
      Check_Mutation (Self);
      if Offset > Self.Used then
         raise Constraint_Error with "byte buffer insertion index";
      elsif Text'Length = 0 then
         return;
      elsif Text'Length > Natural'Last - Self.Used then
         raise Allocation_Error;
      end if;
      Source := Text (Text'First)'Address;
      if Self.Data /= System.Null_Address and then
        To_Integer (Source) >= To_Integer (Self.Data) and then
        To_Integer (Source) <=
          To_Integer (Self.Data) + Integer_Address (Self.Used)
      then
         --  Shifting changes source offsets, so overlapping insertion needs
         --  a real snapshot. It belongs to the same allocator and ceiling.
         Set_Owner (Saved, Self.Memory);
         Append (Saved, Text);
         Source := Saved.Data;
      end if;
      Reserve_Capacity (Self, Self.Used + Text'Length);
      Copy_Bytes (Self.Data + Storage_Offset (Offset),
                  Self.Data + Storage_Offset (Offset + Text'Length),
                  Self.Used - Offset);
      Copy_Bytes (Source, Self.Data + Storage_Offset (Offset), Text'Length);
      Self.Used := Self.Used + Text'Length;
      Characters.To_Pointer (Self.Data + Storage_Offset (Self.Used)).all :=
        Character'Val (0);
   end Insert;

   procedure Delete
     (Self : in out Buffer; First : Positive; Last : Natural)
   is
      Count : Natural;
   begin
      Check_Mutation (Self);
      if First - 1 > Self.Used or else Last > Self.Used then
         raise Constraint_Error with "byte buffer deletion index";
      elsif Last < First then
         return;
      end if;
      Count := Last - First + 1;
      Copy_Bytes (Self.Data + Storage_Offset (Last),
                  Self.Data + Storage_Offset (First - 1), Self.Used - Last);
      Self.Used := Self.Used - Count;
      Characters.To_Pointer (Self.Data + Storage_Offset (Self.Used)).all :=
        Character'Val (0);
   end Delete;

   procedure Set_Value (Self : in out Buffer; Text : String) is
   begin
      Write (Self, Text, At_End => False);
   end Set_Value;

   procedure Clear (Self : in out Buffer) is
   begin
      Check_Mutation (Self);
      Self.Used := 0;
      if Self.Data /= System.Null_Address then
         Characters.To_Pointer (Self.Data).all := Character'Val (0);
      end if;
   end Clear;

   procedure Release (Self : in out Buffer) is
   begin
      Check_Mutation (Self);
      if Self.Data /= System.Null_Address then
         Lua.Storage.Release (Self.Memory.all, Self.Data);
      end if;
      Self.Used := 0;
      Self.Reserved := 0;
   end Release;

   function Element (Self : Buffer; Index : Positive) return Character is
   begin
      if Index > Self.Used then
         raise Constraint_Error with "byte buffer index outside contents";
      end if;
      return Characters.To_Pointer
        (Self.Data + Storage_Offset (Index - 1)).all;
   end Element;

   procedure Replace_Element
     (Self : in out Buffer; Index : Positive; Item : Character)
   is
   begin
      Check_Mutation (Self);
      if Index > Self.Used then
         raise Constraint_Error with "byte buffer index outside contents";
      end if;
      Characters.To_Pointer
        (Self.Data + Storage_Offset (Index - 1)).all := Item;
   end Replace_Element;

   function Slice
     (Self : Buffer; First : Positive; Last : Natural) return String
   is
   begin
      if First - 1 > Self.Used or else Last > Self.Used then
         raise Constraint_Error with "byte buffer slice outside contents";
      end if;
      return Result : String (First .. Last) do
         for Index in Result'Range loop
            Result (Index) := Element (Self, Index);
         end loop;
      end return;
   end Slice;

   function To_String (Self : Buffer) return String is
     (Slice (Self, 1, Self.Used));

   procedure Query
     (Self : in out Buffer;
      Process : not null access procedure (Text : String))
   is
   begin
      if Self.Borrows = Natural'Last then
         raise Program_Error with "byte buffer borrow count overflow";
      end if;
      Self.Borrows := Self.Borrows + 1;
      begin
         if Self.Used = 0 then
            Process ("");
         else
            declare
               View : constant String (1 .. Self.Used)
                 with Import, Address => Self.Data;
            begin
               Process (View);
            end;
         end if;
      exception
         when others =>
            Self.Borrows := Self.Borrows - 1;
            raise;
      end;
      Self.Borrows := Self.Borrows - 1;
   end Query;

   function C_Address (Self : in out Buffer) return System.Address is
   begin
      Reserve_Capacity (Self, 1);
      return Self.Data;
   end C_Address;

   function Copy (Self : Buffer) return Buffer is (Self);

   function To_Buffer
     (Memory : not null Owner_Access; Text : String) return Buffer
   is
   begin
      return Result : Buffer do
         Set_Owner (Result, Memory);
         Append (Result, Text);
      end return;
   end To_Buffer;

   overriding procedure Adjust (Self : in out Buffer) is
      Source : constant System.Address := Self.Data;
   begin
      --  Reset the shallow copy before allocation, protecting the source when
      --  controlled initialization fails. Copies never inherit active borrows.
      Self.Data := System.Null_Address;
      Self.Reserved := 0;
      Self.Borrows := 0;
      if Self.Used /= 0 then
         Reserve_Capacity (Self, Self.Used);
         Copy_Bytes (Source, Self.Data, Self.Used);
         Characters.To_Pointer (Self.Data + Storage_Offset (Self.Used)).all :=
           Character'Val (0);
      end if;
   end Adjust;

   overriding procedure Finalize (Self : in out Buffer) is
   begin
      Release (Self);
   end Finalize;
end Lua.Storage.Buffers;
