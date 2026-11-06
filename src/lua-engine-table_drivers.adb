with Ada.Containers;
with Ada.Unchecked_Conversion;
with Interfaces;
with Lua.Engine.Core_Libraries;
with Lua.Integers;
with Lua.Numbers;

package body Lua.Engine.Table_Drivers is
   use type Ada.Containers.Count_Type;
   use type Integer_Value;
   use type Real_Value;
   use type Lua.Numbers.Number_Kind;
   use type Interfaces.Unsigned_64;
   function Bits is new Ada.Unchecked_Conversion
     (Integer_Value, Interfaces.Unsigned_64);

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action
   is
      Name : constant String := To_String (Activation.Native_Name);
      Result : Native_Action := New_Action (State);
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Activation.Native_Arguments.Length)
         then Activation.Native_Arguments (Index) else Nil_Value);
      function Returned return Value is
        (if Activation.Native_Results.Is_Empty then Nil_Value
         else Activation.Native_Results.First_Element);
      function Capture (Index : Positive) return Value is
        (Activation.Native_Captures (Index));
      function Number (Index : Positive) return Integer_Value is
        (Capture (Index).Integer_Data);
      function Key (Item : Integer_Value) return Value is
        ((Integer_Kind, Item));
      procedure Save (Index : Positive; Item : Value);
      function Integral (Item : Value) return Integer_Value;
      function Text (Item : Value) return String;
      procedure Check_Table
        (Item : Value; Readable, Writable, Sized : Boolean);
      function Request (Helper : String; Args : Values.Vector)
                        return Native_Action;
      function Read (Table : Value; Index : Integer_Value)
                     return Native_Action;
      function Write (Table : Value; Index : Integer_Value; Item : Value)
                      return Native_Action;
      procedure Start_Move (Backwards : Boolean);
      Item, Destination : Value;
      First, Last, Position, Count, Size : Integer_Value := 0;

      procedure Save (Index : Positive; Item : Value) is
      begin
         Activation.Native_Captures.Replace_Element (Index, Item);
      end Save;

      function Integral (Item : Value) return Integer_Value is
         Parsed : Lua.Numbers.Number;
         Real_Item : Real_Value := 0.0;
      begin
         if Item.Kind = Integer_Kind then
            return Item.Integer_Data;
         elsif Item.Kind = Real_Kind then
            Real_Item := Item.Real_Data;
         elsif Item.Kind = String_Kind then
            Parsed := Read_Number (State, Item.Reference.Bytes);
            if Parsed.Kind = Lua.Numbers.Integer_Number then
               return Parsed.Integer_Item;
            elsif Parsed.Kind = Lua.Numbers.Real_Number then
               Real_Item := Parsed.Real_Item;
            else
               Fail (State, "integer expected in " & Name);
            end if;
         else
            Fail (State, "integer expected in " & Name);
         end if;
         if Real_Item >= -2.0 ** 63 and then Real_Item < 2.0 ** 63 and then
           Real_Value'Truncation (Real_Item) = Real_Item
         then
            return Integer_Value (Real_Item);
         end if;
         Fail (State, "number has no integer representation");
         return 0;
      end Integral;

      function Text (Item : Value) return String is
      begin
         if Item.Kind = String_Kind then
            return To_String (Item.Reference.Bytes);
         elsif Item.Kind in Integer_Kind | Real_Kind then
            return Image (State.Current.Memory, Item);
         end if;
         Fail (State, "invalid value in table for concat");
         return "";
      end Text;

      procedure Check_Table
        (Item : Value; Readable, Writable, Sized : Boolean)
      is
      begin
         --  The standard table library also permits non-tables which supply
         --  each event required by that particular operation. Looking up
         --  these events is raw; only actual access invokes the handler.
         if Item.Kind /= Table_Kind and then
           ((Readable and then
               Metafield (State, Item, "__index").Kind = Nil_Kind) or else
            (Writable and then
               Metafield (State, Item, "__newindex").Kind = Nil_Kind) or else
            (Sized and then Item.Kind /= String_Kind and then
               Metafield (State, Item, "__len").Kind = Nil_Kind))
         then
            Fail (State, "table expected in " & Name);
         end if;
      end Check_Table;

      function Request (Helper : String; Args : Values.Vector)
                        return Native_Action
      is
      begin
         return (Kind => Invoke,
                 Function_Value => New_Native (State, Helper),
                 Arguments => Args, others => <>);
      end Request;

      function Read (Table : Value; Index : Integer_Value)
                     return Native_Action
      is
         Args : Values.Vector := Owned_Values (State);
      begin
         Args.Append (Table);
         Args.Append (Key (Index));
         return Request ("@get", Args);
      end Read;

      function Write (Table : Value; Index : Integer_Value; Item : Value)
                      return Native_Action
      is
         Args : Values.Vector := Owned_Values (State);
      begin
         Args.Append (Table);
         Args.Append (Key (Index));
         Args.Append (Item);
         return Request ("@set", Args);
      end Write;

      procedure Start_Move (Backwards : Boolean) is
      begin
         --  Source/destination indices and remaining count remain integer
         --  values in traced captures, independent of Natural's host width.
         if Backwards then
            Save (3, Key (Number (4)));
            --  The final destination was range-checked, but adding Count
            --  before subtracting one can still overflow at maxinteger.
            Save (5, Key (Number (5) + (Number (7) - 1)));
            Save (6, Key (-1));
         else
            Save (6, Key (1));
         end if;
         Activation.Native_Stage := 31;
      end Start_Move;
   begin
      if State.Steps >= State.Bounds.Instructions then
         Fail (State, "instruction limit exceeded", Resource => True);
      end if;
      if State.Policy = Bounded then
         State.Steps := State.Steps + 1;
      end if;
      if Activation.Native_Stage = 0 then
         Item := Arg (1);
         Destination := (if Name = "table.move" and then
                           Arg (5).Kind /= Nil_Kind then Arg (5) else Item);
         if Name = "table.pack" or else
           (Item.Kind = Table_Kind and then Item.Reference.Metatable = null
            and then Destination.Kind = Table_Kind and then
            Destination.Reference.Metatable = null)
         then
            Result.Results := Core_Libraries.Run
              (State, Name, Activation.Native_Arguments);
            return Result;
         end if;
         --  Fixed slots make ownership explicit. Slots 1/2 retain the two
         --  tables; 3..6 hold traversal indices; 7 retains a result/value;
         --  8 retains concat's separator. Unpack appends results after them.
         Activation.Native_Captures.Clear;
         Activation.Native_Captures.Append (Item);
         Activation.Native_Captures.Append (Destination);
         for Index in 3 .. 8 loop
            Activation.Native_Captures.Append (Nil_Value);
         end loop;
         if Name = "table.move" then
            Check_Table (Item, True, False, False);
            Check_Table (Destination, False, True, False);
            First := Integral (Arg (2));
            Last := Integral (Arg (3));
            Position := Integral (Arg (4));
            if Last < First then
               Result.Results.Append (Destination);
               return Result;
            end if;
            if First <= 0 and then Last >= Integer_Value'Last + First then
               Fail (State, "too many elements to move");
            end if;
            Count := Last - First + 1;
            if Position > Integer_Value'Last - Count + 1 then
               Fail (State, "destination wrap around");
            end if;
            Save (3, Key (First));
            Save (4, Key (Last));
            Save (5, Key (Position));
            Save (7, Key (Count));
            if Position > First and then Position <= Last then
               if Equal (Item, Destination) then
                  Start_Move (True);
               elsif Arg (5).Kind /= Nil_Kind then
                  declare
                     Args : Values.Vector := Owned_Values (State);
                  begin
                     Args.Append (Item);
                     Args.Append (Destination);
                     Activation.Native_Stage := 30;
                     return Request ("@equal", Args);
                  end;
               else
                  Start_Move (False);
               end if;
            else
               Start_Move (False);
            end if;
         else
            Activation.Native_Stage := 1;
            if Name = "table.unpack" then
               --  Unpack obtains length lazily, after validating its start
               --  index, and only if the end is absent. Explicit empty ranges
               --  do not even index their receiver, which need not be a table.
               First := (if Arg (2).Kind = Nil_Kind then 1
                         else Integral (Arg (2)));
               if Arg (3).Kind /= Nil_Kind then
                  Activation.Native_Results := One_Value (State, Arg (3), 1);
               else
                  return Request ("@length", One_Value (State, Item, 1));
               end if;
            else
               Check_Table (Item, True,
                            Name in "table.insert" | "table.remove", True);
               return Request ("@length", One_Value (State, Item, 1));
            end if;
         end if;
      end if;

      if Activation.Native_Stage = 1 then
         Size := Integral (Returned);
         if Name in "table.concat" | "table.unpack" then
            First := (if Arg (2).Kind = Nil_Kind or else Name = "table.concat"
                      then 1 else Integral (Arg (2)));
            Last := Size;
            if Name = "table.concat" then
               First := (if Arg (3).Kind = Nil_Kind then 1
                         else Integral (Arg (3)));
               if Arg (4).Kind /= Nil_Kind then
                  Last := Integral (Arg (4));
               end if;
               Save (8, (if Arg (2).Kind = Nil_Kind then New_String (State, "")
                         else New_String (State, Text (Arg (2)))));
            elsif Arg (3).Kind /= Nil_Kind then
               Last := Integral (Arg (3));
            end if;
            Save (3, Key (First));
            Save (4, Key (Last));
            Save (5, Key (First));
            if First > Last then
               if Name = "table.concat" then
                  Result.Results.Append (New_String (State, ""));
               end if;
               return Result;
            end if;
            if Name = "table.unpack" then
               if First <= 0 and then Last >= Integer_Value'Last + First then
                  Fail (State, "too many results to unpack");
               end if;
               --  Results occupy semantic Lua stack slots even though this
               --  backend stores them in a packet. Check before allocating;
               --  semantic overflow remains catchable by resume or pcall.
               if Last - First >= Integer_Value
                 (1_000_000 - Natural'Min
                    (1_000_000, State.Current.Stack_Slots))
               then
                  Fail (State, "too many results to unpack (stack overflow)");
               end if;
               if Last - First >= Integer_Value (State.Bounds.Table_Entries)
               then
                  Fail (State, "table unpack result limit exceeded",
                        Resource => True);
               end if;
            end if;
            Activation.Native_Stage := 2;
         elsif Name = "table.insert" then
            if Activation.Native_Arguments.Length = 2 then
               Position := Lua.Integers.Add (Size, 1);
               Save (7, Arg (2));
            elsif Activation.Native_Arguments.Length = 3 then
               Position := Integral (Arg (2));
               if Bits (Position) - 1 >=
                 Bits (Lua.Integers.Add (Size, 1))
               then
                  Fail (State, "position out of bounds");
               end if;
               Save (7, Arg (3));
            else
               Fail (State, "wrong number of arguments to insert");
            end if;
            Save (3, Key (Size));
            Save (4, Key (Position));
            Save (5, Key (Lua.Integers.Add (Size, 1)));
            if Activation.Native_Arguments.Length = 2 then
               Activation.Native_Stage := 13;
               return Write (Capture (1), Position, Capture (7));
            end if;
            Activation.Native_Stage := 10;
         elsif Name = "table.remove" then
            Position := (if Arg (2).Kind = Nil_Kind then Size
                         else Integral (Arg (2)));
            if Position /= Size and then
              Bits (Position) - 1 > Bits (Size)
            then
               Fail (State, "position out of bounds");
            end if;
            Save (3, Key (Position));
            Save (4, Key (Size));
            Activation.Native_Stage := 20;
            return Read (Capture (1), Position);
         else
            Fail (State, "unknown table driver: " & Name);
         end if;
      end if;

      case Activation.Native_Stage is
         when 2 =>
            Activation.Native_Stage := 3;
            return Read (Capture (1), Number (3));
         when 3 =>
            if Name = "table.concat" then
               declare
                  Part : constant String := Text (Returned);
                  Separator : constant String := Text (Capture (8));
                  Added : constant Natural := Part'Length +
                    (if Number (3) = Number (5) then 0 else Separator'Length);
               begin
                  if Added > State.Bounds.String_Bytes -
                    Length (Activation.Native_Buffer)
                  then
                     Fail (State, "string byte limit exceeded",
                           Resource => True);
                  end if;
                  if Number (3) /= Number (5) then
                     Append (Activation.Native_Buffer, Separator);
                  end if;
                  Append (Activation.Native_Buffer, Part);
               end;
            else
               Activation.Native_Captures.Append (Returned);
            end if;
            if Number (3) = Number (4) then
               if Name = "table.concat" then
                  Result.Results.Append
                    (New_String (State, Activation.Native_Buffer));
               else
                  for Index in 9 ..
                    Natural (Activation.Native_Captures.Length)
                  loop
                     Result.Results.Append (Capture (Index));
                  end loop;
               end if;
               return Result;
            end if;
            Save (3, Key (Number (3) + 1));
            Activation.Native_Stage := 2;
         when 10 =>
            if Number (3) >= Number (4) then
               Activation.Native_Stage := 11;
               return Read (Capture (1), Number (3));
            end if;
            Activation.Native_Stage := 13;
            return Write (Capture (1), Number (4), Capture (7));
         when 11 =>
            Activation.Native_Stage := 12;
            return Write (Capture (1), Number (5), Returned);
         when 12 =>
            Save (3, Key (Number (3) - 1));
            Save (5, Key (Number (5) - 1));
            Activation.Native_Stage := 10;
         when 13 =>
            return Result;
         when 20 =>
            Save (7, Returned);
            if Number (3) < Number (4) then
               Activation.Native_Stage := 21;
               return Read (Capture (1), Number (3) + 1);
            end if;
            Activation.Native_Stage := 23;
            return Write (Capture (1), Number (3), Nil_Value);
         when 21 =>
            Activation.Native_Stage := 22;
            return Write (Capture (1), Number (3), Returned);
         when 22 =>
            Save (3, Key (Number (3) + 1));
            if Number (3) < Number (4) then
               Activation.Native_Stage := 21;
               return Read (Capture (1), Number (3) + 1);
            end if;
            Activation.Native_Stage := 23;
            return Write (Capture (1), Number (3), Nil_Value);
         when 23 =>
            Result.Results.Append (Capture (7));
            return Result;
         when 30 =>
            Start_Move (Truth (Returned));
         when 31 =>
            Activation.Native_Stage := 32;
            return Read (Capture (1), Number (3));
         when 32 =>
            Activation.Native_Stage := 33;
            return Write (Capture (2), Number (5), Returned);
         when 33 =>
            if Number (7) = 1 then
               Result.Results.Append (Capture (2));
               return Result;
            end if;
            Save (7, Key (Number (7) - 1));
            Save (3, Key (Number (3) + Number (6)));
            Save (5, Key (Number (5) + Number (6)));
            Activation.Native_Stage := 31;
         when others =>
            Fail (State, "invalid table continuation state");
      end case;
      Result.Kind := Continue_Step;
      return Result;
   end Advance;
end Lua.Engine.Table_Drivers;
