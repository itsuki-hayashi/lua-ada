with Lua.Engine.Foreign;

private package Lua.Engine.Foreign_Hooks is
   procedure Handle
     (State : in out World; Context : not null Context_Access;
      Input : Foreign.Request; Output : in out Foreign.Response);
   --  Project real per-context hook state and live logical frames through
   --  the public C boundary. This procedure returns before a C hook is called
   --  or a C error/yield transfer occurs; it never invokes foreign code.
   --  Debug frame addresses borrow the active frame's lifetime and are
   --  checked against the context before their metadata is read.
end Lua.Engine.Foreign_Hooks;
