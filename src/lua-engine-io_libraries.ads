with Lua.Engine.Foreign;

package Lua.Engine.IO_Libraries is
   procedure Install (State : in out World);
   --  Install the real FILE* metatable, per-world input/output registry
   --  values, standard borrowed streams, and the complete Lua IO exports.

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action;
   --  Native IO state machine. Retained file/format/iterator values remain
   --  traced in Activation; no nested executor or abandoned Ada stack exists.

   function Close_Primitive
     (State : in out World; Item : Value; Kind : Foreign.IO_Close_Kind)
      return Values.Vector;
   --  Shared Lua/C luaL_Stream.closef path. Execute the real primitive in the
   --  current logical native/C activation, with no extra visible call frame.
   --  The ordinary aux_close caller already cleared closef; direct C calls
   --  are permitted too. Return actual regular/pipe/borrowed result arity.
end Lua.Engine.IO_Libraries;
