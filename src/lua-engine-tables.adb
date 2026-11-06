with System.Storage_Elements;
with Ada.Containers;
with Ada.Unchecked_Conversion;

package body Lua.Engine.Tables is
   use type Ada.Containers.Count_Type;
   use type Interfaces.Unsigned_64;
   use type Integer_Value;
   use type Real_Value;

   subtype Hash_Value is Interfaces.Unsigned_64;
   function Integer_Bits is new Ada.Unchecked_Conversion
     (Integer_Value, Hash_Value);
   function Float_Bits is new Ada.Unchecked_Conversion
     (Real_Value, Hash_Value);

   function Canonical (Key : Value) return Value;
   function Hash (Key : Value) return Hash_Value;
   function Mix (Item : Hash_Value) return Hash_Value;
   function Dense_Index (Key : Value; Capacity : Natural) return Natural;
   function Bucket (Table : Object_Access; Key : Value) return Positive;
   procedure Link (Table : Object_Access; Index : Positive);
   procedure Grow
     (Table : Object_Access; Key : Value; New_Row : Boolean := True);
   procedure Unlink (Table : Object_Access; Index : Positive);
   procedure Remember_Free (Table : Object_Access; Index : Positive);

   function Hash_Bytes (Text : String) return Hash_Value is
      Result : Hash_Value := 16#CBF2_9CE4_8422_2325#;
   begin
      --  FNV-1a uses modular arithmetic over bytes, never character classes.
      --  Embedded zeroes and arbitrary String bounds are ordinary input.
      for Byte of Text loop
         Result := (Result xor Hash_Value (Character'Pos (Byte))) *
           16#100_0000_01B3#;
      end loop;
      return Result;
   end Hash_Bytes;

   function Canonical (Key : Value) return Value is
   begin
      --  Converting only exact, in-range floats gives integers and their
      --  numerically equal floats the same bucket. Strict upper comparison
      --  avoids converting binary64's rounded representation of Integer'Last.
      if Key.Kind = Real_Kind and then
        Key.Real_Data >= -(2.0 ** 63) and then
        Key.Real_Data < 2.0 ** 63 and then
        Real_Value'Floor (Key.Real_Data) = Key.Real_Data
      then
         return (Integer_Kind, Integer_Value (Key.Real_Data));
      end if;
      return Key;
   end Canonical;

   function Hash (Key : Value) return Hash_Value is
      Item : constant Value := Canonical (Key);
      Result : Hash_Value;
   begin
      case Item.Kind is
         when Integer_Kind => Result := Integer_Bits (Item.Integer_Data);
         when Real_Kind => Result := Float_Bits (Item.Real_Data);
         when String_Kind => Result := Item.Reference.String_Hash;
         when Boolean_Kind => Result := Boolean'Pos (Item.Boolean_Data);
         when Light_Identity_Kind | Foreign_Function_Kind =>
            Result := Hash_Value
              (System.Storage_Elements.To_Integer (Item.Identity));
         when Native_Kind_Value =>
            Result := Hash_Value (Native_Kind'Pos (Item.Native_Data));
         when Table_Kind | Closure_Kind | Native_Closure_Kind | Thread_Kind |
           Userdata_Kind =>
            Result := Hash_Value (Item.Reference.Serial);
         when Nil_Kind => Result := 0;
      end case;
      return Mix (Result);
   end Hash;

   function Mix (Item : Hash_Value) return Hash_Value is
      Result : Hash_Value := Item;
   begin
      --  Avalanche low bits before a power-of-two bucket selection. In
      --  particular, consecutive integers and similar IEEE exponents must
      --  not collapse into long collision chains.
      Result := Result xor Interfaces.Shift_Right (Result, 30);
      Result := Result * 16#BF58_476D_1CE4_E5B9#;
      Result := Result xor Interfaces.Shift_Right (Result, 27);
      Result := Result * 16#94D0_49BB_1331_11EB#;
      return Result xor Interfaces.Shift_Right (Result, 31);
   end Mix;

   function Raw_Field (Table : Object_Access; Name : String) return Value is
      Index : Natural;
      Head : Positive;
   begin
      if Table = null or else Table.Hash_Index.Is_Empty then
         return Nil_Value;
      end if;
      Head := Natural (Mix (Hash_Bytes (Name)) mod
        Hash_Value (Table.Hash_Index.Length)) + 1;
      Index := Table.Hash_Index (Head);
      while Index /= 0 loop
         declare
            Member : constant Table_Entry := Table.Members (Index);
         begin
            if Member.Key.Kind = String_Kind and then
              Member.Key.Reference.Bytes = Name
            then
               return Member.Item;
            end if;
            Index := Member.Next;
         end;
      end loop;
      return Nil_Value;
   end Raw_Field;

   function Dense_Index (Key : Value; Capacity : Natural) return Natural is
      Item : constant Value := Canonical (Key);
   begin
      if Item.Kind = Integer_Kind and then Item.Integer_Data > 0 and then
        Item.Integer_Data <= Integer_Value (Capacity)
      then
         return Natural (Item.Integer_Data);
      end if;
      return 0;
   end Dense_Index;

   function Bucket (Table : Object_Access; Key : Value) return Positive is
     (Natural (Hash (Key) mod Hash_Value (Table.Hash_Index.Length)) + 1);

   function Find (Table : Object_Access; Key : Value) return Natural is
      Dense : constant Natural :=
        Dense_Index (Key, Natural (Table.Array_Index.Length));
      Index : Natural;
   begin
      if Key.Kind = Nil_Kind then
         return 0;
      elsif Dense /= 0 then
         return Table.Array_Index (Dense);
      elsif Table.Hash_Index.Is_Empty then
         return 0;
      end if;
      Index := Table.Hash_Index (Bucket (Table, Key));
      while Index /= 0 loop
         if Equal (Table.Members (Index).Key, Key) then
            return Index;
         end if;
         Index := Table.Members (Index).Next;
      end loop;
      return 0;
   end Find;

   procedure Link (Table : Object_Access; Index : Positive) is
      Member : Table_Entry := Table.Members (Index);
      Dense : constant Natural :=
        Dense_Index (Member.Key, Natural (Table.Array_Index.Length));
   begin
      Member.Next := 0;
      if Member.Key.Kind = Nil_Kind then
         null;
      elsif Dense /= 0 then
         Table.Array_Index.Replace_Element (Dense, Index);
      else
         declare
            Head : constant Positive := Bucket (Table, Member.Key);
         begin
            Member.Next := Table.Hash_Index (Head);
            Table.Hash_Index.Replace_Element (Head, Index);
            Table.Hash_Rows := Table.Hash_Rows + 1;
         end;
      end if;
      Table.Members.Replace_Element (Index, Member);
   end Link;

   procedure Unlink (Table : Object_Access; Index : Positive) is
      Member : constant Table_Entry := Table.Members (Index);
      Dense : constant Natural :=
        Dense_Index (Member.Key, Natural (Table.Array_Index.Length));
      Prior : Natural := 0;
      Cursor : Natural;
      Head : Positive;
   begin
      if Member.Key.Kind = Nil_Kind then
         return;
      elsif Dense /= 0 then
         Table.Array_Index.Replace_Element (Dense, 0);
         return;
      end if;
      Head := Bucket (Table, Member.Key);
      Cursor := Table.Hash_Index (Head);
      while Cursor /= 0 loop
         if Cursor = Index then
            if Prior = 0 then
               Table.Hash_Index.Replace_Element (Head, Member.Next);
            else
               declare
                  Previous : Table_Entry := Table.Members (Prior);
               begin
                  Previous.Next := Member.Next;
                  Table.Members.Replace_Element (Prior, Previous);
               end;
            end if;
            Table.Hash_Rows := Table.Hash_Rows - 1;
            return;
         end if;
         Prior := Cursor;
         Cursor := Table.Members (Cursor).Next;
      end loop;
   end Unlink;

   procedure Remember_Free (Table : Object_Access; Index : Positive) is
      Member : Table_Entry := Table.Members (Index);
   begin
      --  Revival keeps an existing list node until a future insertion pops
      --  it. Never enqueue that row twice: repeated delete/revive cycles must
      --  not make a cyclic free list or overwrite a still-live binding.
      if not Member.Free_Listed then
         Member.Free_Next := Table.Free_Row;
         Member.Free_Listed := True;
         Table.Free_Row := Index;
         Table.Members.Replace_Element (Index, Member);
      end if;
   end Remember_Free;

   procedure Rebuild (Table : Object_Access) is
      Index : Natural;
   begin
      --  Buckets contain row numbers rather than heap addresses. Clearing a
      --  weak key removes its row from every borrowed index before sweeping
      --  frees the object; no hash calculation then dereferences a dead key.
      for Cursor in Table.Array_Index.First_Index ..
        Table.Array_Index.Last_Index
      loop
         Table.Array_Index.Replace_Element (Cursor, 0);
      end loop;
      for Cursor in Table.Hash_Index.First_Index .. Table.Hash_Index.Last_Index
      loop
         Table.Hash_Index.Replace_Element (Cursor, 0);
      end loop;
      Table.Free_Row := 0;
      Table.Hash_Rows := 0;
      for Cursor in Table.Members.First_Index .. Table.Members.Last_Index loop
         declare
            Member : Table_Entry := Table.Members (Cursor);
         begin
            Member.Free_Listed := False;
            Member.Free_Next := 0;
            Table.Members.Replace_Element (Cursor, Member);
            Link (Table, Cursor);
            if Member.Item.Kind = Nil_Kind then
               Remember_Free (Table, Cursor);
            end if;
         end;
      end loop;
      Table.Prefix_Length := 0;
      loop
         exit when Table.Prefix_Length = Natural'Last;
         Index := Find (Table,
           (Integer_Kind, Integer_Value (Table.Prefix_Length) + 1));
         exit when Index = 0 or else
           Table.Members (Index).Item.Kind = Nil_Kind;
         Table.Prefix_Length := Table.Prefix_Length + 1;
      end loop;
   end Rebuild;

   procedure Reserve
     (State : in out World; Table : Object_Access;
      Sequence_Size, Hash_Size : Natural)
   is
      Total : constant Integer_Value := Integer_Value (Sequence_Size) +
        Integer_Value (Hash_Size);
      Buckets : Natural := (if Hash_Size = 0 then 0 else 8);
   begin
      if Total > Integer_Value (State.Bounds.Table_Entries) then
         Fail (State, "table entry limit exceeded", Resource => True);
      end if;
      --  These are real allocations through this table's selected provider,
      --  not a reported capacity hint. Members hold eventual keys/values;
      --  the dense index and chained hash buckets retain their own layout.
      while Buckets < Hash_Size loop
         if Buckets > Natural'Last / 2 then
            Fail (State, "table overflow");
         end if;
         Buckets := Buckets * 2;
      end loop;
      Table.Members.Reserve_Capacity (Ada.Containers.Count_Type (Total));
      Table.Array_Index.Reserve_Capacity
        (Ada.Containers.Count_Type (Sequence_Size));
      Table.Hash_Index.Reserve_Capacity (Ada.Containers.Count_Type (Buckets));
      --  Publish lengths only after every reserve succeeds. Rebuild writes
      --  all newly live scalar index slots before any lookup can read them.
      Table.Array_Index.Set_Length
        (Ada.Containers.Count_Type (Sequence_Size));
      Table.Hash_Index.Set_Length (Ada.Containers.Count_Type (Buckets));
      Rebuild (Table);
   end Reserve;

   procedure Grow
     (Table : Object_Access; Key : Value; New_Row : Boolean := True) is
      Count : constant Ada.Containers.Count_Type := Table.Members.Length;
      Array_Size : Natural := Natural (Table.Array_Index.Length);
      Hash_Size : Natural := Natural (Table.Hash_Index.Length);
      Target : constant Value := Canonical (Key);
      Next_Array : constant Natural :=
        (if Array_Size > Natural'Last - Array_Size / 2 then Natural'Last
         else Natural'Max (8, Array_Size + Array_Size / 2));
      Changed : Boolean := False;
   begin
      if New_Row and then Count = Table.Members.Capacity then
         Table.Members.Reserve_Capacity
           (Ada.Containers.Count_Type'Max (8, Count * 2));
      end if;
      --  A sparse distant integer remains in the hash part. Only nearby
      --  positive keys justify geometric direct-index growth; a single huge
      --  key must never request a correspondingly huge array. Reusing one
      --  deleted row also cannot grow a dense history of its former keys.
      if New_Row and then
        Target.Kind = Integer_Kind and then Target.Integer_Data > 0 and then
        Target.Integer_Data <= Integer_Value (Next_Array) and then
        Target.Integer_Data > Integer_Value (Array_Size)
      then
         Array_Size := Next_Array;
      end if;
      --  Dense members occupy their direct index, not chained hash rows.
      --  Counting all member rows here would allocate an unrelated hash while
      --  filling a preallocated sequence, defeating table.create's promise.
      if Dense_Index (Target, Array_Size) = 0 then
         if Hash_Size = 0 then
            Hash_Size := 8;
         elsif Table.Hash_Rows >= Hash_Size then
            if Hash_Size > Natural'Last / 2 then
               raise Storage_Error with "table index capacity overflow";
            end if;
            Hash_Size := Hash_Size * 2;
         end if;
      end if;
      --  Reserve every potentially failing allocation before changing index
      --  lengths. A failed second reserve may leave spare capacity, but the
      --  old table and its bucket modulus remain semantically unchanged.
      Table.Array_Index.Reserve_Capacity
        (Ada.Containers.Count_Type (Array_Size));
      Table.Hash_Index.Reserve_Capacity
        (Ada.Containers.Count_Type (Hash_Size));
      if Array_Size /= Natural (Table.Array_Index.Length) then
         Table.Array_Index.Set_Length (Ada.Containers.Count_Type (Array_Size));
         Changed := True;
      end if;
      if Hash_Size /= Natural (Table.Hash_Index.Length) then
         Table.Hash_Index.Set_Length (Ada.Containers.Count_Type (Hash_Size));
         Changed := True;
      end if;
      if Changed then
         Rebuild (Table);
      end if;
   end Grow;

   procedure Put (State : in out World; Table : Object_Access;
                  Key, Item : Value)
   is
      Index : Natural := Find (Table, Key);
      Number : constant Value := Canonical (Key);
      Dense : Natural;
   begin
      if Index = 0 then
         if Item.Kind = Nil_Kind then
            return;
         end if;
         --  Reusing a deleted dense row for a sparse key can need its first
         --  hash bucket, even though member capacity already exists. Reserve
         --  indexes before touching the free list: rebuilding may relink it,
         --  and a failed allocation must not strand a candidate mid-transfer.
         Grow (Table, Key, New_Row => False);
         while Table.Free_Row /= 0 loop
            declare
               Candidate : constant Positive := Table.Free_Row;
               Member : Table_Entry := Table.Members (Candidate);
            begin
               Table.Free_Row := Member.Free_Next;
               Member.Free_Next := 0;
               Member.Free_Listed := False;
               Table.Members.Replace_Element (Candidate, Member);
               if Member.Item.Kind = Nil_Kind then
                  Index := Candidate;
                  Unlink (Table, Candidate);
                  exit;
               end if;
            end;
         end loop;
         if Index = 0 then
            if State.Entry_Count >= State.Bounds.Table_Entries then
               Fail (State, "table entry limit exceeded", Resource => True);
            end if;
            Grow (Table, Key);
            Table.Members.Append
              (Table_Entry'(Key => Number, Item => Item, others => <>));
            Index := Table.Members.Last_Index;
            State.Entry_Count := State.Entry_Count + 1;
         else
            --  Inserting a new key is a structural change. Deleted-key next
            --  positions need not survive it, so recycle the actual row and
            --  remove its old bucket link before publishing the new key.
            Table.Members.Replace_Element
              (Index, (Key => Number, Item => Item, others => <>));
         end if;
         Link (Table, Index);
      else
         declare
            Member : Table_Entry := Table.Members (Index);
         begin
            --  Retain the original canonical key and collision link. A nil
            --  value keeps a tombstone for next(t, just_deleted_key).
            Member.Item := Item;
            Table.Members.Replace_Element (Index, Member);
         end;
      end if;
      if Item.Kind = Nil_Kind then
         Remember_Free (Table, Index);
      end if;
      if Number.Kind = Integer_Kind and then Number.Integer_Data > 0 and then
        Number.Integer_Data <= Integer_Value (Natural'Last)
      then
         Dense := Natural (Number.Integer_Data);
         if Item.Kind = Nil_Kind and then Dense <= Table.Prefix_Length then
            Table.Prefix_Length := Dense - 1;
         elsif Item.Kind /= Nil_Kind and then
           Dense - 1 = Table.Prefix_Length
         then
            loop
               exit when Table.Prefix_Length = Natural'Last;
               Index := Find (Table,
                 (Integer_Kind, Integer_Value (Table.Prefix_Length) + 1));
               exit when Index = 0 or else
                 Table.Members (Index).Item.Kind = Nil_Kind;
               Table.Prefix_Length := Table.Prefix_Length + 1;
            end loop;
         end if;
      end if;
   end Put;
end Lua.Engine.Tables;
