package Lua.Engine.Hooks is
   function Enabled (Context : not null Context_Access) return Boolean;
   --  Test actual installation controls, independently of the replaceable
   --  Lua callback entry. Foreign hooks retain their scalar C callback.

   function Callback
     (State : World; Context : not null Context_Access) return Value;
   --  Borrow the actual Lua registry entry, or the foreign hook trampoline.
   --  Registry access is raw and invokes no Lua callback. The returned value
   --  remains rooted by the registry until its caller roots an activation.

   procedure Store_Callback
     (State : in out World; Context : not null Context_Access; Item : Value);
   --  Store the real thread-to-callback mapping in registry._HOOKKEY, lazily
   --  creating its weak-key self-metatable. Item may be nil for removal.
   --  Installation controls are committed separately after successful store.
end Lua.Engine.Hooks;
