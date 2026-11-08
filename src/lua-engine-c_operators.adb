package body Lua.Engine.C_Operators is
   use type Real_Value;
   Tokens : constant array (Operation) of Lua.Lexers.Token_Kind :=
     [Lua.Lexers.Plus, Lua.Lexers.Minus, Lua.Lexers.Star,
      Lua.Lexers.Percent, Lua.Lexers.Power, Lua.Lexers.Slash,
      Lua.Lexers.Floor_Divide, Lua.Lexers.Bit_And, Lua.Lexers.Bit_Or,
      Lua.Lexers.Bit_Xor, Lua.Lexers.Shift_Left, Lua.Lexers.Shift_Right,
      Lua.Lexers.Minus, Lua.Lexers.Bit_Xor, Lua.Lexers.Equal,
      Lua.Lexers.Less, Lua.Lexers.Less_Equal];
   function Integer_Operand (Item : Value) return Boolean;

   function Integer_Operand (Item : Value) return Boolean is
     (Item.Kind = Integer_Kind or else
      (Item.Kind = Real_Kind and then Item.Real_Data >= -(2.0 ** 63) and then
       Item.Real_Data < 2.0 ** 63 and then
       Real_Value'Truncation (Item.Real_Data) = Item.Real_Data));

   function Token (Kind : Operation) return Lua.Lexers.Token_Kind is
     (Tokens (Kind));
   function Unary (Kind : Operation) return Boolean is
     (Kind in Negate | Complement);
   function Helper_Name (Kind : Operation) return String is
     ("@api.operator." & Kind'Image);

   function Find (Name : String) return Lookup_Result is
      Prefix : constant String := "@api.operator.";
   begin
      if Name'Length < Prefix'Length or else
        Name (Name'First .. Name'First + Prefix'Length - 1) /= Prefix
      then
         return (others => <>);
      end if;
      for Kind in Operation loop
         if Name = Helper_Name (Kind) then return (True, Kind); end if;
      end loop;
      return (others => <>);
   end Find;

   function Primitive (Kind : Operation; Left, Right : Value) return Boolean
   is
   begin
      case Kind is
         when Equal =>
            return Engine.Equal (Left, Right) or else
              Left.Kind /= Right.Kind or else
              Left.Kind not in Table_Kind | Userdata_Kind;
         when Less | Less_Equal =>
            return (Left.Kind in Integer_Kind | Real_Kind and then
                    Right.Kind in Integer_Kind | Real_Kind) or else
              (Left.Kind = String_Kind and then Right.Kind = String_Kind);
         when Bit_And .. Shift_Right =>
            return Integer_Operand (Left) and then Integer_Operand (Right);
         when Complement => return Integer_Operand (Left);
         when Negate => return Left.Kind in Integer_Kind | Real_Kind;
         when others =>
            return Left.Kind in Integer_Kind | Real_Kind and then
              Right.Kind in Integer_Kind | Real_Kind;
      end case;
   end Primitive;
end Lua.Engine.C_Operators;
