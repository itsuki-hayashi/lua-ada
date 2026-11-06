with Lua_Ada_Config;
with Lua.Storage.Buffers;

package Lua.Engine.Formats is
   procedure Render_Into
     (State : in out World; Specification : String; Item : Value;
      Output : in out Lua.Storage.Buffers.Buffer;
      Host : String := Lua_Ada_Config.Alire_Host_OS);
   --  Append one conversion to managed output. Lua/native continuations use
   --  this form so formatting does not create an unaccounted full-size result.
   function Render
     (State : in out World; Specification : String; Item : Value;
      Host : String := Lua_Ada_Config.Alire_Host_OS)
      return String;
   --  Render exactly one conversion, including its leading percent sign.
   --  VM continuations can resolve __tostring before a %s call into Render.
   --  Host selects the pinned reference's formatting policy. Its explicit
   --  form permits portable tests of each OS policy without changing config.
   function Run
     (State : in out World; Arguments : Values.Vector) return Values.Vector;
   --  Apply the whole format with ordinary primitive-value conversions.
end Lua.Engine.Formats;
