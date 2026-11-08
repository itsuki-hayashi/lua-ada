with Ada.Finalization;
with Ada.Unchecked_Deallocation;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Storage; use Lua.Storage;
with System;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;
with Test_Support;

package body Lua.Storage_Tests is
   use System.Storage_Elements;
   use type Interfaces.C.size_t;
   use type System.Address;

   --  A callback fixture records the raw contract at the provider boundary.
   --  Tests compare these observations with managed accounting rather than
   --  assuming the private header's size or the host's maximum alignment.
   type Provider_State is record
      Calls : Natural := 0;
      Live : Byte_Count := 0;
      Refuse_Growth : Boolean := False;
      Last_Old, Last_New : Interfaces.C.size_t := 0;
   end record;
   package Providers is new
     System.Address_To_Access_Conversions (Provider_State);
   package Bytes is new
     System.Address_To_Access_Conversions (Storage_Element);

   function Tracked
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
     with Convention => C;
   function Tracked
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
   is
      State : constant Providers.Object_Pointer := Providers.To_Pointer (Data);
      Result : System.Address;
   begin
      State.Calls := State.Calls + 1;
      State.Last_Old := Old_Size;
      State.Last_New := New_Size;
      if State.Refuse_Growth and then New_Size > Old_Size then
         return System.Null_Address;
      end if;
      Result := Default_Allocator (System.Null_Address, Block,
                                   Old_Size, New_Size);
      if New_Size = 0 or else Result /= System.Null_Address then
         State.Live := State.Live - Byte_Count (Old_Size) +
           Byte_Count (New_Size);
      end if;
      return Result;
   end Tracked;

   Alternate_Calls : Natural := 0;
   function Alternate
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
     with Convention => C;
   function Alternate
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address is
   begin
      Alternate_Calls := Alternate_Calls + 1;
      return Tracked (Data, Block, Old_Size, New_Size);
   end Alternate;

   type Integer_Access is access Integer;
   for Integer_Access'Storage_Pool use Pool;
   procedure Free_Integer is new Ada.Unchecked_Deallocation
     (Integer, Integer_Access);

   Finalized : Natural := 0;
   type Probe is new Ada.Finalization.Limited_Controlled with record
      Raise_On_Finalize : Boolean := False;
   end record;
   overriding procedure Finalize (Self : in out Probe);
   overriding procedure Finalize (Self : in out Probe) is
   begin
      Finalized := Finalized + 1;
      if Self.Raise_On_Finalize then
         raise Constraint_Error with "test object finalizer";
      end if;
   end Finalize;
   type Probe_Access is access Probe;
   for Probe_Access'Storage_Pool use Pool;

   procedure Owner_Isolation;
   procedure Requested_Alignment;
   procedure Growth_Preserves_Bytes;
   procedure Shrink_Preserves_Bytes;
   procedure Provider_Refusal_Preserves_Block;
   procedure Raw_Size_Contract;
   procedure Countdown_And_Recovery;
   procedure Ceiling_Boundary;
   procedure Zero_Size_Operations;
   procedure Scope_Finalization_Releases;
   procedure Explicit_Typed_Subpool;
   procedure Implicit_Typed_Allocation_Rejected;
   procedure Controlled_Subpool_Finalization;
   procedure Raising_Finalizer_Releases;
   procedure Foreign_Owner_Rejected;
   procedure Unrepresentable_Size_Rejected;
   procedure Safe_Ownership_Query;
   procedure Retained_Provider_Release;
   procedure Retained_Provider_Data;

   procedure Owner_Isolation is
      First, Second : Owner;
      A : System.Address := Allocate (First, 17);
      B : System.Address := Allocate (Second, 23);
   begin
      --  Two owners allocate distinct blocks. Releasing one must not change
      --  the other's list or counts, protecting per-universe isolation.
      Assert (Owns (First, A) and not Owns (Second, A), "first ownership");
      Release (First, A);
      Assert (Statistics (First).Raw_Bytes = 0, "first empty");
      Assert (Statistics (Second).Payload_Bytes = 23, "second unchanged");
      Release (Second, B);
   end Owner_Isolation;

   procedure Requested_Alignment is
      Memory : Owner;
      Alignments : constant array (Positive range <>) of Byte_Count :=
        [1, 2, 3, 8, 16, 64, 256];
      Block : System.Address;
   begin
      --  Include a non-power-of-two request. The returned payload and stored
      --  backlink must both be aligned, while every payload byte is writable.
      for Alignment of Alignments loop
         Block := Allocate (Memory, 31, Alignment);
         Assert (Block mod Alignment = 0, "requested payload alignment");
         Assert (Allocation_Alignment (Block) = Alignment,
                 "recorded alignment");
         for Offset in Storage_Offset range 0 .. 30 loop
            Bytes.To_Pointer (Block + Offset).all := 16#A5#;
         end loop;
         Assert (Bytes.To_Pointer (Block + 30).all = 16#A5#, "payload end");
         Release (Memory, Block);
      end loop;
      Assert (Statistics (Memory).Live_Blocks = 0, "all blocks released");
   end Requested_Alignment;

   procedure Growth_Preserves_Bytes is
      Memory : Owner;
      Block : System.Address := Allocate (Memory, 64, 256);
   begin
      --  The default adapter moves raw storage. Growing a highly aligned
      --  block must repair list links and any changed displacement safely.
      for Offset in Storage_Offset range 0 .. 63 loop
         Bytes.To_Pointer (Block + Offset).all := Storage_Element (Offset);
      end loop;
      Reallocate (Memory, Block, 1_024);
      Assert (Block mod 256 = 0, "growth retained alignment");
      Assert (Allocation_Size (Block) = 1_024, "growth retained size");
      for Offset in Storage_Offset range 0 .. 63 loop
         Assert (Bytes.To_Pointer (Block + Offset).all =
                   Storage_Element (Offset), "growth preserved byte");
      end loop;
      Release (Memory, Block);
   end Growth_Preserves_Bytes;

   procedure Shrink_Preserves_Bytes is
      Memory : Owner;
      Block : System.Address := Allocate (Memory, 256, 64);
   begin
      --  A zero ceiling must still allow shrinking existing storage. This
      --  protects error-recovery paths that reduce memory while over quota.
      Bytes.To_Pointer (Block).all := 41;
      Bytes.To_Pointer (Block + 16).all := 42;
      Set_Ceiling (Memory, 0);
      Reallocate (Memory, Block, 17);
      Assert (Bytes.To_Pointer (Block).all = 41, "first shrink byte");
      Assert (Bytes.To_Pointer (Block + 16).all = 42, "last shrink byte");
      Assert (Allocation_Size (Block) = 17, "shrunken payload size");
      Release (Memory, Block);
   end Shrink_Preserves_Bytes;

   procedure Provider_Refusal_Preserves_Block is
      State : aliased Provider_State;
      Memory : Owner;
      Block, Original : System.Address;
      Before : Allocation_Statistics;
      Refused : Boolean := False;
   begin
      --  Refuse a resize in the actual callback. The caller's address, bytes,
      --  raw accounting and allocation-list identity must all remain valid.
      Set_Allocator (Memory, Tracked'Access, State'Address);
      Block := Allocate (Memory, 19, 64);
      Original := Block;
      Bytes.To_Pointer (Block).all := 77;
      Before := Statistics (Memory);
      State.Refuse_Growth := True;
      begin
         Reallocate (Memory, Block, 2_048);
      exception
         when Allocation_Error => Refused := True;
      end;
      Assert (Refused and Block = Original, "refusal retained address");
      Assert (Bytes.To_Pointer (Block).all = 77, "refusal retained byte");
      Assert (Statistics (Memory).Raw_Bytes = Before.Raw_Bytes,
              "refusal retained raw size");
      Assert (Owns (Memory, Block), "refusal retained ownership");
      Assert (State.Live = Before.Raw_Bytes, "provider live bytes");
      Release (Memory, Block);
      Assert (State.Live = 0, "refused provider balanced");
   end Provider_Refusal_Preserves_Block;

   procedure Raw_Size_Contract is
      State : aliased Provider_State;
      Memory : Owner;
      Block : System.Address;
      Before : Byte_Count;
   begin
      --  Observe exact callback sizes through allocation, resize and release.
      --  Metadata/padding are real storage and remain in the raw totals.
      Set_Allocator (Memory, Tracked'Access, State'Address);
      Block := Allocate (Memory, 31, 64);
      Before := Statistics (Memory).Raw_Bytes;
      Assert (State.Last_Old = 0 and State.Live = Before, "initial raw size");
      Reallocate (Memory, Block, 95);
      Assert (Byte_Count (State.Last_Old) = Before, "resize old raw size");
      Assert (State.Live = Statistics (Memory).Raw_Bytes, "resize raw total");
      Before := State.Live;
      Release (Memory, Block);
      Assert (Byte_Count (State.Last_Old) = Before and State.Last_New = 0,
              "release old raw size");
      Assert (State.Live = 0, "raw contract balanced");
   end Raw_Size_Contract;

   procedure Countdown_And_Recovery is
      Memory : Owner;
      Block : System.Address;
      Refused : Boolean := False;
   begin
      --  Permit one growth, then reject the next. Clearing injection must let
      --  the same owner recover without discarding the original allocation.
      Set_Failure_Countdown (Memory, 1);
      Block := Allocate (Memory, 8);
      begin
         Reallocate (Memory, Block, 16);
      exception
         when Allocation_Error => Refused := True;
      end;
      Assert (Refused and Allocation_Size (Block) = 8, "injected growth");
      Clear_Failures (Memory);
      Reallocate (Memory, Block, 16);
      Assert (Allocation_Size (Block) = 16, "injection recovery");
      Release (Memory, Block);
   end Countdown_And_Recovery;

   procedure Ceiling_Boundary is
      Memory : Owner;
      Block, Extra : System.Address;
      Limit : Byte_Count;
      Refused : Boolean := False;
   begin
      --  Measure the raw size once, then set exactly that ceiling. The first
      --  equal request succeeds; a second live block is rejected before use.
      Block := Allocate (Memory, 41);
      Limit := Statistics (Memory).Raw_Bytes;
      Release (Memory, Block);
      Set_Ceiling (Memory, Limit);
      Block := Allocate (Memory, 41);
      begin
         Extra := Allocate (Memory, 1);
         Release (Memory, Extra);
      exception
         when Allocation_Error => Refused := True;
      end;
      Assert (Refused, "second block exceeded exact ceiling");
      Assert (Statistics (Memory).Raw_Bytes = Limit, "ceiling preserved live");
      Assert (Statistics (Memory).Refusals = 1, "one ceiling refusal");
      Release (Memory, Block);
   end Ceiling_Boundary;

   procedure Zero_Size_Operations is
      Memory : Owner;
      Block : System.Address := Allocate (Memory, 0);
   begin
      --  Empty buffers need no storage. Reallocating null creates a block,
      --  and reallocating to zero releases it and clears the owned address.
      Assert (Block = System.Null_Address, "empty allocation is null");
      Reallocate (Memory, Block, 13);
      Assert (Allocation_Size (Block) = 13, "null resize allocated");
      Reallocate (Memory, Block, 0);
      Assert (Block = System.Null_Address, "zero resize released");
      Release (Memory, Block);
      Assert (Statistics (Memory).Live_Blocks = 0, "zero release harmless");
   end Zero_Size_Operations;

   procedure Scope_Finalization_Releases is
      State : aliased Provider_State;
   begin
      --  Deliberately leave raw blocks owned by a nested universe. Its normal
      --  Ada scope exit must return all managed bytes through its callback.
      declare
         Memory : Owner;
         A, B : System.Address;
      begin
         Set_Allocator (Memory, Tracked'Access, State'Address);
         A := Allocate (Memory, 71);
         B := Allocate (Memory, 53);
         Assert (Owns (Memory, A) and Owns (Memory, B), "scope allocations");
      end;
      Assert (State.Live = 0, "scope finalized callback bytes");
   end Scope_Finalization_Releases;

   procedure Explicit_Typed_Subpool is
      Memory : Owner;
      Item : Integer_Access := new (Handle (Memory)) Integer'(42);
   begin
      --  Exercise Ada's actual allocator syntax and Unchecked_Deallocation,
      --  rather than testing only the raw helper used underneath the pool.
      Assert (Item.all = 42, "typed value initialized");
      Assert (Statistics (Memory).Live_Blocks = 1, "typed block tracked");
      Free_Integer (Item);
      Assert (Item = null and Statistics (Memory).Live_Blocks = 0,
              "typed release accounted");
   end Explicit_Typed_Subpool;

   procedure Implicit_Typed_Allocation_Rejected is
      Item : Integer_Access;
      Rejected : Boolean := False;
   begin
      --  Omitting the universe must fail deterministically. A hidden global
      --  default subpool would route future C states to the wrong allocator.
      begin
         Item := new Integer'(42);
      exception
         when Program_Error => Rejected := True;
      end;
      Assert (Rejected and Item = null, "implicit allocation rejected");
   end Implicit_Typed_Allocation_Rejected;

   procedure Controlled_Subpool_Finalization is
      Memory : Owner;
      Item : Probe_Access;
   begin
      --  Closing a subpool must finalize objects before releasing their raw
      --  storage. A second Close and the later owner finalizer are harmless.
      Finalized := 0;
      Item := new (Handle (Memory)) Probe;
      Assert (not Item.Raise_On_Finalize, "probe initialized");
      Close (Memory);
      Close (Memory);
      Assert (Finalized = 1, "one controlled finalization");
      Assert (Statistics (Memory).Live_Blocks = 0, "controlled block freed");
   end Controlled_Subpool_Finalization;

   procedure Raising_Finalizer_Releases is
      State : aliased Provider_State;
      Memory : Owner;
      Item : Probe_Access;
      Raised : Boolean := False;
   begin
      --  A client finalizer raises during Close. The exception is observable,
      --  but no blocks may leak or be freed twice on owner scope exit.
      Finalized := 0;
      Set_Allocator (Memory, Tracked'Access, State'Address);
      Item := new (Handle (Memory)) Probe;
      Item.Raise_On_Finalize := True;
      begin
         Close (Memory);
      exception
         when Constraint_Error | Program_Error => Raised := True;
      end;
      Assert (Raised and Finalized = 1, "finalizer failure propagated");
      Assert (State.Live = 0, "raising finalizer released raw storage");
   end Raising_Finalizer_Releases;

   procedure Foreign_Owner_Rejected is
      First, Second : Owner;
      Block : System.Address := Allocate (First, 19);
      Rejected : Boolean := False;
   begin
      --  Accidentally returning a valid block to another universe must fail
      --  before either list or allocator is changed; the original can free it.
      begin
         Release (Second, Block);
      exception
         when Program_Error => Rejected := True;
      end;
      Assert (Rejected and Owns (First, Block), "foreign release rejected");
      Assert (Statistics (Second).Raw_Bytes = 0, "foreign owner unchanged");
      Release (First, Block);
   end Foreign_Owner_Rejected;

   procedure Unrepresentable_Size_Rejected is
      Memory : Owner;
      Block, Extra : System.Address;
      Refused : Boolean := False;
   begin
      --  A mathematically overflowing header+payload request must produce the
      --  controlled exception before provider invocation or corruption.
      Block := Allocate (Memory, 7);
      begin
         Extra := Allocate (Memory, Byte_Count'Last);
         Release (Memory, Extra);
      exception
         when Allocation_Error => Refused := True;
      end;
      Assert (Refused and Owns (Memory, Block),
              "oversize allocation rejected");
      Release (Memory, Block);
   end Unrepresentable_Size_Rejected;

   procedure Safe_Ownership_Query is
      Memory : Owner;
      Block : System.Address := Allocate (Memory, 8);
      Old : constant System.Address := Block;
   begin
      --  Diagnostics may be given arbitrary/stale addresses. Query by list
      --  identity, never by dereferencing an untrusted backlink before them.
      Assert (not Owns (Memory, To_Address (1)), "arbitrary address query");
      Release (Memory, Block);
      Assert (not Owns (Memory, Old), "released address query");
      Assert (not Owns (Memory, System.Null_Address), "null address query");
   end Safe_Ownership_Query;

   procedure Retained_Provider_Release is
      State : aliased Provider_State;
      Memory : Owner;
      First, Second : System.Address;
   begin
      --  Two compatible providers share accounting. Publishing an external
      --  payload retains the first callback while ordinary owned bytes use
      --  the replacement; both still retire the same owner's actual list.
      Set_Allocator (Memory, Tracked'Access, State'Address);
      First := Allocate (Memory, 64);
      Second := Allocate (Memory, 128);
      Alternate_Calls := 0;
      Set_Allocator (Memory, Alternate'Access, State'Address);
      Release_Using (Memory, First, Tracked'Access, State'Address);
      Assert (First = System.Null_Address and then Alternate_Calls = 0,
              "retained function releases its transferred allocation");
      Assert (Owns (Memory, Second) and then
                Statistics (Memory).Payload_Bytes = 128 and then
                Statistics (Memory).Live_Blocks = 1,
              "retained release preserves the other actual ownership");
      Release (Memory, Second);
      Assert (Alternate_Calls = 1 and then State.Live = 0 and then
                Statistics (Memory).Raw_Bytes = 0,
              "replacement releases remaining owned bytes without leaks");
   end Retained_Provider_Release;

   procedure Retained_Provider_Data is
      Original, Replacement : aliased Provider_State;
      Memory : Owner;
      Block : System.Address;
   begin
      --  A provider function can be unchanged while its opaque data changes.
      --  The transferred payload must retain that pair, rather than borrowing
      --  the owner's later userdata when its external release eventually runs.
      Set_Allocator (Memory, Tracked'Access, Original'Address);
      Block := Allocate (Memory, 64);
      Set_Allocator (Memory, Tracked'Access, Replacement'Address);
      Release_Using (Memory, Block, Tracked'Access, Original'Address);
      Assert (Original.Live = 0 and then Original.Last_New = 0 and then
                Replacement.Calls = 0 and then
                Statistics (Memory).Live_Blocks = 0,
              "retained data receives release after provider replacement");
   end Retained_Provider_Data;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "storage: owner isolation",
                        Owner_Isolation'Access);
      Test_Support.Add (Suite, "storage: requested alignment",
                        Requested_Alignment'Access);
      Test_Support.Add (Suite, "storage: growth preserves bytes",
                        Growth_Preserves_Bytes'Access);
      Test_Support.Add (Suite, "storage: shrink preserves bytes",
                        Shrink_Preserves_Bytes'Access);
      Test_Support.Add (Suite, "storage: callback refusal preserves block",
                        Provider_Refusal_Preserves_Block'Access);
      Test_Support.Add (Suite, "storage: exact raw callback sizes",
                        Raw_Size_Contract'Access);
      Test_Support.Add (Suite, "storage: failure countdown recovery",
                        Countdown_And_Recovery'Access);
      Test_Support.Add (Suite, "storage: raw ceiling boundary",
                        Ceiling_Boundary'Access);
      Test_Support.Add (Suite, "storage: zero size operations",
                        Zero_Size_Operations'Access);
      Test_Support.Add (Suite, "storage: scope finalization",
                        Scope_Finalization_Releases'Access);
      Test_Support.Add (Suite, "storage: explicit typed subpool",
                        Explicit_Typed_Subpool'Access);
      Test_Support.Add (Suite, "storage: implicit allocation rejected",
                        Implicit_Typed_Allocation_Rejected'Access);
      Test_Support.Add (Suite, "storage: controlled finalization",
                        Controlled_Subpool_Finalization'Access);
      Test_Support.Add (Suite, "storage: raising finalizer cleanup",
                        Raising_Finalizer_Releases'Access);
      Test_Support.Add (Suite, "storage: foreign owner rejection",
                        Foreign_Owner_Rejected'Access);
      Test_Support.Add (Suite, "storage: unrepresentable allocation",
                        Unrepresentable_Size_Rejected'Access);
      Test_Support.Add (Suite, "storage: safe ownership query",
                        Safe_Ownership_Query'Access);
      Test_Support.Add (Suite, "storage: retained provider release",
                        Retained_Provider_Release'Access);
      Test_Support.Add (Suite, "storage: retained provider data",
                        Retained_Provider_Data'Access);
   end Register;
end Lua.Storage_Tests;
