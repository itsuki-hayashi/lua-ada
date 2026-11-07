package Lua.Engine.Library_Openers is
   type Module_Kind is
     (Base_Module, Package_Module, Coroutine_Module, Debug_Module,
      Math_Module, String_Module, Table_Module, UTF8_Module);

   function Open_Module
     (State : in out World; Kind : Module_Kind) return Value;
   --  Construct the requested standard library in the owning universe.
   --  Returned objects remain operation-rooted until the caller publishes
   --  them. Base updates globals; package installs its captured require.
   --  Other modules do not publish globals or loaded-module registry entries.
   --  @param State Owns allocations, captured registries and native closures.
   --  @param Kind Selects one real Ada library initializer.
   --  @return Fresh module table, or the existing globals for base.
   --  @exception Lua.Storage.Allocation_Error Allocation was refused.

   procedure Open_All (State : in out World);
   --  Eager Ada-session initialization through the same module constructors
   --  used by public C opening. Publish each result in globals and _LOADED.
end Lua.Engine.Library_Openers;
