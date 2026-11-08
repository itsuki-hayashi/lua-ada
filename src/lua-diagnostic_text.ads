with Ada.Finalization;
with Lua.Storage;

private package Lua.Diagnostic_Text is
   --  Immutable runtime diagnostics. Short emergency messages live inline;
   --  longer messages share one block allocated by the selected universe.
   --  The owner must outlive every copy, including saved exception state.
   --  All handles sharing a payload follow that owner's serialization rule;
   --  copying or releasing them concurrently requires caller synchronization.
   type Text is new Ada.Finalization.Controlled with private;

   function Length (Self : Text) return Natural;
   --  Count bytes, including embedded NULs; this operation never allocates.
   function To_String (Self : Text) return String;
   --  Materialize a host result. Runtime consumers should use Query instead.
   procedure Query
     (Self : Text;
      Process : not null access procedure (Bytes : String));
   --  Borrow immutable bytes synchronously. A retained, allocation-free
   --  snapshot keeps them alive even if Process clears or replaces Self.
   --  Process must not close the storage owner or retain the borrowed view.
   procedure Set_Value
     (Self : in out Text; Memory : not null Lua.Storage.Owner_Access;
      Bytes : String);
   --  Replace atomically. Allocation refusal preserves the previous value;
   --  inline messages require no provider call, even under permanent refusal.
   procedure Clear (Self : in out Text);
   --  Release this reference without allocating; other copies remain valid.
   function To_Text
     (Memory : not null Lua.Storage.Owner_Access; Bytes : String) return Text;
   --  Construct through Memory. Controlled copies share immutable storage
   --  and never allocate, including failure propagation between contexts.

private
   Inline_Capacity : constant := 96;
   type Payload (Size : Natural) is record
      References : Positive := 1;
      Bytes : String (1 .. Size);
   end record;
   type Payload_Access is access Payload;
   for Payload_Access'Storage_Pool use Lua.Storage.Pool;

   type Text is new Ada.Finalization.Controlled with record
      Data : Payload_Access;
      Used : Natural := 0;
      Inline : String (1 .. Inline_Capacity) := [others => Character'Val (0)];
   end record;
   overriding procedure Adjust (Self : in out Text);
   overriding procedure Finalize (Self : in out Text);
end Lua.Diagnostic_Text;
