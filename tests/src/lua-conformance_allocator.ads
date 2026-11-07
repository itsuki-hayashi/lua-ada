with Lua.Storage;

private package Lua.Conformance_Allocator is
   procedure Attach (Memory : not null Lua.Storage.Owner_Access);
   --  Interpose on the actual provider of the test launcher's one universe.
   --  Existing raw blocks are counted before interposition and remain owned
   --  by the original provider. No interpreter allocations are substituted.
   function Attached_To (Memory : not null Lua.Storage.Owner_Access)
                         return Boolean;
   --  True only while this launcher's provider observes the named owner.
   --  Independently constructed test worlds otherwise retain local controls.
   type Provider_Statistics is record
      Bytes, Blocks, Peak, Refusals : Lua.Storage.Byte_Count := 0;
   end record;
   function Measurements return Provider_Statistics;
   --  Actual raw provider measurements include independently constructed
   --  states which inherit this same callback. No expired owner is read.
   procedure Set_Byte_Limit (Bytes : Lua.Storage.Byte_Count);
   --  Zero removes the test limit; the inherited host ceiling stays active.
   procedure Set_Count_Limit (Growths : Lua.Storage.Byte_Count);
   procedure Clear_Count_Limit;
   --  Refuse after this many successful provider growths. Shrink/free do not
   --  consume it. These setters allocate nothing and execute no Lua code.
   procedure Finish;
   --  Verify physical cleanup and optionally write a PID-specific sidecar.
   --  Call only after session disposal. Idempotent, including after failure;
   --  it never dereferences the expired owner. Test executable only.
end Lua.Conformance_Allocator;
