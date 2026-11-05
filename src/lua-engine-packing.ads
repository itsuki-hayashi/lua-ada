with Interfaces.C;
with System;

package Lua.Engine.Packing is
   Short_Bytes : constant := Interfaces.C.short'Size / System.Storage_Unit;
   Int_Bytes : constant := Interfaces.C.int'Size / System.Storage_Unit;
   Long_Bytes : constant := Interfaces.C.long'Size / System.Storage_Unit;
   Size_Bytes : constant := Interfaces.C.size_t'Size / System.Storage_Unit;
   Float_Bytes : constant := Interfaces.C.C_float'Size / System.Storage_Unit;
   Double_Bytes : constant := Interfaces.C.double'Size / System.Storage_Unit;
   Maximum_Alignment : constant Positive := Positive'Max
     (Interfaces.C.long_double'Alignment, Positive'Max
        (Interfaces.C.double'Alignment, Positive'Max
           (Interfaces.C.long'Alignment, Positive'Max
              (Integer_Value'Alignment, System.Address'Alignment))));
   --  Native options follow the compiler's C ABI, including C99 long double
   --  alignment. An independent C probe verifies these values on each host.

   function Run
     (State : in out World; Name : String; Arguments : Values.Vector)
      return Values.Vector;
   --  Pack/unpack byte strings or calculate a mathematical packed size.
   --  @param State Owner of result strings and the shared work budget.
   --  @param Name One of pack, unpack, or packsize.
   --  @param Arguments Rooted native arguments in Lua source order.
   --  @return Results, including unpack's final one-based position.
end Lua.Engine.Packing;
