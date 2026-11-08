with AUnit.Assertions; use AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces.C;
with Lua.Conformance_Allocator;
with Lua.Engine;
with Lua.Sessions.CLI;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.Sessions.CLI_Prompt_Tests is
   use type Interfaces.C.int;
   use type Lua.Engine.Object_Access;
   use type Lua.Engine.Value_Kind;
   use type Lua.Storage.Byte_Count;
   use type Interfaces.C.size_t;

   procedure Observe_History (Pointer : System.Address)
     with Convention => C;
   procedure Install_History (Pointer : System.Address)
     with Import, Convention => C,
          External_Name => "lua_ada_cli_test_history";
   procedure Restore_History
     with Import, Convention => C,
          External_Name => "lua_ada_cli_test_restore_history";
   function History_Length (Pointer : System.Address)
      return Interfaces.C.size_t
     with Import, Convention => C,
          External_Name => "lua_ada_cli_line_length";
   History_Calls, History_Used : Natural := 0;
   History_Bytes : String (1 .. 80) := [others => ' '];
   History_Overflow : Boolean := False;

   procedure Observe_History (Pointer : System.Address) is
      Size : constant Interfaces.C.size_t := History_Length (Pointer);
   begin
      --  This real C callback only copies a bounded observation. Assertions
      --  run after it returns, never unwinding an Ada exception through C.
      History_Calls := History_Calls + 1;
      if Size > History_Bytes'Length then
         History_Overflow := True;
      else
         History_Used := Natural (Size);
         declare
            Bytes : String (1 .. History_Used)
              with Import, Address => Pointer;
         begin
            History_Bytes (1 .. History_Used) := Bytes;
         end;
      end if;
   end Observe_History;

   procedure Setup (Self : in out Session; Name : String);
   procedure Setup (Self : in out Session; Name : String) is
      Result : constant Execution_Result := Self.Execute
        ("assert(loadfile('tests/lua/cli_prompt_controls.lua'))('" &
         Name & "')", "=prompt-setup");
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Setup;

   procedure Close_Checked (Self : in out Session);
   procedure Close_Checked (Self : in out Session) is
   begin
      Conformance_Allocator.Clear_Count_Limit;
      Conformance_Allocator.Set_Byte_Limit (0);
      Self.Close;
      --  The provider observer survives the expired session owner. Never
      --  dereference Self.State after Close merely to claim balanced cleanup.
      Conformance_Allocator.Finish;
      Assert (Conformance_Allocator.Measurements.Bytes = 0 and then
              Conformance_Allocator.Measurements.Blocks = 0,
              "prompt operation retained selected provider storage");
   end Close_Checked;

   procedure Check
     (Name, Expected : String; First_Line : Boolean := True;
      Expected_Status : Execution_Status := Succeeded);
   procedure Check
     (Name, Expected : String; First_Line : Boolean := True;
      Expected_Status : Execution_Status := Succeeded)
   is
      Self : Session;
      Result : Execution_Result;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Setup (Self, Name);
      Result := CLI.Write_Prompt (Self, First_Line);
      Assert (Result.Status = Expected_Status,
              Name & ": " & To_String (Result.Error.Message));
      if Expected_Status = Succeeded then
         Assert (To_String (Result.Output) = Expected,
                 Name & ": wrong prompt bytes");
      else
         Assert (To_String (Result.Error.Message) = Expected,
                 Name & ": wrong raw prompt failure");
      end if;
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Check;

   procedure Primary_Nil;
   procedure Primary_Nil is
   begin
      --  Nil alone selects the primary native default.
      Check ("primary-nil", "> ");
   end Primary_Nil;

   procedure Secondary_Nil;
   procedure Secondary_Nil is
   begin
      Check ("secondary-nil", ">> ", First_Line => False);
   end Secondary_Nil;

   procedure Custom_String;
   procedure Custom_String is
   begin
      Check ("custom-string", "alo");
   end Custom_String;

   procedure Empty_String;
   procedure Empty_String is
   begin
      --  Empty is a real prompt; it must not select the nil fallback.
      Check ("empty-string", "");
   end Empty_String;

   procedure Numeric_Prompt;
   procedure Numeric_Prompt is
   begin
      Check ("number", "17.0");
   end Numeric_Prompt;

   procedure Boolean_Prompt;
   procedure Boolean_Prompt is
   begin
      Check ("boolean", "false");
   end Boolean_Prompt;

   procedure Embedded_Nul;
   procedure Embedded_Nul is
   begin
      --  Lua keeps the whole value; native prompt output stops at NUL.
      Check ("embedded-nul", "P");
   end Embedded_Nul;

   procedure Replaced_Tostring;
   procedure Replaced_Tostring is
   begin
      Check ("global-tostring", "37");
   end Replaced_Tostring;

   procedure Numeric_Handler;
   procedure Numeric_Handler is
   begin
      --  luaL_tolstring accepts a numeric result through lua_isstring.
      Check ("numeric-tostring", "17.0");
   end Numeric_Handler;

   procedure Global_Handler;
   procedure Global_Handler is
   begin
      Check ("index-value", "index");
   end Global_Handler;

   procedure Tostring_Frame;
   procedure Tostring_Frame is
   begin
      Check ("tostring-frame", "frame");
   end Tostring_Frame;

   procedure Global_Frame;
   procedure Global_Frame is
   begin
      --  Inspect the actual C temporary. Native key-versus-global-table
      --  intermediate layout is distinct from explicit callback arguments.
      Check ("index-frame", "frame");
   end Global_Frame;

   procedure Invalid_Handler_Result;
   procedure Invalid_Handler_Result is
   begin
      Check ("bad-tostring", "'__tostring' must return a string",
             Expected_Status => Runtime_Error);
   end Invalid_Handler_Result;

   procedure Handler_Error;
   procedure Handler_Error is
   begin
      Check ("error-tostring", "prompt-broken",
             Expected_Status => Runtime_Error);
   end Handler_Error;

   procedure Table_Error;
   procedure Table_Error is
      Self : Session;
      Result : Execution_Result;
   begin
      --  The host's raw report does not call the error object's __tostring.
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Setup (Self, "error-table");
      Result := CLI.Write_Prompt (Self, True);
      Assert (Result.Status = Runtime_Error and then
              Result.Error.Message = "(error message not a string)",
              "table error display invoked or invented tostring");
      Assert (Self.State.Current.Has_Failure_Value and then
              Self.State.Current.Failure.Kind = Lua.Engine.Table_Kind and then
              Self.State.Current.Failure.Reference = Lua.Engine.Get
                (Lua.Engine.Global_Environment (Self.State.all),
                 Lua.Engine.New_String
                   (Self.State.all, "prompt_error")).Reference,
              "prompt error display changed the original Lua object");
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Table_Error;

   procedure Boolean_Error;
   procedure Boolean_Error is
   begin
      Check ("error-boolean", "(error message not a string)",
             Expected_Status => Runtime_Error);
   end Boolean_Error;

   procedure Nul_Error;
   procedure Nul_Error is
      Self : Session;
      Result : Execution_Result;
   begin
      --  Preserve the original Lua error internally; truncate host display.
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Setup (Self, "error-nul");
      Result := CLI.Write_Prompt (Self, True);
      Assert (Result.Status = Runtime_Error and then
              Result.Error.Message = "prefix", "NUL error display changed");
      Assert (Lua.Engine.Failure_Image (Self.State.Current) =
              "prefix" & ASCII.NUL & "hidden",
              "prompt display truncated the owned Lua error");
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Nul_Error;

   procedure Global_Error;
   procedure Global_Error is
   begin
      Check ("index-error", "index-broken",
             Expected_Status => Runtime_Error);
   end Global_Error;

   procedure Handler_Yield;
   procedure Handler_Yield is
   begin
      Check ("yield-tostring", "attempt to yield from outside a coroutine",
             Expected_Status => Runtime_Error);
   end Handler_Yield;

   procedure Dynamic_Handler;
   procedure Dynamic_Handler is
      Self : Session;
      Result : Execution_Result;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Setup (Self, "dynamic-tostring");
      for Count in 2 .. 4 loop
         Result := CLI.Write_Prompt (Self, True);
         Assert (Result.Status = Succeeded and then
                 To_String (Result.Output) = String'(1 .. Count => 'X'),
                 "each prompt resolves and converts the current value");
      end loop;
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Dynamic_Handler;

   procedure Retired_Root;
   procedure Retired_Root is
      Self : Session;
      Result : Execution_Result;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Setup (Self, "retired-root");
      Result := CLI.Write_Prompt (Self, True);
      Assert (Result.Status = Succeeded and then Result.Output = "root",
              "prompt argument survives callback collection");
      Result := Self.Execute
        ("collectgarbage();collectgarbage();assert(prompt_weak[1]==nil)",
         "=prompt-retirement");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Retired_Root;

   procedure Budget_Recovery;
   procedure Budget_Recovery is
      Self : Session;
      Result : Execution_Result;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Setup (Self, "budget");
      Self.Set_Limits ((Instructions => 1_000, others => <>));
      Result := CLI.Write_Prompt (Self, True);
      Assert (Result.Status = Resource_Error,
              "prompt callback caught an exhausted host budget");
      Self.Set_Limits ((others => <>));
      Result := Self.Execute ("assert(prompt_started);_PROMPT='ok'",
                              "=prompt-recovery");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Result := CLI.Write_Prompt (Self, True);
      Assert (Result.Status = Succeeded and then Result.Output = "ok",
              "prompt host abort abandoned its actual driver");
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Budget_Recovery;

   procedure Output_Budget;
   procedure Output_Budget is
      Self : Session;
      Result : Execution_Result;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Setup (Self, "custom-string");
      Self.Set_Limits ((Output_Bytes => 2, others => <>));
      Result := CLI.Write_Prompt (Self, True);
      Assert (Result.Status = Resource_Error,
              "prompt output bypassed the owning host policy");
      Self.Set_Limits ((others => <>));
      Result := CLI.Write_Prompt (Self, True);
      Assert (Result.Status = Succeeded and then Result.Output = "alo",
              "prompt output refusal prevents healthy retry");
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Output_Budget;

   procedure Exit_Without_Close;
   procedure Exit_Without_Close is
      Self : Session;
      Result : Execution_Result;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Setup (Self, "exit-no-close");
      Result := CLI.Write_Prompt (Self, True);
      Assert (Result.Status = Exit_Requested and then
              Result.Exit_Request.Code = 37 and then
              not Result.Exit_Request.Close_State,
              "prompt typed exit lost its no-close request");
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Exit_Without_Close;

   procedure Exit_With_Close;
   procedure Exit_With_Close is
      Self : Session;
      Result : Execution_Result;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Setup (Self, "exit-close");
      Result := CLI.Write_Prompt (Self, True);
      Assert (Result.Status = Exit_Requested and then
              Result.Exit_Request.Code = 37 and then
              Result.Exit_Request.Close_State,
              "prompt typed exit lost its completed close request");
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Exit_With_Close;

   procedure Refusal_Recovery;
   procedure Refusal_Recovery is
      Self : Session;
      Result : Execution_Result;
      Before : Lua.Storage.Byte_Count;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Setup (Self, "custom-string");
      Before := Conformance_Allocator.Measurements.Refusals;
      Conformance_Allocator.Set_Count_Limit (0);
      Result := CLI.Write_Prompt (Self, True);
      Conformance_Allocator.Clear_Count_Limit;
      Assert (Conformance_Allocator.Measurements.Refusals > Before,
              "cold prompt fixture did not refuse actual provider growth");
      Assert (Result.Status = Runtime_Error,
              "cold prompt refusal escaped typed failure publication");
      Result := CLI.Write_Prompt (Self, True);
      Assert (Result.Status = Succeeded and then Result.Output = "alo",
              "cold prompt allocation failure prevents healthy retry");
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Refusal_Recovery;

   procedure Empty_History;
   procedure Empty_History is
      Self : Session;
      Result : Execution_Result;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      History_Calls := 0;
      Install_History (Observe_History'Address);
      Conformance_Allocator.Set_Count_Limit (0);
      Result := CLI.Save_REPL_Line (Self, "");
      Assert (Result.Status = Succeeded and then History_Calls = 0 and then
              Conformance_Allocator.Measurements.Refusals = 0,
              "empty history must neither allocate nor invoke the backend");
      Restore_History;
      Close_Checked (Self);
   exception
      when others => Restore_History; Close_Checked (Self); raise;
   end Empty_History;

   procedure History_C_String;
   procedure History_C_String is
      Self : Session;
      Result : Execution_Result;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      History_Calls := 0;
      History_Overflow := False;
      Install_History (Observe_History'Address);
      Result := CLI.Save_REPL_Line (Self, "abc" & ASCII.NUL & "discard");
      Assert (Result.Status = Succeeded and then History_Calls = 1 and then
              not History_Overflow and then History_Used = 3 and then
              History_Bytes (1 .. 3) = "abc",
              "history callback must borrow the actual terminated prefix");
      Restore_History;
      Close_Checked (Self);
   exception
      when others => Restore_History; Close_Checked (Self); raise;
   end History_C_String;

   procedure History_Refusal;
   procedure History_Refusal is
      Self : Session;
      Result : Execution_Result;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      History_Calls := 0;
      Install_History (Observe_History'Address);
      Conformance_Allocator.Set_Count_Limit (0);
      Result := CLI.Save_REPL_Line (Self, "return 37");
      Assert (Result.Status = Runtime_Error and then History_Calls = 0 and then
              Conformance_Allocator.Measurements.Refusals > 0,
              "real history-buffer refusal must precede the native call");
      Conformance_Allocator.Clear_Count_Limit;
      Result := CLI.Save_REPL_Line (Self, "return 37");
      Assert (Result.Status = Succeeded and then History_Calls = 1,
              "history owner must recover after the actual provider refusal");
      Result := Self.Execute ("assert(6*7==42)", "=history-recovery");
      Assert (Result.Status = Succeeded,
              "history refusal must leave the session executable");
      Restore_History;
      Close_Checked (Self);
   exception
      when others => Restore_History; Close_Checked (Self); raise;
   end History_Refusal;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "CLI prompt: nil primary", Primary_Nil'Access);
      Test_Support.Add (Suite, "CLI prompt: nil secondary",
                        Secondary_Nil'Access);
      Test_Support.Add (Suite, "CLI prompt: custom string",
                        Custom_String'Access);
      Test_Support.Add (Suite, "CLI prompt: empty string",
                        Empty_String'Access);
      Test_Support.Add (Suite, "CLI prompt: numeric value",
                        Numeric_Prompt'Access);
      Test_Support.Add (Suite, "CLI prompt: boolean value",
                        Boolean_Prompt'Access);
      Test_Support.Add (Suite, "CLI prompt: embedded NUL",
                        Embedded_Nul'Access);
      Test_Support.Add (Suite, "CLI prompt: replaced global tostring",
                        Replaced_Tostring'Access);
      Test_Support.Add (Suite, "CLI prompt: numeric handler result",
                        Numeric_Handler'Access);
      Test_Support.Add (Suite, "CLI prompt: global handler",
                        Global_Handler'Access);
      Test_Support.Add (Suite, "CLI prompt: actual tostring C frame",
                        Tostring_Frame'Access);
      Test_Support.Add (Suite, "CLI prompt: actual global C frame",
                        Global_Frame'Access);
      Test_Support.Add (Suite, "CLI prompt: invalid handler result",
                        Invalid_Handler_Result'Access);
      Test_Support.Add (Suite, "CLI prompt: handler error",
                        Handler_Error'Access);
      Test_Support.Add (Suite, "CLI prompt: table error report",
                        Table_Error'Access);
      Test_Support.Add (Suite, "CLI prompt: boolean error report",
                        Boolean_Error'Access);
      Test_Support.Add (Suite, "CLI prompt: NUL error display",
                        Nul_Error'Access);
      Test_Support.Add (Suite, "CLI prompt: global error",
                        Global_Error'Access);
      Test_Support.Add (Suite, "CLI prompt: handler yield",
                        Handler_Yield'Access);
      Test_Support.Add (Suite, "CLI prompt: dynamic handler",
                        Dynamic_Handler'Access);
      Test_Support.Add (Suite, "CLI prompt: retired weak argument",
                        Retired_Root'Access);
      Test_Support.Add (Suite, "CLI prompt: charged callback recovery",
                        Budget_Recovery'Access);
      Test_Support.Add (Suite, "CLI prompt: output policy",
                        Output_Budget'Access);
      Test_Support.Add (Suite, "CLI prompt: exit without close",
                        Exit_Without_Close'Access);
      Test_Support.Add (Suite, "CLI prompt: exit with close",
                        Exit_With_Close'Access);
      Test_Support.Add (Suite, "CLI prompt: actual allocation refusal",
                        Refusal_Recovery'Access);
      Test_Support.Add (Suite, "CLI history: empty performs no allocation",
                        Empty_History'Access);
      Test_Support.Add (Suite, "CLI history: actual C string borrow",
                        History_C_String'Access);
      Test_Support.Add (Suite, "CLI history: actual provider refusal retry",
                        History_Refusal'Access);
   end Register;
end Lua.Sessions.CLI_Prompt_Tests;
