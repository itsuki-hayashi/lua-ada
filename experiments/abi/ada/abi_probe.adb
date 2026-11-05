package body Abi_Probe is
   function Invoke
     (Handler : Callback; Value : Interfaces.C.int) return Interfaces.C.int
   is
      use type Interfaces.C.int;
   begin
      if Handler = null then
         return -1;
      end if;
      return Handler (Value);
   end Invoke;
end Abi_Probe;
