private package Lua.Engine.Loaders is
   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action;
   --  Resume text loading or a Lua-only package operation. Reader, searcher,
   --  and loader callbacks are requested from the VM, never executed here.
   --  Names are base.load/loadfile/dofile/require and package.searchpath,
   --  package.preload_searcher, package.lua_searcher. Package operations
   --  capture their original package table in Native_Captures(1).
end Lua.Engine.Loaders;
