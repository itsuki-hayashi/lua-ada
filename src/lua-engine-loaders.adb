with Ada.Containers;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Lua.Engine.Compiler;
with Lua.Sources;
with Lua_Ada_Config;

package body Lua.Engine.Loaders is
   use type Ada.Containers.Count_Type;
   use type Ada.Directories.File_Kind;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_IO.Count;

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action
   is
      Name : constant String := To_String (Activation.Native_Name);
      Result : Native_Action;
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Activation.Native_Arguments.Length)
         then Activation.Native_Arguments (Index) else Nil_Value);
      function Returned (Index : Positive) return Value is
        (if Index <= Natural (Activation.Native_Results.Length)
         then Activation.Native_Results (Index) else Nil_Value);
      function Is_Function (Item : Value) return Boolean is
        (Item.Kind in Closure_Kind | Native_Closure_Kind | Native_Kind_Value);
      function Bytes (Item : Value) return String;
      function Field (Table : Value; Key : String) return Value;
      function Package_Table return Value;
      procedure Work;
      function Read_File (Path : String) return String;
      function Read_Input return String;
      function Replace_All (Source, Pattern, Replacement : String)
                            return String;
      function Search_Path
        (Module_Name, Path, Separator, Replacement : String;
         Errors : out Unbounded_String) return String;
      function Compile_Source
        (Source, Chunk_Name, Mode : String; Environment : Value)
         return Values.Vector;
      function Call (Function_Value : Value; Args : Values.Vector)
                     return Native_Action;
      Package_Value, Item, Function_Value, Data, Environment : Value;
      Buffer, Errors, Chunk_Name, Mode : Unbounded_String;
      Directory_Separator : constant String :=
        (if Lua_Ada_Config.Alire_Host_OS = "windows" then "\" else "/");

      procedure Work is
      begin
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         State.Steps := State.Steps + 1;
      end Work;

      function Bytes (Item : Value) return String is
      begin
         if Item.Kind = String_Kind then
            return To_String (Item.Reference.Bytes);
         elsif Item.Kind in Integer_Kind | Real_Kind then
            return Image (Item);
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
         return Field ((Table_Kind, State.Globals), "package");
      end Package_Table;

      function Call (Function_Value : Value; Args : Values.Vector)
                     return Native_Action
      is
      begin
         return (Kind => Invoke, Function_Value => Function_Value,
                 Arguments => Args, others => <>);
      end Call;

      function Read_File (Path : String) return String is
         package Files renames Ada.Streams.Stream_IO;
         File : Files.File_Type;
      begin
         Files.Open (File, Files.In_File, Path);
         if Files.Size (File) > Files.Count (State.Bounds.Source_Bytes) then
            Files.Close (File);
            Fail (State, "source byte limit exceeded", Resource => True);
         end if;
         declare
            Data : Ada.Streams.Stream_Element_Array
              (1 .. Ada.Streams.Stream_Element_Offset (Files.Size (File)));
            Last : Ada.Streams.Stream_Element_Offset;
            Source : String (1 .. Data'Length);
         begin
            Files.Read (File, Data, Last);
            Files.Close (File);
            if Last /= Data'Last then
               raise Ada.Text_IO.End_Error with "short source read";
            end if;
            for Index in Source'Range loop
               Source (Index) := Character'Val
                 (Data (Ada.Streams.Stream_Element_Offset (Index)));
            end loop;
            return Source;
         end;
      exception
         when others =>
            if Files.Is_Open (File) then
               Files.Close (File);
            end if;
            raise;
      end Read_File;

      function Read_Input return String is
         Buffer : Unbounded_String;
         Byte : Character;
      begin
         while not Ada.Text_IO.End_Of_File loop
            Work;
            if Length (Buffer) >= State.Bounds.Source_Bytes then
               Fail (State, "source byte limit exceeded", Resource => True);
            end if;
            if Ada.Text_IO.End_Of_Line then
               Ada.Text_IO.Skip_Line;
               Append (Buffer, Character'Val (10));
            else
               Ada.Text_IO.Get (Byte);
               Append (Buffer, Byte);
            end if;
         end loop;
         return To_String (Buffer);
      end Read_Input;

      function Replace_All (Source, Pattern, Replacement : String)
                            return String
      is
         Result : Unbounded_String;
         First : Positive := Source'First;
         Found : Natural;
      begin
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
         Errors : out Unbounded_String) return String
      is
         Converted : constant String :=
           Replace_All (Module_Name, Separator, Replacement);
         First : Positive := Path'First;
         Last : Natural;
      begin
         Errors := Null_Unbounded_String;
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
         Results : Values.Vector;
         Code : Prototype_Access;
         Scope : Object_Access;
         Saved_Text : constant Unbounded_String := State.Current.Failure_Text;
         Saved_Value : constant Value := State.Current.Failure;
         Saved_Has_Value : constant Boolean := State.Current.Has_Failure_Value;
         Saved_At : constant Lua.Lexers.Source_Location :=
           State.Current.Failure_At;
         Saved_Syntax : constant Boolean := State.Current.Is_Syntax;
         Saved_Unsupported : constant Boolean := State.Current.Is_Unsupported;
         Saved_Resource : constant Boolean := State.Current.Is_Resource;
         procedure Restore;
         procedure Restore is
         begin
            State.Current.Failure_Text := Saved_Text;
            State.Current.Failure := Saved_Value;
            State.Current.Has_Failure_Value := Saved_Has_Value;
            State.Current.Failure_At := Saved_At;
            State.Current.Is_Syntax := Saved_Syntax;
            State.Current.Is_Unsupported := Saved_Unsupported;
            State.Current.Is_Resource := Saved_Resource;
         end Restore;
      begin
         --  Mode filtering precedes compilation. A binary-capable mode does
         --  not establish binary chunk support; report that boundary plainly.
         if Source'Length > 0 and then Source (Source'First) =
           Character'Val (27)
         then
            Results.Append (Nil_Value);
            Results.Append
              (New_String (State, "binary chunks are unsupported"));
            return Results;
         elsif Ada.Strings.Fixed.Index (Mode, "t") = 0 then
            Results.Append (Nil_Value);
            Results.Append (New_String
              (State, "attempt to load a text chunk (mode is '" & Mode &
               "')"));
            return Results;
         end if;
         --  Dynamic compilation belongs to this execution's work budget.
         --  Per-source limits alone allow a reader/loop to repeatedly scan
         --  a large retained string at effectively constant VM cost.
         if Source'Length > State.Bounds.Instructions - Natural'Min
           (State.Steps, State.Bounds.Instructions)
         then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         State.Steps := State.Steps + Source'Length;
         begin
            State.Current.Is_Syntax := False;
            State.Current.Is_Unsupported := False;
            State.Current.Is_Resource := False;
            Code := Compiler.Compile (State, Source, Chunk_Name);
         exception
            when Language_Error =>
               if State.Current.Is_Resource then
                  raise;
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
         Declare_Local (Scope, Code.Environment_Symbol, Environment);
         Results.Append (New_Closure (State, Code, Scope));
         return Results;
      end Compile_Source;
   begin
      Work;
      if Name in "base.load" | "load" then
         if Activation.Native_Stage = 0 then
            --  Validate host-independent options before requesting a reader.
            --  An invalid mode/name must not run user callbacks as a side
            --  effect before raising its argument error.
            Mode := (if Arg (3).Kind = Nil_Kind then
                        To_Unbounded_String ("bt")
                     else To_Unbounded_String (Bytes (Arg (3))));
            if Arg (2).Kind /= Nil_Kind then
               Chunk_Name := To_Unbounded_String (Bytes (Arg (2)));
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
                            Values.To_Vector (Arg (1), 1));
            end if;
            Activation.Native_Buffer := To_Unbounded_String (Bytes (Arg (1)));
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
                  Part : constant String := Bytes (Item);
               begin
                  if Part'Length > State.Bounds.Source_Bytes -
                    Length (Activation.Native_Buffer)
                  then
                     Fail (State, "source byte limit exceeded",
                           Resource => True);
                  end if;
                  if Part'Length > 0 then
                     Append (Activation.Native_Buffer, Part);
                     return Call ((Native_Kind_Value, Pcall_Function),
                                  Values.To_Vector (Arg (1), 1));
                  end if;
               end;
            end if;
         end if;
         Chunk_Name := (if Arg (2).Kind = Nil_Kind then
                          (if Is_Function (Arg (1)) then
                             To_Unbounded_String ("=(load)")
                           else Activation.Native_Buffer)
                        else To_Unbounded_String (Bytes (Arg (2))));
         Mode := (if Arg (3).Kind = Nil_Kind then To_Unbounded_String ("bt")
                  else To_Unbounded_String (Bytes (Arg (3))));
         Environment := (if Activation.Native_Arguments.Length >= 4
                         then Arg (4) else (Table_Kind, State.Globals));
         Result.Results := Compile_Source
           (To_String (Activation.Native_Buffer), To_String (Chunk_Name),
            To_String (Mode), Environment);
      elsif Name in "base.loadfile" | "loadfile" | "base.dofile" | "dofile"
      then
         if Activation.Native_Stage = 1 then
            Result.Results := Activation.Native_Results;
            return Result;
         end if;
         begin
            Buffer := To_Unbounded_String
              (if Arg (1).Kind = Nil_Kind then
                 Lua.Sources.File_Preamble (Read_Input)
               else Lua.Sources.File_Preamble (Read_File (Bytes (Arg (1)))));
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
         Chunk_Name := (if Arg (1).Kind = Nil_Kind then
                          To_Unbounded_String ("stdin")
                        else To_Unbounded_String (Bytes (Arg (1))));
         Mode := (if Name in "base.dofile" | "dofile" or else
                    Arg (2).Kind = Nil_Kind
                  then To_Unbounded_String ("bt")
                  else To_Unbounded_String (Bytes (Arg (2))));
         Environment := (if Name not in "base.dofile" | "dofile" and then
                            Activation.Native_Arguments.Length >= 3
                         then Arg (3) else (Table_Kind, State.Globals));
         Result.Results := Compile_Source
           (To_String (Buffer), To_String (Chunk_Name), To_String (Mode),
            Environment);
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
               Result.Results.Append (New_String (State, To_String (Errors)));
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
               Result.Results.Append (New_String (State, To_String (Errors)));
            else
               begin
                  Result.Results := Compile_Source
                    (Lua.Sources.File_Preamble (Read_File (Path)), Path, "t",
                     (Table_Kind, State.Globals));
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
            Activation.Native_Captures.Append (Package_Value);
            Activation.Native_Captures.Append (Item);
            Activation.Native_Buffer := To_Unbounded_String
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
            return Call (Function_Value, Values.To_Vector (Item, 1));
         elsif Activation.Native_Stage = 2 then
            Function_Value := Returned (1);
            if Is_Function (Function_Value) then
               Data := Returned (2);
               Activation.Native_Captures.Append (Data);
               Activation.Native_Stage := 3;
               declare
                  Args : Values.Vector;
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
   end Advance;
end Lua.Engine.Loaders;
