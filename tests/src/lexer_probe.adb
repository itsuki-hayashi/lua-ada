with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;
with Interfaces;
with Lua.Lexers; use Lua.Lexers;
with Lua.Numbers;

procedure Lexer_Probe is
   --  Binary-safe inspection of one source file; output is an ASCII protocol
   --  shared with the isolated C oracle. It never parses or executes source.
   use type Interfaces.Unsigned_64;
   function Bits is new Ada.Unchecked_Conversion
     (Lua.Numbers.Real_Value, Interfaces.Unsigned_64);
   Hex_Digits : constant String := "0123456789ABCDEF";
   procedure Hex (Text : String);
   procedure Number (Value : Integer);
   function Code (Item : Token) return Natural;
   procedure Hex (Text : String) is
   begin
      for Byte of Text loop
         Put (Hex_Digits (Character'Pos (Byte) / 16 + 1));
         Put (Hex_Digits (Character'Pos (Byte) mod 16 + 1));
      end loop;
   end Hex;
   procedure Number (Value : Integer) is
   begin
      Put (" " & Ada.Strings.Fixed.Trim (Value'Image, Ada.Strings.Both));
   end Number;
   function Code (Item : Token) return Natural is
   begin
      if Item.Kind in And_Word .. While_Word then
         return 256 + Token_Kind'Pos (Item.Kind) -
           Token_Kind'Pos (And_Word);
      end if;
      case Item.Kind is
         when Floor_Divide => return 279;
         when Concatenate => return 280;
         when Varargs => return 281;
         when Equal => return 282;
         when Greater_Equal => return 283;
         when Less_Equal => return 284;
         when Not_Equal => return 285;
         when Shift_Left => return 286;
         when Shift_Right => return 287;
         when Double_Colon => return 288;
         when End_Of_Input => return 289;
         when Float_Literal => return 290;
         when Integer_Literal => return 291;
         when Identifier => return 292;
         when String_Literal => return 293;
         when others => return Character'Pos (Element (Item.Text, 1));
      end case;
   end Code;
   procedure Emit (Source : String);
   procedure Emit (Source : String) is
   begin
      declare
         Reader : Scanner := Open (Source);
         Step : Scan_Result;
         Value : Interfaces.Unsigned_64;
         Encoded : String (1 .. 16);
      begin
         loop
            Step := Next (Reader);
            if Step.Status /= Success then
               Put ("ERROR");
               Number (Step.Location.Line);
               New_Line;
               exit;
            end if;
            declare
               Item : constant Token := Step.Tokens.First_Element;
            begin
               Put ("TOKEN");
               Number (Code (Item));
               Number (Item.After.Line);
               case Item.Kind is
                  when Identifier | String_Literal =>
                     Put (" "); Hex (To_String (Item.Text));
                  when Integer_Literal =>
                     Put (" " & Ada.Strings.Fixed.Trim
                       (Item.Numeric.Integer_Item'Image, Ada.Strings.Both));
                  when Float_Literal =>
                     Value := Bits (Item.Numeric.Real_Item);
                     for Index in reverse Encoded'Range loop
                        Encoded (Index) :=
                          Hex_Digits (Natural (Value mod 16) + 1);
                        Value := Value / 16;
                     end loop;
                     Put (" " & Encoded);
                  when others => null;
               end case;
               New_Line;
               exit when Item.Kind = End_Of_Input;
            end;
         end loop;
      end;
   end Emit;

   package Files renames Ada.Streams.Stream_IO;
   File : Files.File_Type;
   Batch : Ada.Text_IO.File_Type;
begin
   if Ada.Command_Line.Argument (1) = "--batch" then
      Ada.Text_IO.Open
        (Batch, Ada.Text_IO.In_File, Ada.Command_Line.Argument (2));
      while not Ada.Text_IO.End_Of_File (Batch) loop
         declare
            Encoded : constant String := Ada.Text_IO.Get_Line (Batch);
            Source : String (1 .. Encoded'Length / 2);
         begin
            for Index in Source'Range loop
               Source (Index) := Character'Val (Integer'Value
                 ("16#" & Encoded (2 * Index - 1 .. 2 * Index) & "#"));
            end loop;
            Emit (Source);
            Put_Line ("END");
         end;
      end loop;
      Ada.Text_IO.Close (Batch);
      return;
   end if;
   Files.Open (File, Files.In_File, Ada.Command_Line.Argument (1));
   declare
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Files.Size (File)));
      Last : Ada.Streams.Stream_Element_Offset;
      Source : String (1 .. Data'Length);
   begin
      Files.Read (File, Data, Last);
      Files.Close (File);
      for Index in Source'Range loop
         Source (Index) := Character'Val
           (Data (Ada.Streams.Stream_Element_Offset (Index)));
      end loop;
      Emit (Source);
   end;
end Lexer_Probe;

