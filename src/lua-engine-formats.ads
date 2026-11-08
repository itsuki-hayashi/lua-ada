with Lua_Ada_Config;
with Lua.Storage.Buffers;

package Lua.Engine.Formats is
   procedure Finite_Number_Image
     (Memory : not null Lua.Storage.Owner_Access; Item : Real_Value;
      Precision : Positive; Output : in out Lua.Storage.Buffers.Buffer);
   --  Render a finite binary64 using the shared exact general formatter.
   --  @param Precision Significant decimal digits, normally fifteen or
   --    seventeen for the pinned public number-to-text roundtrip policy.
   --  @param Memory Owner of every rational, limb and output byte. A caller
   --    with a fixed scalar bound may supply a scoped fixed scratch owner.
   --  @param Output Receives a signed, dot-radix general spelling. The
   --    caller applies the native decimal byte and integer-looking suffix.

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
   --  Host selects OS-specific hexadecimal/NaN spelling and permits portable
   --  policy tests. Native libc carry behavior is measured independently;
   --  an OS name does not identify its libc implementation or version.
   function Run
     (State : in out World; Arguments : Values.Vector) return Values.Vector;
   --  Apply the whole format with ordinary primitive-value conversions.
end Lua.Engine.Formats;
