with Ada.Unchecked_Deallocate_Subpool;
with System.Address_To_Access_Conversions;
with System.Storage_Pools;

package body Lua.Storage is
   use System.Storage_Elements;
   use type Interfaces.C.size_t;
   use type System.Address;

   --  Only this boundary interprets raw provider addresses. Everything above
   --  it deals in typed objects or owner-carrying buffers. The header is a
   --  trivially initialized record and contains no controlled Ada components.
   type Header is record
      Parent : Owner_Access;
      Before, After : System.Address;
      Raw : System.Address;
      Raw_Size : Byte_Count;
      User : System.Address;
      Size : Byte_Count;
      Alignment : Byte_Count;
   end record;
   package Headers is new System.Address_To_Access_Conversions (Header);
   package Addresses is new
     System.Address_To_Access_Conversions (System.Address);
   package Bytes is new
     System.Address_To_Access_Conversions (Storage_Element);

   Header_Size : constant Byte_Count :=
     (Header'Size + System.Storage_Unit - 1) / System.Storage_Unit;
   Pointer_Size : constant Byte_Count :=
     (System.Address'Size + System.Storage_Unit - 1) / System.Storage_Unit;

   --  This distinct, ordinary Ada access type supplies the default backing
   --  pool. It is intentionally not associated with Pool, avoiding recursive
   --  calls into the same allocator when an Ada session has no C provider.
   type Default_Bytes is access all Storage_Array;

   function Header_Of (Block : System.Address) return Headers.Object_Pointer;
   procedure Release_All (Self : in out Owner);
   procedure Count_Refusal (Self : in out Owner);
   procedure Check_Growth
     (Self : in out Owner; Old_Size, New_Size : Byte_Count);
   procedure Copy
     (Source, Destination : System.Address; Count : Byte_Count);
   function Raw_Size_For
     (Size, Alignment : Byte_Count) return Byte_Count;
   function Effective_Alignment (Alignment : Byte_Count) return Byte_Count;
   function User_Address
     (Raw : System.Address; Alignment : Byte_Count) return System.Address;

   procedure Copy
     (Source, Destination : System.Address; Count : Byte_Count)
   is
   begin
      --  Resizing may change the payload's offset inside an already moved raw
      --  block. Copy in the memmove direction so overlapping alignment shifts
      --  preserve bytes without allocating an input-sized temporary buffer.
      if Count = 0 or else Source = Destination then
         return;
      elsif To_Integer (Destination) < To_Integer (Source) then
         for Offset in Storage_Offset range 0 .. Count - 1 loop
            Bytes.To_Pointer (Destination + Offset).all :=
              Bytes.To_Pointer (Source + Offset).all;
         end loop;
      else
         for Offset in reverse Storage_Offset range 0 .. Count - 1 loop
            Bytes.To_Pointer (Destination + Offset).all :=
              Bytes.To_Pointer (Source + Offset).all;
         end loop;
      end if;
   end Copy;

   function Default_Allocator
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
   is
      pragma Unreferenced (Data);
      Result : System.Address;
   begin
      if New_Size > Interfaces.C.size_t (Byte_Count'Last) or else
        Old_Size > Interfaces.C.size_t (Byte_Count'Last)
      then
         return System.Null_Address;
      end if;
      if New_Size = 0 then
         if Block /= System.Null_Address then
            System.Storage_Pools.Deallocate
              (Default_Bytes'Storage_Pool, Block,
               Byte_Count (Old_Size), Header'Alignment);
         end if;
         return System.Null_Address;
      end if;

      --  Allocate before touching the old block. A backing-pool Storage_Error
      --  therefore has exactly the callback's null/refusal contract and never
      --  destroys data that a protected Lua memory error may still retain.
      System.Storage_Pools.Allocate
        (Default_Bytes'Storage_Pool, Result,
         Byte_Count (New_Size), Header'Alignment);
      if Block /= System.Null_Address then
         Copy (Block, Result, Byte_Count'Min
           (Byte_Count (Old_Size), Byte_Count (New_Size)));
         System.Storage_Pools.Deallocate
           (Default_Bytes'Storage_Pool, Block,
            Byte_Count (Old_Size), Header'Alignment);
      end if;
      return Result;
   exception
      when Storage_Error =>
         return System.Null_Address;
   end Default_Allocator;

   function Effective_Alignment (Alignment : Byte_Count) return Byte_Count is
      A : Byte_Count := Alignment;
      B : Byte_Count := System.Address'Alignment;
      Remainder : Byte_Count;
   begin
      if Alignment = 0 then
         raise Allocation_Error;
      end if;
      --  The backlink itself must be pointer aligned. Taking the least common
      --  multiple also honors non-power-of-two byte-buffer alignment requests,
      --  instead of assuming that max(request, pointer alignment) suffices.
      while B /= 0 loop
         Remainder := A mod B;
         A := B;
         B := Remainder;
      end loop;
      if Alignment / A > Byte_Count'Last / System.Address'Alignment then
         raise Allocation_Error;
      end if;
      return (Alignment / A) * System.Address'Alignment;
   end Effective_Alignment;

   function Raw_Size_For
     (Size, Alignment : Byte_Count) return Byte_Count
   is
      Effective : constant Byte_Count :=
        Effective_Alignment (Alignment);
      Overhead : Byte_Count;
   begin
      if Effective >
        Byte_Count'Last - Header_Size - Pointer_Size + 1
      then
         raise Allocation_Error;
      end if;
      Overhead := Header_Size + Pointer_Size + Effective - 1;
      if Size > Byte_Count'Last - Overhead then
         raise Allocation_Error;
      end if;
      return Size + Overhead;
   end Raw_Size_For;

   function User_Address
     (Raw : System.Address; Alignment : Byte_Count) return System.Address
   is
      Effective : constant Byte_Count :=
        Effective_Alignment (Alignment);
      First : constant System.Address := Raw + Header_Size + Pointer_Size;
      Remainder : constant Storage_Offset := First mod Effective;
   begin
      return First + (if Remainder = 0 then 0 else Effective - Remainder);
   end User_Address;

   function Header_Of (Block : System.Address) return Headers.Object_Pointer is
   begin
      return Headers.To_Pointer
        (Addresses.To_Pointer (Block - Pointer_Size).all);
   end Header_Of;

   procedure Count_Refusal (Self : in out Owner) is
   begin
      Self.Pending_Refusal := True;
      if Self.Counts.Refusals < Byte_Count'Last then
         Self.Counts.Refusals := Self.Counts.Refusals + 1;
      end if;
      raise Allocation_Error;
   end Count_Refusal;

   procedure Check_Growth
     (Self : in out Owner; Old_Size, New_Size : Byte_Count)
   is
      Remaining : constant Byte_Count := Self.Counts.Raw_Bytes - Old_Size;
   begin
      if Self.Closed then
         raise Program_Error with "closed storage owner";
      end if;
      if New_Size <= Old_Size then
         return;
      end if;
      if Self.Counts.Growth_Attempts < Byte_Count'Last then
         Self.Counts.Growth_Attempts := Self.Counts.Growth_Attempts + 1;
      end if;
      if New_Size > Byte_Count'Last - Remaining or else
        Remaining > Self.Ceiling or else
        New_Size > Self.Ceiling - Remaining or else
        (Self.Injecting and then Self.Countdown = 0)
      then
         Count_Refusal (Self);
      end if;
   end Check_Growth;

   function Allocate
     (Self : in out Owner; Size : Byte_Count;
      Alignment : Byte_Count := 1) return System.Address
   is
      Total : Byte_Count;
      Raw, User : System.Address;
      Item : Headers.Object_Pointer;
   begin
      if Size = 0 then
         if Self.Closed then
            raise Program_Error with "closed storage owner";
         end if;
         return System.Null_Address;
      end if;
      begin
         Total := Raw_Size_For (Size, Alignment);
      exception
         when Allocation_Error => Count_Refusal (Self);
      end;
      Check_Growth (Self, 0, Total);
      Raw := Self.Provider
        (Self.Provider_Data, System.Null_Address, 0,
         Interfaces.C.size_t (Total));
      if Raw = System.Null_Address then
         Count_Refusal (Self);
      end if;
      User := User_Address (Raw, Alignment);
      Item := Headers.To_Pointer (Raw);
      Item.all := (Self'Unchecked_Access, System.Null_Address, Self.First,
                   Raw, Total, User, Size, Alignment);
      Addresses.To_Pointer (User - Pointer_Size).all := Raw;

      --  Publication is last. Until this point no owner list, counters or
      --  countdown changed, so a provider refusal leaves the owner untouched.
      if Self.First /= System.Null_Address then
         Headers.To_Pointer (Self.First).Before := Raw;
      end if;
      Self.First := Raw;
      Self.Counts.Live_Blocks := Self.Counts.Live_Blocks + 1;
      Self.Counts.Payload_Bytes := Self.Counts.Payload_Bytes + Size;
      Self.Counts.Raw_Bytes := Self.Counts.Raw_Bytes + Total;
      Self.Counts.Peak_Raw_Bytes := Byte_Count'Max
        (Self.Counts.Peak_Raw_Bytes, Self.Counts.Raw_Bytes);
      if Self.Injecting then
         Self.Countdown := Self.Countdown - 1;
      end if;
      return User;
   end Allocate;

   procedure Reallocate
     (Self : in out Owner; Block : in out System.Address;
      Size : Byte_Count)
   is
      Old : Headers.Object_Pointer;
      Saved : Header;
      Total, Old_Offset : Byte_Count;
      Raw, User : System.Address;
   begin
      if Block = System.Null_Address then
         Block := Allocate (Self, Size);
         return;
      elsif Size = 0 then
         Release (Self, Block);
         return;
      end if;
      Old := Header_Of (Block);
      if Old.Parent /= Self'Unchecked_Access then
         raise Program_Error with "allocation belongs to another owner";
      end if;
      if Size = Old.Size then
         return;
      end if;
      Saved := Old.all;
      begin
         Total := Raw_Size_For (Size, Saved.Alignment);
      exception
         when Allocation_Error => Count_Refusal (Self);
      end;
      Check_Growth (Self, Saved.Raw_Size, Total);
      Old_Offset := Saved.User - Saved.Raw;
      Raw := Self.Provider
        (Self.Provider_Data, Saved.Raw, Interfaces.C.size_t (Saved.Raw_Size),
         Interfaces.C.size_t (Total));
      if Raw = System.Null_Address then
         Count_Refusal (Self);
      end if;

      --  Realloc may invalidate Old and change the alignment displacement.
      --  Saved contains every link needed to repair the list without reading
      --  released storage. The reserved padding keeps the old payload prefix
      --  present even when the raw provider shrinks before moving it for us.
      User := User_Address (Raw, Saved.Alignment);
      Copy (Raw + Old_Offset, User, Byte_Count'Min (Saved.Size, Size));
      Old := Headers.To_Pointer (Raw);
      Old.all := (Saved.Parent, Saved.Before, Saved.After,
                  Raw, Total, User, Size, Saved.Alignment);
      Addresses.To_Pointer (User - Pointer_Size).all := Raw;
      if Saved.Before = System.Null_Address then
         Self.First := Raw;
      else
         Headers.To_Pointer (Saved.Before).After := Raw;
      end if;
      if Saved.After /= System.Null_Address then
         Headers.To_Pointer (Saved.After).Before := Raw;
      end if;
      Self.Counts.Payload_Bytes :=
        Self.Counts.Payload_Bytes - Saved.Size + Size;
      Self.Counts.Raw_Bytes := Self.Counts.Raw_Bytes - Saved.Raw_Size + Total;
      Self.Counts.Peak_Raw_Bytes := Byte_Count'Max
        (Self.Counts.Peak_Raw_Bytes, Self.Counts.Raw_Bytes);
      if Self.Injecting and then Total > Saved.Raw_Size then
         Self.Countdown := Self.Countdown - 1;
      end if;
      Block := User;
   end Reallocate;

   procedure Release (Self : in out Owner; Block : in out System.Address) is
      Saved : Header;
      Unused : System.Address;
   begin
      if Block = System.Null_Address then
         return;
      end if;
      Saved := Header_Of (Block).all;
      if Saved.Parent /= Self'Unchecked_Access then
         raise Program_Error with "allocation belongs to another owner";
      end if;
      if Saved.Before = System.Null_Address then
         Self.First := Saved.After;
      else
         Headers.To_Pointer (Saved.Before).After := Saved.After;
      end if;
      if Saved.After /= System.Null_Address then
         Headers.To_Pointer (Saved.After).Before := Saved.Before;
      end if;
      Self.Counts.Live_Blocks := Self.Counts.Live_Blocks - 1;
      Self.Counts.Payload_Bytes := Self.Counts.Payload_Bytes - Saved.Size;
      Self.Counts.Raw_Bytes := Self.Counts.Raw_Bytes - Saved.Raw_Size;
      Block := System.Null_Address;
      Unused := Self.Provider
        (Self.Provider_Data, Saved.Raw,
         Interfaces.C.size_t (Saved.Raw_Size), 0);
      pragma Unreferenced (Unused);
   end Release;

   procedure Release_All (Self : in out Owner) is
      Item : System.Address;
   begin
      while Self.First /= System.Null_Address loop
         Item := Headers.To_Pointer (Self.First).User;
         Release (Self, Item);
      end loop;
   end Release_All;

   function Owns (Self : Owner; Block : System.Address) return Boolean is
      Cursor : System.Address := Self.First;
   begin
      while Cursor /= System.Null_Address loop
         if Headers.To_Pointer (Cursor).User = Block then
            return True;
         end if;
         Cursor := Headers.To_Pointer (Cursor).After;
      end loop;
      return False;
   end Owns;

   function Allocation_Size (Block : System.Address) return Byte_Count is
     (if Block = System.Null_Address then 0 else Header_Of (Block).Size);
   function Allocation_Alignment (Block : System.Address) return Byte_Count is
     (if Block = System.Null_Address then 0 else Header_Of (Block).Alignment);
   function Statistics (Self : Owner) return Allocation_Statistics is
     (Self.Counts);
   function Refusal_Pending (Self : Owner) return Boolean is
     (Self.Pending_Refusal);
   procedure Acknowledge_Refusal (Self : in out Owner) is
   begin
      Self.Pending_Refusal := False;
   end Acknowledge_Refusal;
   function Allocator (Self : Owner) return Allocation_Function is
     (Self.Provider);
   function Userdata (Self : Owner) return System.Address is
     (Self.Provider_Data);

   procedure Set_Allocator
     (Self : in out Owner; Allocate : not null Allocation_Function;
      Data : System.Address := System.Null_Address)
   is
   begin
      if Self.Closed then
         raise Program_Error with "closed storage owner";
      end if;
      Self.Provider := Allocate;
      Self.Provider_Data := Data;
   end Set_Allocator;

   procedure Set_Ceiling (Self : in out Owner; Bytes : Byte_Count) is
   begin
      Self.Ceiling := Bytes;
   end Set_Ceiling;

   procedure Set_Failure_Countdown
     (Self : in out Owner; Successful_Growths : Byte_Count)
   is
   begin
      Self.Countdown := Successful_Growths;
      Self.Injecting := True;
   end Set_Failure_Countdown;

   procedure Clear_Failures (Self : in out Owner) is
   begin
      Self.Injecting := False;
   end Clear_Failures;

   function Handle (Self : in out Owner) return not null Subpool_Handle is
   begin
      if Self.Closed then
         raise Program_Error with "closed storage owner";
      end if;
      return Self.Area'Unchecked_Access;
   end Handle;

   function Reference (Self : in out Owner) return not null Owner_Access is
   begin
      if Self.Closed then
         raise Program_Error with "closed storage owner";
      end if;
      return Self'Unchecked_Access;
   end Reference;

   overriding procedure Initialize (Self : in out Owner) is
   begin
      Self.Area.Parent := Self'Unchecked_Access;
      System.Storage_Pools.Subpools.Set_Pool_Of_Subpool
        (Self.Area'Unchecked_Access, Pool);
   end Initialize;

   procedure Close (Self : in out Owner) is
      Area : Subpool_Handle;
   begin
      if Self.Closed then
         return;
      end if;
      Self.Closed := True;
      Area := Self.Area'Unchecked_Access;
      begin
         --  The language runtime finalizes all controlled allocations first.
         --  Our Deallocate_Subpool then releases the remaining raw blocks.
         Ada.Unchecked_Deallocate_Subpool (Area);
      exception
         when others =>
            --  GNAT finalizes every object before propagating a finalizer
            --  exception, but that exception precedes detaching the subpool
            --  from its parent's list. A second standard deallocation skips
            --  the already finalized collection and completes that detach.
            --  Freeing raw blocks first would leave a dangling pool-list node
            --  and make process-level pool finalization loop indefinitely.
            Ada.Unchecked_Deallocate_Subpool (Area);
            Release_All (Self);
            raise;
      end;
   end Close;

   overriding procedure Finalize (Self : in out Owner) is
   begin
      Close (Self);
   end Finalize;

   overriding function Create_Subpool
     (Self : in out Pool_Type) return not null Subpool_Handle
   is
      pragma Unreferenced (Self);
   begin
      return raise Program_Error with "construct an explicit storage owner";
   end Create_Subpool;

   overriding function Default_Subpool_For_Pool
     (Self : in out Pool_Type) return not null Subpool_Handle
   is
      pragma Unreferenced (Self);
   begin
      return raise Program_Error with "runtime allocation requires an owner";
   end Default_Subpool_For_Pool;

   overriding procedure Allocate_From_Subpool
     (Self : in out Pool_Type; Address : out System.Address;
      Size, Alignment : Byte_Count; Subpool : not null Subpool_Handle)
   is
      pragma Unreferenced (Self);
   begin
      Address := Allocate
        (Managed_Subpool (Subpool.all).Parent.all,
         Byte_Count'Max (1, Size), Byte_Count'Max (1, Alignment));
   end Allocate_From_Subpool;

   overriding procedure Deallocate
     (Self : in out Pool_Type; Address : System.Address;
      Size, Alignment : Byte_Count)
   is
      pragma Unreferenced (Self, Size, Alignment);
      Item : System.Address := Address;
      Parent : constant Owner_Access := Header_Of (Address).Parent;
   begin
      Release (Parent.all, Item);
   end Deallocate;

   overriding procedure Deallocate_Subpool
     (Self : in out Pool_Type; Subpool : in out Subpool_Handle)
   is
      pragma Unreferenced (Self);
   begin
      --  The subpool descriptor is embedded in its limited owner, so only its
      --  blocks are freed here. Never deallocate the descriptor independently.
      Release_All (Managed_Subpool (Subpool.all).Parent.all);
      Subpool := null;
   end Deallocate_Subpool;
end Lua.Storage;
