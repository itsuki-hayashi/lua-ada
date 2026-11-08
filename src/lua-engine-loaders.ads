private package Lua.Engine.Loaders is
   function Compile_Chunk
     (State : in out World; Activation : Frame_Access;
      Source, Chunk_Name, Mode : String; Environment : Value)
      return Values.Vector;
   --  Shared dynamic loader and debug-console compilation. Activation stays
   --  traced throughout; its temporary capture roots any saved error value.
   --  Return a closure or nil/message while preserving prior error ownership.

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action;
   --  Resume loading or a package operation. Reader, searcher,
   --  and loader callbacks are requested from the VM, never executed here.
   --  Names are base.load/loadfile/dofile/require and package.searchpath,
   --  package.preload_searcher, package.lua_searcher, package.c_searcher,
   --  package.croot_searcher and package.loadlib. Package operations
   --  capture their original package table in Native_Captures(1).
end Lua.Engine.Loaders;
