with Interfaces.C;
with System;

private package Lua.Runtime_Configuration is
   Name : constant String := "default";
   Compatible_Global : constant Boolean := True;
   Compatibility_Math : constant Boolean := False;
   Random_32_Bits : constant Boolean := False;
   Maximum_Stack : constant Positive := 1_000_000;
   Maximum_C_Calls : constant Positive := 200;
   Absolute_Line_Interval : constant Positive := 128;
   --  Maximum debug-word gap accepted by pinned ldebug.c:getbaseline.
   Auxiliary_Buffer_Bytes : constant Positive :=
     16 * (System.Address'Size / System.Storage_Unit) *
     (Interfaces.C.double'Size / System.Storage_Unit);
   --  Pinned LUAL_BUFFERSIZE derives from pointer/binary64 widths, not a
   --  machine path or manually selected native alignment assumption.
   --  Pinned ordinary Lua 5.5.1 build policy. These are semantic/runtime
   --  configuration constants, independent of bounded host session quotas.
end Lua.Runtime_Configuration;
