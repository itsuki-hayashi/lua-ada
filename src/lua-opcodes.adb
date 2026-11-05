package body Lua.Opcodes is
   use type Interfaces.Unsigned_32;
   Table : constant array (Opcode) of Properties :=
     [Op_MOVE =>
        (IABC, True, False, False, False, False),
      Op_LOADI =>
        (IAsBx, True, False, False, False, False),
      Op_LOADF =>
        (IAsBx, True, False, False, False, False),
      Op_LOADK =>
        (IABx, True, False, False, False, False),
      Op_LOADKX =>
        (IABx, True, False, False, False, False),
      Op_LOADFALSE =>
        (IABC, True, False, False, False, False),
      Op_LFALSESKIP =>
        (IABC, True, False, False, False, False),
      Op_LOADTRUE =>
        (IABC, True, False, False, False, False),
      Op_LOADNIL =>
        (IABC, True, False, False, False, False),
      Op_GETUPVAL =>
        (IABC, True, False, False, False, False),
      Op_SETUPVAL =>
        (IABC, False, False, False, False, False),
      Op_GETTABUP =>
        (IABC, True, False, False, False, False),
      Op_GETTABLE =>
        (IABC, True, False, False, False, False),
      Op_GETI =>
        (IABC, True, False, False, False, False),
      Op_GETFIELD =>
        (IABC, True, False, False, False, False),
      Op_SETTABUP =>
        (IABC, False, False, False, False, False),
      Op_SETTABLE =>
        (IABC, False, False, False, False, False),
      Op_SETI =>
        (IABC, False, False, False, False, False),
      Op_SETFIELD =>
        (IABC, False, False, False, False, False),
      Op_NEWTABLE =>
        (IVABC, True, False, False, False, False),
      Op_SELF =>
        (IABC, True, False, False, False, False),
      Op_ADDI =>
        (IABC, True, False, False, False, False),
      Op_ADDK =>
        (IABC, True, False, False, False, False),
      Op_SUBK =>
        (IABC, True, False, False, False, False),
      Op_MULK =>
        (IABC, True, False, False, False, False),
      Op_MODK =>
        (IABC, True, False, False, False, False),
      Op_POWK =>
        (IABC, True, False, False, False, False),
      Op_DIVK =>
        (IABC, True, False, False, False, False),
      Op_IDIVK =>
        (IABC, True, False, False, False, False),
      Op_BANDK =>
        (IABC, True, False, False, False, False),
      Op_BORK =>
        (IABC, True, False, False, False, False),
      Op_BXORK =>
        (IABC, True, False, False, False, False),
      Op_SHLI =>
        (IABC, True, False, False, False, False),
      Op_SHRI =>
        (IABC, True, False, False, False, False),
      Op_ADD =>
        (IABC, True, False, False, False, False),
      Op_SUB =>
        (IABC, True, False, False, False, False),
      Op_MUL =>
        (IABC, True, False, False, False, False),
      Op_MOD =>
        (IABC, True, False, False, False, False),
      Op_POW =>
        (IABC, True, False, False, False, False),
      Op_DIV =>
        (IABC, True, False, False, False, False),
      Op_IDIV =>
        (IABC, True, False, False, False, False),
      Op_BAND =>
        (IABC, True, False, False, False, False),
      Op_BOR =>
        (IABC, True, False, False, False, False),
      Op_BXOR =>
        (IABC, True, False, False, False, False),
      Op_SHL =>
        (IABC, True, False, False, False, False),
      Op_SHR =>
        (IABC, True, False, False, False, False),
      Op_MMBIN =>
        (IABC, False, False, False, False, True),
      Op_MMBINI =>
        (IABC, False, False, False, False, True),
      Op_MMBINK =>
        (IABC, False, False, False, False, True),
      Op_UNM =>
        (IABC, True, False, False, False, False),
      Op_BNOT =>
        (IABC, True, False, False, False, False),
      Op_NOT =>
        (IABC, True, False, False, False, False),
      Op_LEN =>
        (IABC, True, False, False, False, False),
      Op_CONCAT =>
        (IABC, True, False, False, False, False),
      Op_CLOSE =>
        (IABC, False, False, False, False, False),
      Op_TBC =>
        (IABC, False, False, False, False, False),
      Op_JMP =>
        (IsJ, False, False, False, False, False),
      Op_EQ =>
        (IABC, False, True, False, False, False),
      Op_LT =>
        (IABC, False, True, False, False, False),
      Op_LE =>
        (IABC, False, True, False, False, False),
      Op_EQK =>
        (IABC, False, True, False, False, False),
      Op_EQI =>
        (IABC, False, True, False, False, False),
      Op_LTI =>
        (IABC, False, True, False, False, False),
      Op_LEI =>
        (IABC, False, True, False, False, False),
      Op_GTI =>
        (IABC, False, True, False, False, False),
      Op_GEI =>
        (IABC, False, True, False, False, False),
      Op_TEST =>
        (IABC, False, True, False, False, False),
      Op_TESTSET =>
        (IABC, True, True, False, False, False),
      Op_CALL =>
        (IABC, True, False, True, True, False),
      Op_TAILCALL =>
        (IABC, True, False, True, True, False),
      Op_RETURN =>
        (IABC, False, False, True, False, False),
      Op_RETURN0 =>
        (IABC, False, False, False, False, False),
      Op_RETURN1 =>
        (IABC, False, False, False, False, False),
      Op_FORLOOP =>
        (IABx, True, False, False, False, False),
      Op_FORPREP =>
        (IABx, True, False, False, False, False),
      Op_TFORPREP =>
        (IABx, False, False, False, False, False),
      Op_TFORCALL =>
        (IABC, False, False, False, False, False),
      Op_TFORLOOP =>
        (IABx, True, False, False, False, False),
      Op_SETLIST =>
        (IVABC, False, False, True, False, False),
      Op_CLOSURE =>
        (IABx, True, False, False, False, False),
      Op_VARARG =>
        (IABC, True, False, False, True, False),
      Op_GETVARG =>
        (IABC, True, False, False, False, False),
      Op_ERRNNIL =>
        (IABx, False, False, False, False, False),
      Op_VARARGPREP =>
        (IABC, False, False, False, False, False),
      Op_EXTRAARG =>
        (IAx, False, False, False, False, False)];

   function Describe (Op : Opcode) return Properties is (Table (Op));

   function Name (Op : Opcode) return String is
      Image : constant String := Opcode'Image (Op);
   begin
      return Image (Image'First + 3 .. Image'Last);
   end Name;

   function Valid (Item : Word) return Boolean is
     ((Item and 127) < Opcode_Count);

   function Operation (Item : Word) return Opcode is
     (Opcode'Val (Integer (Item and 127)));

   function Create (Op : Opcode) return Word is (Word (Opcode'Enum_Rep (Op)));

   type Layout is record
      Position, Width, Bias : Natural;
   end record;
   Layouts : constant array (Field) of Layout :=
     [A => (7, 8, 0), K => (15, 1, 0),
      B => (16, 8, 0), C => (24, 8, 0),
      VB => (16, 6, 0), VC => (22, 10, 0),
      Bx => (15, 17, 0), SBx => (15, 17, 65_535),
      Ax => (7, 25, 0), SJ => (7, 25, 16_777_215),
      SB => (16, 8, 127), SC => (24, 8, 127)];
   --  Layouts are arithmetic descriptions of the wire bits. Using shifts
   --  avoids host endianness and Ada record representation dependencies.

   function Allowed (Mode : Format; Part : Field) return Boolean;
   function Allowed (Mode : Format; Part : Field) return Boolean is
     (case Part is
         when A => Mode /= IsJ and then Mode /= IAx,
         when K => Mode in IABC | IVABC | IsJ,
         when B | C | SB | SC => Mode = IABC,
         when VB | VC => Mode = IVABC,
         when Bx => Mode = IABx,
         when SBx => Mode = IAsBx,
         when Ax => Mode = IAx,
         when SJ => Mode = IsJ);

   function Get (Item : Word; Part : Field) return Operand_Result is
      Bits : constant Layout := Layouts (Part);
   begin
      if not Valid (Item) then
         return (Invalid_Opcode, 0);
      elsif not Allowed (Table (Operation (Item)).Mode, Part) then
         return (Wrong_Format, 0);
      end if;
      return (Success, Integer
        (Interfaces.Shift_Right (Item, Bits.Position) and
           (2 ** Bits.Width - 1)) - Bits.Bias);
   end Get;

   function Set
     (Item : Word; Part : Field; Value : Integer)
      return Instruction_Result
   is
      Bits : constant Layout := Layouts (Part);
      Maximum : constant Integer := 2 ** Bits.Width - 1;
      Mask : constant Word := Interfaces.Shift_Left
        (Word (Maximum), Bits.Position);
   begin
      if not Valid (Item) then
         return (Invalid_Opcode, Item);
      elsif not Allowed (Table (Operation (Item)).Mode, Part) then
         return (Wrong_Format, Item);
      elsif Value < -Integer (Bits.Bias) or else
        Value > Maximum - Integer (Bits.Bias)
      then
         return (Out_Of_Range, Item);
      end if;
      --  Bounds are checked before biasing/conversion, so callers never
      --  accidentally encode a truncated operand or trigger signed overflow.
      return (Success, (Item and not Mask) or Interfaces.Shift_Left
        (Word (Value + Bits.Bias), Bits.Position));
   end Set;

   function Uses_Top (Item : Word) return Boolean is
      Op : constant Opcode := Operation (Item);
   begin
      --  SETLIST reads the six-bit vB field, not the ordinary eight-bit B.
      --  VARARGPREP always consumes top even though its metadata IT bit is 0.
      if Op = Op_SETLIST then
         return Get (Item, VB).Value = 0;
      elsif Op = Op_VARARGPREP then
         return True;
      else
         return Table (Op).Input_Top and then Get (Item, B).Value = 0;
      end if;
   end Uses_Top;

   function Sets_Top (Item : Word) return Boolean is
      Op : constant Opcode := Operation (Item);
   begin
      return Op = Op_TAILCALL or else
        (Table (Op).Output_Top and then Get (Item, C).Value = 0);
   end Sets_Top;
end Lua.Opcodes;

