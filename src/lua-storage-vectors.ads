with Ada.Containers;
with Ada.Finalization;
with Ada.Iterator_Interfaces;

generic
   type Element_Type is private;
   with function "=" (Left, Right : Element_Type) return Boolean is <>;
package Lua.Storage.Vectors is
   --  Positive-indexed, owner-carrying storage for runtime vectors. An empty
   --  default vector is unbound and cannot allocate until Set_Owner is called.
   --  Copies inherit the source owner; their buffers and elements are copied,
   --  never shared. Every borrower must die before its storage owner closes.
   subtype Count_Type is Ada.Containers.Count_Type;
   subtype Extended_Index is Natural;
   No_Index : constant Extended_Index := 0;

   type Cursor is private;
   No_Element : constant Cursor;
   function Has_Element (Position : Cursor) return Boolean;
   package Iterator_Interfaces is new
     Ada.Iterator_Interfaces (Cursor, Has_Element);

   type Constant_Reference_Type
     (Element : not null access constant Element_Type) is limited private
     with Implicit_Dereference => Element;
   type Reference_Type (Element : not null access Element_Type) is
     limited private
     with Implicit_Dereference => Element;
   --  References borrow the buffer until finalization. Structural changes
   --  are forbidden while a reference or iterator is live. Ordinary element
   --  assignment remains possible through a variable reference.

   type Vector is new Ada.Finalization.Controlled with private
     with Constant_Indexing => Constant_Reference,
          Variable_Indexing => Reference,
          Default_Iterator => Iterate,
          Iterator_Element => Element_Type;
   Empty_Vector : constant Vector;

   procedure Set_Owner (Self : in out Vector; Memory : not null Owner_Access);
   --  Bind an unallocated vector; rebinding to its existing owner is harmless.
   --  A different owner cannot replace the owner of an allocated buffer.
   function Owner_Of (Self : Vector) return Owner_Access;
   function Length (Self : Vector) return Count_Type;
   function Capacity (Self : Vector) return Count_Type;
   function Is_Empty (Self : Vector) return Boolean;
   function First_Index (Self : Vector) return Positive;
   function Last_Index (Self : Vector) return Extended_Index;
   function Element (Self : Vector; Index : Positive) return Element_Type;
   function Element (Position : Cursor) return Element_Type;
   function First_Element (Self : Vector) return Element_Type;
   function Last_Element (Self : Vector) return Element_Type;
   function Constant_Reference
     (Self : aliased Vector; Index : Positive) return Constant_Reference_Type;
   function Constant_Reference
     (Self : aliased Vector; Position : Cursor) return Constant_Reference_Type;
   function Reference
     (Self : aliased in out Vector; Index : Positive) return Reference_Type;
   function Reference
     (Self : aliased in out Vector; Position : Cursor) return Reference_Type;
   function Iterate
     (Self : Vector) return Iterator_Interfaces.Reversible_Iterator'Class;

   procedure Reserve_Capacity (Self : in out Vector; Capacity : Count_Type);
   --  Grow geometrically; never reduce existing capacity. Failed growth
   --  preserves the original elements, length, owner and buffer.
   procedure Set_Length (Self : in out Vector; Length : Count_Type);
   --  New elements receive ordinary Ada default initialization. As with Ada
   --  containers, a scalar without a default must be assigned before reading.
   procedure Append
     (Self : in out Vector; New_Item : Element_Type; Count : Count_Type := 1);
   procedure Append (Self : in out Vector; New_Item : Vector);
   procedure Insert
     (Self : in out Vector; Before : Positive;
      New_Item : Element_Type; Count : Count_Type := 1);
   procedure Prepend
     (Self : in out Vector; New_Item : Element_Type; Count : Count_Type := 1);
   procedure Delete
     (Self : in out Vector; Index : Positive; Count : Count_Type := 1);
   procedure Delete_First (Self : in out Vector; Count : Count_Type := 1);
   procedure Delete_Last (Self : in out Vector; Count : Count_Type := 1);
   procedure Clear (Self : in out Vector);
   --  Clear destroys live elements and retains capacity and owner binding.
   procedure Release (Self : in out Vector);
   --  Destroy elements and capacity while preserving the explicit owner.
   --  All borrowers must be gone before release, just as for structural edits.
   procedure Replace_Element
     (Self : in out Vector; Index : Positive; New_Item : Element_Type);
   procedure Swap (Self : in out Vector; First, Second : Positive);
   --  Exchange values without changing length/capacity or reference addresses.
   procedure Update_Element
     (Self : in out Vector; Index : Positive;
      Process : not null access procedure (Item : in out Element_Type));
   --  Update the actual stored element, without a copy of nested containers.
   function Contains (Self : Vector; Item : Element_Type) return Boolean;
   function Find_Index
     (Self : Vector; Item : Element_Type) return Extended_Index;
   function Copy (Self : Vector) return Vector;
   procedure Move (Target, Source : in out Vector);
   --  Finalize Target's previous elements, then transfer Source's allocation,
   --  capacity and owner without copying or allocating. Source becomes empty
   --  and unbound. Both buffers must be unborrowed; self-move has no effect.
   --  If Target cleanup raises, Source remains unchanged and owns its buffer.
   function "=" (Left, Right : Vector) return Boolean;
   function "&" (Left, Right : Vector) return Vector;
   --  Concatenate through Left's owner, or Right's when Left is unbound.
   --  Two unbound empty operands produce an unbound empty result.
   function To_Vector
     (Memory : not null Owner_Access; New_Item : Element_Type;
      Length : Count_Type) return Vector;

