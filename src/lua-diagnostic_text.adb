with Ada.Unchecked_Deallocation;

package body Lua.Diagnostic_Text is
   procedure Free is new Ada.Unchecked_Deallocation (Payload, Payload_Access);

   function Length (Self : Text) return Natural is (Self.Used);

   overriding procedure Adjust (Self : in out Text) is
   begin
      if Self.Data /= null then
         --  Assignment copied only the pointer. Claim its immutable payload
         --  before publishing the independent handle; no allocator is used.
         --  Clear a rejected shallow pointer so failed Adjust cleanup cannot
         --  decrement the source's last reference.
         if Self.Data.References = Positive'Last then
            Self.Data := null;
            Self.Used := 0;
            raise Program_Error with "diagnostic reference count overflow";
         end if;
         Self.Data.References := Self.Data.References + 1;
      end if;
   end Adjust;

   overriding procedure Finalize (Self : in out Text) is
      Old : Payload_Access := Self.Data;
   begin
      --  Detach first, making explicit Clear and later automatic finalization
      --  idempotent. Exactly the final handle returns the selected block.
      Self.Data := null;
      Self.Used := 0;
      if Old /= null then
         if Old.References = 1 then
            Free (Old);
         else
            Old.References := Old.References - 1;
         end if;
      end if;
   end Finalize;

   procedure Clear (Self : in out Text) is
   begin
      Finalize (Self);
   end Clear;

   procedure Set_Value
     (Self : in out Text; Memory : not null Lua.Storage.Owner_Access;
      Bytes : String)
   is
      Fresh : Payload_Access;
   begin
      if Bytes'Length <= Inline_Capacity then
         --  A callback can provide a view into the old payload. Copy that
         --  bounded prefix before releasing its final reference.
         declare
            Saved : constant String := Bytes;
         begin
            Clear (Self);
            Self.Inline (1 .. Saved'Length) := Saved;
            Self.Used := Saved'Length;
         end;
      else
         --  Construct and fill the complete replacement before releasing any
         --  old storage. A refused provider call leaves Self and aliases
         --  intact; input-sized bytes live only in this managed payload.
         Fresh := new (Lua.Storage.Handle (Memory.all)) Payload (Bytes'Length);
         Fresh.Bytes := Bytes;
         Clear (Self);
         Self.Data := Fresh;
         Self.Used := Bytes'Length;
      end if;
   end Set_Value;

   function To_Text
     (Memory : not null Lua.Storage.Owner_Access; Bytes : String) return Text
   is
   begin
      return Result : Text do
         Set_Value (Result, Memory, Bytes);
      end return;
   end To_Text;

   procedure Query
     (Self : Text;
      Process : not null access procedure (Bytes : String))
   is
      Snapshot : constant Text := Self;
   begin
      --  An immutable snapshot needs no separate borrow allocation or mutable
      --  tampering counter. A callback may replace the original handle while
      --  this reference keeps the borrowed payload alive, also on exceptions.
      if Snapshot.Data = null then
         Process (Snapshot.Inline (1 .. Snapshot.Used));
      else
         Process (Snapshot.Data.Bytes);
      end if;
   end Query;

   function To_String (Self : Text) return String is
     (if Self.Data = null then Self.Inline (1 .. Self.Used)
      else Self.Data.Bytes);
end Lua.Diagnostic_Text;
