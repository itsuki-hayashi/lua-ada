with Ada.Containers;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces.C;
with Lua.Diagnostic_Text;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Compiler;
with Lua.Engine.External_Releases;
with Lua.Engine.Foreign;
with Lua.Engine.Machine;
with Lua.Engine.Warnings;
with Lua.Runtime_Configuration;
with Lua.Storage;
with Lua.Storage.Buffers;
with System;

package body Lua.Sessions.CLI is
   use type Ada.Containers.Count_Type;
   use type Integer_Value;
   use type Interfaces.C.int;
   use type System.Address;

   function Primary (Pointer : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_cli_primary_prompt";
   function Secondary (Pointer : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_cli_secondary_prompt";
   function String_Prompt (Pointer : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_cli_string_prompt";

   function Argument_Table (Pointer : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_cli_argument_table";
   function Argument_Length (Pointer : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_cli_argument_length";

   function Init_Readline (Pointer : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_cli_initreadline";
   function Native_Readline (Prompt : System.Address) return System.Address
     with Import, Convention => C,
          External_Name => "lua_ada_cli_readline";
   function Line_Length (Line : System.Address) return Interfaces.C.size_t
     with Import, Convention => C,
          External_Name => "lua_ada_cli_line_length";
   procedure Free_Line (Line : System.Address)
     with Import, Convention => C,
          External_Name => "lua_ada_cli_freeline";
   procedure Save_Line (Line : System.Address)
     with Import, Convention => C,
          External_Name => "lua_ada_cli_saveline";
   function Has_History return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_cli_has_history";

   type Prompt_Operation_Kind is (Write_Only, Read_Input, Initialize_Input);
   function Prompt_Operation
     (Self : in out Session; First_Line : Boolean;
      Operation : Prompt_Operation_Kind;
      Line : out Unbounded_String; Available : out Boolean)
      return Execution_Result;

   function Prompt_Operation
     (Self : in out Session; First_Line : Boolean;
      Operation : Prompt_Operation_Kind;
      Line : out Unbounded_String; Available : out Boolean)
      return Execution_Result
   is
      Result : Execution_Result;

      function Prompt_Failure return Execution_Result;
      function Prompt_Failure return Execution_Result is
         Failed : Execution_Result := Failure (Self, "");
      begin
         --  lua.c's enclosing report converts strings/numbers but does not
         --  invoke __tostring on a nonstring error object. Keep that original
         --  engine object untouched: only this CLI operation's displayed
         --  result uses the native fallback and C-string-prefix convention.
         --  Host abort and memory classification retain normal publication.
         if Self.State.Current.Failure_Class = Language_Failure then
            if Self.State.Current.Has_Failure_Value and then
              Self.State.Current.Failure.Kind not in
                String_Kind | Integer_Kind | Real_Kind
            then
               Failed.Error.Message := To_Unbounded_String
                 ("(error message not a string)");
            else
               Failed.Error.Message := To_Unbounded_String
                 (C_Option (To_String (Failed.Error.Message)));
            end if;
         end if;
         return Failed;
      end Prompt_Failure;

      procedure Recover;
      procedure Recover is
         State : World renames Self.State.all;
      begin
         --  Each local drive cancels its borrow before reaching this cleanup.
         --  No C body remains live here. Preserve the typed failure while
         --  retiring failed phases and their actual scalar/cell owners; do
         --  not run another Lua callback or force a new collection on failure.
         State.Entry_Code := null;
         State.Current.Arguments.Clear;
         Machine.Clear_Frames (State);
         State.Current.Status := Suspended_Context;
      end Recover;
   begin
      Line := Null_Unbounded_String;
      Available := False;
      if Self.State = null then
         return Failure (Self, "");
      end if;
      declare
         State : World renames Self.State.all;

         procedure Drive (Function_Address : System.Address);
         procedure Drive (Function_Address : System.Address) is
            Driver : Machine.Driver;
            Callee : constant Value :=
              (Foreign_Function_Kind, Function_Address);
         begin
            --  An actual C host activation, not a saved public tostring or
            --  Lua shim, owns each lookup/conversion. All Lua/metamethod calls
            --  still execute in the one existing explicit driver. Its C guard
            --  is installed only after Step returns, above every waiting Ada
            --  helper. Warning/release callbacks use the ordinary same pump.
            Machine.Start (Driver, Self.State, Callee,
                           State.Current.Arguments);
            while not Machine.Is_Complete (Driver) or else
              External_Releases.Pending (State)
            loop
               if Machine.Needs_Foreign_Call (Driver) or else
                 Warnings.Pending (State) or else
                 External_Releases.Pending (State)
               then
                  Foreign.Invoke_Borrowed (State, Driver);
               else
                  Machine.Step (Driver);
               end if;
            end loop;
            if State.Exit_Phase /= Exit_Complete then
               if Machine.Outcome (Driver) /= Completed then
                  raise Language_Error;
               end if;
               --  Transfer the completed packet before Finish drops its
               --  result root. The preceding prompt argument remains rooted
               --  until conversion completes; the string then replaces it.
               State.Current.Arguments.Clear;
               Machine.Take_Results (Driver, State.Current.Arguments);
            end if;
            Machine.Finish (Driver);
         exception
            when others =>
               Machine.Cancel (Driver);
               raise;
         end Drive;

         procedure Emit (Bytes : String; Pointer : System.Address);
         procedure Emit (Bytes : String; Pointer : System.Address) is
            Last : Natural := Bytes'Last;
         begin
            --  Lua stores all bytes, while native readline/fputs consumes
            --  their C-string prefix. Charge the actual scan and retain the
            --  original Lua string through both output and flush. No callback
            --  or source execution occurs while this byte view is borrowed.
            for Index in Bytes'Range loop
               if State.Policy = Bounded then
                  if State.Steps >= State.Bounds.Instructions then
                     Fail (State, "instruction limit exceeded", True);
                  end if;
                  State.Steps := State.Steps + 1;
               end if;
               if Bytes (Index) = ASCII.NUL then
                  Last := Index - 1;
                  exit;
               end if;
            end loop;
            if Operation = Read_Input then
               declare
                  Input : constant System.Address := Native_Readline
                    (Pointer);
               begin
                  if Input /= System.Null_Address then
                     begin
                        declare
                           Size : constant Natural :=
                             Natural (Line_Length (Input));
                           Text : String (1 .. Size)
                             with Import, Address => Input;
                        begin
                           --  Native pushline removes one final LF after
                           --  strlen, so embedded NUL truncation takes place
                           --  before that decision. Keep CR/high bytes.
                           if Size > 0 and then Text (Size) = ASCII.LF then
                              Line := To_Unbounded_String
                                (Text (1 .. Size - 1));
                           else
                              Line := To_Unbounded_String (Text);
                           end if;
                           Available := True;
                        end;
                     exception
                        when others => Free_Line (Input); raise;
                     end;
                     Free_Line (Input);
                  end if;
               end;
            else
               Emit_Output (State, Bytes (Bytes'First .. Last));
               Flush_Output (State);
            end if;
         end Emit;
      begin
         --  This host operation has one policy epoch across lookup,
         --  conversion and output. It creates no new world, parser or budget
         --  for a nested callback, and does not force collection between
         --  prompt evaluation and the next input line.
         State.Current.Arguments.Clear;
         State.Current.Status := Running_Context;
         State.Current.Failure := Nil_Value;
         State.Current.Has_Failure_Value := False;
         State.Current.Failure_Class := No_Failure;
         State.Current.Failure_Handled := False;
         State.Current.Protected_Failure_Class := No_Failure;
         State.Current.Protected_Handler_Called := False;
         State.Current.Failure_At := (others => 1);
         Lua.Diagnostic_Text.Clear (State.Current.Failure_Text);
         State.Output := Null_Unbounded_String;
         State.Output_Used := 0;
         State.Steps := 0;

         if Operation = Initialize_Input then
            --  This operation's flag is Ignore_Environment, rather than the
            --  primary/secondary selector used by the two prompt operations.
            Append_Root (State, State.Current.Arguments,
                         (Boolean_Kind, First_Line));
            Drive (Init_Readline'Address);
         else
            Drive (if First_Line then Primary'Address else Secondary'Address);
         end if;
         if State.Exit_Phase = Exit_Complete then
            Result.Output := State.Output;
            Apply_Exit (Self, Result);
            return Result;
         end if;
         if Operation = Initialize_Input then
            State.Current.Status := Suspended_Context;
            Result.Output := State.Output;
            return Result;
         elsif State.Current.Arguments.Length /= 1 then
            raise Program_Error with "invalid prompt lookup result";
         end if;
         if State.Current.Arguments.First_Element.Kind = Nil_Kind then
            declare
               Default : aliased constant String :=
                 (if First_Line then "> " else ">> ") & ASCII.NUL;
            begin
               Emit (Default (1 .. Default'Last - 1), Default'Address);
            end;
         else
            Drive (String_Prompt'Address);
            if State.Exit_Phase = Exit_Complete then
               Result.Output := State.Output;
               Apply_Exit (Self, Result);
               return Result;
            end if;
            declare
               Item : constant Value :=
                 State.Current.Arguments.First_Element;
            begin
               if State.Current.Arguments.Length /= 1 or else
                 Item.Kind /= String_Kind
               then
                  raise Program_Error with "invalid prompt conversion";
               end if;
               --  Copy only the scalar discriminated value, never hold a
               --  vector element borrow while output can report a failure.
               declare
                  Bytes : constant Byte_String := Item.Reference.Bytes;
                  View : String (1 .. Bytes.Size)
                    with Import, Address => Bytes.Address;
               begin
                  Emit (View, Item.Reference.C_Bytes);
               end;
            end;
         end if;
         State.Current.Arguments.Clear;
         State.Current.Status := Suspended_Context;
         Result.Output := State.Output;
         return Result;
      end;
   exception
      when Language_Error =>
         Recover;
         return Prompt_Failure;
      when Lua.Storage.Allocation_Error =>
         Record_Memory_Error (Self.State.all);
         Recover;
         return Failure (Self, "");
      when Storage_Error =>
         Recover;
         Self.State.Current.Failure_Class := Host_Abort;
         Result.Status := Resource_Error;
         Result.Error.Message := To_Unbounded_String
           ("host storage exhausted");
         return Result;
      when Error : Constraint_Error | Program_Error =>
         if Lua.Storage.Refusal_Pending (Self.State.Memory) then
            Record_Memory_Error (Self.State.all);
         else
            Set_Failure_Text
              (Self.State.all, Self.State.Current, "internal Ada check: " &
               Ada.Exceptions.Exception_Message (Error));
         end if;
         Recover;
         return Failure (Self, "");
   end Prompt_Operation;

   function Write_Prompt
     (Self : in out Session; First_Line : Boolean) return Execution_Result
   is
      Line : Unbounded_String;
      Available : Boolean;
   begin
      return Prompt_Operation
        (Self, First_Line, Write_Only, Line, Available);
   end Write_Prompt;

   function Initialize_Readline
     (Self : in out Session; Ignore_Environment : Boolean)
      return Execution_Result
   is
      Line : Unbounded_String;
      Available : Boolean;
   begin
      return Prompt_Operation
        (Self, Ignore_Environment, Initialize_Input, Line, Available);
   end Initialize_Readline;

   function Read_REPL_Line
     (Self : in out Session; First_Line : Boolean;
      Line : out Unbounded_String; Available : out Boolean)
      return Execution_Result is
   begin
      return Prompt_Operation
        (Self, First_Line, Read_Input, Line, Available);
   end Read_REPL_Line;

   function Save_REPL_Line
     (Self : in out Session; Line : String) return Execution_Result
   is
      Buffer : Lua.Storage.Buffers.Buffer;
      Result : Execution_Result;
   begin
      if Self.State = null then return Failure (Self, ""); end if;
      if Has_History = 0 or else Line'Length = 0 or else
        Line (Line'First) = ASCII.NUL
      then
         return Result;
      end if;
      Buffer.Set_Owner (Lua.Storage.Reference (Self.State.Memory));
      Buffer.Append (Line);
      Save_Line (Buffer.C_Address);
      return Result;
   exception
      when Lua.Storage.Allocation_Error =>
         Record_Memory_Error (Self.State.all);
         return Failure (Self, "");
      when Storage_Error =>
         Self.State.Current.Failure_Class := Host_Abort;
         Result.Status := Resource_Error;
         Result.Error.Message := To_Unbounded_String
           ("host storage exhausted");
         return Result;
   end Save_REPL_Line;

   function Execute_Selected_Script
     (Self : in out Session; Source, Name : String) return Execution_Result
   is
      Result : Execution_Result;

      procedure Recover;
      procedure Recover is
         State : World renames Self.State.all;
      begin
         --  Every local driver cancels before reaching this host cleanup.
         --  End temporary compilation pins only after the real packet has
         --  retained the callable/arguments through any failed publication.
         End_Operation (State);
         State.Entry_Code := null;
         Machine.Clear_Frames (State);
         State.Current.Arguments.Clear;
         State.Current.Status := Suspended_Context;
      end Recover;

      procedure Execute_Body;
      procedure Execute_Body is
         State : World renames Self.State.all;
         Arguments : Values.Vector := Owned_Values (State);
         Code : Prototype_Access;
         Callee, Table, Length_Value : Value;
         Count : Natural;

         procedure Charge (Work : Natural);
         procedure Charge (Work : Natural) is
         begin
            if State.Policy = Bounded then
               if Work > State.Bounds.Instructions - Natural'Min
                 (State.Steps, State.Bounds.Instructions)
               then
                  Fail (State, "instruction limit exceeded", Resource => True);
               end if;
               State.Steps := State.Steps + Work;
            end if;
         end Charge;

         procedure Pump (Driver : in out Machine.Driver);
         procedure Pump (Driver : in out Machine.Driver) is
         begin
            while not Machine.Is_Complete (Driver) or else
              External_Releases.Pending (State)
            loop
               if Machine.Needs_Foreign_Call (Driver) or else
                 Warnings.Pending (State) or else
                 External_Releases.Pending (State)
               then
                  Foreign.Invoke_Borrowed (State, Driver);
               else
                  Machine.Step (Driver);
               end if;
            end loop;
            if State.Exit_Phase /= Exit_Complete and then
              Machine.Outcome (Driver) /= Completed
            then
               raise Language_Error;
            end if;
         end Pump;

         procedure Query (Address : System.Address);
         procedure Query (Address : System.Address) is
            Driver : Machine.Driver;
         begin
            --  Each tiny callback returns the callable prefix as well as its
            --  primitive result. The existing result transfer preserves our
            --  prepared arena and keeps the source packet rooted until its
            --  allocation-free copy publishes the replacement prefix.
            Machine.Start
              (Driver, Self.State, (Foreign_Function_Kind, Address),
               State.Current.Arguments);
            Pump (Driver);
            if State.Exit_Phase /= Exit_Complete then
               Machine.Take_Results (Driver, State.Current.Arguments);
            end if;
            Machine.Finish (Driver);
         exception
            when others => Machine.Cancel (Driver); raise;
         end Query;
      begin
         State.Current.Arguments.Clear;
         State.Current.Status := Running_Context;
         State.Current.Failure := Nil_Value;
         State.Current.Has_Failure_Value := False;
         State.Current.Failure_Class := No_Failure;
         State.Current.Failure_Handled := False;
         State.Current.Protected_Failure_Class := No_Failure;
         State.Current.Protected_Handler_Called := False;
         State.Current.Failure_At := (others => 1);
         Lua.Diagnostic_Text.Clear (State.Current.Failure_Text);
         State.Output := Null_Unbounded_String;
         State.Output_Used := 0;
         State.Steps := 0;
         if Source'Length > State.Bounds.Source_Bytes then
            Fail (State, "source byte limit exceeded", Resource => True);
         end if;

         --  Reserve real public C-call headroom before a user handler can
         --  disable allocation. A later larger count remains an ordinary
         --  transactional reservation. These are two selected-owner arenas,
         --  not another context root or an uncharged input-sized C array.
         State.Current.Arguments.Reserve_Capacity (Minimum_C_Stack + 3);
         Arguments.Reserve_Capacity (Minimum_C_Stack);
         Begin_Operation (State);
         Code := Compiler.Compile (State, Source, Name);
         State.Entry_Code := Code;
         Callee := New_Closure (State, Code, null);
         Append_Root (State, State.Current.Arguments, Callee);
         End_Operation (State);

         --  Loading precedes pushargs in lua.c. The actual closure already
         --  captures its initial _ENV before either handler can replace the
         --  registry globals. C carries it as a genuine first parameter.
         Query (Argument_Table'Address);
         if State.Exit_Phase = Exit_Complete then return; end if;
         if State.Current.Arguments.Length /= 2 then
            raise Program_Error with "invalid CLI argument lookup packet";
         end if;
         if State.Current.Arguments.Element (2).Kind /= Table_Kind then
            Fail (State, "'arg' is not a table");
         end if;
         Query (Argument_Length'Address);
         if State.Exit_Phase = Exit_Complete then return; end if;
         if State.Current.Arguments.Length /= 3 then
            raise Program_Error with "invalid CLI argument length packet";
         end if;
         Table := State.Current.Arguments.Element (2);
         Length_Value := State.Current.Arguments.Element (3);
         if Length_Value.Kind /= Integer_Kind then
            raise Program_Error with "noninteger CLI argument length packet";
         end if;
         --  Undefined negative/overflowing C-int counts are not translated
         --  into unchecked Ada arithmetic. Valid positive counts retain the
         --  semantic stack admission bound before requesting storage.
         if Length_Value.Integer_Data < 0 or else
           Length_Value.Integer_Data > Integer_Value
             (Lua.Runtime_Configuration.Maximum_Stack - 3)
         then
            Fail (State, "too many arguments to script");
         end if;
         Count := Natural (Length_Value.Integer_Data);
         Charge (3 * Count + 3);
         State.Current.Arguments.Reserve_Capacity
           (Ada.Containers.Count_Type (Count + 3));
         --  Raw reads have no callback/safe point after this reservation.
         --  Publish each value in the actual traced packet, including nil;
         --  a weak/mutated original table alone is not a strong value owner.
         for Index in 1 .. Count loop
            Append_Root
              (State, State.Current.Arguments,
               Get (Table, (Integer_Kind, Integer_Value (Index))));
         end loop;
         Arguments.Reserve_Capacity (Ada.Containers.Count_Type (Count));
         for Index in 1 .. Count loop
            Arguments.Append (State.Current.Arguments.Element (Index + 3));
         end loop;
         Callee := State.Current.Arguments.First_Element;
         declare
            Driver : Machine.Driver;
         begin
            --  Keep the full prefix AND all copied values in Current.Arguments
            --  until Start has pinned and published the real call. Its new
            --  temporary-root epoch may allocate; neither a local Callee nor
            --  this local argument arena is an independent collector root.
            Machine.Start (Driver, Self.State, Callee, Arguments);
            State.Current.Arguments.Clear;
            Pump (Driver);
            Machine.Finish (Driver);
         exception
            when others => Machine.Cancel (Driver); raise;
         end;
         State.Current.Status := Suspended_Context;
      end Execute_Body;
   begin
      if Self.State = null then return Failure (Self, Name); end if;
      Execute_Body;
      --  Execute_Body's local owned arena has finalized while the owner is
      --  still alive. Only now may a close=true typed exit physically free
      --  the world and its allocator; no local buffer can outlive that owner.
      Result.Output := Self.State.Output;
      if Self.State.Exit_Phase = Exit_Complete then
         Apply_Exit (Self, Result);
      end if;
      return Result;
   exception
      when Language_Error => Recover; return Failure (Self, Name);
      when Lua.Storage.Allocation_Error =>
         Record_Memory_Error (Self.State.all);
         Recover;
         return Failure (Self, Name);
      when Storage_Error =>
         Recover;
         Self.State.Current.Failure_Class := Host_Abort;
         Result.Status := Resource_Error;
         Result.Error.Source := To_Unbounded_String (Name);
         Result.Error.Message := To_Unbounded_String
           ("host storage exhausted");
         return Result;
      when Error : Constraint_Error | Program_Error =>
         if Lua.Storage.Refusal_Pending (Self.State.Memory) then
            Record_Memory_Error (Self.State.all);
         else
            Set_Failure_Text
              (Self.State.all, Self.State.Current, "internal Ada check: " &
               Ada.Exceptions.Exception_Message (Error));
         end if;
         Recover;
         return Failure (Self, Name);
   end Execute_Selected_Script;
end Lua.Sessions.CLI;
