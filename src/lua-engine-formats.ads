package Lua.Engine.Formats is
   function Render
     (State : in out World; Specification : String; Item : Value)
      return String;
   --  Render exactly one conversion, including its leading percent sign.
   --  VM continuations can resolve __tostring before a %s call into Render.
   function Run
     (State : in out World; Arguments : Values.Vector) return Values.Vector;
   --  Apply the whole format with ordinary primitive-value conversions.
end Lua.Engine.Formats;
