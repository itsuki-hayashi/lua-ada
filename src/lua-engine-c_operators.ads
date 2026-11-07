with Lua.Lexers;

package Lua.Engine.C_Operators is
   type Operation is
     (Add, Subtract, Multiply, Modulo, Exponentiate, Divide, Floor_Divide,
      Bit_And, Bit_Or, Bit_Xor, Shift_Left, Shift_Right, Negate, Complement,
      Equal, Less, Less_Equal);
   --  First fourteen positions are pinned LUA_OPADD..LUA_OPBNOT order.
   --  Final three positions are LUA_OPEQ..LUA_OPLE plus Equal's position.
   subtype Arithmetic_Operation is Operation range Add .. Complement;
   subtype Comparison_Operation is Operation range Equal .. Less_Equal;
   function Token (Kind : Operation) return Lua.Lexers.Token_Kind;
   function Unary (Kind : Operation) return Boolean;
   function Helper_Name (Kind : Operation) return String;
   type Lookup_Result is record
      Found : Boolean := False;
      Kind : Operation := Add;
   end record;
   function Find (Name : String) return Lookup_Result;
   --  Fixed private continuation names carry the operation, avoiding another
   --  physical C-stack scalar solely for interpreter transport metadata.
   function Primitive (Kind : Operation; Left, Right : Value) return Boolean;
   --  True only when pinned raw arithmetic/comparison applies without any
   --  metamethod. Numeric strings use their actual installed string handler.
end Lua.Engine.C_Operators;
