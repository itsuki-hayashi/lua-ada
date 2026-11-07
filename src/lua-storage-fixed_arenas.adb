with System.Address_To_Access_Conversions;

package body Lua.Storage.Fixed_Arenas is
   use System.Storage_Elements;
   use type Interfaces.C.size_t;
   use type System.Address;
   package Arenas is new System.Address_To_Access_Conversions (Arena);
   package Bytes is new System.Address_To_Access_Conversions (Storage_Element);

   function Allocate
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
     with Convention => C;

   function Allocate
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
   is
      Self : constant Arenas.Object_Pointer := Arenas.To_Pointer (Data);
      Alignment : constant Byte_Count := Header'Alignment;
      Padding, Start, Count : Byte_Count;
      Result : System.Address;
   begin
      if New_Size = 0 then
         --  Owner detaches and finalizes its actual typed/raw records. The
         --  arena keeps the bytes until its enclosing lexical scope ends;
         --  no free-list, hidden allocation or input-sized stack copy exists.
         return System.Null_Address;
      elsif New_Size > Interfaces.C.size_t (Self.Capacity) then
         return System.Null_Address;
      end if;
      Padding := Byte_Count
        ((Integer_Address (Alignment) -
          To_Integer (Self.Bytes'Address + Self.Taken) mod
            Integer_Address (Alignment)) mod Integer_Address (Alignment));
      if Padding > Self.Capacity - Self.Taken then
         return System.Null_Address;
      end if;
      Start := Self.Taken + Padding;
      Count := Byte_Count (New_Size);
      if Count > Self.Capacity - Start then
         return System.Null_Address;
      end if;
      Result := Self.Bytes'Address + Start;
      if Block /= System.Null_Address then
         --  A fresh nonoverlapping region is reserved before copying. The
         --  caller's old region and cursor survive refusal unchanged. Raw
         --  provider extents include Storage's real alignment/header bytes.
         for Offset in Byte_Count range 0 ..
           Byte_Count (Interfaces.C.size_t'Min (Old_Size, New_Size)) - 1
         loop
            Bytes.To_Pointer (Result + Offset).all :=
              Bytes.To_Pointer (Block + Offset).all;
         end loop;
      end if;
      Self.Taken := Start + Count;
      return Result;
   end Allocate;

   procedure Bind (Self : in out Arena; Memory : in out Owner) is
   begin
      if Self.Bound or else Statistics (Memory).Live_Blocks /= 0 then
         raise Program_Error with "fixed arena requires fresh ownership";
      end if;
      Set_Allocator (Memory, Allocate'Access, Self'Address);
      Self.Bound := True;
   end Bind;

   function Used (Self : Arena) return Byte_Count is (Self.Taken);
end Lua.Storage.Fixed_Arenas;
