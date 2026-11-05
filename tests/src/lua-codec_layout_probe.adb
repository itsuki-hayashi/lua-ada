with Ada.Strings.Fixed;
with Ada.Text_IO;
with Ada.Unchecked_Conversion;
with Interfaces;
with Interfaces.C;
with System;
with Lua.Engine;
with Lua.Engine.Packing;

procedure Lua.Codec_Layout_Probe is
   --  Each type is the Ada binding to the same C type measured by the
   --  standalone C99 probe. The report intentionally uses decimal ASCII.
   procedure Put (Name : String; Size, Alignment : Positive);
   procedure Item (Name : String; Value : Natural);
   procedure Item (Name : String; Value : Natural) is
   begin
      Ada.Text_IO.Put_Line (Name & "=" & Ada.Strings.Fixed.Trim
        (Value'Image, Ada.Strings.Both));
   end Item;
   procedure Put (Name : String; Size, Alignment : Positive) is
   begin
      Item (Name & ".size", Size / System.Storage_Unit);
      Item (Name & ".align", Alignment);
   end Put;
   type Four_Bytes is array (1 .. 4) of Character;
   function Bytes is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_32, Four_Bytes);
begin
   Item ("char.bits", System.Storage_Unit);
   Put ("cshort", Interfaces.C.short'Size, Interfaces.C.short'Alignment);
   Put ("cint", Interfaces.C.int'Size, Interfaces.C.int'Alignment);
   Put ("clong", Interfaces.C.long'Size, Interfaces.C.long'Alignment);
   Put ("csize", Interfaces.C.size_t'Size, Interfaces.C.size_t'Alignment);
   Put ("cfloat", Interfaces.C.C_float'Size, Interfaces.C.C_float'Alignment);
   Put ("cdouble", Interfaces.C.double'Size, Interfaces.C.double'Alignment);
   Put ("cldouble", Interfaces.C.long_double'Size,
        Interfaces.C.long_double'Alignment);
   Put ("linteger", Lua.Engine.Integer_Value'Size,
        Lua.Engine.Integer_Value'Alignment);
   Put ("lnumber", Lua.Engine.Real_Value'Size,
        Lua.Engine.Real_Value'Alignment);
   Item ("maximum.align", Lua.Engine.Packing.Maximum_Alignment);
   Item ("endian.little", Boolean'Pos (Character'Pos (Bytes (1) (1)) = 1));
end Lua.Codec_Layout_Probe;
