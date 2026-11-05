with Lua_Ada_Config;

package Lua.Engine.Formats is
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
