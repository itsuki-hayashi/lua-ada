with Ada.Unchecked_Conversion;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.C_Loadfile_Tests is
   use type Interfaces.C.int;
   use type Lua.Storage.Byte_Count;
   function Check (Which : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_loadfile";
   function Prepare return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_loadfile_budget";
   function Cleanup return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_test_loadfile_cleanup";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Bounded_Check (Bounds : Limits);
   procedure Source_Quota;
   procedure Work_Quota;
   procedure Empty_File;
   procedure Bom;
   procedure Shebang;
   procedure CrLf;
   procedure Incomplete_Bom;
   procedure Syntax_Class;
   procedure Text_Mode;
   procedure Binary_Mode;
   procedure Dump_Load;
   procedure Stripped_Dump;
   procedure Source_Info;
   procedure Missing_Errno;
   procedure Nul_Filename;
   procedure Success_Stack;
   procedure Missing_Stack;
   procedure Syntax_Stack;
   procedure Protected_Call;
   procedure Refusal_Recovery;
   procedure Prefixed_Binary;
   procedure Growth_Sweep;
   procedure Shebang_CR;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Empty_File is
   begin
      Assert (Check (0) = 1, "empty file");
   end Empty_File;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Bom is
   begin
      Assert (Check (1) = 1, "BOM skipped");
   end Bom;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Shebang is
   begin
      Assert (Check (2) = 1, "shebang lines");
   end Shebang;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure CrLf is
   begin
      Assert (Check (3) = 1, "CRLF lines");
   end CrLf;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Incomplete_Bom is
   begin
      Assert (Check (4) = 1, "incomplete BOM");
   end Incomplete_Bom;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Syntax_Class is
   begin
      Assert (Check (5) = 1, "syntax error class");
   end Syntax_Class;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Text_Mode is
   begin
      Assert (Check (6) = 1, "text mode rejects binary");
   end Text_Mode;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Binary_Mode is
   begin
      Assert (Check (7) = 1, "binary mode rejects text");
   end Binary_Mode;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Dump_Load is
   begin
      Assert (Check (8) = 1, "dump file loads");
   end Dump_Load;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Stripped_Dump is
   begin
      Assert (Check (9) = 1, "stripped dump metadata");
   end Stripped_Dump;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Source_Info is
   begin
      Assert (Check (10) = 1, "source metadata");
   end Source_Info;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Missing_Errno is
   begin
      Assert (Check (11) = 1, "native missing errno");
   end Missing_Errno;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Nul_Filename is
   begin
      Assert (Check (12) = 1, "NUL filename");
   end Nul_Filename;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Success_Stack is
   begin
      Assert (Check (13) = 1, "success preserves stack");
   end Success_Stack;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Missing_Stack is
   begin
      Assert (Check (14) = 1, "missing preserves stack");
   end Missing_Stack;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Syntax_Stack is
   begin
      Assert (Check (15) = 1, "syntax preserves stack");
   end Syntax_Stack;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Protected_Call is
   begin
      Assert (Check (16) = 1, "protected callback");
   end Protected_Call;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Refusal_Recovery is
   begin
      Assert (Check (17) = 1, "refusal and recovery");
   end Refusal_Recovery;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Prefixed_Binary is
   begin
      Assert (Check (18) = 1, "prefixed binary alignment");
   end Prefixed_Binary;

   --  Shared C source documents setup/action/expected and closes its state.
   procedure Growth_Sweep is
   begin
      Assert (Check (19) = 1, "actual growth refusal sweep");
   end Growth_Sweep;

   procedure Shebang_CR is
   begin
      --  The identical native C case proves LF-only comment termination.
      Assert (Check (20) = 1, "lone CR within ignored interpreter line");
   end Shebang_CR;

   procedure Bounded_Check (Bounds : Limits) is
      State : World;
      Item : Value;
      Ready : Boolean := False;
      Ignored : Interfaces.C.int;
      pragma Unreferenced (Ignored);
   begin
      Initialize (State, Bounds);
      Begin_Operation (State);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Prepare);
      Ready := True;
      Set (State, Global_Environment (State), New_String (State, "fileload"),
           Item);
      End_Operation (State);
      Assert (not Execute (State,
        "pcall(fileload); error('file host abort was caught')", "file-quota"),
        "public file loading must retain the uncatchable host policy");
      Assert (State.Current.Failure_Class = Host_Abort,
              "file source/work quota became a catchable error");
      --  Dispose immediately without running another Lua operation or GC.
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "file source/provider ownership survived physical teardown");
      Assert (Cleanup = 0, "quota fixture was not removed after file close");
      Ready := False;
   exception
      when others =>
         Finalize (State);
         if Ready then Ignored := Cleanup; end if;
         raise;
   end Bounded_Check;

   procedure Source_Quota is
   begin
      --  The script fits; the actual 2056-byte file exceeds this source cap.
      Bounded_Check ((Source_Bytes => 512, others => <>));
   end Source_Quota;

   procedure Work_Quota is
   begin
      --  The file fits; its real stream work exceeds the shared step budget.
      Bounded_Check
        ((Instructions => 1_000, Source_Bytes => 8_192, others => <>));
   end Work_Quota;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "C file loading: empty file",
                        Empty_File'Access);
      Test_Support.Add (Suite, "C file loading: BOM skipped",
                        Bom'Access);
      Test_Support.Add (Suite, "C file loading: shebang lines",
                        Shebang'Access);
      Test_Support.Add (Suite, "C file loading: CRLF lines",
                        CrLf'Access);
      Test_Support.Add (Suite, "C file loading: incomplete BOM",
                        Incomplete_Bom'Access);
      Test_Support.Add (Suite, "C file loading: syntax error class",
                        Syntax_Class'Access);
      Test_Support.Add (Suite, "C file loading: text mode rejects binary",
                        Text_Mode'Access);
      Test_Support.Add (Suite, "C file loading: binary mode rejects text",
                        Binary_Mode'Access);
      Test_Support.Add (Suite, "C file loading: dump file loads",
                        Dump_Load'Access);
      Test_Support.Add (Suite, "C file loading: stripped dump metadata",
                        Stripped_Dump'Access);
      Test_Support.Add (Suite, "C file loading: source metadata",
                        Source_Info'Access);
      Test_Support.Add (Suite, "C file loading: native missing errno",
                        Missing_Errno'Access);
      Test_Support.Add (Suite, "C file loading: NUL filename",
                        Nul_Filename'Access);
      Test_Support.Add (Suite, "C file loading: success preserves stack",
                        Success_Stack'Access);
      Test_Support.Add (Suite, "C file loading: missing preserves stack",
                        Missing_Stack'Access);
      Test_Support.Add (Suite, "C file loading: syntax preserves stack",
                        Syntax_Stack'Access);
      Test_Support.Add (Suite, "C file loading: protected callback",
                        Protected_Call'Access);
      Test_Support.Add (Suite, "C file loading: refusal and recovery",
                        Refusal_Recovery'Access);
      Test_Support.Add (Suite, "C file loading: prefixed binary alignment",
                        Prefixed_Binary'Access);
      Test_Support.Add (Suite, "C file loading: actual growth refusal sweep",
                        Growth_Sweep'Access);
      Test_Support.Add (Suite, "C file loading: shebang lone CR",
                        Shebang_CR'Access);
      Test_Support.Add (Suite, "C file loading: source host quota cleanup",
                        Source_Quota'Access);
      Test_Support.Add (Suite, "C file loading: work host quota cleanup",
                        Work_Quota'Access);
   end Register;
end Lua.C_Loadfile_Tests;
