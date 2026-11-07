private package Lua.Engine.Loaders is
   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action;
   --  Resume loading or a package operation. Reader, searcher,
   --  and loader callbacks are requested from the VM, never executed here.
   --  Names are base.load/loadfile/dofile/require and package.searchpath,
   --  package.preload_searcher, package.lua_searcher, package.c_searcher,
   --  package.croot_searcher and package.loadlib. Package operations
   --  capture their original package table in Native_Captures(1).
end Lua.Engine.Loaders;
