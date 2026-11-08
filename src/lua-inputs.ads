with Lua.Storage.Buffers;
with System;

private package Lua.Inputs is
   --  A frontend input is either a borrowed, immutable whole source or an
   --  owned growing byte buffer filled only when the shared parser/decoder
   --  requests a byte beyond those already supplied. Offsets are one-based.
   type Piece is record
      Address : System.Address := System.Null_Address;
      Length : Natural := 0;
   end record;
   type Refill_Function is access function
     (Context : System.Address) return Piece;
   --  Returned bytes remain valid until the next refill. Ensure copies them
   --  before invoking another refill; it never retains the foreign address.
   --  A guarded foreign adapter raises Reader_Error only after returning its
   --  actual callback status through the C-owned checkpoint above Ada.
   type Retry_Function is access function
     (Context : System.Address; Retried : in out Boolean) return Boolean;
   --  Optional universe emergency-collection policy for buffer growth. It
   --  must not replace the reader, reset its work budget or lose live roots.

   Reader_Error : exception;
   Input_Limit : exception;

   type Source is tagged limited private;
   procedure Borrow
     (Self : in out Source; Address : System.Address; Length : Natural);
   --  Borrow a fixed view until Self is no longer used. The caller owns its
   --  immutable backing storage; this explicit address never borrows a
   --  short-lived formal String descriptor or silently copies the source.
   procedure Open
     (Self : in out Source; Memory : not null Lua.Storage.Owner_Access;
      Refill : not null Refill_Function; Context : System.Address;
      Maximum_Bytes : Positive; Retry : Retry_Function := null);
   --  Source and every supplied callback/context borrow must stay alive
   --  through parsing/decoding. Its controlled buffer releases on all exits.
   function Available (Self : Source) return Natural;
   function Streaming (Self : Source) return Boolean;
   function Ensure (Self : in out Source; Last : Natural) return Boolean;
   --  Make inclusive Last available, or report actual reader EOF. Last=0
   --  requests no bytes. Only a missing byte can trigger another refill.
   --  @exception Reader_Error The guarded callback returned an error status.
   --  @exception Input_Limit A piece exceeds the configured source extent.
   --  @exception Lua.Storage.Allocation_Error Managed acquisition refused.
   function Ensure_Block
     (Self : in out Source; First : Positive; Count : Natural)
      return Boolean;
   --  A fixed-buffer binary block must fit in its current reader piece. A
   --  missing first byte may refill once; a split block fails without reading
   --  ahead into another piece, matching pinned luaZ_getaddr's contract.
   function Element (Self : Source; Index : Positive) return Character;
   --  Observe an already available byte; this operation never refills.
   procedure Query
     (Self : in out Source; First : Positive; Length : Natural;
      Process : not null access procedure (Text : String));
   --  Borrow an already available span synchronously. Process must not
   --  refill/mutate Self or retain its view. Empty spans need no allocation.

private
   type Source is tagged limited record
      Data : Lua.Storage.Buffers.Buffer;
      View : System.Address := System.Null_Address;
      View_Length : Natural := 0;
      Is_Stream : Boolean := False;
      Ended : Boolean := True;
      Refill : Refill_Function;
      Retry : Retry_Function;
      Context : System.Address := System.Null_Address;
      Maximum : Positive := Positive'Last;
      Piece_First : Positive := 1;
      Piece_Last : Natural := 0;
      Borrows : Natural := 0;
   end record;
end Lua.Inputs;
