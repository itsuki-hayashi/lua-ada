with AUnit.Assertions; use AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces.C;
with Lua.Conformance_Adapter;
with Lua.Conformance_Allocator;
with Lua.Sessions.CLI;
with Lua.Storage;
with Test_Support;

package body Lua.Sessions.CLI_Argument_Tests is
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
              "CLI argument operation retained provider storage");
   end Close_Checked;

   procedure Check
     (Name : String; Error : String := ""; Syntax : Boolean := False;
      Exit_Close : Boolean := False; Fault : Boolean := False);
   procedure Check
     (Name : String; Error : String := ""; Syntax : Boolean := False;
      Exit_Close : Boolean := False; Fault : Boolean := False)
   is
      Self : Session;
      Result : Execution_Result;
      Script : constant String :=
        (if Syntax then "local =" else
           (if Name = "refused-script-entry" then "T.alloccount();" else "") &
         "local v=table.pack(...);check_dynamic_arg(v);" &
         "io.write('PASS: cli-dynamic-arg-',case_name,'\n')");
   begin
      Conformance_Allocator.Attach (Lua.Storage.Reference (Self.State.Memory));
      if Fault then Conformance_Adapter.Install (Self.State.all); end if;
      Result := Self.Set_Arguments
        ([0 => To_Unbounded_String ("selected script.lua"),
          1 => To_Unbounded_String ("a"), 2 => To_Unbounded_String ("b"),
          3 => To_Unbounded_String ("c")]);
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Result := Self.Execute
        ("assert(loadfile('tests/lua/cli_argument_controls.lua'))('" &
         Name & "')", "=arg-setup");
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      --  Setup has returned before the selected script compiles. Real C
      --  primitive callbacks query arg/length, and the script gets actual
      --  values before its separately authored Lua checker runs.
      Result := CLI.Execute_Selected_Script
        (Self, Script, "@selected script.lua");
      if Exit_Close then
         Assert (Result.Status = Exit_Requested and then
                 Result.Exit_Request.Code = 37 and then
                 Result.Exit_Request.Close_State,
                 Name & ": wrong typed exit");
      elsif Syntax then
         Assert (Result.Status = Syntax_Error,
                 Name & ": " & To_String (Result.Error.Message));
      elsif Error'Length > 0 then
         Assert (Result.Status = Runtime_Error and then
                 Ada.Strings.Unbounded.Index (Result.Error.Message, Error) > 0,
                 Name & ": " & To_String (Result.Error.Message));
      else
         Assert (Result.Status = Succeeded,
                 Name & ": " & To_String (Result.Error.Message));
         Assert (Ada.Strings.Unbounded.Index
                   (Result.Output, "PASS: cli-dynamic-arg-" & Name) > 0,
                 Name & ": missing actual selected-script marker");
      end if;
      Close_Checked (Self);
   exception
      when others => Close_Checked (Self); raise;
   end Check;

   procedure Unchanged_Strings;
   procedure Unchanged_Strings is
   begin
      Check
        ("unchanged-strings");
   end Unchanged_Strings;

   procedure Numeric_Slot;
   procedure Numeric_Slot is
   begin
      Check
        ("numeric-slot");
   end Numeric_Slot;

   procedure Boolean_Slot;
   procedure Boolean_Slot is
   begin
      Check
        ("boolean-slot");
   end Boolean_Slot;

   procedure Replace_Table;
   procedure Replace_Table is
   begin
      Check
        ("replace-table");
   end Replace_Table;

   procedure Replace_Empty;
   procedure Replace_Empty is
   begin
      Check
        ("replace-empty");
   end Replace_Empty;

   procedure Mixed_Object_Identity;
   procedure Mixed_Object_Identity is
   begin
      Check
        ("mixed-object-identity");
   end Mixed_Object_Identity;

   procedure Metalen_Holes;
   procedure Metalen_Holes is
   begin
      Check
        ("metalen-holes");
   end Metalen_Holes;

   procedure Raw_Indexing;
   procedure Raw_Indexing is
   begin
      Check
        ("raw-indexing");
   end Raw_Indexing;

   procedure Metalen_Number_String;
   procedure Metalen_Number_String is
   begin
      Check
        ("metalen-number-string");
   end Metalen_Number_String;

   procedure Metalen_Float_Integer;
   procedure Metalen_Float_Integer is
   begin
      Check
        ("metalen-float-integer");
   end Metalen_Float_Integer;

   procedure Metalen_Mutates_Values;
   procedure Metalen_Mutates_Values is
   begin
      Check
        ("metalen-mutates-values");
   end Metalen_Mutates_Values;

   procedure Metalen_Replaces_Global_Gc;
   procedure Metalen_Replaces_Global_Gc is
   begin
      Check
        ("metalen-replaces-global-gc");
   end Metalen_Replaces_Global_Gc;

   procedure Global_Handler;
   procedure Global_Handler is
   begin
      Check
        ("global-handler");
   end Global_Handler;

   procedure Non_Table_Number;
   procedure Non_Table_Number is
   begin
      Check
        ("non-table-number",
         Error => "'arg' is not a table");
   end Non_Table_Number;

   procedure Non_Table_Nil;
   procedure Non_Table_Nil is
   begin
      Check
        ("non-table-nil",
         Error => "'arg' is not a table");
   end Non_Table_Nil;

   procedure Metalen_Fraction;
   procedure Metalen_Fraction is
   begin
      Check
        ("metalen-fraction",
         Error => "object length is not an integer");
   end Metalen_Fraction;

   procedure Metalen_Table_Result;
   procedure Metalen_Table_Result is
   begin
      Check
        ("metalen-table-result",
         Error => "object length is not an integer");
   end Metalen_Table_Result;

   procedure Metalen_Error;
   procedure Metalen_Error is
   begin
      Check
        ("metalen-error",
         Error => "ARG LENGTH FAILURE");
   end Metalen_Error;

   procedure Metalen_Yield;
   procedure Metalen_Yield is
   begin
      Check
        ("metalen-yield",
         Error => "attempt to yield from outside a coroutine");
   end Metalen_Yield;

   procedure Arg_Zero_Does_Not_Retarget;
   procedure Arg_Zero_Does_Not_Retarget is
   begin
      Check
        ("arg-zero-does-not-retarget");
   end Arg_Zero_Does_Not_Retarget;

   procedure Negative_Index_Does_Not_Retarget;
   procedure Negative_Index_Does_Not_Retarget is
   begin
      Check
        ("negative-index-does-not-retarget");
   end Negative_Index_Does_Not_Retarget;

   procedure Length_Real_C_Frame;
   procedure Length_Real_C_Frame is
   begin
      Check
        ("length-real-c-frame");
   end Length_Real_C_Frame;

   procedure Global_Real_C_Frame;
   procedure Global_Real_C_Frame is
   begin
      Check
        ("global-real-c-frame");
   end Global_Real_C_Frame;

   procedure Syntax_Before_Length;
   procedure Syntax_Before_Length is
   begin
      Check
        ("syntax-before-length",
         Error => "expected",
         Syntax => True);
   end Syntax_Before_Length;

   procedure Loaded_Initial_Environment;
   procedure Loaded_Initial_Environment is
   begin
      Check
        ("loaded-initial-environment");
   end Loaded_Initial_Environment;

   procedure Length_Exit_Close;
   procedure Length_Exit_Close is
   begin
      Check
        ("length-exit-close",
         Exit_Close => True);
   end Length_Exit_Close;

   procedure Length_Refusal_Recovery;
   procedure Length_Refusal_Recovery is
   begin
      Check
        ("length-refusal-recovery",
         Fault => True);
   end Length_Refusal_Recovery;

   procedure Refused_Script_Entry;
   procedure Refused_Script_Entry is
   begin
      Check
        ("refused-script-entry",
         Fault => True);
   end Refused_Script_Entry;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "CLI arguments: unchanged-strings",
         Unchanged_Strings'Access);
      Test_Support.Add
        (Suite, "CLI arguments: numeric-slot",
         Numeric_Slot'Access);
      Test_Support.Add
        (Suite, "CLI arguments: boolean-slot",
         Boolean_Slot'Access);
      Test_Support.Add
        (Suite, "CLI arguments: replace-table",
         Replace_Table'Access);
      Test_Support.Add
        (Suite, "CLI arguments: replace-empty",
         Replace_Empty'Access);
      Test_Support.Add
        (Suite, "CLI arguments: mixed-object-identity",
         Mixed_Object_Identity'Access);
      Test_Support.Add
        (Suite, "CLI arguments: metalen-holes",
         Metalen_Holes'Access);
      Test_Support.Add
        (Suite, "CLI arguments: raw-indexing",
         Raw_Indexing'Access);
      Test_Support.Add
        (Suite, "CLI arguments: metalen-number-string",
         Metalen_Number_String'Access);
      Test_Support.Add
        (Suite, "CLI arguments: metalen-float-integer",
         Metalen_Float_Integer'Access);
      Test_Support.Add
        (Suite, "CLI arguments: metalen-mutates-values",
         Metalen_Mutates_Values'Access);
      Test_Support.Add
        (Suite, "CLI arguments: metalen-replaces-global-gc",
         Metalen_Replaces_Global_Gc'Access);
      Test_Support.Add
        (Suite, "CLI arguments: global-handler",
         Global_Handler'Access);
      Test_Support.Add
        (Suite, "CLI arguments: non-table-number",
         Non_Table_Number'Access);
      Test_Support.Add
        (Suite, "CLI arguments: non-table-nil",
         Non_Table_Nil'Access);
      Test_Support.Add
        (Suite, "CLI arguments: metalen-fraction",
         Metalen_Fraction'Access);
      Test_Support.Add
        (Suite, "CLI arguments: metalen-table-result",
         Metalen_Table_Result'Access);
      Test_Support.Add
        (Suite, "CLI arguments: metalen-error",
         Metalen_Error'Access);
      Test_Support.Add
        (Suite, "CLI arguments: metalen-yield",
         Metalen_Yield'Access);
      Test_Support.Add
        (Suite, "CLI arguments: arg-zero-does-not-retarget",
         Arg_Zero_Does_Not_Retarget'Access);
      Test_Support.Add
        (Suite, "CLI arguments: negative-index-does-not-retarget",
         Negative_Index_Does_Not_Retarget'Access);
      Test_Support.Add
        (Suite, "CLI arguments: length-real-c-frame",
         Length_Real_C_Frame'Access);
      Test_Support.Add
        (Suite, "CLI arguments: global-real-c-frame",
         Global_Real_C_Frame'Access);
      Test_Support.Add
        (Suite, "CLI arguments: syntax-before-length",
         Syntax_Before_Length'Access);
      Test_Support.Add
        (Suite, "CLI arguments: loaded-initial-environment",
         Loaded_Initial_Environment'Access);
      Test_Support.Add
        (Suite, "CLI arguments: length-exit-close",
         Length_Exit_Close'Access);
      Test_Support.Add
        (Suite, "CLI arguments: length-refusal-recovery",
         Length_Refusal_Recovery'Access);
      Test_Support.Add
        (Suite, "CLI arguments: refused-script-entry",
         Refused_Script_Entry'Access);
   end Register;
end Lua.Sessions.CLI_Argument_Tests;
