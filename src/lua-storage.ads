with Ada.Finalization;
with Interfaces.C;
with System;
with System.Storage_Elements;
with System.Storage_Pools.Subpools;

private package Lua.Storage is
   --  Runtime storage is owned by one universe. A pool is only a dispatch
   --  point: allocator selection and accounting belong to the named owner,
   --  never to a process-wide current-state variable. All operations on one
   --  owner require serialization; independent owners share no allocation
   --  lists, quotas or failure-injection state.
   subtype Byte_Count is System.Storage_Elements.Storage_Count;
   subtype Subpool_Handle is
     System.Storage_Pools.Subpools.Subpool_Handle;

   type Allocation_Function is access function
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
     with Convention => C;
   --  Lua allocator convention: null on refusal, preserving Block; a zero
   --  New_Size releases Block and returns null. Successful resizing preserves
   --  min(Old_Size, New_Size) bytes. Callbacks must not raise exceptions or
   --  reenter the same owner. Their address and Data must outlive the owner.

   function Default_Allocator
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
     with Convention => C;
   --  Standard-Ada backing pool adapter, also usable as a C callback. It has
   --  realloc's failure guarantee; it does not import malloc or interpreter C.

   type Pool_Type is new
     System.Storage_Pools.Subpools.Root_Storage_Pool_With_Subpools
       with null record;

   overriding function Create_Subpool
     (Self : in out Pool_Type) return not null Subpool_Handle;
   overriding procedure Allocate_From_Subpool
     (Self : in out Pool_Type; Address : out System.Address;
      Size, Alignment : Byte_Count; Subpool : not null Subpool_Handle);
   overriding procedure Deallocate
     (Self : in out Pool_Type; Address : System.Address;
      Size, Alignment : Byte_Count);
   overriding procedure Deallocate_Subpool
     (Self : in out Pool_Type; Subpool : in out Subpool_Handle);
   overriding function Default_Subpool_For_Pool
     (Self : in out Pool_Type) return not null Subpool_Handle;

   Pool : Pool_Type;
   --  Associate runtime access types with this pool using Storage_Pool.
   --  Every allocator must explicitly name Handle(its owning universe).

   type Owner is new Ada.Finalization.Limited_Controlled with private;
   type Owner_Access is access all Owner;
   Allocation_Error : exception;
   --  Callback refusal, quota rejection or unrepresentable allocation size.
   --  The engine maps this private exception to a semantic Lua memory error;
   --  explicit execution quotas remain a separate host-abort mechanism.

   function Handle (Self : in out Owner) return not null Subpool_Handle;
   --  Borrow the stable subpool identity until Self is closed/finalized.
   --  No access value allocated on it may survive Self. Owner is limited so
   --  its embedded subpool cannot move or be copied into another universe.
   function Reference (Self : in out Owner) return not null Owner_Access;
   --  Borrow the same stable owner for allocator-aware containers. The caller
   --  must finalize every borrower before closing or finalizing Self.

   procedure Set_Allocator
     (Self : in out Owner; Allocate : not null Allocation_Function;
      Data : System.Address := System.Null_Address);
   --  Replace the current provider without moving existing blocks. As with
   --  lua_setallocf, the new callback must accept all existing raw blocks and
   --  their recorded sizes. It is the host's responsibility to ensure that
   --  the old and new providers are compatible.
   function Allocator (Self : Owner) return Allocation_Function;
   function Userdata (Self : Owner) return System.Address;

   procedure Set_Ceiling (Self : in out Owner; Bytes : Byte_Count);
   --  Bound total raw live bytes, including alignment/ownership metadata.
   --  Lowering below current use is allowed; releases and shrinking remain
   --  possible. This is an allocator ceiling, not an instruction quota.
   procedure Set_Failure_Countdown
     (Self : in out Owner; Successful_Growths : Byte_Count);
   --  Permit this many successful growth operations, then refuse subsequent
   --  growth until Clear_Failures. Shrinks, equal-size requests and releases
   --  never consume the countdown. No retry or collection is performed here:
   --  the engine owns emergency collection and its single retry policy.
   procedure Clear_Failures (Self : in out Owner);

   function Allocate
     (Self : in out Owner; Size : Byte_Count;
      Alignment : Byte_Count := 1) return System.Address;
   --  Allocate an uninitialized byte block. Zero size returns null without
   --  calling the provider. Positive alignment may be any positive count.
   --  @exception Allocation_Error The old owner state remains unchanged.
   procedure Reallocate
     (Self : in out Owner; Block : in out System.Address;
      Size : Byte_Count);
   --  Preserve alignment and the initial min(old size, Size) payload bytes.
   --  Only raw byte blocks may be resized: Ada objects with finalization or
   --  self-references require typed allocation and explicit ownership moves.
   --  Zero size releases Block. Null Block allocates with alignment one.
   --  @exception Allocation_Error Block and its original bytes remain valid.
   procedure Release (Self : in out Owner; Block : in out System.Address);
   --  Release a valid block belonging to Self, clearing the caller's address.
   --  Null is harmless. A live block from another owner raises Program_Error.

   type Allocation_Statistics is record
      Live_Blocks : Byte_Count := 0;
      Payload_Bytes : Byte_Count := 0;
      Raw_Bytes : Byte_Count := 0;
      Peak_Raw_Bytes : Byte_Count := 0;
      Growth_Attempts : Byte_Count := 0;
      Refusals : Byte_Count := 0;
   end record;
   function Statistics (Self : Owner) return Allocation_Statistics;
   --  Counts describe actual managed storage, not sampled process memory.
   function Refusal_Pending (Self : Owner) return Boolean;
   procedure Acknowledge_Refusal (Self : in out Owner);
   --  A failed controlled Adjust can be rethrown as Program_Error by Ada.
   --  The engine uses this witness to preserve semantic memory classification,
   --  then acknowledges it when producing the Lua error. It must never infer
   --  memory failure from an unrelated Ada exception without this witness.
   function Owns (Self : Owner; Block : System.Address) return Boolean;
   --  Safe diagnostic lookup, including arbitrary/non-owned addresses. This
   --  walks the allocation list; normal release/reallocate use O(1) backlinks.
   function Allocation_Size (Block : System.Address) return Byte_Count;
   function Allocation_Alignment (Block : System.Address) return Byte_Count;
   --  Inspect valid live managed blocks only; null yields zero.

   procedure Close (Self : in out Owner);
   --  Finalize typed subpool objects before releasing residual raw blocks.
   --  Idempotent. Even a raising object finalizer cannot leak the raw list.
   --  A closed owner cannot be reused; construct a fresh owner for reset.

private
   type Managed_Subpool is new
     System.Storage_Pools.Subpools.Root_Subpool with record
      Parent : Owner_Access;
   end record;

   type Owner is new Ada.Finalization.Limited_Controlled with record
      Area : aliased Managed_Subpool;
      First : System.Address := System.Null_Address;
      Provider : Allocation_Function := Default_Allocator'Access;
      Provider_Data : System.Address := System.Null_Address;
      Counts : Allocation_Statistics;
      Ceiling : Byte_Count := Byte_Count'Last;
      Countdown : Byte_Count := 0;
      Injecting : Boolean := False;
      Closed : Boolean := False;
      Pending_Refusal : Boolean := False;
   end record;
   overriding procedure Initialize (Self : in out Owner);
   overriding procedure Finalize (Self : in out Owner);
end Lua.Storage;
