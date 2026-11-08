with Interfaces.C;
with Lua.Storage.Buffers;
with System;

private package Lua.Engine.File_Inputs is
   type Outcome is (Ready, Open_Failure, Reopen_Failure, Read_Failure);
   type Result is record
      Status : Outcome := Ready;
      Error : Interfaces.C.int := 0;
   end record;
   --  Native errno is captured before any allocating error construction.
   function Message (Observed : Result; Filename : String) return String;
   --  Format the pinned open/reopen/read diagnostic after resource cleanup.

   procedure Read_All
     (State : in out World; Filename : System.Address;
      Output : in out Lua.Storage.Buffers.Buffer; Observed : out Result);
   --  Read a borrowed NUL-terminated native filename, or stdin for null.
   --  Own source-proportional bytes through State.Memory. Close every owned
   --  FILE before returning or propagating an exception; never close stdin.
   --  Open text first and reopen binary signatures in rb, as pinned loadfile.
   --  No Lua callback, execution transfer or foreign jump occurs here.

   procedure Prepare (Source : in out Lua.Storage.Buffers.Buffer);
   --  Apply the existing shared file-preamble policy in place, without a
   --  second source-sized temporary or a borrowed view across mutation.

end Lua.Engine.File_Inputs;
