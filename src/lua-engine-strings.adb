with Lua.Prototypes;
with Lua.Chunks;
with Lua.Storage.Buffers;
with Ada.Characters.Handling;
with Ada.Containers;
with Ada.Strings.Fixed;
with Interfaces;
with Lua.Engine.Patterns;
with Lua.Engine.Formats;

package body Lua.Engine.Strings is
   package Managed renames Lua.Storage.Buffers;
   use type Integer_Value;
   use type Real_Value;
   use type Lua.Numbers.Number_Kind;
   use type Lua.Prototypes.Prototype_Access;
   use type Ada.Containers.Count_Type;
   use type Interfaces.Unsigned_64;

   function String_Argument
     (State : in out World; Item : Value) return String
   is
   begin
      if Item.Kind = String_Kind then
         return To_String (Item.Reference.Bytes);
      elsif Item.Kind in Integer_Kind | Real_Kind then
         return Image (Item);
      end if;
      Fail (State, "string expected, got " & Type_Name (Item));
      return "";
   end String_Argument;

   procedure Query_Argument
     (State : in out World; Item : Value;
      Process : not null access procedure (Text : String))
   is
   begin
      if Item.Kind = String_Kind then
         declare
            View : constant String (1 .. Length (Item.Reference.Bytes))
              with Import, Address => Item.Reference.Bytes.Address;
         begin
            Process (View);
         end;
      else
         --  Numeric conversion is bounded by the fixed Lua number widths.
         --  Type errors retain the same validation path as String_Argument.
         Process (String_Argument (State, Item));
      end if;
   end Query_Argument;

   function Integer_Argument
     (State : in out World; Item : Value) return Integer_Value
   is
      Number : Lua.Numbers.Number;
   begin
      case Item.Kind is
         when Integer_Kind => return Item.Integer_Data;
         when Real_Kind =>
            Number := (Lua.Numbers.Real_Number, Item.Real_Data);
         when String_Kind =>
            Number := Lua.Numbers.Read (To_String (Item.Reference.Bytes));
         when others => Number := (Kind => Lua.Numbers.Invalid);
      end case;
      if Number.Kind = Lua.Numbers.Integer_Number then
         return Number.Integer_Item;
      elsif Number.Kind = Lua.Numbers.Real_Number and then
        Number.Real_Item >= -2.0 ** 63 and then
        Number.Real_Item < 2.0 ** 63 and then
        Real_Value'Truncation (Number.Real_Item) = Number.Real_Item
      then
         return Integer_Value (Number.Real_Item);
      end if;
      Fail (State, "number has no integer representation");
      return 0;
   end Integer_Argument;

   function Relative_Position
     (Index : Integer_Value; Length : Natural) return Integer_Value
   is
   begin
      if Index >= 0 then
         return Index;
      elsif Index < -Integer_Value (Length) then
         return 0;
      else
         return Integer_Value (Length) + Index + 1;
      end if;
   end Relative_Position;

   function Run
     (State : in out World; Name : String; Arguments : Values.Vector)
      return Values.Vector
   is
      Result : Values.Vector := Owned_Values (State);
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Arguments.Length) then Arguments (Index)
         else Nil_Value);
      function Optional
        (Index : Positive; Default : Integer_Value) return Integer_Value;
      procedure Work (Count : Natural := 1);
      procedure Return_String (Text : String);
      procedure Repeat_Text (Subject : String; Count : Integer_Value);

      function Optional
        (Index : Positive; Default : Integer_Value) return Integer_Value
      is
      begin
         return (if Arg (Index).Kind = Nil_Kind then Default else
                   Integer_Argument (State, Arg (Index)));
      end Optional;

      procedure Work (Count : Natural := 1) is
      begin
         if Count > State.Bounds.Instructions -
           Natural'Min (State.Steps, State.Bounds.Instructions)
         then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         if State.Policy = Bounded then
            State.Steps := State.Steps + Count;
         end if;
      end Work;

      procedure Repeat_Text (Subject : String; Count : Integer_Value) is
         procedure With_Separator (Separator : String);
         procedure With_Separator (Separator : String) is
            Total : Integer_Value := 0;
            Buffer : Managed.Buffer;
         begin
            Buffer.Set_Owner (Lua.Storage.Reference (State.Memory));
            if Count > 0 and then Subject'Length + Separator'Length > 0 then
               --  Validate mathematical size before multiplication, then
               --  apply the actual per-session allocation budget.
               if Interfaces.Unsigned_64 (Count) >
                 (Interfaces.Unsigned_64 (Integer_Value'Last) +
                  Interfaces.Unsigned_64 (Separator'Length)) /
                 Interfaces.Unsigned_64 (Subject'Length + Separator'Length)
               then
                  Fail (State, "resulting string too large");
               end if;
               Total := Integer_Value
                 (Interfaces.Unsigned_64 (Count) *
                  Interfaces.Unsigned_64
                    (Subject'Length + Separator'Length) -
                  Interfaces.Unsigned_64 (Separator'Length));
            end if;
            if Total > Integer_Value (State.Bounds.String_Bytes) then
               Fail (State, "string byte limit exceeded", Resource => True);
            end if;
            if Total > 0 then
               Work (Natural (Total));
               Buffer.Reserve_Capacity (Natural (Total));
               for Index in 1 .. Natural (Count) loop
                  if Index > 1 then
                     Append (Buffer, Separator);
                  end if;
                  Append (Buffer, Subject);
               end loop;
            end if;
            Result.Append (New_String (State, Buffer));
         end With_Separator;
      begin
         if Arg (3).Kind = Nil_Kind then
            With_Separator ("");
         else
            Query_Argument (State, Arg (3), With_Separator'Access);
         end if;
      end Repeat_Text;

      procedure Return_String (Text : String) is
      begin
         Result.Append (New_String (State, Text));
      end Return_String;
   begin
      if Name = "dump" then
         if Arg (1).Kind not in Closure_Kind | Native_Closure_Kind |
           Native_Kind_Value | Foreign_Function_Kind
         then
            Fail (State, "bad argument #1 to 'dump' (function expected)");
         elsif Arg (1).Kind /= Closure_Kind or else
           Arg (1).Reference.Code.Canonical_Node = null
         then
            Fail (State, "unable to dump given function");
         end if;
         declare
            Code : constant Prototype_Access := Arg (1).Reference.Code;
            Bytes : Managed.Buffer := Lua.Chunks.Encode
              (Code.Canonical_Owner.Model, Strip => Truth (Arg (2)),
               Maximum_Depth => State.Bounds.Syntax_Depth,
               Root_Node => Code.Canonical_Node);
         begin
            --  Serialize the actual function subtree, without source reparse,
            --  upvalue-value snapshots or mutation of the shared program root.
            --  Returned bytes become one managed, NUL-safe Lua string.
            Work (Bytes.Length);
            Result.Append (New_String (State, Bytes));
         end;
         return Result;
      elsif Name = "format" then
         return Formats.Run (State, Arguments);
      elsif Name = "char" then
         if Arguments.Length > Ada.Containers.Count_Type
           (State.Bounds.String_Bytes)
         then
            Fail (State, "string byte limit exceeded", Resource => True);
         end if;
         declare
            Text : Managed.Buffer;
            Number : Integer_Value;
         begin
            Text.Set_Owner (Lua.Storage.Reference (State.Memory));
            Text.Reserve_Capacity (Natural (Arguments.Length));
            for Index in 1 .. Natural (Arguments.Length) loop
               Work;
               Number := Integer_Argument (State, Arguments (Index));
               if Number not in 0 .. 255 then
                  Fail (State, "value out of range");
               end if;
               Text.Append (Character'Val (Number));
            end loop;
            Result.Append (New_String (State, Text));
         end;
         return Result;
      end if;
      declare
         procedure Apply_Text (Text : String);
         procedure Apply_Text (Text : String) is
            Size : constant Integer_Value := Integer_Value (Text'Length);
            First, Last, Count : Integer_Value;
         begin
            if Name = "len" then
               Result.Append (Value'(Integer_Kind, Size));
            elsif Name = "sub" or else Name = "byte" then
               First := Relative_Position (Optional (2, 1), Text'Length);
               Last := Relative_Position
                 (Optional (3, (if Name = "sub" then -1 else Optional (2, 1))),
                  Text'Length);
               First := Integer_Value'Max (1, First);
               Last := Integer_Value'Min (Size, Last);
               if Name = "sub" then
                  if First <= Last then
                     Return_String (Text (Natural (First) .. Natural (Last)));
                  else
                     Return_String ("");
                  end if;
               elsif First <= Last then
                  Work (Natural (Last - First + 1));
                  for Index in Natural (First) .. Natural (Last) loop
                     Result.Append
                       (Value'(Integer_Kind, Character'Pos (Text (Index))));
                  end loop;
               end if;
            elsif Name in "lower" | "upper" | "reverse" then
               declare
                  Changed : Managed.Buffer;
                  Byte : Character;
               begin
                  Work (Text'Length);
                  Changed.Set_Owner (Lua.Storage.Reference (State.Memory));
                  Changed.Reserve_Capacity (Text'Length);
                  for Index in Text'Range loop
                     Byte := Text (Index);
                     if Name = "reverse" then
                        Byte := Text (Text'Last - Index + 1);
                     elsif Name = "lower" then
                        --  Lua's default locale is C, not Unicode/Latin-1.
                        if Text (Index) in 'A' .. 'Z' then
                           Byte := Ada.Characters.Handling.To_Lower
                             (Text (Index));
                        end if;
                     elsif Text (Index) in 'a' .. 'z' then
                        Byte := Ada.Characters.Handling.To_Upper
                          (Text (Index));
                     end if;
                     Changed.Append (Byte);
                  end loop;
                  Result.Append (New_String (State, Changed));
               end;
            elsif Name = "rep" then
               Count := Integer_Argument (State, Arg (2));
               Repeat_Text (Text, Count);
            elsif Name in "find" | "match" then
               declare
                  procedure Apply_Pattern (Pattern : String);
                  procedure Apply_Pattern (Pattern : String) is
                     Start : constant Integer_Value := Integer_Value'Max
                       (1, Relative_Position (Optional (3, 1), Text'Length));
                     Found : Patterns.Match_Result;
                     Plain : Boolean := Name = "find" and then Truth (Arg (4));
                     Position : Natural := 0;
                  begin
                     if Start > Size + 1 then
                        Result.Append (Nil_Value);
                        return;
                     end if;
                     if Name = "find" and then not Plain then
                        Plain := True;
                        for Byte of Pattern loop
                           if Byte in '^' | '$' | '*' | '+' | '?' | '.' |
                             '(' | '[' | '%' | '-'
                           then
                              Plain := False;
                              exit;
                           end if;
                        end loop;
                     end if;
                     if Plain then
                        Work (Text'Length + Pattern'Length);
                        if Pattern'Length = 0 then
                           Position := Natural (Start);
                        elsif Start > Integer_Value (Text'Length) then
                           Position := 0;
                        else
                           Position := Ada.Strings.Fixed.Index
                             (Text, Pattern, From => Natural (Start));
                        end if;
                        if Position > 0 then
                           Found.Found := True;
                           Found.First := Position - 1;
                           Found.After := Found.First + Pattern'Length;
                        end if;
                     else
                        Found := Patterns.Find
                          (State, Text, Pattern, Natural (Start - 1));
                     end if;
                     if not Found.Found then
                        Result.Append (Nil_Value);
                     else
                        if Name = "find" then
                           Result.Append
                             (Value'(Integer_Kind,
                                     Integer_Value (Found.First + 1)));
                           Result.Append
                             (Value'(Integer_Kind,
                                     Integer_Value (Found.After)));
                        end if;
                        for Item of Patterns.Capture_Values
                          (State, Text, Found, Whole_If_None => Name = "match")
                        loop
                           Result.Append (Item);
                        end loop;
                     end if;
                  end Apply_Pattern;
               begin
                  Query_Argument (State, Arg (2), Apply_Pattern'Access);
               end;
            else
               Fail (State, "unknown string operation: " & Name);
            end if;
         end Apply_Text;
      begin
         Query_Argument (State, Arg (1), Apply_Text'Access);
      end;
      return Result;
   end Run;
end Lua.Engine.Strings;
