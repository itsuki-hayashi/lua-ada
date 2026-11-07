package Lua.Engine.Call_Names is
   type Name_Kind is
     (Unknown, Local_Binding, Upvalue_Binding, Constant_Value,
      Global_Field, Table_Field, Method_Call, Iterator_Call, Metamethod_Call);
   type Identity is record
      Item : Value;
      Kind : Name_Kind := Unknown;
   end record;
   function Kind_Image (Kind : Name_Kind) return String;
   function From_Caller
     (State : in out World; Caller : Frame_Access) return Identity;
   --  Infer a logical callee's name only when debug inspection requests it.
   --  Read the actual saved canonical call word and its reaching definitions;
   --  no source-time name map or per-call bytecode scan is maintained.
   subtype Arithmetic_Operand is Positive range 1 .. 2;
   function From_Operand
     (State : in out World; Caller : Frame_Access; Index : Arithmetic_Operand)
      return Identity;
   --  Resolve a failed arithmetic operand from the saved canonical word.
   --  Index is the logical left/right operand (one/two), including flipped
   --  immediate fallbacks. Unknown or stripped names remain unknown.
end Lua.Engine.Call_Names;
