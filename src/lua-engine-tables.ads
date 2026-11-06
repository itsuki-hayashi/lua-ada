with Interfaces;

private package Lua.Engine.Tables is
   function Hash_Bytes (Text : String) return Interfaces.Unsigned_64;
   --  Cache a byte string's hash at creation. Equal byte strings must have
   --  equal hashes even when they occupy different nonmoving heap objects.

   function Find (Table : Object_Access; Key : Value) return Natural;
   --  Return the member row, including a retained deletion tombstone, or zero.
   --  The direct integer index and collision chains borrow member storage.

   function Raw_Field (Table : Object_Access; Name : String) return Value;
   --  Lookup a byte-string field without constructing a temporary Lua string.
   --  Metamethod and collector queries must not allocate while inspecting it.

   procedure Put (State : in out World; Table : Object_Access;
                  Key, Item : Value);
   --  Grow indexes before publishing a new member. Failed allocation leaves
   --  existing bindings readable and keeps the owning world's count accurate.

   procedure Reserve
     (State : in out World; Table : Object_Access;
      Sequence_Size, Hash_Size : Natural);
   --  Reserve actual empty table storage without publishing keys or changing
   --  the sequence border. A failed reserve leaves a valid empty table.

   procedure Rebuild (Table : Object_Access);
   --  Reconstruct borrowed indexes after weak-key cleanup, without allocation.
   --  Clearing dead keys before calling this prevents stale heap references.
end Lua.Engine.Tables;
