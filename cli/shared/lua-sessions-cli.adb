with Ada.Containers;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces.C;
with Lua.Diagnostic_Text;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.External_Releases;
with Lua.Engine.Foreign;
with Lua.Engine.Machine;
with Lua.Engine.Warnings;
with Lua.Storage;
with System;

package body Lua.Sessions.CLI is
   use type Ada.Containers.Count_Type;

   function Primary (Pointer : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_cli_primary_prompt";
   function Secondary (Pointer : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_cli_secondary_prompt";
   function String_Prompt (Pointer : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_cli_string_prompt";

   function Write_Prompt
     (Self : in out Session; First_Line : Boolean) return Execution_Result
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

         procedure Emit (Bytes : String);
         procedure Emit (Bytes : String) is
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
            Emit_Output (State, Bytes (Bytes'First .. Last));
            Flush_Output (State);
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

         Drive (if First_Line then Primary'Address else Secondary'Address);
         if State.Exit_Phase = Exit_Complete then
            Result.Output := State.Output;
            Apply_Exit (Self, Result);
            return Result;
         end if;
         if State.Current.Arguments.Length /= 1 then
            raise Program_Error with "invalid prompt lookup result";
         end if;
         if State.Current.Arguments.First_Element.Kind = Nil_Kind then
            Emit (if First_Line then "> " else ">> ");
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
                  Emit (View);
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
   end Write_Prompt;
end Lua.Sessions.CLI;
