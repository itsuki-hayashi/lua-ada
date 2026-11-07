with System.Storage_Elements;

package Lua.Storage.Fixed_Arenas is
   Numeric_Scratch_Bytes : constant Byte_Count := 131_072;
   --  Conservative fixed bound for the existing binary64 exact parser and
   --  formatter. Input scanning retains 1,100 significant digits plus sticky
   --  state, so rational scratch is independent of the full input length.
   type Arena (Capacity : Byte_Count := Numeric_Scratch_Bytes) is
     limited private;
   procedure Bind (Self : in out Arena; Memory : in out Owner);
   --  Bind once to a fresh owner with no live blocks. Declare Self before
   --  Memory, finalize all borrowers then Memory before Self leaves scope.
   --  The provider uses only Self's fixed storage, never a backing allocator.
   --  Releases reclaim owner records; the bump cursor is not reused/reset.
   function Used (Self : Arena) return Byte_Count;
   --  Actual cumulative provider bytes, including alignment padding. This
   --  remains available after the bound owner has released every block.
private
   type Arena (Capacity : Byte_Count := Numeric_Scratch_Bytes) is
   limited record
      Bytes : System.Storage_Elements.Storage_Array (1 .. Capacity);
      Taken : Byte_Count := 0;
      Bound : Boolean := False;
   end record;
end Lua.Storage.Fixed_Arenas;
