with Binary_Runtime_Tests;
with Ada.Command_Line;
with AUnit.Reporter.Text;
with AUnit.Run;
with AUnit.Test_Suites;
with Integer_Tests;
with Lexer_Tests;
with Number_Tests;
with Session_Tests;
with Lifecycle_Tests;
with Runtime_Control_Tests;
with Runtime_Inspection_Tests;
with Lua.Opcode_Tests;
with Lua.Context_Tests;
with Lua.Table_Storage_Tests;
with Lua.Table_Reservation_Tests;
with Table_Algorithm_Tests;
with Lua.Storage_Tests;
with Lua.Big_Natural_Tests;
with Lua.Number_Storage_Tests;
with Lua.Storage_Vector_Tests;
with Lua.Mathematics_Tests;
with Lua.Managed_Runtime_Tests;
with Lua.Managed_Format_Tests;
with Lua.Runtime_Vector_Tests;
with Lua.Storage_Buffer_Tests;
with Lua.Loader_Storage_Tests;
with Lua.Frontend_Storage_Tests;
with Lua.Chunk_Tests;
with Lua.Canonical_Compiler_Tests;
with Lua.Canonical_Runtime_Tests;
with Lua.Machine_Driver_Tests;
with Syntax_Tests;
with Incremental_Lexer_Tests;
with Lua.Library_Codec_Tests;
with Lua.String_Helper_Tests;
with Library_Runtime_Tests;
with Native_Tests;
with Message_Handler_Tests;
with Source_Tests;

procedure Test_Runner is
   use type AUnit.Status;
   function Suite return AUnit.Test_Suites.Access_Test_Suite;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        new AUnit.Test_Suites.Test_Suite;
   begin
      --  Each registered procedure is a separate AUnit case, so one failing
      --  boundary does not hide the results of unrelated behavior checks.
      Integer_Tests.Register (Result);
      Lexer_Tests.Register (Result);
      Number_Tests.Register (Result);
      Session_Tests.Register (Result);
      Lifecycle_Tests.Register (Result);
      Runtime_Control_Tests.Register (Result);
      Runtime_Inspection_Tests.Register (Result);
      Lua.Opcode_Tests.Register (Result);
      Lua.Context_Tests.Register (Result);
      Lua.Table_Storage_Tests.Register (Result);
      Lua.Table_Reservation_Tests.Register (Result);
      Table_Algorithm_Tests.Register (Result);
      Lua.Storage_Tests.Register (Result);
      Lua.Big_Natural_Tests.Register (Result);
      Lua.Number_Storage_Tests.Register (Result);
      Lua.Storage_Vector_Tests.Register (Result);
      Lua.Mathematics_Tests.Register (Result);
      Lua.Managed_Runtime_Tests.Register (Result);
      Lua.Managed_Format_Tests.Register (Result);
      Lua.Runtime_Vector_Tests.Register (Result);
      Lua.Storage_Buffer_Tests.Register (Result);
      Lua.Loader_Storage_Tests.Register (Result);
      Lua.Frontend_Storage_Tests.Register (Result);
      Lua.Chunk_Tests.Register (Result);
      Lua.Canonical_Compiler_Tests.Register (Result);
      Lua.Canonical_Runtime_Tests.Register (Result);
      Lua.Machine_Driver_Tests.Register (Result);
      Syntax_Tests.Register (Result);
      Incremental_Lexer_Tests.Register (Result);
      Lua.Library_Codec_Tests.Register (Result);
      Lua.String_Helper_Tests.Register (Result);
      Library_Runtime_Tests.Register (Result);
      Native_Tests.Register (Result);
      Message_Handler_Tests.Register (Result);
      Source_Tests.Register (Result);
      Binary_Runtime_Tests.Register (Result);
      return Result;
   end Suite;

   function Run is new AUnit.Run.Test_Runner_With_Status (Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
begin
   if Run (Reporter) /= AUnit.Success then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Runner;
