with Ada.Characters.Latin_1;
with Ada.Command_Line;
with Ada.Containers.Vectors;
with Ada.Environment_Variables;
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
with System;

procedure Lua_CLI is
   use Ada.Command_Line;
   use Lua.Sessions;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_IO.Count;
   use type Interfaces.C.int;
   use type Interfaces.C.size_t;
   use type Lua.Syntax.Check_Status;

   LF : constant Character := Ada.Characters.Latin_1.LF;

   --  Ordered pre-script actions. lua.c runs -e, -l and -W strictly in
   --  command-line order, so they share one list instead of separate ones.
   type Action_Kind is (Run_Snippet, Load_Library, Warnings_On);
   type Action is record
      Kind : Action_Kind := Run_Snippet;
      Text : Unbounded_String;
   end record;
   package Action_Vectors is new Ada.Containers.Vectors (Positive, Action);
   Actions : Action_Vectors.Vector;

   Script_Index : Natural := 0;
   Script_After_Dashes : Boolean := False;
   Version_Requested : Boolean := False;   --  project --version
   Banner_Requested : Boolean := False;    --  lua.c -v (also implied by -i)
   Interactive_Requested : Boolean := False;
   Ignore_Environment : Boolean := False;
   Check_Requested : Boolean := False;
   Process_Exit_Requested : Boolean := False;
   Process_Exit_Status : Interfaces.C.int := 0;

   procedure Exit_Process (Code : Interfaces.C.int)
     with Import, Convention => C, No_Return, External_Name => "exit";
   --  Process mechanics run only after the Ada execution boundary returns.
   --  Physical disposal precedes process exit. os.exit(false) never requests
   --  Lua state closure or Lua close handlers during that disposal.

   --  Shared native stdio. These are the same FILE objects the Lua io library
   --  uses, so bytes consumed here are never seen again by io.read.
   function Standard_Stream (Which : Interfaces.C.int) return System.Address
     with Import, Convention => C, External_Name => "lua_ada_stream_standard";
   function Set_Binary (File : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_stream_set_binary";
   procedure Begin_Read (File : System.Address)
     with Import, Convention => C,
          External_Name => "lua_ada_stream_begin_read";
   function Raw_Read
     (File : System.Address; Bytes : System.Address;
      Count : Interfaces.C.size_t; Error : access Interfaces.C.int)
      return Interfaces.C.size_t
     with Import, Convention => C, External_Name => "lua_ada_stream_read";
   function Raw_Get
     (File : System.Address; Error : access Interfaces.C.int)
      return Interfaces.C.int
     with Import, Convention => C, External_Name => "lua_ada_stream_get";
   function Stream_Failed (File : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "lua_ada_stream_error";
   function End_Marker return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_stream_end_marker";
   function Is_Terminal (File : System.Address) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "lua_ada_stream_is_terminal";

   Stdin_Prepared : Boolean := False;

   procedure Usage;
   procedure Version;
   procedure Banner;
   procedure Bad_Option (Option : String);
   procedure Report
     (Result : Execution_Result; Fail_Process : Boolean := True);
   function Read_Source (Path : String) return String;
   function Read_Stdin return String;
   procedure Prepare_Stdin;
   function Read_Line
     (Prompt : String; Line : out Unbounded_String) return Boolean;
   function Arguments_After (Index : Natural) return Argument_Array;
   function Check_Source
     (Source, Name : String) return Lua.Syntax.Check_Result;
   function Incomplete (Result : Lua.Syntax.Check_Result) return Boolean;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line
        ("Usage: lua_ada [--check] [options] [script [arguments...]]");
      Ada.Text_IO.Put_Line ("       lua_ada --help | --version");
      Ada.Text_IO.Put_Line ("  -e stat   execute string 'stat'");
      Ada.Text_IO.Put_Line
        ("  -i        enter interactive mode after executing 'script'");
      Ada.Text_IO.Put_Line
        ("  -l mod    require library 'mod' into global 'mod'");
      Ada.Text_IO.Put_Line
        ("  -l g=mod  require library 'mod' into global 'g'");
      Ada.Text_IO.Put_Line ("  -v        show version information");
      Ada.Text_IO.Put_Line ("  -E        ignore environment variables");
      Ada.Text_IO.Put_Line ("  -W        turn warnings on");
      Ada.Text_IO.Put_Line ("  --        stop handling options");
      Ada.Text_IO.Put_Line
        ("  -         stop handling options and execute stdin");
      Ada.Text_IO.Put_Line
        ("--check validates complete Lua syntax without executing source.");
      Ada.Text_IO.Put_Line
        ("Lua 5.5 subset; native binary files supported. Native modules, "
         & "readline and signal handling are deferred.");
   end Usage;

   procedure Version is
   begin
      Ada.Text_IO.Put_Line
        ("Lua Ada " & Lua.Implementation_Version &
         " (target " & Lua.Reference_Release & ")");
   end Version;

   procedure Banner is
   begin
      --  lua.c print_version writes LUA_COPYRIGHT and a line end to stdout.
      Ada.Text_IO.Put_Line
        ("Lua " & Lua.Reference_Release &
         "  Copyright (C) 1994-2026 Lua.org, PUC-Rio");
      Ada.Text_IO.Flush;
   end Banner;

   procedure Bad_Option (Option : String) is
   begin
      --  Same wording and layout as lua.c print_usage, on stderr.
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "lua_ada: " &
         (if Option'Length >= 2 and then
             Option (Option'First + 1) in 'e' | 'l'
          then "'" & Option & "' needs argument"
          else "unrecognized option '" & Option & "'"));
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "usage: lua_ada [options] [script [args]]");
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "Available options are:");
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "  -e stat   execute string 'stat'");
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "  -i        enter interactive mode after executing 'script'");
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "  -l mod    require library 'mod' into global 'mod'");
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "  -l g=mod  require library 'mod' into global 'g'");
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "  -v        show version information");
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "  -E        ignore environment variables");
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "  -W        turn warnings on");
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "  --        stop handling options");
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "  -         stop handling options and execute stdin");
      Set_Exit_Status (Failure);
   end Bad_Option;

   procedure Report
     (Result : Execution_Result; Fail_Process : Boolean := True) is
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
            Source : constant String := To_String (Result.Error.Source);
            Prefix : constant String :=
              (if Source'Length > 0 and then
                  Source (Source'First) in '@' | '='
               then Source (Source'First + 1 .. Source'Last)
               else Source) & ":";
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
         --  The interactive loop reports errors and keeps running; only
         --  batch execution converts a failed chunk into process failure.
         if Fail_Process then
            Set_Exit_Status (Failure);
         end if;
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

   procedure Prepare_Stdin is
   begin
      --  Select untranslated bytes once, before the first consumer. The
      --  Windows C runtime otherwise folds CRLF and stops at Ctrl-Z, which
      --  corrupts binary chunks and the byte content of long strings.
      if not Stdin_Prepared then
         Stdin_Prepared := True;
         if Set_Binary (Standard_Stream (0)) /= 0 then
            raise Ada.Text_IO.Use_Error with "cannot select binary stdin";
         end if;
         Begin_Read (Standard_Stream (0));
      end if;
   end Prepare_Stdin;

   function Read_Stdin return String is
      Text : Unbounded_String;
      Buffer : String (1 .. 4096);
      Error : aliased Interfaces.C.int := 0;
      Count : Interfaces.C.size_t;
   begin
      --  Whole-stream byte read through the shared native stream. Every
      --  byte (NUL, high bit, CR, LF) is preserved; the Lua frontend, not
      --  the CLI, defines line-end semantics. Total size stays bounded by
      --  the String index range.
      Prepare_Stdin;
      loop
         Count := Raw_Read
           (Standard_Stream (0), Buffer'Address, Buffer'Length, Error'Access);
         exit when Count = 0;
         if Length (Text) > Positive'Last - Integer (Count) then
            raise Constraint_Error with "source byte limit exceeded";
         end if;
         Append (Text, Buffer (1 .. Integer (Count)));
      end loop;
      if Stream_Failed (Standard_Stream (0)) /= 0 then
         raise Ada.Text_IO.Device_Error with "stdin read failed";
      end if;
      return To_String (Text);
   end Read_Stdin;

   function Read_Line
     (Prompt : String; Line : out Unbounded_String) return Boolean
   is
      Error : aliased Interfaces.C.int := 0;
      Byte : Interfaces.C.int;
   begin
      --  Prompt, flush, then read bytes up to LF or end of input, as the
      --  fgets-based lua_readline does without the readline library. A
      --  final unterminated line is still a line; end of input with no
      --  bytes yields False. The LF itself is not part of the result.
      Prepare_Stdin;
      Ada.Text_IO.Put (Prompt);
      Ada.Text_IO.Flush;
      Line := Null_Unbounded_String;
      loop
         Byte := Raw_Get (Standard_Stream (0), Error'Access);
         if Byte = End_Marker then
            return Length (Line) > 0;
         elsif Byte = Character'Pos (Ada.Characters.Latin_1.LF) then
            return True;
         end if;
         Append (Line, Character'Val (Byte));
      end loop;
   end Read_Line;

   function Arguments_After (Index : Natural) return Argument_Array is
      Result : Argument_Array (1 .. Argument_Count - Index);
   begin
      for Position in Result'Range loop
         Result (Position) := To_Unbounded_String
           (Argument (Index + Position));
      end loop;
      return Result;
   end Arguments_After;

   function Check_Source
     (Source, Name : String) return Lua.Syntax.Check_Result is
     (Lua.Syntax.Check
        (Source, Name, (Nesting => 200, others => Positive'Last)));
   --  Policy-derived limits shared by --check and the REPL's completeness
   --  probe. This is the one shared frontend; the CLI has no grammar.

   function Incomplete (Result : Lua.Syntax.Check_Result) return Boolean is
     (Result.Status = Lua.Syntax.Syntax_Error and then
      Result.Incomplete_Input);
   --  The owned frontend distinguishes an unfinished token or grammar rule
   --  from a complete but invalid chunk. Diagnostic wording is not a second
   --  grammar, and a semantic error at EOF must not consume the next command.

   Position : Positive := 1;
begin
   --  Parse everything first: snippets must see the final script's arg table.
   --  Once a script is found, remaining options are script arguments. The
   --  rules follow lua.c collectargs.
   while Position <= Argument_Count loop
      declare
         Item : constant String := Argument (Position);
      begin
         if Item = "--help" or else Item = "-h" then
            Usage;
            return;
         elsif Item = "--version" then
            Version_Requested := True;
         elsif Item = "--check" then
            Check_Requested := True;
         elsif Item = "--" then
            if Position < Argument_Count then
               Script_Index := Position + 1;
               Script_After_Dashes := True;
            end if;
            exit;
         elsif Item = "-" or else Item'Length = 0 or else Item (1) /= '-' then
            Script_Index := Position;
            exit;
         elsif Item = "-v" then
            Banner_Requested := True;
         elsif Item = "-i" then
            Interactive_Requested := True;
            Banner_Requested := True;   --  -i implies -v
         elsif Item = "-E" then
            Ignore_Environment := True;
         elsif Item = "-W" then
            Actions.Append (Action'(Warnings_On, Null_Unbounded_String));
         elsif Item (2) in 'e' | 'l' then
            declare
               Kind : constant Action_Kind :=
                 (if Item (2) = 'e' then Run_Snippet else Load_Library);
            begin
               if Item'Length > 2 then
                  Actions.Append
                    (Action'(Kind, To_Unbounded_String
                       (Item (3 .. Item'Last))));
               elsif Position = Argument_Count or else
                 (Argument (Position + 1)'Length > 0 and then
                  Argument (Position + 1) (1) = '-')
               then
                  --  lua.c: the operand must exist and not be an option.
                  Bad_Option (Item);
                  return;
               else
                  Position := Position + 1;
                  Actions.Append
                    (Action'(Kind, To_Unbounded_String (Argument (Position))));
               end if;
            end;
         else
            Bad_Option (Item);
            return;
         end if;
      end;
      Position := Position + 1;
   end loop;

   declare
      Has_Snippet : Boolean := False;
      Has_Action : constant Boolean := not Actions.Is_Empty;
   begin
      for Item of Actions loop
         if Item.Kind = Run_Snippet then
            Has_Snippet := True;
         end if;
      end loop;

      if Version_Requested then
         Version;
      end if;
      if Banner_Requested then
         Banner;
      end if;

      if Check_Requested then
         --  Syntax-only operation never constructs a runtime session,
         --  creates globals, installs arguments, loads libraries, reads the
         --  environment or calls an output sink. Only -e and the script are
         --  checked; -l/-W/-i/-E have nothing to validate.
         if not Has_Snippet and then Script_Index = 0 then
            if not (Version_Requested or else Banner_Requested) then
               Usage;
            end if;
            return;
         end if;
         declare
            function Check (Source, Name : String) return Boolean;
            function Check (Source, Name : String) return Boolean is
               Result : constant Lua.Syntax.Check_Result :=
                 Check_Source (Source, Name);
               Reported : Execution_Result;
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
            for Item of Actions loop
               if Item.Kind = Run_Snippet and then
                 not Check (To_String (Item.Text), "(command line)")
               then
                  return;
               end if;
            end loop;
            if Script_Index /= 0 then
               declare
                  Path : constant String := Argument (Script_Index);
                  Use_Stdin : constant Boolean :=
                    Path = "-" and then not Script_After_Dashes;
                  Source : constant String := Lua.Sources.File_Preamble
                    (if Use_Stdin then Read_Stdin else Read_Source (Path));
                  Ignored : constant Boolean := Check
                    (Source, (if Use_Stdin then "stdin" else Path));
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            end if;
         end;
         return;
      end if;

      --  Plain project --version (no other work requested) stays a pure
      --  informational command, as before; it must not wait on stdin.
      if Version_Requested and then not Has_Action and then
        Script_Index = 0 and then not Interactive_Requested
      then
         return;
      end if;

      declare
         --  lua.c: with no script and no -e/-v/-i, stdin is the program.
         Implicit_Stdin : constant Boolean :=
           Script_Index = 0 and then not Has_Snippet
           and then not Banner_Requested and then not Version_Requested;

         procedure Execute_Main;
         procedure Execute_Main is
            Universe : Session;
            Args : Argument_Array
              (-Integer (Script_Index) .. Argument_Count - Script_Index);
            Result : Execution_Result;

            function Run
              (Source, Name : String;
               Arguments : Argument_Array := No_Arguments) return Boolean;
            function Run
              (Source, Name : String;
               Arguments : Argument_Array := No_Arguments) return Boolean is
            begin
               --  One batch chunk: report it, and on failure release the
               --  state unless a typed exit already decided its disposal.
               Result := Universe.Execute (Source, Name, Arguments);
               Report (Result);
               if Result.Status /= Succeeded then
                  if not Process_Exit_Requested then
                     Universe.Close;
                  end if;
                  return False;
               end if;
               return True;
            end Run;

            function Control_Warnings (Enabled : Boolean) return Boolean;
            function Control_Warnings (Enabled : Boolean) return Boolean is
            begin
               --  -W is an interpreter control, not a lookup of the Lua
               --  warn global. The host API also preserves custom handlers.
               Result := Universe.Set_Warnings_Enabled (Enabled);
               Report (Result);
               if Result.Status /= Succeeded then
                  if not Process_Exit_Requested then Universe.Close; end if;
                  return False;
               end if;
               return True;
            end Control_Warnings;

            function Environment_Value (Name : String) return String is
              (Ada.Environment_Variables.Value (Name));

            function Set_Search_Path
              (Variable, Field : String) return Boolean;
            function Set_Search_Path
              (Variable, Field : String) return Boolean
            is
               Versioned : constant String := Variable & "_5_5";
               Chosen : constant String :=
                 (if Ada.Environment_Variables.Exists (Versioned)
                  then Versioned else Variable);
            begin
               --  loadlib.c setpath: the versioned variable wins; ";;" in
               --  the value expands, once, to the default. The library
               --  keeps only its default; this host step applies the
               --  environment before any user code, so the observable
               --  package field matches. The value travels as a vararg
               --  string, never spliced into source text.
               if not Ada.Environment_Variables.Exists (Chosen) then
                  return True;
               end if;
               return Run
                 ("local field, value = ..." & LF &
                  "local mark = string.find(value, ';;', 1, true)" & LF &
                  "if mark then" & LF &
                  "  local out = ''" & LF &
                  "  if mark > 1 then out = string.sub(value, 1, mark - 1)" &
                  " .. ';' end" & LF &
                  "  out = out .. package[field]" & LF &
                  "  if mark < #value - 1 then out = out .. ';' .. " &
                  "string.sub(value, mark + 2) end" & LF &
                  "  value = out" & LF &
                  "end" & LF &
                  "package[field] = value" & LF,
                  "=" & Chosen,
                  [1 => To_Unbounded_String (Field),
                   2 => To_Unbounded_String (Environment_Value (Chosen))]);
            end Set_Search_Path;

            function Run_Init return Boolean;
            function Run_Init return Boolean is
               Versioned : constant String := "LUA_INIT_5_5";
               Name : constant String :=
                 (if Ada.Environment_Variables.Exists (Versioned)
                  then Versioned else "LUA_INIT");
            begin
               if not Ada.Environment_Variables.Exists (Name) then
                  return True;
               end if;
               declare
                  Init : constant String := Environment_Value (Name);
               begin
                  if Init'Length > 0 and then Init (Init'First) = '@' then
                     --  "@file" is dofile semantics: file preamble and an
                     --  "@" source label.
                     declare
                        Path : constant String :=
                          Init (Init'First + 1 .. Init'Last);
                     begin
                        return Run
                          (Lua.Sources.File_Preamble (Read_Source (Path)),
                           "@" & Path);
                     end;
                  end if;
                  return Run (Init, "=" & Name);
               end;
            end Run_Init;

            function Require_Library (Spec : String) return Boolean;
            function Require_Library (Spec : String) return Boolean is
               Equals : constant Natural :=
                 Ada.Strings.Fixed.Index (Spec, "=");
               Mark : constant Natural :=
                 (if Equals = 0 then Ada.Strings.Fixed.Index (Spec, "-")
                  else 0);
               Module : constant String :=
                 (if Equals = 0 then Spec
                  else Spec (Equals + 1 .. Spec'Last));
               Global : constant String :=
                 (if Equals /= 0 then Spec (Spec'First .. Equals - 1)
                  elsif Mark /= 0 then Spec (Spec'First .. Mark - 1)
                  else Spec);
            begin
               --  dolibrary: global = require(module), with the "-version"
               --  suffix cut from an implicit global name. The current
               --  global require is looked up at call time because the
               --  chunk reads it through its environment. Names are varargs.
               return Run
                 ("local global, module = ..." & LF &
                  "_ENV[global] = require(module)" & LF,
                  "=(command line)",
                  [1 => To_Unbounded_String (Global),
                   2 => To_Unbounded_String (Module)]);
            end Require_Library;

            procedure Evaluate (Source : String);
            procedure Evaluate (Source : String) is
               Print_Failed : Boolean;
               Shown : constant Execution_Result :=
                 Universe.Execute_Display (Source, "=stdin", Print_Failed);
            begin
               if Print_Failed and then Shown.Status = Runtime_Error then
                  --  l_print's pcall wrapper message (lua.c l_message).
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "error calling 'print' (" &
                     To_String (Shown.Error.Message) & ")");
               else
                  Report (Shown, Fail_Process => False);
               end if;
            end Evaluate;

            procedure Run_REPL;
            procedure Run_REPL is
               Line, Next : Unbounded_String;
            begin
               --  Host read-eval-print loop (lua.c doREPL). Each entry is
               --  a separate chunk, so locals never survive a line. Results
               --  are printed by the real global print after the chunk has
               --  returned; there is no bootstrap Lua loop and no extra Lua
               --  frame. _PROMPT/_PROMPT2, readline and SIGINT are deferred.
               while not Process_Exit_Requested
                 and then Read_Line ("> ", Line)
               loop
                  declare
                     Text : constant String := To_String (Line);
                     Expression : constant String :=
                       "return " & Text & ";";
                  begin
                     if Check_Source (Expression, "stdin").Status =
                       Lua.Syntax.Success
                     then
                        --  Expression form first, exactly as addreturn.
                        Evaluate (Expression);
                     else
                        declare
                           Accumulated : Unbounded_String := Line;
                           Index : Natural := Text'First;
                        begin
                           --  checklocal: locals cannot persist across
                           --  separate chunks, so say so on stderr.
                           while Index <= Text'Last and then
                             Text (Index) in ' ' | Ada.Characters.Latin_1.HT
                           loop
                              Index := Index + 1;
                           end loop;
                           if Index + 5 <= Text'Last and then
                             Text (Index .. Index + 4) = "local" and then
                             Text (Index + 5) in
                               ' ' | Ada.Characters.Latin_1.HT
                           then
                              Ada.Text_IO.Put_Line
                                (Ada.Text_IO.Standard_Error,
                                 "warning: locals do not survive across " &
                                 "lines in interactive mode");
                           end if;
                           --  Continuation: while the shared checker says
                           --  the statement merely ran out of input, read
                           --  another line (">> ") and join with LF.
                           while Incomplete
                             (Check_Source (To_String (Accumulated), "stdin"))
                             and then Read_Line (">> ", Next)
                           loop
                              Append (Accumulated, Ada.Characters.Latin_1.LF);
                              Append (Accumulated, Next);
                           end loop;
                           --  Complete code runs; a real syntax error (or
                           --  end of input mid-statement) is reported by
                           --  the same execution path as any other error.
                           Evaluate (To_String (Accumulated));
                        end;
                     end if;
                  end;
               end loop;
               --  lua_writeline at end of input, so the shell prompt starts
               --  on a fresh line.
               if not Process_Exit_Requested then
                  Ada.Text_IO.New_Line;
                  Ada.Text_IO.Flush;
               end if;
            end Run_REPL;
         begin
            --  Index zero names the script. Negative indices preserve
            --  executable and interpreter options, as in the reference
            --  interpreter.
            for Index in Args'Range loop
               Args (Index) := To_Unbounded_String
                 (if Index + Script_Index = 0 then Command_Name
                  else Argument (Index + Script_Index));
            end loop;
            Universe.Set_Execution_Policy (Lua_Compatible);
            --  Flush earlier Ada help/version text before C stdio starts
            --  writing. Runtime bytes are published immediately, in Lua
            --  program order, and are not printed again from result packets.
            Ada.Text_IO.Flush;
            Universe.Set_Output_Policy (Process_Streams);
            Configure (Universe);
            Result := Universe.Set_Arguments (Args);
            if Result.Status /= Succeeded then
               Report (Result);
               Universe.Close;
               return;
            end if;
            --  Package paths precede LUA_INIT. runargs then turns warnings
            --  off before the ordered -e/-l/-W actions and the script; a
            --  warning emitted during initialization uses the initial mode.
            if not Ignore_Environment then
               if not Set_Search_Path ("LUA_PATH", "path")
                 or else not Set_Search_Path ("LUA_CPATH", "cpath")
                 or else not Run_Init
               then
                  return;
               end if;
            end if;
            if not Control_Warnings (False) then
               return;
            end if;
            for Item of Actions loop
               if not (case Item.Kind is
                  when Run_Snippet =>
                     Run (To_String (Item.Text), "=(command line)"),
                  when Load_Library =>
                     Require_Library (To_String (Item.Text)),
                  when Warnings_On => Control_Warnings (True))
               then
                  return;
               end if;
            end loop;
            if Script_Index /= 0 then
               declare
                  Path : constant String := Argument (Script_Index);
                  Use_Stdin : constant Boolean :=
                    Path = "-" and then not Script_After_Dashes;
                  Source : constant String := Lua.Sources.File_Preamble
                    (if Use_Stdin then Read_Stdin else Read_Source (Path));
               begin
                  if not Run
                    (Source, (if Use_Stdin then "=stdin" else "@" & Path),
                     Arguments_After (Script_Index))
                  then
                     return;
                  end if;
               end;
            end if;
            if Interactive_Requested then
               Run_REPL;
            elsif Implicit_Stdin then
               Prepare_Stdin;
               if Is_Terminal (Standard_Stream (0)) /= 0 then
                  Banner;
                  Run_REPL;
               elsif not Run
                 (Lua.Sources.File_Preamble (Read_Stdin), "=stdin")
               then
                  return;
               end if;
            end if;
            --  CLI completion closes the state, including reachable
            --  finalizers. Controlled finalization is only the physical
            --  disposal fallback.
            if not Process_Exit_Requested then
               Universe.Close;
            end if;
         end Execute_Main;
      begin
         --  Returning from Execute_Main disposes the owned Ada session even
         --  for a typed exit. Its Close call above is deliberately omitted
         --  for the exit(false) path, so only physical host cleanup runs.
         Execute_Main;
         Finish;
         if Process_Exit_Requested then
            Ada.Text_IO.Flush;
            Ada.Text_IO.Flush (Ada.Text_IO.Standard_Error);
            Exit_Process (Process_Exit_Status);
         end if;
      end;
   end;
exception
   when Error : others =>
      Finish;
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "lua_ada: " & Ada.Exceptions.Exception_Message (Error));
      Set_Exit_Status (Failure);
end Lua_CLI;
