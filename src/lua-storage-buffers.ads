with Ada.Finalization;
with System;

package Lua.Storage.Buffers is
   --  Mutable owned byte strings for runtime builders. Byte length is
   --  independent of embedded NULs; an additional trailing NUL is maintained
   --  for C consumers. The owner must outlive every buffer and borrowed view.
   type Buffer is new Ada.Finalization.Controlled with private;
   procedure Set_Owner (Self : in out Buffer; Memory : not null Owner_Access);
   function Owner_Of (Self : Buffer) return Owner_Access;
   function Length (Self : Buffer) return Natural;
   function Capacity (Self : Buffer) return Natural;
   function Is_Empty (Self : Buffer) return Boolean;
   procedure Reserve_Capacity (Self : in out Buffer; Capacity : Natural);
   --  Grow geometrically. Refusal leaves the original bytes/length intact.
   procedure Append (Self : in out Buffer; Text : String);
   procedure Append (Self : in out Buffer; Item : Character);
   procedure Append (Self : in out Buffer; Source : in out Buffer);
   --  Append a borrowed view directly, with no unmanaged String snapshot.
   procedure Insert
     (Self : in out Buffer; Before : Positive; Text : String);
   procedure Delete
     (Self : in out Buffer; First : Positive; Last : Natural);
   --  Ordered byte mutation; an overlapping inserted source is snapshotted
   --  through the same managed owner before shifting the existing suffix.
   procedure Set_Value (Self : in out Buffer; Text : String);
   --  Strings may have arbitrary bounds and may alias the current payload.
   --  Aliased views are rebased after growth, without an unmanaged snapshot.
   procedure Clear (Self : in out Buffer);
   --  Retain allocator binding and capacity; clear only the logical contents.
   procedure Release (Self : in out Buffer);
   --  Release capacity while retaining the owner for later reuse.
   function Element (Self : Buffer; Index : Positive) return Character;
   procedure Replace_Element
     (Self : in out Buffer; Index : Positive; Item : Character);
   function To_String (Self : Buffer) return String;
   function Slice
     (Self : Buffer; First : Positive; Last : Natural) return String;
   --  These convenience functions create ordinary Ada String results. Use
   --  Query for runtime algorithms that must avoid an input-sized copy.
   procedure Query
     (Self : in out Buffer;
      Process : not null access procedure (Text : String));
   --  Invoke Process synchronously with a borrowed view of the actual bytes.
   --  Every mutation/relocation is rejected until Process returns, including
   --  exceptional return. Process must not retain the view or close the owner.
   function Address (Self : Buffer) return System.Address;
   --  Borrow the payload until mutation/release/finalization. Null means no
   --  allocation; the length, rather than a NUL scan, defines the byte string.
   function C_Address (Self : in out Buffer) return System.Address;
   --  Ensure even an empty buffer has an allocated trailing NUL, then borrow
   --  it under the same lifetime rules as Address. May allocate or refuse.
   function Copy (Self : Buffer) return Buffer;
   function To_Buffer
     (Memory : not null Owner_Access; Text : String) return Buffer;

private
   type Buffer is new Ada.Finalization.Controlled with record
      Memory : Owner_Access;
      Data : System.Address := System.Null_Address;
      Used : Natural := 0;
      Reserved : Natural := 0;
      Borrows : Natural := 0;
   end record;
   overriding procedure Adjust (Self : in out Buffer);
   overriding procedure Finalize (Self : in out Buffer);
end Lua.Storage.Buffers;
