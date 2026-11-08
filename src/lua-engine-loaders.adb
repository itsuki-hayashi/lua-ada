with Lua.Diagnostic_Text;
with Ada.Containers;
with Ada.Finalization;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Lua.Engine.Compiler;
with Lua.Engine.Call_Names;
with Lua.Engine.Inspection;
with Lua.Engine.Native_Modules;
with Lua.Engine.File_Inputs;
with Lua.Engine.Stacks;
with System;
with Lua.Storage.Buffers;
with Lua_Ada_Config;

package body Lua.Engine.Loaders is
   package Managed renames Lua.Storage.Buffers;
   use type Ada.Containers.Count_Type;
   use type Ada.Exceptions.Exception_Id;
   use type Ada.Directories.File_Kind;
   use type Native_Modules.Failure_Stage;
   use type File_Inputs.Outcome;

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action
   is
      Name : constant String := Native_Operation_Name (Activation);
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
      function C_Bytes (Item : Value) return String;
      procedure Check_String_Argument (Index : Positive);
      function Field (Table : Value; Key : String) return Value;
      function Package_Table return Value;
      procedure Work;
      procedure Read_File (Path : String; Output : in out Managed.Buffer);
      procedure Read_Input (Output : in out Managed.Buffer);
      procedure Prepare_File (Source : in out Managed.Buffer);
      procedure Copy_Bytes
        (Item : Value; Output : in out Managed.Buffer; Appending : Boolean);
      procedure Copy_Option
        (Index : Positive; Output : in out Managed.Buffer);
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
      procedure Load_C_Module
        (Path, Module_Name : String; Handler : out Value;
         Stage : out Native_Modules.Failure_Stage);
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

      procedure Load_C_Module
        (Path, Module_Name : String; Handler : out Value;
         Stage : out Native_Modules.Failure_Stage)
      is
         Converted, Symbol : Managed.Buffer;
         Mark : Natural := 0;

         procedure Lookup (Text : String);
         procedure Lookup (Text : String) is
         begin
            Native_Modules.Resolve (State, Path, Text, Handler, Errors, Stage);
         end Lookup;
      begin
         Converted.Set_Owner (Lua.Storage.Reference (State.Memory));
         Symbol.Set_Owner (Lua.Storage.Reference (State.Memory));
         for Byte of Module_Name loop
            Work;
            exit when Byte = Character'Val (0);
            Converted.Append ((if Byte = '.' then '_' else Byte));
            if Byte = '-' and then Mark = 0 then
               Mark := Converted.Length;
            end if;
         end loop;
         --  Resolve the prefix before an ignore mark first. Only a missing
         --  entry symbol tries the historical suffix spelling; a failed
         --  library open is an actual loader error and must not be retried.
         if Mark /= 0 then
            Symbol.Set_Value ("luaopen_");
            for Index in 1 .. Mark - 1 loop
               Symbol.Append (Converted.Element (Index));
            end loop;
            Symbol.Query (Lookup'Access);
            if Stage /= Native_Modules.Symbol_Failed then return; end if;
         end if;
         Symbol.Set_Value ("luaopen_");
         for Index in Mark + 1 .. Converted.Length loop
            Symbol.Append (Converted.Element (Index));
         end loop;
         Symbol.Query (Lookup'Access);
      end Load_C_Module;

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

      function C_Bytes (Item : Value) return String is
         Size : Natural := 0;
      begin
         if Item.Kind /= String_Kind then return Bytes (Item); end if;
         declare
            Text : constant String (1 .. Length (Item.Reference.Bytes))
              with Import, Address => Item.Reference.Bytes.Address;
         begin
            --  Package names, paths and symbols use the pinned C-string
            --  interfaces. Counted load source and reader results still use
            --  Copy_Bytes and must retain embedded zero bytes.
            for Byte of Text loop
               Work;
               exit when Byte = Character'Val (0);
               Size := Size + 1;
            end loop;
            return Text (1 .. Size);
         end;
      end C_Bytes;

      procedure Check_String_Argument (Index : Positive) is
         use type Call_Names.Name_Kind;
         Identity : Call_Names.Borrowed_Identity;
         Position : Natural := Index;
         Extra : Boolean;
         Label, Detail : Owned_Buffer;
         Meta : Object_Access;
         Type_Label : Value := Nil_Value;
      begin
         if Arg (Index).Kind in String_Kind | Integer_Kind | Real_Kind then
            return;
         end if;
         Label.Set_Owner (Lua.Storage.Reference (State.Memory));
         Detail.Set_Owner (Lua.Storage.Reference (State.Memory));
         Identity := Call_Names.View_From_Caller
           (State, Inspection.Caller_Frame
              (State, State.Current, Activation));
         Label.Set_Value
           ((if Identity.Kind = Call_Names.Unknown then Name
             else Call_Names.Name_Image (Identity)));
         Meta := Raw_Metatable (State, Arg (Index));
         if Meta /= null then
            Type_Label := Get
              ((Table_Kind, Meta), New_String (State, "__name"));
         end if;
         Detail.Set_Value ("string expected, got ");
         Detail.Append
           ((if Type_Label.Kind = String_Kind then C_Bytes (Type_Label)
             elsif Index > Natural (Activation.Native_Arguments.Length)
             then "no value"
             elsif Arg (Index).Kind = Light_Identity_Kind
             then "light userdata" else Type_Name (Arg (Index))));
         --  Match auxiliary diagnostics using the actual call origin,
         --  including __call's prepended values and colon-call self.
         Extra := Index <= Activation.Call_Metamethod_Count;
         if not Extra then
            Position := Index - Activation.Call_Metamethod_Count;
            if Identity.Kind = Call_Names.Method_Call then
               Position := Position - 1;
               if Position = 0 then
                  Fail (State, "calling '" & To_String (Label) &
                    "' on bad self (" & To_String (Detail) & ")");
               end if;
            end if;
         end if;
         Fail (State, "bad " &
           (if Extra then "extra argument #" else "argument #") &
           Ada.Strings.Fixed.Trim (Position'Image, Ada.Strings.Both) &
           " to '" & To_String (Label) & "' (" & To_String (Detail) & ")");
      end Check_String_Argument;

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
         Filename : Managed.Buffer;
         Observed : File_Inputs.Result;
         Terminator : constant Natural := Ada.Strings.Fixed.Index
           (Path, "" & Character'Val (0));
         Last : constant Natural :=
           (if Terminator = 0 then Path'Last else Terminator - 1);
      begin
         Filename.Set_Owner (Lua.Storage.Reference (State.Memory));
         Filename.Set_Value (Path);
         File_Inputs.Read_All
           (State, Filename.C_Address, Output, Observed);
         if Observed.Status /= File_Inputs.Ready then
            raise Ada.Text_IO.Name_Error with
              File_Inputs.Message (Observed, Path (Path'First .. Last));
         end if;
      end Read_File;

      procedure Read_Input (Output : in out Managed.Buffer) is
         Observed : File_Inputs.Result;
      begin
         File_Inputs.Read_All (State, System.Null_Address, Output, Observed);
         if Observed.Status /= File_Inputs.Ready then
            raise Ada.Text_IO.Use_Error with
              File_Inputs.Message (Observed, "stdin");
         end if;
      end Read_Input;

      procedure Prepare_File (Source : in out Managed.Buffer) is
      begin
         File_Inputs.Prepare (Source);
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

      procedure Copy_Option
        (Index : Positive; Output : in out Managed.Buffer)
      is
         Item : Value := Arg (Index);
      begin
         if Item.Kind in Integer_Kind | Real_Kind then
            --  luaL_optstring coerces the actual name/mode argument, not
            --  just a private option copy. Reader callbacks can inspect or
            --  replace these same C cells before the parser completes.
            Item := New_String (State, Bytes (Item));
            Replace_Root (State, Activation.Native_Arguments, Index, Item);
            Stacks.Write
              (State, Activation.Context, Activation.Stack_Base + Index,
               Item);
         end if;
         Copy_Bytes (Item, Output, False);
      end Copy_Option;

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
         --  Empty templates are skipped for opening, but remain in the
         --  original path used by Lua's diagnostic. This includes a final
         --  separator and the completely empty path (loadlib.c searchpath).
         loop
            Work;
            Last := First;
            while Last <= Path'Last and then Path (Last) /= ';' loop
               Last := Last + 1;
            end loop;
            declare
               File : constant String := Replace_All
                 (Path (First .. Last - 1), "?", Converted);
               Readable : Boolean := False;
               Handle : Ada.Streams.Stream_IO.File_Type;
            begin
               --  Opening is the test: existence alone does not establish
               --  readability, and directories are not Lua source files.
               begin
                  if File'Length /= 0 and then
                    Ada.Directories.Exists (File) and then
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
               if not Errors.Is_Empty then
                  Append (Errors, Character'Val (10) & Character'Val (9));
               end if;
               Append (Errors, "no file '" & File & "'");
            end;
            exit when Last > Path'Last;
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
         function Prefix_Last (Bytes : String) return Natural;
         function Prefix_Last (Bytes : String) return Natural is
            Terminator : Natural;
         begin
            --  Name/mode are C options even though their Lua values contain
            --  counted bytes. Charge the scan, then borrow the prefix rather
            --  than materializing another input-sized ordinary String.
            Diagnostic_Work (State, Bytes'Length);
            Terminator := Ada.Strings.Fixed.Index
              (Bytes, "" & Character'Val (0));
            return (if Terminator = 0 then Bytes'Last else Terminator - 1);
         end Prefix_Last;
         Label : String renames Chunk_Name
           (Chunk_Name'First .. Prefix_Last (Chunk_Name));
         Flags : String renames Mode (Mode'First .. Prefix_Last (Mode));
         --  Lua load's name is a C string, even though its source is counted
         --  bytes. Borrow the prefix without copying/truncating the source.
         Saved_Text : constant Lua.Diagnostic_Text.Text :=
           State.Current.Failure_Text;
         Saved_Value : constant Value := State.Current.Failure;
         Saved_Has_Value : constant Boolean := State.Current.Has_Failure_Value;
         Saved_At : constant Lua.Lexers.Source_Location :=
           State.Current.Failure_At;
         Saved_Class : constant Failure_Kind := State.Current.Failure_Class;
         Saved_Captures : constant Ada.Containers.Count_Type :=
           Activation.Native_Captures.Length;
         type Saved_Error_Root is new Ada.Finalization.Limited_Controlled with
         record
            Registered : Boolean := False;
         end record;
         overriding procedure Finalize (Self : in out Saved_Error_Root);
         overriding procedure Finalize (Self : in out Saved_Error_Root) is
         begin
            if Self.Registered then
               --  Compilation never executes this loader's continuation.
               --  Its one temporary capture remains the last owned slot;
               --  remove it on every return, refusal or host-abort path.
               if Activation.Native_Captures.Length = Saved_Captures + 1 then
                  Activation.Native_Captures.Delete_Last;
               end if;
               --  Restore checks normal-path ownership. During exceptional
               --  unwinding, never replace the original host stop/refusal
               --  with a finalizer exception. An unexpected capture layout
               --  remains owned by the departing frame's ordinary cleanup.
               Self.Registered := False;
            end if;
         end Finalize;
         Saved_Root : Saved_Error_Root;
         procedure Restore;
         procedure Restore is
         begin
            State.Current.Failure_Text := Saved_Text;
            State.Current.Failure := Saved_Value;
            State.Current.Has_Failure_Value := Saved_Has_Value;
            if Saved_Has_Value then
               if not Saved_Root.Registered or else
                 Activation.Native_Captures.Length /= Saved_Captures + 1
               then
                  raise Program_Error with "saved error lost its root";
               end if;
               Root_Barrier (State, Saved_Value);
            end if;
            State.Current.Failure_At := Saved_At;
            State.Current.Failure_Class := Saved_Class;
         end Restore;
      begin
         if Saved_Has_Value then
            --  A local Value is not a tracing root. Preserve the original
            --  error while compilation replaces context failure state and
            --  can collect, then transfer ownership back before this guard
            --  removes its actual activation capture. Shared text copies
            --  alone must not conceal a collected original error identity.
            Append_Root (State, Activation.Native_Captures, Saved_Value);
            Saved_Root.Registered := True;
         end if;
         --  The signature selects binary versus text before parsing. Mode
         --  filtering applies to that selection even for a malformed chunk;
         --  allowed binary input then uses the same owned codec as C loading.
         Diagnostic_Work (State, Flags'Length);
         declare
            Binary : constant Boolean := Source'Length > 0 and then
              Source (Source'First) = Character'Val (27);
            Accepted : constant Boolean := Ada.Strings.Fixed.Index
              (Flags, (if Binary then "b" else "t")) /= 0;
         begin
            if not Accepted then
               declare
                  Message : Managed.Buffer;
               begin
                  Message.Set_Owner (Lua.Storage.Reference (State.Memory));
                  Message.Append ("attempt to load a ");
                  Message.Append ((if Binary then "binary" else "text"));
                  Message.Append (" chunk (mode is '");
                  Diagnostic_Work (State, Flags'Length);
                  Message.Append (Flags);
                  Message.Append ("')");
                  Diagnostic_Work (State, Message.Length);
                  Diagnostic_Work (State, Message.Length);
                  Results.Append (Nil_Value);
                  Results.Append (New_String (State, Message));
               end;
               Restore;
               return Results;
            end if;
         end;
         --  Dynamic compilation belongs to this execution's work budget.
         --  Per-source limits alone allow a reader/loop to repeatedly scan
         --  a large retained string at effectively constant VM cost.
         if State.Policy = Bounded and then
           Source'Length > State.Bounds.Instructions - Natural'Min
             (State.Steps, State.Bounds.Instructions)
         then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         if State.Policy = Bounded then
            State.Steps := State.Steps + Source'Length;
         end if;
         begin
            State.Current.Failure_Class := No_Failure;
            Code := Compiler.Compile (State, Source, Label);
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
                  Display_Name : constant String :=
                    Inspection.Short_Source (Label);
                  --  luaG_addinfo uses the same bounded chunk identifier as
                  --  debug records. A default string-load name is source
                  --  text, not an unquoted file path or a synthetic label.
                  Message : Managed.Buffer;
                  procedure Append_Diagnostic (Bytes : String);
                  procedure Publish_Message (Bytes : String);
                  procedure Append_Diagnostic (Bytes : String) is
                  begin
                     Diagnostic_Work (State, Bytes'Length);
                     Message.Append (Bytes);
                  end Append_Diagnostic;
                  procedure Publish_Message (Bytes : String) is
                  begin
                     Diagnostic_Work (State, Bytes'Length);
                     Diagnostic_Work (State, Bytes'Length);
                     Results.Append (New_String (State, Bytes));
                  end Publish_Message;
               begin
                  Message.Set_Owner (Lua.Storage.Reference (State.Memory));
                  if State.Current.Failure_Class = Syntax_Failure then
                     Message.Append (Display_Name);
                     Message.Append (":");
                     Message.Append (Ada.Strings.Fixed.Trim
                       (State.Current.Failure_At.Line'Image,
                        Ada.Strings.Both));
                     Message.Append (": ");
                  end if;
                  --  Pending syntax text is already managed. Borrow it into
                  --  the destination builder, avoiding concatenation through
                  --  an input-sized ordinary Ada String during error handling.
                  Lua.Diagnostic_Text.Query
                    (State.Current.Failure_Text, Append_Diagnostic'Access);
                  Restore;
                  Results.Append (Nil_Value);
                  Message.Query (Publish_Message'Access);
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
               Copy_Option (3, Mode);
            end if;
            Validate_Mode;
            if Arg (2).Kind /= Nil_Kind then
               Copy_Option (2, Chunk_Name);
            end if;
            if Is_Function (Arg (1)) or else
              Arg (1).Kind not in String_Kind | Integer_Kind | Real_Kind
            then
               --  Unlike ordinary calls, load requires a function value.
               --  A table with __call is deliberately not a reader here.
               if not Is_Function (Arg (1)) then
                  Fail (State, "bad argument #1 to load (function expected)");
               end if;
               if Arg (2).Kind = Nil_Kind then
                  Chunk_Name.Set_Value ("=(load)");
               end if;
               --  The protected parser can return nil/error after a reader
               --  has permanently refused provider growth. Reserve this
               --  actual C completion packet before entering user code;
               --  constructing it after guard acknowledgement would turn
               --  load's protected memory result into an outer call error.
               Activation.Native_Results.Reserve_Capacity
                 (Ada.Containers.Count_Type (2 + Activation.Protection));
               --  The current activation owns these immutable C strings
               --  throughout every reader callback. The actual streaming
               --  parser starts only after Step returns to its C guard;
               --  a generic reader never jumps through a live Ada parser.
               Activation.Native_Buffer.Clear;
               Activation.Native_Buffer.Append (Chunk_Name);
               Activation.Native_Buffer.Append (ASCII.NUL);
               Activation.Load_Reader_Mode_Offset :=
                 Activation.Native_Buffer.Length;
               Activation.Native_Buffer.Append (Mode);
               Activation.Native_Buffer.Append (ASCII.NUL);
               Activation.Load_Reader_Arguments :=
                 Natural (Activation.Native_Arguments.Length);
               Result.Kind := Start_Reader_Portal;
               return Result;
            end if;
            Copy_Bytes (Arg (1), Activation.Native_Buffer, False);
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
         --  luaB_loadfile validates its optional filename before its mode,
         --  then opens the file. dofile validates only the filename and
         --  ignores later arguments. Nil retains the stdin path; numeric
         --  names still use the existing string coercion/copy below.
         if Arg (1).Kind /= Nil_Kind then Check_String_Argument (1); end if;
         if Name in "base.loadfile" | "loadfile" and then
           Arg (2).Kind /= Nil_Kind
         then
            Check_String_Argument (2);
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
            Chunk_Name.Set_Value ("=stdin");
         else
            --  A filename is debug source identity, not a source snippet.
            --  Keep Lua's marker in the prototype; only display formatting
            --  removes it when constructing a diagnostic prefix.
            Chunk_Name.Append ('@');
            Copy_Bytes (Arg (1), Chunk_Name, True);
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
         Check_String_Argument (1);
         Check_String_Argument (2);
         if Arg (3).Kind /= Nil_Kind then Check_String_Argument (3); end if;
         if Arg (4).Kind /= Nil_Kind then Check_String_Argument (4); end if;
         declare
            Path : constant String := Search_Path
              (C_Bytes (Arg (1)), C_Bytes (Arg (2)),
               (if Arg (3).Kind = Nil_Kind then "." else C_Bytes (Arg (3))),
               (if Arg (4).Kind = Nil_Kind then Directory_Separator
                else C_Bytes (Arg (4))), Errors);
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
         Check_String_Argument (1);
         Item := Get ((Table_Kind, State.Preload_Modules),
                      New_String (State, C_Bytes (Arg (1))));
         if Item.Kind = Nil_Kind then
            Result.Results.Append (New_String (State,
              "no field package.preload['" & C_Bytes (Arg (1)) & "']"));
         else
            Result.Results.Append (Item);
            Result.Results.Append (New_String (State, ":preload:"));
         end if;
      elsif Name in "package.lua_searcher" | "package.searcher_lua" then
         Check_String_Argument (1);
         Package_Value := Package_Table;
         if Field (Package_Value, "path").Kind not in String_Kind |
           Integer_Kind | Real_Kind
         then
            Fail (State, "'package.path' must be a string");
         end if;
         declare
            Path : constant String := Search_Path
              (C_Bytes (Arg (1)), C_Bytes (Field (Package_Value, "path")), ".",
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
                    (Buffer, "@" & Path, "bt",
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
      elsif Name = "package.loadlib" then
         Check_String_Argument (1);
         Check_String_Argument (2);
         declare
            Stage : Native_Modules.Failure_Stage;
         begin
            Native_Modules.Resolve
              (State, Bytes (Arg (1)), Bytes (Arg (2)),
               Function_Value, Errors, Stage);
            if Stage = Native_Modules.Loaded then
               Result.Results.Append (Function_Value);
            else
               Result.Results.Append (Nil_Value);
               Result.Results.Append
                 ((if Errors.Is_Empty then Nil_Value
                   else New_String (State, Errors)));
               Result.Results.Append (New_String
                 (State, (if Stage = Native_Modules.Open_Failed
                          then "open" else "init")));
            end if;
         end;
      elsif Name in "package.c_searcher" | "package.croot_searcher" then
         Check_String_Argument (1);
         Package_Value := Package_Table;
         declare
            Module_Name : constant String := C_Bytes (Arg (1));
            Root_End : Natural := Module_Name'Last;
            Root_Found : Boolean := False;
            Root_Search : constant Boolean := Name = "package.croot_searcher";
            Stage : Native_Modules.Failure_Stage;
            Search_Path_Value : constant Value := Field
              (Package_Value, "cpath");
         begin
            if Root_Search then
               Root_End := 0;
               for Index in Module_Name'Range loop
                  Work;
                  exit when Module_Name (Index) = Character'Val (0);
                  if Module_Name (Index) = '.' then
                     Root_Found := True;
                     Root_End := Index - 1;
                     exit;
                  end if;
               end loop;
               if not Root_Found then return Result; end if;
            end if;
            if Search_Path_Value.Kind not in String_Kind | Integer_Kind |
              Real_Kind
            then
               Fail (State, "'package.cpath' must be a string");
            end if;
            declare
               Path : constant String := Search_Path
                 (Module_Name (Module_Name'First .. Root_End),
                  C_Bytes (Search_Path_Value), ".", Directory_Separator,
                  Errors);
            begin
               if Path'Length = 0 then
                  Result.Results.Append (New_String (State, Errors));
               else
                  Load_C_Module (Path, Module_Name, Function_Value, Stage);
                  if Stage = Native_Modules.Loaded then
                     Result.Results.Append (Function_Value);
                     Result.Results.Append (New_String (State, Path));
                  elsif Root_Search and then
                    Stage = Native_Modules.Symbol_Failed
                  then
                     Result.Results.Append (New_String
                       (State, "no module '" & Module_Name & "' in file '" &
                        Path & "'"));
                  else
                     Fail (State, "error loading module '" & Module_Name &
                       "' from file '" & Path & "':" & Character'Val (10) &
                       Character'Val (9) & To_String (Errors));
                  end if;
               end if;
            end;
         end;
      elsif Name in "base.require" | "require" then
         if Activation.Native_Stage = 0 then
            Package_Value := Package_Table;
            Check_String_Argument (1);
            Item := New_String (State, C_Bytes (Arg (1)));
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
            Data := Field (Package_Value, "searchers");
            if Data.Kind /= Table_Kind then
               Fail (State, "'package.searchers' must be a table");
            end if;
            Append_Root (State, Activation.Native_Captures, Data);
            --  findloader passes the C-string spelling to each searcher,
            --  while ll_require later passes its original counted name to
            --  the selected loader. Keep those distinct for embedded zeroes.
            Append_Root (State, Activation.Native_Captures,
              (if Arg (1).Kind = String_Kind then Arg (1)
               else New_String (State, Bytes (Arg (1)))));
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
            Function_Value := Get
              (Activation.Native_Captures (3),
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
                  Args.Append (Activation.Native_Captures (4));
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
               Append (Activation.Native_Buffer,
                       Character'Val (10) & Character'Val (9));
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
            Result.Results.Append (Activation.Native_Captures (5));
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
         Lua.Diagnostic_Text.Clear (State.Current.Failure_Text);
         return Result;
   end Advance;
end Lua.Engine.Loaders;
