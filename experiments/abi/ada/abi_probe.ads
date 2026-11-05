with Interfaces.C;

package Abi_Probe is
   type Callback is access function
     (Value : Interfaces.C.int) return Interfaces.C.int
     with Convention => C;
   --  Probe callback: returns a status instead of jumping across Ada frames.

   function Invoke
     (Handler : Callback; Value : Interfaces.C.int) return Interfaces.C.int
     with Export, Convention => C, External_Name => "ada_probe_invoke";
   --  Invoke Handler and return its status to the C caller.
   --  @param Handler Non-null C callback with no nonlocal control transfer.
   --  @param Value Opaque test argument forwarded to Handler.
   --  @return Handler's result, or -1 for a null handler.
end Abi_Probe;
