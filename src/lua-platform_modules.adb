package body Lua.Platform_Modules is
   overriding procedure Finalize (Self : in out Code_Lease) is
   begin
      --  Close accepts a null reference too, including a main executable
      --  whose native loader does not offer a separately counted handle.
      Close (Self.Handle);
      Self.Handle := System.Null_Address;
   end Finalize;
end Lua.Platform_Modules;
