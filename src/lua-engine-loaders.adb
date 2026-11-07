with Ada.Containers;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Lua.Engine.Compiler;
with Lua.Sources;
with Lua.Storage.Buffers;
with Lua_Ada_Config;

package body Lua.Engine.Loaders is
   package Managed renames Lua.Storage.Buffers;
   use type Ada.Containers.Count_Type;
   use type Ada.Exceptions.Exception_Id;
   use type Ada.Directories.File_Kind;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_IO.Count;

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action
   is
      Name : constant String := To_String (Activation.Native_Name);
      Result : Native_Action := New_Action (State);
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Activation.Native_Arguments.Length)
         then Activation.Native_Arguments (Index) else Nil_Value);
      function Returned (Index : Positive) return Value is
        (if Index <= Natural (Activation.Native_Results.Length)
         then Activation.Native_Results (Index) else Nil_Value);
      function Is_Function (Item : Value) return Boolean is
        (Item.Kind in Closure_Kind | Native_Closure_Kind | Native_Kind_Value |
           Foreign_Function_Kind);
      function Bytes (Item : Value) return String;
      function Field (Table : Value; Key : String) return Value;
      function Package_Table return Value;
      procedure Work;
      procedure Read_File (Path : String; Output : in out Managed.Buffer);
      procedure Read_Input (Output : in out Managed.Buffer);
      procedure Prepare_File (Source : in out Managed.Buffer);
      procedure Copy_Bytes
        (Item : Value; Output : in out Managed.Buffer; Appending : Boolean);
      function Replace_All (Source, Pattern, Replacement : String)
                            return String;
      function Search_Path
        (Module_Name, Path, Separator, Replacement : String;
         Errors : in out Managed.Buffer) return String;
      function Compile_Source
        (Source, Chunk_Name, Mode : String; Environment : Value)
         return Values.Vector;
      function Compile_Buffer
        (Source : in out Managed.Buffer; Chunk_Name, Mode : String;
         Environment : Value; Source_Name : Boolean := False)
         return Values.Vector;
      function Compile_Buffer
        (Source, Chunk_Name, Mode : in out Managed.Buffer;
         Environment : Value; Source_Name : Boolean := False)
         return Values.Vector;
      function Call (Function_Value : Value; Args : Values.Vector)
                     return Native_Action;
      Package_Value, Item, Function_Value, Data, Environment : Value;
      Buffer, Errors, Chunk_Name, Mode : Managed.Buffer;
      procedure Validate_Mode;

      procedure Validate_Mode is
      begin
         --  Fixed-buffer binary loading is a host C API facility. Lua source
         --  cannot promise the lifetime of that backing storage, so lbaselib
         --  rejects B before reading a file or invoking a reader callback.
         for Index in 1 .. Length (Mode) loop
            exit when Mode.Element (Index) = Character'Val (0);
            if Mode.Element (Index) = 'B' then
               Fail (State, "invalid mode");
            end if;
         end loop;
      end Validate_Mode;
      Directory_Separator : constant String :=
        (if Lua_Ada_Config.Alire_Host_OS = "windows" then "\" else "/");

      procedure Work is
      begin
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         if State.Policy = Bounded then
            State.Steps := State.Steps + 1;
         end if;
      end Work;

      function Bytes (Item : Value) return String is
      begin
         if Item.Kind = String_Kind then
            return To_String (Item.Reference.Bytes);
         elsif Item.Kind in Integer_Kind | Real_Kind then
            return Image (State.Current.Memory, Item);
         end if;
         Fail (State, "string expected in " & Name);
         return "";
      end Bytes;

      function Field (Table : Value; Key : String) return Value is
      begin
         return Get (Table, New_String (State, Key));
      end Field;

      function Package_Table return Value is
      begin
         if not Activation.Native_Captures.Is_Empty then
            return Activation.Native_Captures (1);
         end if;
         --  Initialization normally captures the original package table.
         --  The fallback supports explicitly constructed test activations.
         return Field (Global_Environment (State), "package");
      end Package_Table;

      function Call (Function_Value : Value; Args : Values.Vector)
                     return Native_Action
      is
      begin
         return (Kind => Invoke, Function_Value => Function_Value,
                 Arguments => Args, others => <>);
      end Call;

      procedure Read_File (Path : String; Output : in out Managed.Buffer) is
         package Files renames Ada.Streams.Stream_IO;
         File : Files.File_Type;
         Data : Ada.Streams.Stream_Element_Array (1 .. 4_096);
         Last : Ada.Streams.Stream_Element_Offset;
         Text : String (1 .. 4_096);
      begin
         Files.Open (File, Files.In_File, Path);
         if Files.Size (File) > Files.Count (State.Bounds.Source_Bytes) then
            Files.Close (File);
            Fail (State, "source byte limit exceeded", Resource => True);
         end if;
         Output.Clear;
         --  File control records and this fixed transfer block are bounded
         --  host I/O storage. Source-proportional bytes grow only in the
         --  universe's managed buffer, including files that change after open.
         while not Files.End_Of_File (File) loop
            Files.Read (File, Data, Last);
            if Natural (Last) > State.Bounds.Source_Bytes - Output.Length then
               Fail (State, "source byte limit exceeded", Resource => True);
            end if;
            for Index in 1 .. Natural (Last) loop
               Text (Index) := Character'Val
                 (Data (Ada.Streams.Stream_Element_Offset (Index)));
            end loop;
            Output.Append (Text (1 .. Natural (Last)));
         end loop;
         Files.Close (File);
      exception
         when others =>
            if Files.Is_Open (File) then
               Files.Close (File);
            end if;
            raise;
      end Read_File;

      procedure Read_Input (Output : in out Managed.Buffer) is
         Byte : Character;
      begin
         Output.Clear;
         while not Ada.Text_IO.End_Of_File loop
            Work;
            if Output.Length >= State.Bounds.Source_Bytes then
               Fail (State, "source byte limit exceeded", Resource => True);
            end if;
            if Ada.Text_IO.End_Of_Line then
               Ada.Text_IO.Skip_Line;
               Output.Append (Character'Val (10));
            else
               Ada.Text_IO.Get (Byte);
               Output.Append (Byte);
            end if;
         end loop;
      end Read_Input;

      procedure Prepare_File (Source : in out Managed.Buffer) is
         Info : Lua.Sources.File_Preamble_Info;
         procedure Inspect (Text : String);
         procedure Inspect (Text : String) is
         begin
            Info := Lua.Sources.Inspect_File_Preamble (Text);
         end Inspect;
      begin
         Source.Query (Inspect'Access);
         --  Apply the shared pure policy after releasing the borrowed view.
         --  Moving away the BOM and blanking the interpreter line preserve
         --  every newline byte without creating another full source string.
         if Info.Skipped_Bytes /= 0 then
            Source.Delete (1, Info.Skipped_Bytes);
         end if;
         for Index in 1 .. Info.Blanked_Bytes loop
            Source.Replace_Element (Index, ' ');
         end loop;
      end Prepare_File;

      procedure Copy_Bytes
        (Item : Value; Output : in out Managed.Buffer; Appending : Boolean)
      is
         procedure Write (Text : String);
         procedure Write (Text : String) is
         begin
            if Appending then
               Output.Append (Text);
            else
               Output.Set_Value (Text);
            end if;
         end Write;
      begin
         if Item.Kind = String_Kind then
            declare
               View : constant String (1 .. Length (Item.Reference.Bytes))
                 with Import, Address => Item.Reference.Bytes.Address;
            begin
               Write (View);
            end;
         else
            Write (Bytes (Item));
         end if;
      end Copy_Bytes;

      function Replace_All (Source, Pattern, Replacement : String)
                            return String
      is
         Result : Managed.Buffer;
         First : Positive := Source'First;
         Found : Natural;
      begin
         Result.Set_Owner (Lua.Storage.Reference (State.Memory));
         if Pattern'Length = 0 then
            return Source;
         end if;
         while First <= Source'Last loop
            Work;
            Found := Ada.Strings.Fixed.Index
              (Source (First .. Source'Last), Pattern);
            if Found = 0 then
               Append (Result, Source (First .. Source'Last));
               exit;
            end if;
            Append (Result, Source (First .. Found - 1));
            Append (Result, Replacement);
            if Length (Result) > State.Bounds.String_Bytes then
               Fail (State, "path byte limit exceeded", Resource => True);
            end if;
            First := Found + Pattern'Length;
         end loop;
         if Length (Result) > State.Bounds.String_Bytes then
            Fail (State, "path byte limit exceeded", Resource => True);
         end if;
         return To_String (Result);
      end Replace_All;

      function Search_Path
        (Module_Name, Path, Separator, Replacement : String;
         Errors : in out Managed.Buffer) return String
      is
         Converted : constant String :=
           Replace_All (Module_Name, Separator, Replacement);
         First : Positive := Path'First;
         Last : Natural;
      begin
         Errors.Clear;
         while First <= Path'Last loop
            Work;
            Last := First;
            while Last <= Path'Last and then Path (Last) /= ';' loop
               Last := Last + 1;
            end loop;
            if Last > First then
               declare
                  File : constant String := Replace_All
                    (Path (First .. Last - 1), "?", Converted);
                  Readable : Boolean := False;
                  Handle : Ada.Streams.Stream_IO.File_Type;
               begin
                  --  Opening is the test: existence alone does not establish
                  --  readability, and directories are not Lua source files.
                  begin
                     if Ada.Directories.Exists (File) and then
                       Ada.Directories.Kind (File) =
                         Ada.Directories.Ordinary_File
                     then
                        Ada.Streams.Stream_IO.Open
                          (Handle, Ada.Streams.Stream_IO.In_File, File);
                        Ada.Streams.Stream_IO.Close (Handle);
                        Readable := True;
                     end if;
                  exception
                     when Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error =>
                        null;
                  end;
                  if Readable then
                     return File;
                  end if;
                  --  Each template may expand to a large module name. Bound
                  --  the accumulated error text as well as each individual
                  --  filename so a long failing path cannot multiply memory.
                  if File'Length + 12 > State.Bounds.String_Bytes -
                    Length (Errors)
                  then
                     Fail (State, "module diagnostic limit exceeded",
                           Resource => True);
                  end if;
                  Append (Errors, Character'Val (10) & Character'Val (9) &
                          "no file '" & File & "'");
               end;
            end if;
            First := Last + 1;
         end loop;
         return "";
      end Search_Path;

      function Compile_Source
        (Source, Chunk_Name, Mode : String; Environment : Value)
         return Values.Vector
      is
         Results : Values.Vector := Owned_Values (State);
         Code : Prototype_Access;
         Scope : Object_Access;
         Saved_Text : constant Unbounded_String := State.Current.Failure_Text;
         Saved_Value : constant Value := State.Current.Failure;
         Saved_Has_Value : constant Boolean := State.Current.Has_Failure_Value;
         Saved_At : constant Lua.Lexers.Source_Location :=
           State.Current.Failure_At;
         Saved_Class : constant Failure_Kind := State.Current.Failure_Class;
         procedure Restore;
         procedure Restore is
         begin
            State.Current.Failure_Text := Saved_Text;
            State.Current.Failure := Saved_Value;
            State.Current.Has_Failure_Value := Saved_Has_Value;
            State.Current.Failure_At := Saved_At;
            State.Current.Failure_Class := Saved_Class;
         end Restore;
      begin
         --  The signature selects binary versus text before parsing. Mode
         --  filtering applies to that selection even for a malformed chunk;
         --  allowed binary input then uses the same owned codec as C loading.
         declare
            Binary : constant Boolean := Source'Length > 0 and then
              Source (Source'First) = Character'Val (27);
            Accepted : constant Boolean := Ada.Strings.Fixed.Index
              (Mode, (if Binary then "b" else "t")) /= 0;
         begin
            if not Accepted then
               Results.Append (Nil_Value);
               Results.Append (New_String
                 (State, "attempt to load a " &
                  (if Binary then "binary" else "text") &
                  " chunk (mode is '" & Mode & "')"));
               return Results;
            end if;
         end;
         --  Dynamic compilation belongs to this execution's work budget.
         --  Per-source limits alone allow a reader/loop to repeatedly scan
         --  a large retained string at effectively constant VM cost.
         if Source'Length > State.Bounds.Instructions - Natural'Min
           (State.Steps, State.Bounds.Instructions)
         then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         if State.Policy = Bounded then
            State.Steps := State.Steps + Source'Length;
         end if;
         begin
            State.Current.Failure_Class := No_Failure;
            Code := Compiler.Compile (State, Source, Chunk_Name);
         exception
            when Language_Error =>
               if (State.Current.Failure_Class = Host_Abort) then
                  raise;
               elsif State.Current.Failure_Class = Memory_Failure then
                  Restore;
                  Results.Append (Nil_Value);
                  Results.Append (State.Memory_Error_Value);
                  return Results;
               end if;
               declare
                  Message : constant String := Chunk_Name & ":" &
                    Ada.Strings.Fixed.Trim
                      (State.Current.Failure_At.Line'Image, Ada.Strings.Both) &
                    ": " & To_String (State.Current.Failure_Text);
               begin
                  Restore;
                  Results.Append (Nil_Value);
                  Results.Append (New_String (State, Message));
                  return Results;
               end;
         end;
         Restore;
         --  A loaded closure captures its own root _ENV cell. Passing nil is
         --  different from omitting argument four; no caller locals leak in.
         Scope := New_Environment (State, null);
         Declare_Local (State, Scope, Code.Environment_Symbol, Environment);
         Results.Append (New_Closure (State, Code, Scope));
         return Results;
      end Compile_Source;

      function Compile_Buffer
        (Source : in out Managed.Buffer; Chunk_Name, Mode : String;
         Environment : Value; Source_Name : Boolean := False)
         return Values.Vector
      is
         Results : Values.Vector := Owned_Values (State);
         procedure Compile (Text : String);
         procedure Compile (Text : String) is
         begin
            Results := Compile_Source
              (Text, (if Source_Name then Text else Chunk_Name),
               Mode, Environment);
         end Compile;
      begin
         --  The compiler consumes the borrowed view synchronously. Its owned
         --  syntax/prototype storage must never retain this transient address.
         Source.Query (Compile'Access);
         return Results;
      end Compile_Buffer;

      function Compile_Buffer
        (Source, Chunk_Name, Mode : in out Managed.Buffer;
         Environment : Value; Source_Name : Boolean := False)
         return Values.Vector
      is
         Results : Values.Vector := Owned_Values (State);
         procedure Compile_Text (Text : String);
         procedure Compile_Text (Text : String) is
            procedure With_Name (Name : String);
            procedure With_Name (Name : String) is
               procedure With_Mode (Flags : String);
               procedure With_Mode (Flags : String) is
               begin
                  Results := Compile_Source
                    (Text, (if Source_Name then Text else Name),
                     Flags, Environment);
               end With_Mode;
            begin
               Mode.Query (With_Mode'Access);
            end With_Name;
         begin
            Chunk_Name.Query (With_Name'Access);
         end Compile_Text;
      begin
         Source.Query (Compile_Text'Access);
         return Results;
      end Compile_Buffer;
   begin
      Buffer.Set_Owner (Lua.Storage.Reference (State.Memory));
      Errors.Set_Owner (Lua.Storage.Reference (State.Memory));
      Chunk_Name.Set_Owner (Lua.Storage.Reference (State.Memory));
      Mode.Set_Owner (Lua.Storage.Reference (State.Memory));
      Work;
      if Name in "base.load" | "load" then
         if Activation.Native_Stage = 0 then
            --  Validate host-independent options before requesting a reader.
            --  An invalid mode/name must not run user callbacks as a side
            --  effect before raising its argument error.
            if Arg (3).Kind = Nil_Kind then
               Mode.Set_Value ("bt");
            else
               Copy_Bytes (Arg (3), Mode, False);
            end if;
            Validate_Mode;
            if Arg (2).Kind /= Nil_Kind then
               Copy_Bytes (Arg (2), Chunk_Name, False);
            end if;
            if Is_Function (Arg (1)) or else
              Arg (1).Kind not in String_Kind | Integer_Kind | Real_Kind
            then
               --  Unlike ordinary calls, load requires a function value.
               --  A table with __call is deliberately not a reader here.
               if not Is_Function (Arg (1)) then
                  Fail (State, "bad argument #1 to load (function expected)");
               end if;
               Activation.Native_Stage := 1;
               --  C Lua requests readers inside its protected parser. Use
               --  the VM's protected-call continuation to preserve that
               --  boundary without entering the executor recursively.
               return Call ((Native_Kind_Value, Pcall_Function),
                            One_Value (State, Arg (1), 1));
            end if;
            Copy_Bytes (Arg (1), Activation.Native_Buffer, False);
         elsif Activation.Native_Stage = 1 then
            if not Truth (Returned (1)) then
               --  Error values need not be strings. Keep the exact object
               --  (including nil) as load's second result, without coercion.
               Result.Results.Append (Nil_Value);
               Result.Results.Append (Returned (2));
               return Result;
            end if;
            Item := Returned (2);
            if Item.Kind not in Nil_Kind | String_Kind | Integer_Kind |
              Real_Kind
            then
               Result.Results.Append (Nil_Value);
               Result.Results.Append
                 (New_String (State, "reader function must return a string"));
               return Result;
            end if;
            if Item.Kind /= Nil_Kind then
               declare
                  Size : constant Natural :=
                    (if Item.Kind = String_Kind then
                       Length (Item.Reference.Bytes) else Bytes (Item)'Length);
               begin
                  if Size > State.Bounds.Source_Bytes -
                    Length (Activation.Native_Buffer)
                  then
                     Fail (State, "source byte limit exceeded",
                           Resource => True);
                  end if;
                  if Size > 0 then
                     Copy_Bytes (Item, Activation.Native_Buffer, True);
                     return Call ((Native_Kind_Value, Pcall_Function),
                                  One_Value (State, Arg (1), 1));
                  end if;
               end;
            end if;
         end if;
         if Arg (2).Kind = Nil_Kind then
            Chunk_Name.Set_Value
              ((if Is_Function (Arg (1)) then "=(load)" else ""));
         else
            Copy_Bytes (Arg (2), Chunk_Name, False);
         end if;
         if Arg (3).Kind = Nil_Kind then
            Mode.Set_Value ("bt");
         else
            Copy_Bytes (Arg (3), Mode, False);
         end if;
         Environment := (if Activation.Native_Arguments.Length >= 4
                         then Arg (4) else Global_Environment (State));
         Result.Results := Compile_Buffer
           (Activation.Native_Buffer, Chunk_Name, Mode, Environment,
            Source_Name => Arg (2).Kind = Nil_Kind and then
              not Is_Function (Arg (1)));
      elsif Name in "base.loadfile" | "loadfile" | "base.dofile" | "dofile"
      then
         if Activation.Native_Stage = 1 then
            Result.Results := Activation.Native_Results;
            return Result;
         end if;
         if Name in "base.dofile" | "dofile" or else Arg (2).Kind = Nil_Kind
         then
            Mode.Set_Value ("bt");
         else
            Copy_Bytes (Arg (2), Mode, False);
         end if;
         Validate_Mode;
         begin
            if Arg (1).Kind = Nil_Kind then
               Read_Input (Buffer);
            else
               Read_File (Bytes (Arg (1)), Buffer);
            end if;
            Prepare_File (Buffer);
         exception
            when Error : Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error |
              Ada.Text_IO.End_Error =>
               if Name in "base.dofile" | "dofile" then
                  Fail (State, Ada.Exceptions.Exception_Message (Error));
               end if;
               Result.Results.Append (Nil_Value);
               Result.Results.Append (New_String
                 (State, Ada.Exceptions.Exception_Message (Error)));
               return Result;
         end;
         if Arg (1).Kind = Nil_Kind then
            Chunk_Name.Set_Value ("stdin");
         else
            Copy_Bytes (Arg (1), Chunk_Name, False);
         end if;
         Environment := (if Name not in "base.dofile" | "dofile" and then
                            Activation.Native_Arguments.Length >= 3
                         then Arg (3) else Global_Environment (State));
         Result.Results := Compile_Buffer
           (Buffer, Chunk_Name, Mode, Environment);
         if Name in "base.dofile" | "dofile" then
            if Result.Results.First_Element.Kind = Nil_Kind then
               Fail (State, Bytes (Result.Results (2)));
            end if;
            Activation.Native_Stage := 1;
            return Call (Result.Results.First_Element, Values.Empty_Vector);
         end if;
      elsif Name = "package.searchpath" then
         declare
            Path : constant String := Search_Path
              (Bytes (Arg (1)), Bytes (Arg (2)),
               (if Arg (3).Kind = Nil_Kind then "." else Bytes (Arg (3))),
               (if Arg (4).Kind = Nil_Kind then Directory_Separator
                else Bytes (Arg (4))), Errors);
         begin
            if Path'Length = 0 then
               Result.Results.Append (Nil_Value);
               Result.Results.Append (New_String (State, Errors));
            else
               Result.Results.Append (New_String (State, Path));
            end if;
         end;
      elsif Name in "package.preload_searcher" | "package.searcher_preload"
      then
         Item := Get ((Table_Kind, State.Preload_Modules), Arg (1));
         if Item.Kind = Nil_Kind then
            Result.Results.Append (New_String (State,
              Character'Val (10) & Character'Val (9) &
              "no field package.preload['" & Bytes (Arg (1)) & "']"));
         else
            Result.Results.Append (Item);
            Result.Results.Append (New_String (State, ":preload:"));
         end if;
      elsif Name in "package.lua_searcher" | "package.searcher_lua" then
         Package_Value := Package_Table;
         declare
            Path : constant String := Search_Path
              (Bytes (Arg (1)), Bytes (Field (Package_Value, "path")), ".",
               Directory_Separator, Errors);
         begin
            if Path'Length = 0 then
               Result.Results.Append (New_String (State, Errors));
            else
               begin
                  Read_File (Path, Buffer);
                  Prepare_File (Buffer);
                  --  A Lua searcher accepts the same native binary chunks
                  --  as loadfile. The path's suffix is not a format filter;
                  --  package.path may deliberately select dumped modules.
                  Result.Results := Compile_Buffer
                    (Buffer, Path, "bt",
                     Global_Environment (State));
               exception
                  when Error : Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error |
                    Ada.Text_IO.End_Error =>
                     --  The successful readability probe and actual open
                     --  can race with filesystem changes. Keep that ordinary
                     --  I/O failure inside Lua's protected error boundary.
                     Fail (State, Ada.Exceptions.Exception_Message (Error));
               end;
               if Result.Results.First_Element.Kind = Nil_Kind then
                  Fail (State, "error loading module '" & Bytes (Arg (1)) &
                        "' from file '" & Path & "': " &
                        Bytes (Result.Results (2)));
               end if;
               Result.Results.Append (New_String (State, Path));
            end if;
         end;
      elsif Name in "base.require" | "require" then
         if Activation.Native_Stage = 0 then
            Package_Value := Package_Table;
            Item := New_String (State, Bytes (Arg (1)));
            Data := Get ((Table_Kind, State.Loaded_Modules), Item);
            if Truth (Data) then
               Result.Results.Append (Data);
               return Result;
            end if;
            Activation.Native_Captures.Clear;
            Append_Root
              (State, Activation.Native_Captures,
               Package_Value);
            Append_Root
              (State, Activation.Native_Captures,
               Item);
            Activation.Native_Buffer.Set_Value
              ("module '" & Bytes (Item) & "' not found:");
            if Length (Activation.Native_Buffer) > State.Bounds.String_Bytes
            then
               Fail (State, "module diagnostic limit exceeded",
                     Resource => True);
            end if;
            Activation.Native_Index := 1;
            Activation.Native_Stage := 1;
         end if;
         Item := Activation.Native_Captures (2);
         if Activation.Native_Stage = 1 then
            Package_Value := Activation.Native_Captures (1);
            Function_Value := Get
              (Field (Package_Value, "searchers"),
               (Integer_Kind, Integer_Value (Activation.Native_Index)));
            if Function_Value.Kind = Nil_Kind then
               Fail (State, To_String (Activation.Native_Buffer));
            end if;
            Activation.Native_Stage := 2;
            return Call (Function_Value, One_Value (State, Item, 1));
         elsif Activation.Native_Stage = 2 then
            Function_Value := Returned (1);
            if Is_Function (Function_Value) then
               Data := Returned (2);
               Append_Root
                 (State, Activation.Native_Captures,
                  Data);
               Activation.Native_Stage := 3;
               declare
                  Args : Values.Vector := Owned_Values (State);
               begin
                  Args.Append (Item);
                  Args.Append (Data);
                  return Call (Function_Value, Args);
               end;
            elsif Function_Value.Kind in String_Kind | Integer_Kind | Real_Kind
            then
               if Bytes (Function_Value)'Length > State.Bounds.String_Bytes -
                 Length (Activation.Native_Buffer)
               then
                  Fail (State, "module diagnostic limit exceeded",
                        Resource => True);
               end if;
               Append (Activation.Native_Buffer, Bytes (Function_Value));
            end if;
            Activation.Native_Index := Activation.Native_Index + 1;
            Activation.Native_Stage := 1;
            Result.Kind := Continue_Step;
         elsif Activation.Native_Stage = 3 then
            Data := Returned (1);
            if Data.Kind /= Nil_Kind then
               Set (State, (Table_Kind, State.Loaded_Modules), Item, Data);
            end if;
            Data := Get ((Table_Kind, State.Loaded_Modules), Item);
            if Data.Kind = Nil_Kind then
               Data := (Boolean_Kind, True);
               Set (State, (Table_Kind, State.Loaded_Modules), Item, Data);
            end if;
            Result.Results.Append (Data);
            Result.Results.Append (Activation.Native_Captures (3));
         end if;
      else
         Fail (State, "unknown loader: " & Name);
      end if;
      return Result;
   exception
      when Error : Lua.Storage.Allocation_Error | Program_Error =>
         if not Lua.Storage.Refusal_Pending (State.Memory) and then
           Ada.Exceptions.Exception_Identity (Error) /=
             Lua.Storage.Allocation_Error'Identity
         then
            raise;
         end if;
         if Name not in "base.load" | "load" | "base.loadfile" | "loadfile"
         then
            raise;
         end if;
         --  C Lua's protected parser returns nil/message for memory errors,
         --  while dofile and module search raise them. Host quotas never enter
         --  this branch: they retain the execution-abort policy.
         Record_Memory_Error (State);
         Result.Results.Clear;
         Result.Results.Append (Nil_Value);
         Result.Results.Append (State.Memory_Error_Value);
         State.Current.Failure := Nil_Value;
         State.Current.Has_Failure_Value := False;
         State.Current.Failure_Class := No_Failure;
         State.Current.Failure_Text := Null_Unbounded_String;
         return Result;
   end Advance;
end Lua.Engine.Loaders;
