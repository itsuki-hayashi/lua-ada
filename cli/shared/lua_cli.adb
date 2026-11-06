with Ada.Characters.Latin_1;
with Ada.Command_Line;
with Ada.Containers.Vectors;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces.C;
with Lua;
with Lua.Sessions;
with Lua.Sources;
with Lua.Syntax;

procedure Lua_CLI is
   use Ada.Command_Line;
   use Lua.Sessions;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_IO.Count;

   package Sources is new Ada.Containers.Vectors
     (Positive, Unbounded_String);
   Snippets : Sources.Vector;
   Script_Index : Natural := 0;
   Version_Requested : Boolean := False;
   Check_Requested : Boolean := False;
   Process_Exit_Requested : Boolean := False;
   Process_Exit_Status : Interfaces.C.int := 0;

   procedure Exit_Process (Code : Interfaces.C.int)
     with Import, Convention => C, No_Return, External_Name => "exit";
   --  Process mechanics run only after the Ada execution boundary returns.
   --  Physical disposal precedes process exit. os.exit(false) never requests
   --  Lua state closure or Lua close handlers during that disposal.

   procedure Usage;
   procedure Version;
   procedure Report (Result : Execution_Result);
   function Read_Source (Path : String) return String;
   function Read_Stdin return String;
   function Arguments_After (Index : Natural) return Argument_Array;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line
        ("Usage: lua_ada [--check] [-e code]... " &
         "[--] [script | -] [arguments...]");
      Ada.Text_IO.Put_Line ("       lua_ada --help | --version");
      Ada.Text_IO.Put_Line
        ("--check validates complete Lua syntax without executing source.");
      Ada.Text_IO.Put_Line
        ("Lua 5.5 subset; native binary files supported; REPL deferred.");
   end Usage;

   procedure Version is
   begin
      Ada.Text_IO.Put_Line
        ("Lua Ada " & Lua.Implementation_Version &
         " (target " & Lua.Reference_Release & ")");
   end Version;

   procedure Report (Result : Execution_Result) is
   begin
      --  Output before a failed statement is observable Lua behavior.
      --  Preserve it before sending the structured diagnostic to stderr.
      --  Feeding LF bytes to Put would not reset Text_IO's column counter;
      --  finalization could then append a spurious second newline. Use the
      --  line operation, which also matches C stdout translation on Windows.
      for Byte of To_String (Result.Output) loop
         if Byte = Ada.Characters.Latin_1.LF then
            Ada.Text_IO.New_Line;
         else
            Ada.Text_IO.Put (Byte);
         end if;
      end loop;
      if Result.Status = Exit_Requested then
         Process_Exit_Requested := True;
         Process_Exit_Status := Result.Exit_Request.Code;
      elsif Result.Status /= Succeeded then
         declare
            Message : constant String := To_String (Result.Error.Message);
            Prefix : constant String := To_String (Result.Error.Source) & ":";
         begin
            if Message'Length >= Prefix'Length and then
              Message (Message'First .. Message'First + Prefix'Length - 1) =
                Prefix
            then
               Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Message);
            else
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error, Prefix &
                  Ada.Strings.Fixed.Trim
                    (Result.Error.Line'Image, Ada.Strings.Both) & ": " &
                  Message);
            end if;
         end;
         Set_Exit_Status (Failure);
      end if;
   end Report;

   function Read_Source (Path : String) return String is
      package Files renames Ada.Streams.Stream_IO;
      File : Files.File_Type;
   begin
      --  Binary file reading preserves NULs and original line endings.
      --  Bound the user-controlled allocation before creating its buffer.
      Files.Open (File, Files.In_File, Path);
      if Files.Size (File) > Files.Count (Positive'Last) then
         Files.Close (File);
         raise Constraint_Error with "source byte limit exceeded";
      end if;
      declare
         Bytes : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Files.Size (File)));
         Last : Ada.Streams.Stream_Element_Offset;
         Text : String (1 .. Bytes'Length);
      begin
         Files.Read (File, Bytes, Last);
         Files.Close (File);
         if Last /= Bytes'Last then
            raise Ada.Text_IO.End_Error with "short source read";
         end if;
         for Index in Text'Range loop
            Text (Index) := Character'Val
              (Bytes (Ada.Streams.Stream_Element_Offset (Index)));
         end loop;
         return Text;
      end;
   exception
      when others =>
         if Files.Is_Open (File) then
            Files.Close (File);
         end if;
         raise;
   end Read_Source;

   function Read_Stdin return String is
      Text : Unbounded_String;
      Item : Character;
   begin
      --  Character Get skips line terminators. Handle them explicitly to
      --  retain source line structure rather than joining adjacent tokens.
      while not Ada.Text_IO.End_Of_File loop
         if Length (Text) = Positive'Last then
            raise Constraint_Error with "source byte limit exceeded";
         end if;
         if Ada.Text_IO.End_Of_Line then
            Ada.Text_IO.Skip_Line;
            Append (Text, Ada.Characters.Latin_1.LF);
         else
            Ada.Text_IO.Get (Item);
            Append (Text, Item);
         end if;
      end loop;
      return To_String (Text);
   end Read_Stdin;

   function Arguments_After (Index : Natural) return Argument_Array is
      Result : Argument_Array (1 .. Argument_Count - Index);
   begin
      for Position in Result'Range loop
         Result (Position) := To_Unbounded_String
           (Argument (Index + Position));
      end loop;
      return Result;
   end Arguments_After;

   Position : Positive := 1;
begin
   --  Parse everything first: snippets must see the final script's arg table.
   --  Once a script is found, remaining options are script arguments.
   while Position <= Argument_Count loop
      declare
         Item : constant String := Argument (Position);
      begin
         if Item = "--help" or else Item = "-h" then
            Usage;
            return;
         elsif Item = "--version" or else Item = "-v" then
            Version_Requested := True;
         elsif Item = "--check" then
            Check_Requested := True;
         elsif Item = "--" then
            if Position < Argument_Count then
               Script_Index := Position + 1;
            end if;
            exit;
         elsif Item = "-e" then
            if Position = Argument_Count then
               raise Constraint_Error with "-e requires a source argument";
            end if;
            Position := Position + 1;
            Snippets.Append (To_Unbounded_String (Argument (Position)));
         elsif Item'Length > 2 and then Item (1 .. 2) = "-e" then
            Snippets.Append (To_Unbounded_String (Item (3 .. Item'Last)));
         elsif Item = "-" or else Item'Length = 0 or else Item (1) /= '-' then
            Script_Index := Position;
            exit;
         else
            raise Constraint_Error with "unrecognized option: " & Item;
         end if;
      end;
      Position := Position + 1;
   end loop;
   if Version_Requested then
      Version;
   end if;
   if Snippets.Is_Empty and then Script_Index = 0 then
      if not Version_Requested then
         Usage;
      end if;
      return;
   end if;
   if Check_Requested then
      --  Syntax-only operation never constructs a runtime session, creates
      --  globals, installs arguments, or calls an output sink.
      declare
         function Check (Source, Name : String) return Boolean;
         function Check (Source, Name : String) return Boolean is
            Result : constant Lua.Syntax.Check_Result :=
              Lua.Syntax.Check
                (Source, Name,
                 (Nesting => 200, others => Positive'Last));
            Reported : Execution_Result;
            use type Lua.Syntax.Check_Status;
         begin
            if Result.Status = Lua.Syntax.Success then
               return True;
            end if;
            Reported.Status :=
              (if Result.Status = Lua.Syntax.Resource_Error
               then Resource_Error else Syntax_Error);
            Reported.Error := Result.Error;
            Report (Reported);
            return False;
         end Check;
      begin
         for Source of Snippets loop
            if not Check (To_String (Source), "(command line)") then
               return;
            end if;
         end loop;
         if Script_Index /= 0 then
            declare
               Path : constant String := Argument (Script_Index);
               Source : constant String := Lua.Sources.File_Preamble
                 (if Path = "-" then Read_Stdin else Read_Source (Path));
               Ignored : constant Boolean := Check
                 (Source, (if Path = "-" then "stdin" else Path));
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         end if;
      end;
      return;
   end if;
   declare
      procedure Execute_Main;
      procedure Execute_Main is
         Universe : Session;
         Args : Argument_Array
           (-Integer (Script_Index) .. Argument_Count - Script_Index);
         Result : Execution_Result;
      begin
         --  Index zero names the script. Negative indices preserve executable
         --  and interpreter options, as in the reference interpreter.
         for Index in Args'Range loop
            Args (Index) := To_Unbounded_String
              (if Index + Script_Index = 0 then Command_Name
               else Argument (Index + Script_Index));
         end loop;
         Universe.Set_Execution_Policy (Lua_Compatible);
         --  Flush earlier Ada help/version text before C stdio starts writing.
         --  Runtime bytes are published immediately, in Lua program order,
         --  and are not printed a second time from captured result packets.
         Ada.Text_IO.Flush;
         Universe.Set_Output_Policy (Process_Streams);
         Configure (Universe);
         Result := Universe.Set_Arguments (Args);
         if Result.Status /= Succeeded then
            Report (Result);
            Universe.Close;
            return;
         end if;
         for Source of Snippets loop
            Result := Universe.Execute (To_String (Source), "(command line)");
            Report (Result);
            if Result.Status /= Succeeded then
               if not Process_Exit_Requested then Universe.Close; end if;
               return;
            end if;
         end loop;
         if Script_Index /= 0 then
            declare
               Path : constant String := Argument (Script_Index);
               Source : constant String := Lua.Sources.File_Preamble
                 (if Path = "-" then Read_Stdin else Read_Source (Path));
            begin
               Result := Universe.Execute
                 (Source, (if Path = "-" then "stdin" else Path),
                  Arguments => Arguments_After (Script_Index));
               Report (Result);
            end;
         end if;
         --  CLI completion closes the state, including reachable finalizers.
         --  Controlled finalization is only the physical disposal fallback.
         if not Process_Exit_Requested then Universe.Close; end if;
      end Execute_Main;
   begin
      --  Returning from Execute_Main disposes the owned Ada session even for
      --  a typed exit. Its Close call above is deliberately omitted for the
      --  exit(false) path, so only physical host cleanup runs in that case.
      Execute_Main;
      Finish;
      if Process_Exit_Requested then
         Ada.Text_IO.Flush;
         Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);
         Exit_Process (Process_Exit_Status);
      end if;
   end;
exception
   when Error : others =>
      Finish;
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "lua_ada: " & Ada.Exceptions.Exception_Message (Error));
      Set_Exit_Status (Failure);
end Lua_CLI;
