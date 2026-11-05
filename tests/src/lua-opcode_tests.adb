with AUnit.Assertions; use AUnit.Assertions;
with Interfaces;
with Lua.Opcodes; use Lua.Opcodes;
with Test_Support;

package body Lua.Opcode_Tests is
   use type Interfaces.Unsigned_32;
   procedure Test_MOVE;
   procedure Test_LOADI;
   procedure Test_LOADF;
   procedure Test_LOADK;
   procedure Test_LOADKX;
   procedure Test_LOADFALSE;
   procedure Test_LFALSESKIP;
   procedure Test_LOADTRUE;
   procedure Test_LOADNIL;
   procedure Test_GETUPVAL;
   procedure Test_SETUPVAL;
   procedure Test_GETTABUP;
   procedure Test_GETTABLE;
   procedure Test_GETI;
   procedure Test_GETFIELD;
   procedure Test_SETTABUP;
   procedure Test_SETTABLE;
   procedure Test_SETI;
   procedure Test_SETFIELD;
   procedure Test_NEWTABLE;
   procedure Test_SELF;
   procedure Test_ADDI;
   procedure Test_ADDK;
   procedure Test_SUBK;
   procedure Test_MULK;
   procedure Test_MODK;
   procedure Test_POWK;
   procedure Test_DIVK;
   procedure Test_IDIVK;
   procedure Test_BANDK;
   procedure Test_BORK;
   procedure Test_BXORK;
   procedure Test_SHLI;
   procedure Test_SHRI;
   procedure Test_ADD;
   procedure Test_SUB;
   procedure Test_MUL;
   procedure Test_MOD;
   procedure Test_POW;
   procedure Test_DIV;
   procedure Test_IDIV;
   procedure Test_BAND;
   procedure Test_BOR;
   procedure Test_BXOR;
   procedure Test_SHL;
   procedure Test_SHR;
   procedure Test_MMBIN;
   procedure Test_MMBINI;
   procedure Test_MMBINK;
   procedure Test_UNM;
   procedure Test_BNOT;
   procedure Test_NOT;
   procedure Test_LEN;
   procedure Test_CONCAT;
   procedure Test_CLOSE;
   procedure Test_TBC;
   procedure Test_JMP;
   procedure Test_EQ;
   procedure Test_LT;
   procedure Test_LE;
   procedure Test_EQK;
   procedure Test_EQI;
   procedure Test_LTI;
   procedure Test_LEI;
   procedure Test_GTI;
   procedure Test_GEI;
   procedure Test_TEST;
   procedure Test_TESTSET;
   procedure Test_CALL;
   procedure Test_TAILCALL;
   procedure Test_RETURN;
   procedure Test_RETURN0;
   procedure Test_RETURN1;
   procedure Test_FORLOOP;
   procedure Test_FORPREP;
   procedure Test_TFORPREP;
   procedure Test_TFORCALL;
   procedure Test_TFORLOOP;
   procedure Test_SETLIST;
   procedure Test_CLOSURE;
   procedure Test_VARARG;
   procedure Test_GETVARG;
   procedure Test_ERRNNIL;
   procedure Test_VARARGPREP;
   procedure Test_EXTRAARG;
   procedure Operand_Boundaries;
   procedure Invalid_Words;
   procedure Top_Predicates;
   procedure Round_Trips;

   procedure Test_MOVE is
      --  Protect the pinned MOVE ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_MOVE) = 0, "opcode ID");
      Assert (Name (Op_MOVE) = "MOVE", "mnemonic");
      Assert (Describe (Op_MOVE) = Expected, "mode properties");
   end Test_MOVE;

   procedure Test_LOADI is
      --  Protect the pinned LOADI ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IAsBx, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_LOADI) = 1, "opcode ID");
      Assert (Name (Op_LOADI) = "LOADI", "mnemonic");
      Assert (Describe (Op_LOADI) = Expected, "mode properties");
   end Test_LOADI;

   procedure Test_LOADF is
      --  Protect the pinned LOADF ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IAsBx, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_LOADF) = 2, "opcode ID");
      Assert (Name (Op_LOADF) = "LOADF", "mnemonic");
      Assert (Describe (Op_LOADF) = Expected, "mode properties");
   end Test_LOADF;

   procedure Test_LOADK is
      --  Protect the pinned LOADK ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABx, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_LOADK) = 3, "opcode ID");
      Assert (Name (Op_LOADK) = "LOADK", "mnemonic");
      Assert (Describe (Op_LOADK) = Expected, "mode properties");
   end Test_LOADK;

   procedure Test_LOADKX is
      --  Protect the pinned LOADKX ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABx, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_LOADKX) = 4, "opcode ID");
      Assert (Name (Op_LOADKX) = "LOADKX", "mnemonic");
      Assert (Describe (Op_LOADKX) = Expected, "mode properties");
   end Test_LOADKX;

   procedure Test_LOADFALSE is
      --  Protect the pinned LOADFALSE ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_LOADFALSE) = 5, "opcode ID");
      Assert (Name (Op_LOADFALSE) = "LOADFALSE", "mnemonic");
      Assert (Describe (Op_LOADFALSE) = Expected, "mode properties");
   end Test_LOADFALSE;

   procedure Test_LFALSESKIP is
      --  Protect the pinned LFALSESKIP ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_LFALSESKIP) = 6, "opcode ID");
      Assert (Name (Op_LFALSESKIP) = "LFALSESKIP", "mnemonic");
      Assert (Describe (Op_LFALSESKIP) = Expected, "mode properties");
   end Test_LFALSESKIP;

   procedure Test_LOADTRUE is
      --  Protect the pinned LOADTRUE ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_LOADTRUE) = 7, "opcode ID");
      Assert (Name (Op_LOADTRUE) = "LOADTRUE", "mnemonic");
      Assert (Describe (Op_LOADTRUE) = Expected, "mode properties");
   end Test_LOADTRUE;

   procedure Test_LOADNIL is
      --  Protect the pinned LOADNIL ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_LOADNIL) = 8, "opcode ID");
      Assert (Name (Op_LOADNIL) = "LOADNIL", "mnemonic");
      Assert (Describe (Op_LOADNIL) = Expected, "mode properties");
   end Test_LOADNIL;

   procedure Test_GETUPVAL is
      --  Protect the pinned GETUPVAL ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_GETUPVAL) = 9, "opcode ID");
      Assert (Name (Op_GETUPVAL) = "GETUPVAL", "mnemonic");
      Assert (Describe (Op_GETUPVAL) = Expected, "mode properties");
   end Test_GETUPVAL;

   procedure Test_SETUPVAL is
      --  Protect the pinned SETUPVAL ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_SETUPVAL) = 10, "opcode ID");
      Assert (Name (Op_SETUPVAL) = "SETUPVAL", "mnemonic");
      Assert (Describe (Op_SETUPVAL) = Expected, "mode properties");
   end Test_SETUPVAL;

   procedure Test_GETTABUP is
      --  Protect the pinned GETTABUP ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_GETTABUP) = 11, "opcode ID");
      Assert (Name (Op_GETTABUP) = "GETTABUP", "mnemonic");
      Assert (Describe (Op_GETTABUP) = Expected, "mode properties");
   end Test_GETTABUP;

   procedure Test_GETTABLE is
      --  Protect the pinned GETTABLE ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_GETTABLE) = 12, "opcode ID");
      Assert (Name (Op_GETTABLE) = "GETTABLE", "mnemonic");
      Assert (Describe (Op_GETTABLE) = Expected, "mode properties");
   end Test_GETTABLE;

   procedure Test_GETI is
      --  Protect the pinned GETI ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_GETI) = 13, "opcode ID");
      Assert (Name (Op_GETI) = "GETI", "mnemonic");
      Assert (Describe (Op_GETI) = Expected, "mode properties");
   end Test_GETI;

   procedure Test_GETFIELD is
      --  Protect the pinned GETFIELD ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_GETFIELD) = 14, "opcode ID");
      Assert (Name (Op_GETFIELD) = "GETFIELD", "mnemonic");
      Assert (Describe (Op_GETFIELD) = Expected, "mode properties");
   end Test_GETFIELD;

   procedure Test_SETTABUP is
      --  Protect the pinned SETTABUP ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_SETTABUP) = 15, "opcode ID");
      Assert (Name (Op_SETTABUP) = "SETTABUP", "mnemonic");
      Assert (Describe (Op_SETTABUP) = Expected, "mode properties");
   end Test_SETTABUP;

   procedure Test_SETTABLE is
      --  Protect the pinned SETTABLE ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_SETTABLE) = 16, "opcode ID");
      Assert (Name (Op_SETTABLE) = "SETTABLE", "mnemonic");
      Assert (Describe (Op_SETTABLE) = Expected, "mode properties");
   end Test_SETTABLE;

   procedure Test_SETI is
      --  Protect the pinned SETI ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_SETI) = 17, "opcode ID");
      Assert (Name (Op_SETI) = "SETI", "mnemonic");
      Assert (Describe (Op_SETI) = Expected, "mode properties");
   end Test_SETI;

   procedure Test_SETFIELD is
      --  Protect the pinned SETFIELD ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_SETFIELD) = 18, "opcode ID");
      Assert (Name (Op_SETFIELD) = "SETFIELD", "mnemonic");
      Assert (Describe (Op_SETFIELD) = Expected, "mode properties");
   end Test_SETFIELD;

   procedure Test_NEWTABLE is
      --  Protect the pinned NEWTABLE ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IVABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_NEWTABLE) = 19, "opcode ID");
      Assert (Name (Op_NEWTABLE) = "NEWTABLE", "mnemonic");
      Assert (Describe (Op_NEWTABLE) = Expected, "mode properties");
   end Test_NEWTABLE;

   procedure Test_SELF is
      --  Protect the pinned SELF ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_SELF) = 20, "opcode ID");
      Assert (Name (Op_SELF) = "SELF", "mnemonic");
      Assert (Describe (Op_SELF) = Expected, "mode properties");
   end Test_SELF;

   procedure Test_ADDI is
      --  Protect the pinned ADDI ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_ADDI) = 21, "opcode ID");
      Assert (Name (Op_ADDI) = "ADDI", "mnemonic");
      Assert (Describe (Op_ADDI) = Expected, "mode properties");
   end Test_ADDI;

   procedure Test_ADDK is
      --  Protect the pinned ADDK ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_ADDK) = 22, "opcode ID");
      Assert (Name (Op_ADDK) = "ADDK", "mnemonic");
      Assert (Describe (Op_ADDK) = Expected, "mode properties");
   end Test_ADDK;

   procedure Test_SUBK is
      --  Protect the pinned SUBK ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_SUBK) = 23, "opcode ID");
      Assert (Name (Op_SUBK) = "SUBK", "mnemonic");
      Assert (Describe (Op_SUBK) = Expected, "mode properties");
   end Test_SUBK;

   procedure Test_MULK is
      --  Protect the pinned MULK ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_MULK) = 24, "opcode ID");
      Assert (Name (Op_MULK) = "MULK", "mnemonic");
      Assert (Describe (Op_MULK) = Expected, "mode properties");
   end Test_MULK;

   procedure Test_MODK is
      --  Protect the pinned MODK ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_MODK) = 25, "opcode ID");
      Assert (Name (Op_MODK) = "MODK", "mnemonic");
      Assert (Describe (Op_MODK) = Expected, "mode properties");
   end Test_MODK;

   procedure Test_POWK is
      --  Protect the pinned POWK ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_POWK) = 26, "opcode ID");
      Assert (Name (Op_POWK) = "POWK", "mnemonic");
      Assert (Describe (Op_POWK) = Expected, "mode properties");
   end Test_POWK;

   procedure Test_DIVK is
      --  Protect the pinned DIVK ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_DIVK) = 27, "opcode ID");
      Assert (Name (Op_DIVK) = "DIVK", "mnemonic");
      Assert (Describe (Op_DIVK) = Expected, "mode properties");
   end Test_DIVK;

   procedure Test_IDIVK is
      --  Protect the pinned IDIVK ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_IDIVK) = 28, "opcode ID");
      Assert (Name (Op_IDIVK) = "IDIVK", "mnemonic");
      Assert (Describe (Op_IDIVK) = Expected, "mode properties");
   end Test_IDIVK;

   procedure Test_BANDK is
      --  Protect the pinned BANDK ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_BANDK) = 29, "opcode ID");
      Assert (Name (Op_BANDK) = "BANDK", "mnemonic");
      Assert (Describe (Op_BANDK) = Expected, "mode properties");
   end Test_BANDK;

   procedure Test_BORK is
      --  Protect the pinned BORK ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_BORK) = 30, "opcode ID");
      Assert (Name (Op_BORK) = "BORK", "mnemonic");
      Assert (Describe (Op_BORK) = Expected, "mode properties");
   end Test_BORK;

   procedure Test_BXORK is
      --  Protect the pinned BXORK ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_BXORK) = 31, "opcode ID");
      Assert (Name (Op_BXORK) = "BXORK", "mnemonic");
      Assert (Describe (Op_BXORK) = Expected, "mode properties");
   end Test_BXORK;

   procedure Test_SHLI is
      --  Protect the pinned SHLI ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_SHLI) = 32, "opcode ID");
      Assert (Name (Op_SHLI) = "SHLI", "mnemonic");
      Assert (Describe (Op_SHLI) = Expected, "mode properties");
   end Test_SHLI;

   procedure Test_SHRI is
      --  Protect the pinned SHRI ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_SHRI) = 33, "opcode ID");
      Assert (Name (Op_SHRI) = "SHRI", "mnemonic");
      Assert (Describe (Op_SHRI) = Expected, "mode properties");
   end Test_SHRI;

   procedure Test_ADD is
      --  Protect the pinned ADD ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_ADD) = 34, "opcode ID");
      Assert (Name (Op_ADD) = "ADD", "mnemonic");
      Assert (Describe (Op_ADD) = Expected, "mode properties");
   end Test_ADD;

   procedure Test_SUB is
      --  Protect the pinned SUB ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_SUB) = 35, "opcode ID");
      Assert (Name (Op_SUB) = "SUB", "mnemonic");
      Assert (Describe (Op_SUB) = Expected, "mode properties");
   end Test_SUB;

   procedure Test_MUL is
      --  Protect the pinned MUL ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_MUL) = 36, "opcode ID");
      Assert (Name (Op_MUL) = "MUL", "mnemonic");
      Assert (Describe (Op_MUL) = Expected, "mode properties");
   end Test_MUL;

   procedure Test_MOD is
      --  Protect the pinned MOD ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_MOD) = 37, "opcode ID");
      Assert (Name (Op_MOD) = "MOD", "mnemonic");
      Assert (Describe (Op_MOD) = Expected, "mode properties");
   end Test_MOD;

   procedure Test_POW is
      --  Protect the pinned POW ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_POW) = 38, "opcode ID");
      Assert (Name (Op_POW) = "POW", "mnemonic");
      Assert (Describe (Op_POW) = Expected, "mode properties");
   end Test_POW;

   procedure Test_DIV is
      --  Protect the pinned DIV ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_DIV) = 39, "opcode ID");
      Assert (Name (Op_DIV) = "DIV", "mnemonic");
      Assert (Describe (Op_DIV) = Expected, "mode properties");
   end Test_DIV;

   procedure Test_IDIV is
      --  Protect the pinned IDIV ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_IDIV) = 40, "opcode ID");
      Assert (Name (Op_IDIV) = "IDIV", "mnemonic");
      Assert (Describe (Op_IDIV) = Expected, "mode properties");
   end Test_IDIV;

   procedure Test_BAND is
      --  Protect the pinned BAND ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_BAND) = 41, "opcode ID");
      Assert (Name (Op_BAND) = "BAND", "mnemonic");
      Assert (Describe (Op_BAND) = Expected, "mode properties");
   end Test_BAND;

   procedure Test_BOR is
      --  Protect the pinned BOR ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_BOR) = 42, "opcode ID");
      Assert (Name (Op_BOR) = "BOR", "mnemonic");
      Assert (Describe (Op_BOR) = Expected, "mode properties");
   end Test_BOR;

   procedure Test_BXOR is
      --  Protect the pinned BXOR ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_BXOR) = 43, "opcode ID");
      Assert (Name (Op_BXOR) = "BXOR", "mnemonic");
      Assert (Describe (Op_BXOR) = Expected, "mode properties");
   end Test_BXOR;

   procedure Test_SHL is
      --  Protect the pinned SHL ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_SHL) = 44, "opcode ID");
      Assert (Name (Op_SHL) = "SHL", "mnemonic");
      Assert (Describe (Op_SHL) = Expected, "mode properties");
   end Test_SHL;

   procedure Test_SHR is
      --  Protect the pinned SHR ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_SHR) = 45, "opcode ID");
      Assert (Name (Op_SHR) = "SHR", "mnemonic");
      Assert (Describe (Op_SHR) = Expected, "mode properties");
   end Test_SHR;

   procedure Test_MMBIN is
      --  Protect the pinned MMBIN ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, True);
   begin
      Assert (Opcode'Enum_Rep (Op_MMBIN) = 46, "opcode ID");
      Assert (Name (Op_MMBIN) = "MMBIN", "mnemonic");
      Assert (Describe (Op_MMBIN) = Expected, "mode properties");
   end Test_MMBIN;

   procedure Test_MMBINI is
      --  Protect the pinned MMBINI ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, True);
   begin
      Assert (Opcode'Enum_Rep (Op_MMBINI) = 47, "opcode ID");
      Assert (Name (Op_MMBINI) = "MMBINI", "mnemonic");
      Assert (Describe (Op_MMBINI) = Expected, "mode properties");
   end Test_MMBINI;

   procedure Test_MMBINK is
      --  Protect the pinned MMBINK ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, True);
   begin
      Assert (Opcode'Enum_Rep (Op_MMBINK) = 48, "opcode ID");
      Assert (Name (Op_MMBINK) = "MMBINK", "mnemonic");
      Assert (Describe (Op_MMBINK) = Expected, "mode properties");
   end Test_MMBINK;

   procedure Test_UNM is
      --  Protect the pinned UNM ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_UNM) = 49, "opcode ID");
      Assert (Name (Op_UNM) = "UNM", "mnemonic");
      Assert (Describe (Op_UNM) = Expected, "mode properties");
   end Test_UNM;

   procedure Test_BNOT is
      --  Protect the pinned BNOT ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_BNOT) = 50, "opcode ID");
      Assert (Name (Op_BNOT) = "BNOT", "mnemonic");
      Assert (Describe (Op_BNOT) = Expected, "mode properties");
   end Test_BNOT;

   procedure Test_NOT is
      --  Protect the pinned NOT ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_NOT) = 51, "opcode ID");
      Assert (Name (Op_NOT) = "NOT", "mnemonic");
      Assert (Describe (Op_NOT) = Expected, "mode properties");
   end Test_NOT;

   procedure Test_LEN is
      --  Protect the pinned LEN ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_LEN) = 52, "opcode ID");
      Assert (Name (Op_LEN) = "LEN", "mnemonic");
      Assert (Describe (Op_LEN) = Expected, "mode properties");
   end Test_LEN;

   procedure Test_CONCAT is
      --  Protect the pinned CONCAT ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_CONCAT) = 53, "opcode ID");
      Assert (Name (Op_CONCAT) = "CONCAT", "mnemonic");
      Assert (Describe (Op_CONCAT) = Expected, "mode properties");
   end Test_CONCAT;

   procedure Test_CLOSE is
      --  Protect the pinned CLOSE ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_CLOSE) = 54, "opcode ID");
      Assert (Name (Op_CLOSE) = "CLOSE", "mnemonic");
      Assert (Describe (Op_CLOSE) = Expected, "mode properties");
   end Test_CLOSE;

   procedure Test_TBC is
      --  Protect the pinned TBC ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_TBC) = 55, "opcode ID");
      Assert (Name (Op_TBC) = "TBC", "mnemonic");
      Assert (Describe (Op_TBC) = Expected, "mode properties");
   end Test_TBC;

   procedure Test_JMP is
      --  Protect the pinned JMP ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IsJ, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_JMP) = 56, "opcode ID");
      Assert (Name (Op_JMP) = "JMP", "mnemonic");
      Assert (Describe (Op_JMP) = Expected, "mode properties");
   end Test_JMP;

   procedure Test_EQ is
      --  Protect the pinned EQ ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, True, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_EQ) = 57, "opcode ID");
      Assert (Name (Op_EQ) = "EQ", "mnemonic");
      Assert (Describe (Op_EQ) = Expected, "mode properties");
   end Test_EQ;

   procedure Test_LT is
      --  Protect the pinned LT ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, True, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_LT) = 58, "opcode ID");
      Assert (Name (Op_LT) = "LT", "mnemonic");
      Assert (Describe (Op_LT) = Expected, "mode properties");
   end Test_LT;

   procedure Test_LE is
      --  Protect the pinned LE ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, True, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_LE) = 59, "opcode ID");
      Assert (Name (Op_LE) = "LE", "mnemonic");
      Assert (Describe (Op_LE) = Expected, "mode properties");
   end Test_LE;

   procedure Test_EQK is
      --  Protect the pinned EQK ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, True, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_EQK) = 60, "opcode ID");
      Assert (Name (Op_EQK) = "EQK", "mnemonic");
      Assert (Describe (Op_EQK) = Expected, "mode properties");
   end Test_EQK;

   procedure Test_EQI is
      --  Protect the pinned EQI ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, True, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_EQI) = 61, "opcode ID");
      Assert (Name (Op_EQI) = "EQI", "mnemonic");
      Assert (Describe (Op_EQI) = Expected, "mode properties");
   end Test_EQI;

   procedure Test_LTI is
      --  Protect the pinned LTI ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, True, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_LTI) = 62, "opcode ID");
      Assert (Name (Op_LTI) = "LTI", "mnemonic");
      Assert (Describe (Op_LTI) = Expected, "mode properties");
   end Test_LTI;

   procedure Test_LEI is
      --  Protect the pinned LEI ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, True, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_LEI) = 63, "opcode ID");
      Assert (Name (Op_LEI) = "LEI", "mnemonic");
      Assert (Describe (Op_LEI) = Expected, "mode properties");
   end Test_LEI;

   procedure Test_GTI is
      --  Protect the pinned GTI ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, True, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_GTI) = 64, "opcode ID");
      Assert (Name (Op_GTI) = "GTI", "mnemonic");
      Assert (Describe (Op_GTI) = Expected, "mode properties");
   end Test_GTI;

   procedure Test_GEI is
      --  Protect the pinned GEI ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, True, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_GEI) = 65, "opcode ID");
      Assert (Name (Op_GEI) = "GEI", "mnemonic");
      Assert (Describe (Op_GEI) = Expected, "mode properties");
   end Test_GEI;

   procedure Test_TEST is
      --  Protect the pinned TEST ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, True, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_TEST) = 66, "opcode ID");
      Assert (Name (Op_TEST) = "TEST", "mnemonic");
      Assert (Describe (Op_TEST) = Expected, "mode properties");
   end Test_TEST;

   procedure Test_TESTSET is
      --  Protect the pinned TESTSET ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, True, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_TESTSET) = 67, "opcode ID");
      Assert (Name (Op_TESTSET) = "TESTSET", "mnemonic");
      Assert (Describe (Op_TESTSET) = Expected, "mode properties");
   end Test_TESTSET;

   procedure Test_CALL is
      --  Protect the pinned CALL ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, True, True, False);
   begin
      Assert (Opcode'Enum_Rep (Op_CALL) = 68, "opcode ID");
      Assert (Name (Op_CALL) = "CALL", "mnemonic");
      Assert (Describe (Op_CALL) = Expected, "mode properties");
   end Test_CALL;

   procedure Test_TAILCALL is
      --  Protect the pinned TAILCALL ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, True, True, False);
   begin
      Assert (Opcode'Enum_Rep (Op_TAILCALL) = 69, "opcode ID");
      Assert (Name (Op_TAILCALL) = "TAILCALL", "mnemonic");
      Assert (Describe (Op_TAILCALL) = Expected, "mode properties");
   end Test_TAILCALL;

   procedure Test_RETURN is
      --  Protect the pinned RETURN ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, True, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_RETURN) = 70, "opcode ID");
      Assert (Name (Op_RETURN) = "RETURN", "mnemonic");
      Assert (Describe (Op_RETURN) = Expected, "mode properties");
   end Test_RETURN;

   procedure Test_RETURN0 is
      --  Protect the pinned RETURN0 ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_RETURN0) = 71, "opcode ID");
      Assert (Name (Op_RETURN0) = "RETURN0", "mnemonic");
      Assert (Describe (Op_RETURN0) = Expected, "mode properties");
   end Test_RETURN0;

   procedure Test_RETURN1 is
      --  Protect the pinned RETURN1 ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_RETURN1) = 72, "opcode ID");
      Assert (Name (Op_RETURN1) = "RETURN1", "mnemonic");
      Assert (Describe (Op_RETURN1) = Expected, "mode properties");
   end Test_RETURN1;

   procedure Test_FORLOOP is
      --  Protect the pinned FORLOOP ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABx, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_FORLOOP) = 73, "opcode ID");
      Assert (Name (Op_FORLOOP) = "FORLOOP", "mnemonic");
      Assert (Describe (Op_FORLOOP) = Expected, "mode properties");
   end Test_FORLOOP;

   procedure Test_FORPREP is
      --  Protect the pinned FORPREP ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABx, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_FORPREP) = 74, "opcode ID");
      Assert (Name (Op_FORPREP) = "FORPREP", "mnemonic");
      Assert (Describe (Op_FORPREP) = Expected, "mode properties");
   end Test_FORPREP;

   procedure Test_TFORPREP is
      --  Protect the pinned TFORPREP ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABx, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_TFORPREP) = 75, "opcode ID");
      Assert (Name (Op_TFORPREP) = "TFORPREP", "mnemonic");
      Assert (Describe (Op_TFORPREP) = Expected, "mode properties");
   end Test_TFORPREP;

   procedure Test_TFORCALL is
      --  Protect the pinned TFORCALL ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_TFORCALL) = 76, "opcode ID");
      Assert (Name (Op_TFORCALL) = "TFORCALL", "mnemonic");
      Assert (Describe (Op_TFORCALL) = Expected, "mode properties");
   end Test_TFORCALL;

   procedure Test_TFORLOOP is
      --  Protect the pinned TFORLOOP ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABx, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_TFORLOOP) = 77, "opcode ID");
      Assert (Name (Op_TFORLOOP) = "TFORLOOP", "mnemonic");
      Assert (Describe (Op_TFORLOOP) = Expected, "mode properties");
   end Test_TFORLOOP;

   procedure Test_SETLIST is
      --  Protect the pinned SETLIST ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IVABC, False, False, True, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_SETLIST) = 78, "opcode ID");
      Assert (Name (Op_SETLIST) = "SETLIST", "mnemonic");
      Assert (Describe (Op_SETLIST) = Expected, "mode properties");
   end Test_SETLIST;

   procedure Test_CLOSURE is
      --  Protect the pinned CLOSURE ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABx, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_CLOSURE) = 79, "opcode ID");
      Assert (Name (Op_CLOSURE) = "CLOSURE", "mnemonic");
      Assert (Describe (Op_CLOSURE) = Expected, "mode properties");
   end Test_CLOSURE;

   procedure Test_VARARG is
      --  Protect the pinned VARARG ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, True, False);
   begin
      Assert (Opcode'Enum_Rep (Op_VARARG) = 80, "opcode ID");
      Assert (Name (Op_VARARG) = "VARARG", "mnemonic");
      Assert (Describe (Op_VARARG) = Expected, "mode properties");
   end Test_VARARG;

   procedure Test_GETVARG is
      --  Protect the pinned GETVARG ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, True, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_GETVARG) = 81, "opcode ID");
      Assert (Name (Op_GETVARG) = "GETVARG", "mnemonic");
      Assert (Describe (Op_GETVARG) = Expected, "mode properties");
   end Test_GETVARG;

   procedure Test_ERRNNIL is
      --  Protect the pinned ERRNNIL ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABx, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_ERRNNIL) = 82, "opcode ID");
      Assert (Name (Op_ERRNNIL) = "ERRNNIL", "mnemonic");
      Assert (Describe (Op_ERRNNIL) = Expected, "mode properties");
   end Test_ERRNNIL;

   procedure Test_VARARGPREP is
      --  Protect the pinned VARARGPREP ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IABC, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_VARARGPREP) = 83, "opcode ID");
      Assert (Name (Op_VARARGPREP) = "VARARGPREP", "mnemonic");
      Assert (Describe (Op_VARARGPREP) = Expected, "mode properties");
   end Test_VARARGPREP;

   procedure Test_EXTRAARG is
      --  Protect the pinned EXTRAARG ID and all independent mode bits.
      --  A changed ordinal must fail even if the Ada enum is reordered.
      Expected : constant Properties :=
        (IAx, False, False, False, False, False);
   begin
      Assert (Opcode'Enum_Rep (Op_EXTRAARG) = 84, "opcode ID");
      Assert (Name (Op_EXTRAARG) = "EXTRAARG", "mnemonic");
      Assert (Describe (Op_EXTRAARG) = Expected, "mode properties");
   end Test_EXTRAARG;

   procedure Operand_Boundaries is
      --  Check each physical field at both endpoints and immediately outside.
      --  A distinctive seed makes accidental damage to other bits observable.
      type Bound is record
         Op : Opcode;
         Part : Field;
         Low, High : Integer;
      end record;
      Bounds : constant array (Positive range <>) of Bound :=
        [(Op_MOVE, A, 0, 255), (Op_MOVE, K, 0, 1),
         (Op_MOVE, B, 0, 255), (Op_MOVE, C, 0, 255),
         (Op_NEWTABLE, VB, 0, 63), (Op_NEWTABLE, VC, 0, 1023),
         (Op_LOADK, Bx, 0, 131_071),
         (Op_LOADI, SBx, -65_535, 65_536),
         (Op_EXTRAARG, Ax, 0, 33_554_431),
         (Op_JMP, SJ, -16_777_215, 16_777_216),
         (Op_MOVE, SB, -127, 128), (Op_MOVE, SC, -127, 128)];
      Updated : Instruction_Result;
      Samples : array (1 .. 3) of Integer;
   begin
      for Item of Bounds loop
         Samples := [Item.Low, 0, Item.High];
         for Value of Samples loop
            Updated := Set (Create (Item.Op), Item.Part, Value);
            Assert (Updated.Status = Success, "boundary accepted");
            Assert (Get (Updated.Value, Item.Part) = (Success, Value),
                    "boundary decoded exactly");
            Assert (Operation (Updated.Value) = Item.Op,
                    "operand update preserves opcode");
         end loop;
         Assert (Set (Create (Item.Op), Item.Part, Item.Low - 1).Status =
                 Out_Of_Range, "lower overflow rejected");
         Assert (Set (Create (Item.Op), Item.Part, Item.High + 1).Status =
                 Out_Of_Range, "upper overflow rejected");
      end loop;
      Assert (Get (Create (Op_LOADK), B).Status = Wrong_Format,
              "ordinary B is not a Bx operand");
      Assert (Set (Create (Op_NEWTABLE), B, 0).Status = Wrong_Format,
              "variant fields cannot be mistaken for ordinary fields");
   end Operand_Boundaries;

   procedure Invalid_Words is
      --  All unused seven-bit IDs must be rejected before enum conversion,
      --  including when the rest of an untrusted instruction is all ones.
      Item : Word;
   begin
      for Id in 85 .. 127 loop
         Item := 16#FFFF_FF80# or Word (Id);
         Assert (not Valid (Item), "unused ID");
         Assert (Get (Item, A).Status = Invalid_Opcode, "safe decode");
         Assert (Set (Item, A, 0).Status = Invalid_Opcode, "safe update");
      end loop;
   end Invalid_Words;

   procedure Top_Predicates is
      --  Lua 5.5 SETLIST uses vB, and VARARGPREP is a special input-top
      --  instruction. TAILCALL sets top even with a nonzero C operand.
      Item : Word;
   begin
      Assert (Uses_Top (Create (Op_VARARGPREP)), "vararg preparation");
      Item := Set (Create (Op_SETLIST), VC, 1023).Value;
      Assert (Uses_Top (Item), "vC must not contaminate vB");
      Item := Set (Item, VB, 1).Value;
      Assert (not Uses_Top (Item), "closed sequence count");
      Item := Set (Create (Op_TAILCALL), C, 1).Value;
      Assert (Sets_Top (Item), "tail call always produces open results");
      Item := Set (Create (Op_CALL), B, 1).Value;
      Assert (not Uses_Top (Item), "fixed argument count");
      Assert (Sets_Top (Item), "zero result count opens top");
      Item := Set (Item, C, 1).Value;
      Assert (not Sets_Top (Item), "fixed result count");
   end Top_Predicates;

   procedure Round_Trips is
      --  Deterministic arbitrary words exercise bit preservation, independent
      --  of source code. Decode and replace every legal field; the original
      --  word must survive even when signed fields or k overlap other views.
      Seed : Word := 16#A51C_9237#;
      Item : Word;
      Read : Operand_Result;
      Updated : Instruction_Result;
   begin
      for Index in 1 .. 4096 loop
         Seed := Seed * 1_664_525 + 1_013_904_223;
         Item := (Seed and 16#FFFF_FF80#) or Word (Index mod Opcode_Count);
         for Part in Field loop
            Read := Get (Item, Part);
            if Read.Status = Success then
               Updated := Set (Item, Part, Read.Value);
               Assert (Updated.Status = Success and then
                       Updated.Value = Item, "round trip preserves all bits");
            end if;
         end loop;
      end loop;
   end Round_Trips;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "opcode: MOVE", Test_MOVE'Access);
      Test_Support.Add (Suite, "opcode: LOADI", Test_LOADI'Access);
      Test_Support.Add (Suite, "opcode: LOADF", Test_LOADF'Access);
      Test_Support.Add (Suite, "opcode: LOADK", Test_LOADK'Access);
      Test_Support.Add (Suite, "opcode: LOADKX", Test_LOADKX'Access);
      Test_Support.Add (Suite, "opcode: LOADFALSE", Test_LOADFALSE'Access);
      Test_Support.Add (Suite, "opcode: LFALSESKIP", Test_LFALSESKIP'Access);
      Test_Support.Add (Suite, "opcode: LOADTRUE", Test_LOADTRUE'Access);
      Test_Support.Add (Suite, "opcode: LOADNIL", Test_LOADNIL'Access);
      Test_Support.Add (Suite, "opcode: GETUPVAL", Test_GETUPVAL'Access);
      Test_Support.Add (Suite, "opcode: SETUPVAL", Test_SETUPVAL'Access);
      Test_Support.Add (Suite, "opcode: GETTABUP", Test_GETTABUP'Access);
      Test_Support.Add (Suite, "opcode: GETTABLE", Test_GETTABLE'Access);
      Test_Support.Add (Suite, "opcode: GETI", Test_GETI'Access);
      Test_Support.Add (Suite, "opcode: GETFIELD", Test_GETFIELD'Access);
      Test_Support.Add (Suite, "opcode: SETTABUP", Test_SETTABUP'Access);
      Test_Support.Add (Suite, "opcode: SETTABLE", Test_SETTABLE'Access);
      Test_Support.Add (Suite, "opcode: SETI", Test_SETI'Access);
      Test_Support.Add (Suite, "opcode: SETFIELD", Test_SETFIELD'Access);
      Test_Support.Add (Suite, "opcode: NEWTABLE", Test_NEWTABLE'Access);
      Test_Support.Add (Suite, "opcode: SELF", Test_SELF'Access);
      Test_Support.Add (Suite, "opcode: ADDI", Test_ADDI'Access);
      Test_Support.Add (Suite, "opcode: ADDK", Test_ADDK'Access);
      Test_Support.Add (Suite, "opcode: SUBK", Test_SUBK'Access);
      Test_Support.Add (Suite, "opcode: MULK", Test_MULK'Access);
      Test_Support.Add (Suite, "opcode: MODK", Test_MODK'Access);
      Test_Support.Add (Suite, "opcode: POWK", Test_POWK'Access);
      Test_Support.Add (Suite, "opcode: DIVK", Test_DIVK'Access);
      Test_Support.Add (Suite, "opcode: IDIVK", Test_IDIVK'Access);
      Test_Support.Add (Suite, "opcode: BANDK", Test_BANDK'Access);
      Test_Support.Add (Suite, "opcode: BORK", Test_BORK'Access);
      Test_Support.Add (Suite, "opcode: BXORK", Test_BXORK'Access);
      Test_Support.Add (Suite, "opcode: SHLI", Test_SHLI'Access);
      Test_Support.Add (Suite, "opcode: SHRI", Test_SHRI'Access);
      Test_Support.Add (Suite, "opcode: ADD", Test_ADD'Access);
      Test_Support.Add (Suite, "opcode: SUB", Test_SUB'Access);
      Test_Support.Add (Suite, "opcode: MUL", Test_MUL'Access);
      Test_Support.Add (Suite, "opcode: MOD", Test_MOD'Access);
      Test_Support.Add (Suite, "opcode: POW", Test_POW'Access);
      Test_Support.Add (Suite, "opcode: DIV", Test_DIV'Access);
      Test_Support.Add (Suite, "opcode: IDIV", Test_IDIV'Access);
      Test_Support.Add (Suite, "opcode: BAND", Test_BAND'Access);
      Test_Support.Add (Suite, "opcode: BOR", Test_BOR'Access);
      Test_Support.Add (Suite, "opcode: BXOR", Test_BXOR'Access);
      Test_Support.Add (Suite, "opcode: SHL", Test_SHL'Access);
      Test_Support.Add (Suite, "opcode: SHR", Test_SHR'Access);
      Test_Support.Add (Suite, "opcode: MMBIN", Test_MMBIN'Access);
      Test_Support.Add (Suite, "opcode: MMBINI", Test_MMBINI'Access);
      Test_Support.Add (Suite, "opcode: MMBINK", Test_MMBINK'Access);
      Test_Support.Add (Suite, "opcode: UNM", Test_UNM'Access);
      Test_Support.Add (Suite, "opcode: BNOT", Test_BNOT'Access);
      Test_Support.Add (Suite, "opcode: NOT", Test_NOT'Access);
      Test_Support.Add (Suite, "opcode: LEN", Test_LEN'Access);
      Test_Support.Add (Suite, "opcode: CONCAT", Test_CONCAT'Access);
      Test_Support.Add (Suite, "opcode: CLOSE", Test_CLOSE'Access);
      Test_Support.Add (Suite, "opcode: TBC", Test_TBC'Access);
      Test_Support.Add (Suite, "opcode: JMP", Test_JMP'Access);
      Test_Support.Add (Suite, "opcode: EQ", Test_EQ'Access);
      Test_Support.Add (Suite, "opcode: LT", Test_LT'Access);
      Test_Support.Add (Suite, "opcode: LE", Test_LE'Access);
      Test_Support.Add (Suite, "opcode: EQK", Test_EQK'Access);
      Test_Support.Add (Suite, "opcode: EQI", Test_EQI'Access);
      Test_Support.Add (Suite, "opcode: LTI", Test_LTI'Access);
      Test_Support.Add (Suite, "opcode: LEI", Test_LEI'Access);
      Test_Support.Add (Suite, "opcode: GTI", Test_GTI'Access);
      Test_Support.Add (Suite, "opcode: GEI", Test_GEI'Access);
      Test_Support.Add (Suite, "opcode: TEST", Test_TEST'Access);
      Test_Support.Add (Suite, "opcode: TESTSET", Test_TESTSET'Access);
      Test_Support.Add (Suite, "opcode: CALL", Test_CALL'Access);
      Test_Support.Add (Suite, "opcode: TAILCALL", Test_TAILCALL'Access);
      Test_Support.Add (Suite, "opcode: RETURN", Test_RETURN'Access);
      Test_Support.Add (Suite, "opcode: RETURN0", Test_RETURN0'Access);
      Test_Support.Add (Suite, "opcode: RETURN1", Test_RETURN1'Access);
      Test_Support.Add (Suite, "opcode: FORLOOP", Test_FORLOOP'Access);
      Test_Support.Add (Suite, "opcode: FORPREP", Test_FORPREP'Access);
      Test_Support.Add (Suite, "opcode: TFORPREP", Test_TFORPREP'Access);
      Test_Support.Add (Suite, "opcode: TFORCALL", Test_TFORCALL'Access);
      Test_Support.Add (Suite, "opcode: TFORLOOP", Test_TFORLOOP'Access);
      Test_Support.Add (Suite, "opcode: SETLIST", Test_SETLIST'Access);
      Test_Support.Add (Suite, "opcode: CLOSURE", Test_CLOSURE'Access);
      Test_Support.Add (Suite, "opcode: VARARG", Test_VARARG'Access);
      Test_Support.Add (Suite, "opcode: GETVARG", Test_GETVARG'Access);
      Test_Support.Add (Suite, "opcode: ERRNNIL", Test_ERRNNIL'Access);
      Test_Support.Add (Suite, "opcode: VARARGPREP", Test_VARARGPREP'Access);
      Test_Support.Add (Suite, "opcode: EXTRAARG", Test_EXTRAARG'Access);
      Test_Support.Add
        (Suite, "opcode: operand boundaries", Operand_Boundaries'Access);
      Test_Support.Add
        (Suite, "opcode: invalid words", Invalid_Words'Access);
      Test_Support.Add
        (Suite, "opcode: dynamic top predicates", Top_Predicates'Access);
      Test_Support.Add
        (Suite, "opcode: 4096 round trips", Round_Trips'Access);
   end Register;
end Lua.Opcode_Tests;

