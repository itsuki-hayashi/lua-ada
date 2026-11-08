package body Lua.Engine.Unicode is
   package Managed renames Lua.Storage.Buffers;
   use type Integer_Value;
   use type Real_Value;
   use type Lua.Numbers.Number_Kind;

   procedure Emit (Code : Natural; Text : in out Managed.Buffer) is
      Remaining : Natural := Code;
      Bytes : String (1 .. 6);
      First : Positive := Bytes'Last;
      Prefix : Natural := 16#80#;
      Capacity : Natural := 16#40#;
   begin
      --  Fill continuation bytes backwards in a fixed six-byte span. The
      --  same encoder serves utf8.char and C ABI %U; neither uses C encoding
      --  logic or an input-sized unmanaged temporary.
      if Code < 16#80# then
         Append (Text, Character'Val (Code));
      else
         loop
            Bytes (First) := Character'Val (16#80# + Remaining mod 64);
            Remaining := Remaining / 64;
            First := First - 1;
            Prefix := Prefix + Capacity;
            Capacity := Capacity / 2;
            exit when Remaining < Capacity;
         end loop;
         Bytes (First) := Character'Val (Prefix + Remaining);
         Append (Text, Bytes (First .. Bytes'Last));
      end if;
   end Emit;

   function Run
     (State : in out World; Name : String; Arguments : Values.Vector)
      return Values.Vector
   is
      Result : Values.Vector := Owned_Values (State);
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Arguments.Length) then Arguments (Index)
         else Nil_Value);
      procedure Charge (Amount : Natural := 1);
      function Integer_Arg
        (Index : Positive; Default : Integer_Value := 0;
         Optional : Boolean := False) return Integer_Value;
      function String_Arg return String;
      function Iterator_Control return Integer_Value;
      function Relative (Position : Integer_Value; Size : Natural)
                         return Integer_Value;
      function Continuation (Text : String; Position : Integer_Value)
                             return Boolean;
      procedure Decode
        (Text : String; Position : Positive; Lax : Boolean;
         Code : out Natural; Following : out Positive; Valid : out Boolean);
      procedure Push_Integer (Item : Integer_Value);

      procedure Charge (Amount : Natural := 1) is
      begin
         if State.Steps > State.Bounds.Instructions or else
           Amount > State.Bounds.Instructions - State.Steps
         then
            Fail (State, "instruction budget exceeded", Resource => True);
         end if;
         if State.Policy = Bounded then
            State.Steps := State.Steps + Amount;
         end if;
      end Charge;

      function Integer_Arg
        (Index : Positive; Default : Integer_Value := 0;
         Optional : Boolean := False) return Integer_Value
      is
         Item : constant Value := Arg (Index);
         Number : Lua.Numbers.Number;
      begin
         if Optional and then Item.Kind = Nil_Kind then
            return Default;
         end if;
         case Item.Kind is
            when Integer_Kind => return Item.Integer_Data;
            when Real_Kind =>
               Number := (Lua.Numbers.Real_Number, Item.Real_Data);
            when String_Kind =>
               Charge (Length (Item.Reference.Bytes));
               Number := Read_Number
                 (State.Current.Memory, Item.Reference.Bytes);
            when others => Number := (Kind => Lua.Numbers.Invalid);
         end case;
         if Number.Kind = Lua.Numbers.Integer_Number then
            return Number.Integer_Item;
         elsif Number.Kind = Lua.Numbers.Real_Number then
            declare
               Real : constant Real_Value := Number.Real_Item;
            begin
               if Real = Real and then Real_Value'Floor (Real) = Real and then
                 not Lua.Numbers.Less
                   (Number, (Lua.Numbers.Integer_Number, Integer_Value'First))
                 and then not Lua.Numbers.Less
                   ((Lua.Numbers.Integer_Number, Integer_Value'Last), Number)
               then
                  return Integer_Value (Real);
               end if;
            end;
         end if;
         Fail (State, "number has no integer representation");
         return 0;
      end Integer_Arg;

      function Iterator_Control return Integer_Value is
         Item : constant Value := Arg (2);
         Parsed : Lua.Numbers.Number;
         Real : Real_Value;
      begin
         --  Unlike utf8's positional arguments, iterator controls use Lua's
         --  non-raising integer conversion. A failed conversion becomes zero;
         --  negative integers become exhausted unsigned positions.
         case Item.Kind is
            when Integer_Kind => return Item.Integer_Data;
            when Real_Kind =>
               Parsed := (Lua.Numbers.Real_Number, Item.Real_Data);
            when String_Kind =>
               Charge (Length (Item.Reference.Bytes));
               Parsed := Read_Number
                 (State.Current.Memory, Item.Reference.Bytes);
            when others => return 0;
         end case;
         if Parsed.Kind = Lua.Numbers.Integer_Number then
            return Parsed.Integer_Item;
         elsif Parsed.Kind = Lua.Numbers.Real_Number then
            Real := Parsed.Real_Item;
            if Real = Real and then Real_Value'Floor (Real) = Real and then
              not Lua.Numbers.Less
                (Parsed, (Lua.Numbers.Integer_Number, Integer_Value'First))
              and then not Lua.Numbers.Less
                ((Lua.Numbers.Integer_Number, Integer_Value'Last), Parsed)
            then
               return Integer_Value (Real);
            end if;
         end if;
         return 0;
      end Iterator_Control;

      function String_Arg return String is
         Item : constant Value := Arg (1);
      begin
         if Item.Kind = String_Kind then
            --  The decoder below owns a String copy of the retained subject.
            --  Even a one-character iterator step copies every source byte,
            --  so charge that work before allocating or materializing it.
            --  Repeated steps must not bypass the shared execution budget.
            Charge (Length (Item.Reference.Bytes));
            return To_String (Item.Reference.Bytes);
         elsif Item.Kind in Integer_Kind | Real_Kind then
            return Image (State.Current.Memory, Item);
         end if;
         Fail (State, "string expected");
         return "";
      end String_Arg;

      function Relative (Position : Integer_Value; Size : Natural)
                         return Integer_Value
      is
      begin
         --  Avoid negating mininteger when translating negative indices.
         if Position >= 0 then
            return Position;
         elsif Position < -Integer_Value (Size) then
            return 0;
         else
            return Integer_Value (Size) + Position + 1;
         end if;
      end Relative;

      function Continuation (Text : String; Position : Integer_Value)
                             return Boolean is
        (Position >= 1 and then Position <= Integer_Value (Text'Length)
         and then Character'Pos (Text (Natural (Position))) in
           16#80# .. 16#BF#);

      procedure Decode
        (Text : String; Position : Positive; Lax : Boolean;
         Code : out Natural; Following : out Positive; Valid : out Boolean)
      is
         Lead : Natural;
         Width : Positive;
         Minimum : Natural;
         Byte : Natural;
      begin
         --  Every read is length checked. The decoder neither relies on a C
         --  terminator nor treats an embedded NUL as end-of-input.
         Valid := False;
         Code := 0;
         Following := Position;
         if Position > Text'Last then
            return;
         end if;
         Charge;
         Lead := Character'Pos (Text (Position));
         if Lead < 16#80# then
            Code := Lead;
            Following := Position + 1;
            Valid := True;
            return;
         elsif Lead in 16#C0# .. 16#DF# then
            Width := 2; Minimum := 16#80#; Code := Lead mod 32;
         elsif Lead in 16#E0# .. 16#EF# then
            Width := 3; Minimum := 16#800#; Code := Lead mod 16;
         elsif Lead in 16#F0# .. 16#F7# then
            Width := 4; Minimum := 16#1_0000#; Code := Lead mod 8;
         elsif Lead in 16#F8# .. 16#FB# then
            Width := 5; Minimum := 16#20_0000#; Code := Lead mod 4;
         elsif Lead in 16#FC# .. 16#FD# then
            Width := 6; Minimum := 16#400_0000#; Code := Lead mod 2;
         else
            return;
         end if;
         if Text'Last - Position < Width - 1 then
            return;
         end if;
         for Index in Position + 1 .. Position + Width - 1 loop
            Charge;
            Byte := Character'Pos (Text (Index));
            if Byte not in 16#80# .. 16#BF# then
               return;
            end if;
            Code := Code * 64 + Byte mod 64;
         end loop;
         if Code < Minimum or else
           (not Lax and then
             (Code > 16#10_FFFF# or else Code in 16#D800# .. 16#DFFF#))
         then
            return;
         end if;
         Following := Position + Width;
         Valid := True;
      end Decode;

      procedure Push_Integer (Item : Integer_Value) is
      begin
         Result.Append (Value'(Integer_Kind, Item));
      end Push_Integer;
   begin
      if Name = "char" then
         declare
            Text : Managed.Buffer;
            Code : Integer_Value;
            Needed : Positive;
         begin
            Text.Set_Owner (Lua.Storage.Reference (State.Memory));
            for Index in 1 .. Natural (Arguments.Length) loop
               Charge;
               Code := Integer_Arg (Index);
               if Code < 0 or else Code > 16#7FFF_FFFF# then
                  Fail (State, "value out of range");
               end if;
               Needed := (if Code < 16#80# then 1
                          elsif Code < 16#800# then 2
                          elsif Code < 16#1_0000# then 3
                          elsif Code < 16#20_0000# then 4
                          elsif Code < 16#400_0000# then 5 else 6);
               if Needed > State.Bounds.String_Bytes - Length (Text) then
                  Fail (State, "string byte limit exceeded", True);
               end if;
               Emit (Natural (Code), Text);
            end loop;
            Result.Append (New_String (State, Text));
         end;
         return Result;
      end if;
      declare
         Text : constant String := String_Arg;
         Size : constant Integer_Value := Integer_Value (Text'Length);
         First, Last, Count : Integer_Value;
         Code : Natural;
         Following : Positive;
         Valid : Boolean;
         Lax : Boolean;
      begin
         if Name = "codes" then
            if Continuation (Text, 1) then
               Fail (State, "invalid UTF-8 code");
            end if;
            Result.Append (New_String (State, Text));
            Push_Integer (0);
         elsif Name = "step" then
            --  The iterator's control is the previous one-based start.
            --  Negative controls exhaust iteration; failed integer conversion
            --  becomes zero, matching lua_tointeger in the reference iterator.
            First := Iterator_Control;
            if First < 0 or else First >= Size then
               return Result;
            end if;
            First := First + 1;
            while Continuation (Text, First) loop
               Charge;
               First := First + 1;
            end loop;
            if First > Size then
               return Result;
            end if;
            Decode (Text, Positive (First), Truth (Arg (3)),
                    Code, Following, Valid);
            if not Valid or else
              Continuation (Text, Integer_Value (Following))
            then
               Fail (State, "invalid UTF-8 code");
            end if;
            Push_Integer (First);
            Push_Integer (Integer_Value (Code));
         elsif Name in "len" | "codepoint" then
            First := Relative (Integer_Arg (2, 1, True), Text'Length);
            Last := Relative
              (Integer_Arg (3, (if Name = "len" then -1 else First), True),
               Text'Length);
            Lax := Truth (Arg (4));
            if First < 1 or else
              (Name = "len" and then First > Size + 1)
            then
               Fail (State, "initial position out of bounds");
            elsif Last > Size then
               Fail (State, "final position out of bounds");
            end if;
            Count := 0;
            while First <= Last loop
               Decode (Text, Positive (First), Lax, Code, Following, Valid);
               if not Valid then
                  if Name = "len" then
                     Result.Append (Nil_Value);
                     Push_Integer (First);
                     return Result;
                  end if;
                  Fail (State, "invalid UTF-8 code");
               end if;
               Count := Count + 1;
               if Name = "codepoint" then
                  Push_Integer (Integer_Value (Code));
               end if;
               First := Integer_Value (Following);
            end loop;
            if Name = "len" then
               Push_Integer (Count);
            end if;
         elsif Name = "offset" then
            Count := Integer_Arg (2);
            First := Relative
              (Integer_Arg (3, (if Count >= 0 then 1 else Size + 1), True),
               Text'Length);
            if First < 1 or else First > Size + 1 then
               Fail (State, "position out of bounds");
            end if;
            if Count = 0 then
               while First > 1 and then Continuation (Text, First) loop
                  Charge;
                  First := First - 1;
               end loop;
            else
               if Continuation (Text, First) then
                  Fail (State, "initial position is a continuation byte");
               end if;
               if Count < 0 then
                  while Count < 0 and then First > 1 loop
                     Charge;
                     First := First - 1;
                     while First > 1 and then Continuation (Text, First) loop
                        Charge;
                        First := First - 1;
                     end loop;
                     Count := Count + 1;
                  end loop;
               else
                  Count := Count - 1;
                  while Count > 0 and then First <= Size loop
                     Charge;
                     First := First + 1;
                     while Continuation (Text, First) loop
                        Charge;
                        First := First + 1;
                     end loop;
                     Count := Count - 1;
                  end loop;
               end if;
            end if;
            if Count /= 0 then
               Result.Append (Nil_Value);
            else
               Last := First;
               if Continuation (Text, First) then
                  Fail (State, "initial position is a continuation byte");
               end if;
               if First <= Size and then
                 Character'Pos (Text (Natural (First))) >= 16#80#
               then
                  while Continuation (Text, Last + 1) loop
                     Charge;
                     Last := Last + 1;
                  end loop;
               end if;
               Push_Integer (First);
               Push_Integer (Last);
            end if;
         else
            raise Program_Error with "unknown UTF-8 library action";
         end if;
      end;
      return Result;
   end Run;
end Lua.Engine.Unicode;
