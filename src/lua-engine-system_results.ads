with Interfaces.C;

package Lua.Engine.System_Results is
   function File_Result
     (State : in out World; Succeeded : Boolean; Error : Interfaces.C.int;
      Filename : String := ""; Include_Name : Boolean := False)
      return Values.Vector;
   --  Construct true or nil/message/errno from the already captured native
   --  status. Error zero uses Lua's literal "(no extra info)". A filename is
   --  interpreted as a C prefix only in the error message, preserving the
   --  caller's separately retained Lua byte string and actual native errno.

   function Process_Result
     (State : in out World; Status, Error : Interfaces.C.int)
      return Values.Vector;
   --  Construct nil/message/errno for an errno-bearing process error, or the
   --  true/nil, exit/signal, status triple using native wait-status mechanics.
end Lua.Engine.System_Results;
