private package Lua.Engine.Native_Modules is
   type Failure_Stage is (Loaded, Open_Failed, Symbol_Failed);

   procedure Resolve
     (State : in out World; Path, Symbol : String;
      Item : out Value; Error : in out Owned_Buffer;
      Stage : out Failure_Stage);
   --  Cache one actual OS reference per C-string path and resolve a real
   --  foreign function. A leading '*' requests global visibility and returns
   --  true without symbol lookup. No Lua code runs in this operation.
   --  @param Error Copies borrowed native diagnostics into selected storage.
   --  @param Item A callable code address remains valid until world disposal.

   procedure Configure_Paths
     (State : in out World; Package_Value : Value;
      Native_Defaults : Boolean);
   --  Set package.path/cpath from pinned native defaults and environment,
   --  respecting the actual registry LUA_NOENV field. Bounded Ada defaults
   --  retain their existing local Lua path and ignore ambient environment.

   procedure Close_All (State : in out World);
   --  Call after all Lua objects, callbacks and execution storage retire.
   --  Release each path/record and OS reference exactly once. Retain the
   --  current provider's code image through final cache-record release and
   --  subsequent storage-owner finalization via the world's code lease.
end Lua.Engine.Native_Modules;
