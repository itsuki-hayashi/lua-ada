with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Fixed;
with Interfaces;
with Lua.Opcodes; use Lua.Opcodes;

procedure Lua.Opcode_Probe is
   --  Separate Ada executable for raw comparison with the C-only oracle.
   --  Decimal fields and mnemonics avoid locale and endianness dependencies.
   use type Interfaces.Unsigned_32;
   procedure Put_Number (Value : Integer);
   procedure Put_Word (Value : Word);
   procedure Put_Number (Value : Integer) is
   begin
      Put (" " & Ada.Strings.Fixed.Trim (Value'Image, Ada.Strings.Both));
   end Put_Number;
   procedure Put_Word (Value : Word) is
   begin
      Put (" " & Ada.Strings.Fixed.Trim (Value'Image, Ada.Strings.Both));
   end Put_Word;
   Seed : Word := 16#A51C_9237#;
   Item : Word;
   Bits : Natural;
   P : Properties;
begin
   Put_Line
     ("BASELINE 5.5.1 7579fc9d7ed90240487251dfb69168f8e64e9294");
   for Op in Opcode loop
      P := Describe (Op);
      Bits := Format'Pos (P.Mode) + 8 * Boolean'Pos (P.Sets_A) +
        16 * Boolean'Pos (P.Tests) + 32 * Boolean'Pos (P.Input_Top) +
        64 * Boolean'Pos (P.Output_Top) + 128 * Boolean'Pos (P.Metamethod);
      Put ("OP");
      Put_Number (Opcode'Enum_Rep (Op));
      Put (" " & Name (Op));
      Put_Number (Bits);
      New_Line;
   end loop;
   for Index in 1 .. 4096 loop
      Seed := Seed * 1_664_525 + 1_013_904_223;
      Item := (Seed and 16#FFFF_FF80#) or Word (Index mod Opcode_Count);
      Put ("WORD");
      Put_Number (Index);
      Put_Word (Item);
      Put_Number (Opcode'Enum_Rep (Operation (Item)));
      --  These two physical views exist in every C word, even when their
      --  interpretation is not meaningful for this opcode's format.
      Put_Word (Interfaces.Shift_Right (Item, 7) and 255);
      Put_Word (Interfaces.Shift_Right (Item, 15) and 1);
      case Describe (Operation (Item)).Mode is
         when IABC =>
            Put (" ABC");
            Put_Number (Get (Item, B).Value);
            Put_Number (Get (Item, C).Value);
            Put_Number (Get (Item, SB).Value);
            Put_Number (Get (Item, SC).Value);
         when IVABC =>
            Put (" VABC");
            Put_Number (Get (Item, VB).Value);
            Put_Number (Get (Item, VC).Value);
         when IABx => Put (" ABX"); Put_Number (Get (Item, Bx).Value);
         when IAsBx => Put (" ASBX"); Put_Number (Get (Item, SBx).Value);
         when IAx => Put (" AX"); Put_Number (Get (Item, Ax).Value);
         when IsJ => Put (" SJ"); Put_Number (Get (Item, SJ).Value);
      end case;
      Put_Number (Boolean'Pos (Uses_Top (Item)));
      Put_Number (Boolean'Pos (Sets_Top (Item)));
      New_Line;
   end loop;
end Lua.Opcode_Probe;