private
   --  A discriminated slot lets standard Ada finalize a removed element
   --  immediately without compiler-specific finalization intrinsics or an
   --  uninitialized dummy Element_Type value. Unused capacity holds no value.
   type Slot (Present : Boolean := False) is record
      case Present is
         when False => null;
         when True => Item : aliased Element_Type;
      end case;
   end record;
   type Slots is array (Positive range <>) of Slot;
   type Buffer (Capacity : Natural) is
     new Ada.Finalization.Limited_Controlled with record
      Borrows : aliased Natural := 0;
      Items : Slots (1 .. Capacity);
   end record;
   overriding procedure Finalize (Self : in out Buffer);
   type Buffer_Access is access Buffer;
   for Buffer_Access'Storage_Pool use Pool;

   type Cursor is record
      Storage : Buffer_Access;
      Index : Natural := 0;
   end record;
   No_Element : constant Cursor := (null, 0);

   type Counter_Access is access all Natural;
   for Counter_Access'Storage_Size use 0;
   type Borrow_Guard is new Ada.Finalization.Limited_Controlled with record
      Counter : Counter_Access;
   end record;
   overriding procedure Finalize (Self : in out Borrow_Guard);
   type Constant_Reference_Type
     (Element : not null access constant Element_Type) is limited record
      Guard : Borrow_Guard;
   end record;
   type Reference_Type
     (Element : not null access Element_Type) is limited record
      Guard : Borrow_Guard;
   end record;

   type Vector is new Ada.Finalization.Controlled with record
      Memory : Owner_Access;
      Data : Buffer_Access;
      Used : Natural := 0;
   end record;
   overriding procedure Adjust (Self : in out Vector);
   overriding procedure Finalize (Self : in out Vector);
   Empty_Vector : constant Vector :=
     (Ada.Finalization.Controlled with null, null, 0);

   type Iterator is new Ada.Finalization.Limited_Controlled and
     Iterator_Interfaces.Reversible_Iterator with record
      Storage : Buffer_Access;
      Length : Natural := 0;
   end record;
   overriding function First (Self : Iterator) return Cursor;
   overriding function Next
     (Self : Iterator; Position : Cursor) return Cursor;
   overriding function Last (Self : Iterator) return Cursor;
   overriding function Previous
     (Self : Iterator; Position : Cursor) return Cursor;
   overriding procedure Finalize (Self : in out Iterator);
end Lua.Storage.Vectors;
