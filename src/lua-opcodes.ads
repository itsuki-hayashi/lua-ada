with Interfaces;

private package Lua.Opcodes is
   --  Canonical Lua 5.5.1 instruction definitions, independent of the M1 VM.
   --  The numeric representation is a compatibility contract with lopcodes.h;
   --  it is not a promise that the current compiler emits these instructions.
   type Opcode is
     (Op_MOVE,
      Op_LOADI,
      Op_LOADF,
      Op_LOADK,
      Op_LOADKX,
      Op_LOADFALSE,
      Op_LFALSESKIP,
      Op_LOADTRUE,
      Op_LOADNIL,
      Op_GETUPVAL,
      Op_SETUPVAL,
      Op_GETTABUP,
      Op_GETTABLE,
      Op_GETI,
      Op_GETFIELD,
      Op_SETTABUP,
      Op_SETTABLE,
      Op_SETI,
      Op_SETFIELD,
      Op_NEWTABLE,
      Op_SELF,
      Op_ADDI,
      Op_ADDK,
      Op_SUBK,
      Op_MULK,
      Op_MODK,
      Op_POWK,
      Op_DIVK,
      Op_IDIVK,
      Op_BANDK,
      Op_BORK,
      Op_BXORK,
      Op_SHLI,
      Op_SHRI,
      Op_ADD,
      Op_SUB,
      Op_MUL,
      Op_MOD,
      Op_POW,
      Op_DIV,
      Op_IDIV,
      Op_BAND,
      Op_BOR,
      Op_BXOR,
      Op_SHL,
      Op_SHR,
      Op_MMBIN,
      Op_MMBINI,
      Op_MMBINK,
      Op_UNM,
      Op_BNOT,
      Op_NOT,
      Op_LEN,
      Op_CONCAT,
      Op_CLOSE,
      Op_TBC,
      Op_JMP,
      Op_EQ,
      Op_LT,
      Op_LE,
      Op_EQK,
      Op_EQI,
      Op_LTI,
      Op_LEI,
      Op_GTI,
      Op_GEI,
      Op_TEST,
      Op_TESTSET,
      Op_CALL,
      Op_TAILCALL,
      Op_RETURN,
      Op_RETURN0,
      Op_RETURN1,
      Op_FORLOOP,
      Op_FORPREP,
      Op_TFORPREP,
      Op_TFORCALL,
      Op_TFORLOOP,
      Op_SETLIST,
      Op_CLOSURE,
      Op_VARARG,
      Op_GETVARG,
      Op_ERRNNIL,
      Op_VARARGPREP,
      Op_EXTRAARG);
   for Opcode use
     (Op_MOVE => 0,
      Op_LOADI => 1,
      Op_LOADF => 2,
      Op_LOADK => 3,
      Op_LOADKX => 4,
      Op_LOADFALSE => 5,
      Op_LFALSESKIP => 6,
      Op_LOADTRUE => 7,
      Op_LOADNIL => 8,
      Op_GETUPVAL => 9,
      Op_SETUPVAL => 10,
      Op_GETTABUP => 11,
      Op_GETTABLE => 12,
      Op_GETI => 13,
      Op_GETFIELD => 14,
      Op_SETTABUP => 15,
      Op_SETTABLE => 16,
      Op_SETI => 17,
      Op_SETFIELD => 18,
      Op_NEWTABLE => 19,
      Op_SELF => 20,
      Op_ADDI => 21,
      Op_ADDK => 22,
      Op_SUBK => 23,
      Op_MULK => 24,
      Op_MODK => 25,
      Op_POWK => 26,
      Op_DIVK => 27,
      Op_IDIVK => 28,
      Op_BANDK => 29,
      Op_BORK => 30,
      Op_BXORK => 31,
      Op_SHLI => 32,
      Op_SHRI => 33,
      Op_ADD => 34,
      Op_SUB => 35,
      Op_MUL => 36,
      Op_MOD => 37,
      Op_POW => 38,
      Op_DIV => 39,
      Op_IDIV => 40,
      Op_BAND => 41,
      Op_BOR => 42,
      Op_BXOR => 43,
      Op_SHL => 44,
      Op_SHR => 45,
      Op_MMBIN => 46,
      Op_MMBINI => 47,
      Op_MMBINK => 48,
      Op_UNM => 49,
      Op_BNOT => 50,
      Op_NOT => 51,
      Op_LEN => 52,
      Op_CONCAT => 53,
      Op_CLOSE => 54,
      Op_TBC => 55,
      Op_JMP => 56,
      Op_EQ => 57,
      Op_LT => 58,
      Op_LE => 59,
      Op_EQK => 60,
      Op_EQI => 61,
      Op_LTI => 62,
      Op_LEI => 63,
      Op_GTI => 64,
      Op_GEI => 65,
      Op_TEST => 66,
      Op_TESTSET => 67,
      Op_CALL => 68,
      Op_TAILCALL => 69,
      Op_RETURN => 70,
      Op_RETURN0 => 71,
      Op_RETURN1 => 72,
      Op_FORLOOP => 73,
      Op_FORPREP => 74,
      Op_TFORPREP => 75,
      Op_TFORCALL => 76,
      Op_TFORLOOP => 77,
      Op_SETLIST => 78,
      Op_CLOSURE => 79,
      Op_VARARG => 80,
      Op_GETVARG => 81,
      Op_ERRNNIL => 82,
      Op_VARARGPREP => 83,
      Op_EXTRAARG => 84);
   for Opcode'Size use 7;

   Opcode_Count : constant := 85;
   subtype Word is Interfaces.Unsigned_32;
   type Format is (IABC, IVABC, IABx, IAsBx, IAx, IsJ);
   type Properties is record
      Mode : Format;
      Sets_A, Tests, Input_Top, Output_Top, Metamethod : Boolean;
   end record;
   function Describe (Op : Opcode) return Properties;
   --  Return the six independent properties encoded by luaP_opmodes.
   function Name (Op : Opcode) return String;
   --  Return the exact upstream mnemonic without the OP_ prefix.

   type Field is (A, K, B, C, VB, VC, Bx, SBx, Ax, SJ, SB, SC);
   --  Signed operands use excess-K, never two's-complement sign extension.
   type Outcome is (Success, Invalid_Opcode, Wrong_Format, Out_Of_Range);
   type Instruction_Result is record
      Status : Outcome := Success;
      Value : Word := 0;
   end record;
   type Operand_Result is record
      Status : Outcome := Success;
      Value : Integer := 0;
   end record;

   function Valid (Item : Word) return Boolean;
   --  Check the low seven bits before converting them to an enumeration.
   function Operation (Item : Word) return Opcode
     with Pre => Valid (Item);
   --  Decode a validated word; use Valid on untrusted instruction words.
   function Create (Op : Opcode) return Word;
   --  Create a zero-filled instruction carrying only its opcode.
   function Get (Item : Word; Part : Field) return Operand_Result;
   --  Decode one operand, checking the opcode and format first.
   function Set
     (Item : Word; Part : Field; Value : Integer)
      return Instruction_Result;
   --  Replace one operand without disturbing any unrelated bit.
   --  @param Item Original instruction; invalid opcodes are rejected.
   --  @param Part Requested operand, including signed/variant forms.
   --  @param Value Mathematical operand value, checked before conversion.
   --  @return Updated word or an explicit failure; no truncation occurs.
   function Uses_Top (Item : Word) return Boolean
     with Pre => Valid (Item);
   function Sets_Top (Item : Word) return Boolean
     with Pre => Valid (Item);
   --  These predicates include instruction-dependent Lua 5.5 special cases.
end Lua.Opcodes;

