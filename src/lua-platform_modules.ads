with Ada.Finalization;
with Interfaces.C;
with System;

private package Lua.Platform_Modules is
   --  OS loader mechanics for native Lua modules, implemented in
   --  src/platform/lua_ada_modules.c. This package owns no package search
   --  policy: LUA_EXEC_DIR substitution, ';;' expansion, and module name
   --  construction belong to the Ada loader. Nothing here calls Lua,
   --  allocates, or keeps a pointer after a call returns.
   package C renames Interfaces.C;

   Error_Buffer_Size : constant C.size_t := 128;
   --  Caller-owned writable scratch of exactly this many bytes. Only the
   --  Windows implementation writes it (FormatMessageA text, or the fallback
   --  "system error %d" line). POSIX returns the loader's own borrowed text
   --  and never touches it. Any error text returned in it stays valid only
   --  until the caller reuses or releases that storage.

   --  Error out-parameters below are the address of one object of type
   --  System.Address, which the C side fills with a `const char *`. Every
   --  call sets it to Null_Address on success. POSIX can also return null
   --  text for a zero-address symbol without a loader diagnostic; preserve
   --  that distinction rather than inventing a Lua-visible error string.

   function Open
     (Path         : System.Address;
      Global       : C.int;
      Error_Buffer : System.Address;
      Error        : not null access System.Address) return System.Address
     with Import, Convention => C, External_Name => "lua_ada_modules_open";
   --  Path must be a nonnull borrowed NUL-terminated name; the callee does
   --  not retain it. Global nonzero requests RTLD_GLOBAL on POSIX; Windows
   --  ignores it, because loaded symbols are visible process-wide there.
   --  Result is the opaque library handle, or Null_Address on failure.
   --  Ownership: a non-null handle must eventually go to Close, exactly once.

   function Symbol
     (Handle       : System.Address;
      Name         : System.Address;
      Error_Buffer : System.Address;
      Error        : not null access System.Address) return System.Address
     with Import, Convention => C, External_Name => "lua_ada_modules_symbol";
   --  Handle is a live handle from Open, not yet closed. Name is a borrowed
   --  nonnull NUL-terminated symbol name. Result carries the function
   --  address bytes as an object pointer, copied with memcpy after a size
   --  check; it is Null_Address on failure. The address is valid only while
   --  the library stays open, so the caller must not use it after Close.
   --  The result is raw native code: the caller must cast it to the exact
   --  function type it knows, outside this package.

   procedure Close (Handle : System.Address)
     with Import, Convention => C, External_Name => "lua_ada_modules_close";
   --  Releases one handle from Open. Null_Address is accepted and ignored.
   --  Any symbol address obtained from that handle becomes invalid here.

   type Code_Lease is new Ada.Finalization.Limited_Controlled with record
      Handle : System.Address := System.Null_Address;
   end record;
   --  Declare before the allocator owner in its enclosing world. Reverse
   --  component finalization then keeps this one code reference through
   --  the owner's final controlled-allocation and raw-block cleanup.

   overriding procedure Finalize (Self : in out Code_Lease);
   --  Release the held image only after the world's storage owner retires.

   function Keep_Code (Address : System.Address) return System.Address
     with Import, Convention => C,
          External_Name => "lua_ada_modules_keep_code";
   --  Acquire one native reference to the image containing Address. Hold
   --  a module-owned allocator through the last provider-owned cache block's
   --  release, then pass this reference to Close. A null result is normal
   --  for permanently loaded main-program code on some native loaders.

   function Default_Path return System.Address
     with Import, Convention => C,
          External_Name => "lua_ada_modules_default_path";
   --  Unexpanded LUA_PATH_DEFAULT from the installed luaconf.h. The string
   --  is static program storage; the caller must not free or modify it.

   function Default_CPath return System.Address
     with Import, Convention => C,
          External_Name => "lua_ada_modules_default_cpath";
   --  Unexpanded LUA_CPATH_DEFAULT, with the same lifetime as Default_Path.

   function Program_Directory
     (Buffer : System.Address; Capacity : C.size_t) return C.int
     with Import, Convention => C,
          External_Name => "lua_ada_modules_program_directory";
   --  Windows only: writes the running executable's directory into Buffer,
   --  without the final backslash segment, and returns 1. Returns 0 when
   --  Buffer is null, Capacity is zero or too large, the module path cannot
   --  be read, it is truncated, or it has no backslash. Buffer contents are
   --  unspecified after a 0 result. POSIX always returns 0 and leaves Buffer
   --  untouched, because LUA_EXEC_DIR substitution is not used there.
end Lua.Platform_Modules;
