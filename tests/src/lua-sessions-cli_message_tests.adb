with AUnit.Assertions; use AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces.C;
with Lua.Conformance_Adapter;
with Lua.Conformance_Allocator;
with Lua.Sessions.CLI;
with Lua.Storage;
with Test_Support;

package body Lua.Sessions.CLI_Message_Tests is
   use type Interfaces.C.int;
   use type Lua.Storage.Byte_Count;

   procedure Close_Checked (Self : in out Session);
   procedure Close_Checked (Self : in out Session) is
   begin
      Conformance_Allocator.Clear_Count_Limit;
      Conformance_Allocator.Set_Byte_Limit (0);
      Self.Close;
      Conformance_Allocator.Finish;
      Assert (Conformance_Allocator.Measurements.Bytes = 0 and then
              Conformance_Allocator.Measurements.Blocks = 0,
              "CLI message operation retained selected provider storage");
   end Close_Checked;

   procedure Check
     (Name, Expected : String; Trace : Boolean; Exact : Boolean := False;
      Expected_Output : String := ""; Memory : Boolean := False;
      Selected : Boolean := False; Exit_Close : Boolean := False;
      Exits : Boolean := False);
   procedure Check
     (Name, Expected : String; Trace : Boolean; Exact : Boolean := False;
      Expected_Output : String := ""; Memory : Boolean := False;
      Selected : Boolean := False; Exit_Close : Boolean := False;
      Exits : Boolean := False)
   is
      Self : Session;
      Result : Execution_Result;
      Before : Lua.Storage.Byte_Count;
      Source : constant String :=
        "assert(loadfile('tests/lua/cli_message_handler_controls.lua'))('" &
        Name & "')";
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      if Memory then Conformance_Adapter.Install (Self.State.all); end if;
      Before := Conformance_Allocator.Measurements.Refusals;
      if Selected then
         Result := Self.Set_Arguments
           ([0 => To_Unbounded_String ("selected.lua")]);
         Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
         Result := CLI.Execute_Selected_Script (Self, Source, "@selected.lua");
      else
         Result := CLI.Execute (Self, Source, "@case.lua");
      end if;
      Conformance_Allocator.Clear_Count_Limit;
      if Exits then
         Assert (Result.Status = Exit_Requested and then
                 Result.Exit_Request.Code = 37 and then
                 Result.Exit_Request.Close_State = Exit_Close,
                 Name & ": lost typed handler exit");
      else
         Assert (Result.Status = Runtime_Error,
                 Name & ": wrong classification: " &
                 To_String (Result.Error.Message));
         if Exact then
            Assert (To_String (Result.Error.Message) = Expected,
                    Name & ": wrong raw message: " &
                    To_String (Result.Error.Message));
         else
            Assert (Index (Result.Error.Message, Expected) > 0,
                    Name & ": missing native message: " &
                    To_String (Result.Error.Message));
         end if;
         Assert ((Index (Result.Error.Message, "stack traceback:") > 0) =
                   Trace, Name & ": wrong traceback policy");
         if Memory then
            Assert (Conformance_Allocator.Measurements.Refusals > Before,
                    Name & ": selected provider never refused growth");
         end if;
      end if;
      Assert (To_String (Result.Output) = Expected_Output,
              Name & ": wrong callback output: " & To_String (Result.Output));
      if Name = "weak-error" then
         --  The original object is retained during handler GC, then released
         --  when failed frames retire. The final string is its replacement.
         Result := Self.Execute
           ("collectgarbage();assert(weak_error_watch[1]==nil)", "=weak");
         Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      end if;
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Check;

   procedure Before_Handler (Syntax, Length_Error : Boolean);
   procedure Before_Handler (Syntax, Length_Error : Boolean) is
      Self : Session;
      Result : Execution_Result;
      Setup : constant String :=
        "global *;local e=setmetatable({},{__tostring=function() " &
        "io.write('BAD_META');return 'BAD_MESSAGE' end});" &
        (if Length_Error then
           "arg=setmetatable({},{__len=function() error(e,0) end})"
         else "arg=nil;setmetatable(_G,{__index=function(_,k) " &
           "if k=='arg' then error(e,0) end end})");
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Result := Self.Execute (Setup, "=setup");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Result := CLI.Execute_Selected_Script
        (Self, (if Syntax then "local =" else "error('BAD_EXECUTION')"),
         "@selected.lua");
      Assert (Result.Output = "", "pre-docall error invoked __tostring");
      if Syntax then
         Assert (Result.Status = Syntax_Error and then
                 Index (Result.Error.Message, "<name> expected") > 0,
                 "compilation did not precede argument lookup");
      else
         Assert (Result.Status = Runtime_Error and then
                 Result.Error.Message = "(error message not a string)",
                 "pushargs error incorrectly acquired docall handler");
      end if;
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Before_Handler;

   procedure Compile_Before_Args;
   procedure Compile_Before_Args is
   begin
      Before_Handler (True, False);
   end Compile_Before_Args;

   procedure Arg_Lookup_Before_Handler;
   procedure Arg_Lookup_Before_Handler is
   begin
      Before_Handler (False, False);
   end Arg_Lookup_Before_Handler;

   procedure Arg_Length_Before_Handler;
   procedure Arg_Length_Before_Handler is
   begin
      Before_Handler (False, True);
   end Arg_Length_Before_Handler;

   procedure Display_Phases;
   procedure Display_Phases is
      Self : Session;
      Result : Execution_Result;
      Failed : Boolean;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Result := CLI.Execute_Display
        (Self, "return 1,nil,3", "=stdin", Failed);
      Assert (Result.Status = Succeeded and then not Failed and then
              Result.Output = "1" & ASCII.HT & "nil" & ASCII.HT & "3" &
                ASCII.LF, "docall lost actual REPL result arity/nil slots");
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Display_Phases;

   procedure Display_Error_Unhandled;
   procedure Display_Error_Unhandled is
      Self : Session;
      Result : Execution_Result;
      Failed : Boolean;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Result := Self.Execute
        ("global *;print=function() error(setmetatable({},{__tostring=" &
         "function() io.write('BAD_META');return 'BAD_MESSAGE' end}),0) end",
         "=setup");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Result := CLI.Execute_Display (Self, "return 1", "=stdin", Failed);
      Assert (Failed and then Result.Status = Runtime_Error and then
              Result.Error.Message = "(null)" and then
              Result.Output = "", "print incorrectly retained docall handler");
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Display_Error_Unhandled;

   procedure Host_Abort_Recovery;
   procedure Host_Abort_Recovery is
      Self : Session;
      Result : Execution_Result;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Self.Set_Limits ((Instructions => 2_000, others => <>));
      Result := CLI.Execute (Self, "while true do end", "=budget");
      Assert (Result.Status = Resource_Error and then
              Index (Result.Error.Message, "instruction limit") > 0 and then
              Index (Result.Error.Message, "stack traceback:") = 0,
              "host budget stop became a catchable handler error");
      Result := CLI.Execute (Self, "local x=1", "=retry");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Host_Abort_Recovery;

   procedure Cold_Refusal_Recovery;
   procedure Cold_Refusal_Recovery is
      Self : Session;
      Result : Execution_Result;
      Before : Lua.Storage.Byte_Count;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Before := Conformance_Allocator.Measurements.Refusals;
      Conformance_Allocator.Set_Count_Limit (0);
      Result := CLI.Execute (Self, "local x=1", "=refused");
      Conformance_Allocator.Clear_Count_Limit;
      Assert (Conformance_Allocator.Measurements.Refusals > Before,
              "cold CLI fixture did not refuse actual provider growth");
      Assert (Result.Status = Runtime_Error and then
              Result.Error.Message = "not enough memory",
              "cold compilation refusal acquired handler traceback");
      Result := CLI.Execute (Self, "local x=1", "=retry");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Cold_Refusal_Recovery;

   procedure Generic_Embedding_Unchanged;
   procedure Generic_Embedding_Unchanged is
      Self : Session;
      Result : Execution_Result;
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      Result := Self.Execute
        ("error(setmetatable({},{__tostring=function() " &
         "io.write('BAD_META');return 'BAD_MESSAGE' end}),0)", "=embedding");
      Assert (Result.Status = Runtime_Error and then Result.Output = "" and
                then Index (Result.Error.Message, "stack traceback:") = 0,
              "CLI policy leaked into generic session execution");
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Generic_Embedding_Unchanged;

   procedure String_Trace;
   procedure String_Trace is
   begin
      Check
        ("string",
         "E_STRING",
         True);
   end String_Trace;

   procedure Primitive_Table;
   procedure Primitive_Table is
   begin
      Check
        ("table",
         "(error object is a table value)",
         True);
   end Primitive_Table;

   procedure Ignore_Name;
   procedure Ignore_Name is
   begin
      Check
        ("table-name",
         "(error object is a table value)",
         True);
   end Ignore_Name;

   procedure String_Metamethod;
   procedure String_Metamethod is
   begin
      Check
        ("tostring-string",
         "MM_STRING",
         False,
         Exact => True,
         Expected_Output => "MM_ENTER" & ASCII.LF);
   end String_Metamethod;

   procedure Number_Metamethod;
   procedure Number_Metamethod is
   begin
      Check
        ("tostring-number",
         "(error object is a table value)",
         True,
         Expected_Output => "MM_ENTER" & ASCII.LF);
   end Number_Metamethod;

   procedure Nil_Metamethod;
   procedure Nil_Metamethod is
   begin
      Check
        ("tostring-nil",
         "(error object is a table value)",
         True,
         Expected_Output => "MM_ENTER" & ASCII.LF);
   end Nil_Metamethod;

   procedure Throwing_Metamethod;
   procedure Throwing_Metamethod is
   begin
      Check
        ("tostring-throws",
         "MM_THROW",
         True,
         Expected_Output => "MM_ENTER" & ASCII.LF);
   end Throwing_Metamethod;

   procedure Nul_Message;
   procedure Nul_Message is
   begin
      Check
        ("tostring-nul",
         "MM",
         False,
         Exact => True);
   end Nul_Message;

   procedure Numeric_Error;
   procedure Numeric_Error is
   begin
      Check
        ("numeric",
         "37",
         True);
   end Numeric_Error;

   procedure Ignore_Numeric_Meta;
   procedure Ignore_Numeric_Meta is
   begin
      Check
        ("numeric-meta",
         "37",
         True);
   end Ignore_Numeric_Meta;

   procedure Callable_Metamethod;
   procedure Callable_Metamethod is
   begin
      Check
        ("callable-meta",
         "MM_CALLABLE",
         False,
         Exact => True);
   end Callable_Metamethod;

   procedure Raw_Metafield;
   procedure Raw_Metafield is
   begin
      Check
        ("raw-meta",
         "(error object is a table value)",
         True);
   end Raw_Metafield;

   procedure Mutable_Error_Slot;
   procedure Mutable_Error_Slot is
   begin
      Check
        ("mutate-parent",
         "(error object is a number value)",
         True);
   end Mutable_Error_Slot;

   procedure Actual_Handler_Frames;
   procedure Actual_Handler_Frames is
   begin
      Check
        ("frames",
         "FRAME_MESSAGE",
         False,
         Exact => True,
         Expected_Output => "FRAME_CONTROLS" & ASCII.LF);
   end Actual_Handler_Frames;

   procedure Original_Error_Root;
   procedure Original_Error_Root is
   begin
      Check
        ("weak-error",
         "WEAK_MESSAGE",
         False,
         Exact => True);
   end Original_Error_Root;

   procedure Handler_Yield;
   procedure Handler_Yield is
   begin
      Check
        ("handler-yield",
         "attempt to yield",
         True);
   end Handler_Yield;

   procedure Close_After_Handler;
   procedure Close_After_Handler is
   begin
      Check
        ("closer-error",
         "CLOSE_MESSAGE",
         False,
         Exact => True,
         Expected_Output => "CLOSED_AFTER_HANDLER" & ASCII.LF);
   end Close_After_Handler;

   procedure Selected_Script_Handler;
   procedure Selected_Script_Handler is
   begin
      Check
        ("tostring-string",
         "MM_STRING",
         False,
         Exact => True,
         Expected_Output => "MM_ENTER" & ASCII.LF,
         Selected => True);
   end Selected_Script_Handler;

   procedure Memory_Skips_Handler;
   procedure Memory_Skips_Handler is
   begin
      Check
        ("memory",
         "not enough memory",
         False,
         Exact => True,
         Expected_Output => "ARMED" & ASCII.LF,
         Memory => True);
   end Memory_Skips_Handler;

   procedure Entered_Handler_Refusal;
   procedure Entered_Handler_Refusal is
   begin
      Check
        ("entered-handler-memory",
         "not enough memory",
         False,
         Exact => True,
         Expected_Output => "HANDLER_ARMED" & ASCII.LF,
         Memory => True);
   end Entered_Handler_Refusal;

   procedure Exit_Without_Close;
   procedure Exit_Without_Close is
   begin
      Check
        ("exit-no-close",
         "",
         False,
         Expected_Output => "EXIT_HANDLER" & ASCII.LF,
         Exits => True);
   end Exit_Without_Close;

   procedure Exit_With_Close;
   procedure Exit_With_Close is
   begin
      Check
        ("exit-close",
         "",
         False,
         Expected_Output => "EXIT_HANDLER" & ASCII.LF,
         Exits => True,
         Exit_Close => True);
   end Exit_With_Close;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "CLI message: string trace",
         String_Trace'Access);
      Test_Support.Add
        (Suite, "CLI message: primitive table",
         Primitive_Table'Access);
      Test_Support.Add
        (Suite, "CLI message: ignore name",
         Ignore_Name'Access);
      Test_Support.Add
        (Suite, "CLI message: string metamethod",
         String_Metamethod'Access);
      Test_Support.Add
        (Suite, "CLI message: number metamethod",
         Number_Metamethod'Access);
      Test_Support.Add
        (Suite, "CLI message: nil metamethod",
         Nil_Metamethod'Access);
      Test_Support.Add
        (Suite, "CLI message: throwing metamethod",
         Throwing_Metamethod'Access);
      Test_Support.Add
        (Suite, "CLI message: nul message",
         Nul_Message'Access);
      Test_Support.Add
        (Suite, "CLI message: numeric error",
         Numeric_Error'Access);
      Test_Support.Add
        (Suite, "CLI message: ignore numeric meta",
         Ignore_Numeric_Meta'Access);
      Test_Support.Add
        (Suite, "CLI message: callable metamethod",
         Callable_Metamethod'Access);
      Test_Support.Add
        (Suite, "CLI message: raw metafield",
         Raw_Metafield'Access);
      Test_Support.Add
        (Suite, "CLI message: mutable error slot",
         Mutable_Error_Slot'Access);
      Test_Support.Add
        (Suite, "CLI message: actual handler frames",
         Actual_Handler_Frames'Access);
      Test_Support.Add
        (Suite, "CLI message: original error root",
         Original_Error_Root'Access);
      Test_Support.Add
        (Suite, "CLI message: handler yield",
         Handler_Yield'Access);
      Test_Support.Add
        (Suite, "CLI message: close after handler",
         Close_After_Handler'Access);
      Test_Support.Add
        (Suite, "CLI message: selected script handler",
         Selected_Script_Handler'Access);
      Test_Support.Add
        (Suite, "CLI message: memory skips handler",
         Memory_Skips_Handler'Access);
      Test_Support.Add
        (Suite, "CLI message: entered handler refusal",
         Entered_Handler_Refusal'Access);
      Test_Support.Add
        (Suite, "CLI message: exit without close",
         Exit_Without_Close'Access);
      Test_Support.Add
        (Suite, "CLI message: exit with close",
         Exit_With_Close'Access);
      Test_Support.Add
        (Suite, "CLI message: compile before args",
         Compile_Before_Args'Access);
      Test_Support.Add
        (Suite, "CLI message: arg lookup before handler",
         Arg_Lookup_Before_Handler'Access);
      Test_Support.Add
        (Suite, "CLI message: arg length before handler",
         Arg_Length_Before_Handler'Access);
      Test_Support.Add
        (Suite, "CLI message: display phases",
         Display_Phases'Access);
      Test_Support.Add
        (Suite, "CLI message: display error unhandled",
         Display_Error_Unhandled'Access);
      Test_Support.Add
        (Suite, "CLI message: host abort recovery",
         Host_Abort_Recovery'Access);
      Test_Support.Add
        (Suite, "CLI message: cold refusal recovery",
         Cold_Refusal_Recovery'Access);
      Test_Support.Add
        (Suite, "CLI message: generic embedding unchanged",
         Generic_Embedding_Unchanged'Access);
   end Register;
end Lua.Sessions.CLI_Message_Tests;
