with Ada.Containers;
with Ada.Unchecked_Conversion;
with Interfaces;
with Interfaces.C;
with Lua.Engine.File_Resources;
with Lua.Engine.Diagnostics;
with Lua.Engine.Machine;
with Lua.Engine.Strings;
with Lua.Engine.System_Results;
with Lua.Engine.Tables;
with Lua.Numbers;
with Lua.Platform_Locales;
with Lua.Platform_Streams;
with Lua.Runtime_Configuration;
with Lua.Storage.Buffers;
with Lua_Ada_Config;
with System;

package body Lua.Engine.IO_Libraries is
   package C renames Interfaces.C;
   package Files renames Lua.Engine.File_Resources;
   package Streams renames Lua.Platform_Streams;
   package Managed renames Lua.Storage.Buffers;
   package Locales renames Lua.Platform_Locales;
   use type Ada.Containers.Count_Type;
   use type C.int;
   use type C.size_t;
   use type Integer_Value;
   use type Real_Value;
   use type Interfaces.Unsigned_64;
   use type Foreign.C_Function;
   use type Foreign.IO_Close_Kind;
   use type Streams.Handle;
   use type Lua.Numbers.Number_Kind;
   use type System.Address;

   function Function_Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   function Signed_Total is new Ada.Unchecked_Conversion
     (Interfaces.Unsigned_64, Integer_Value);
   function Signed_Native_Int is new Ada.Unchecked_Conversion
     (C.unsigned, C.int);
   function Windows_Host
     (Host : String := Lua_Ada_Config.Alire_Host_OS) return Boolean is
     (Host = "windows");

   procedure Work (State : in out World);
   function File_Argument (State : in out World; Item : Value;
                           Opened : Boolean := True) return Value;

   procedure Work (State : in out World) is
   begin
      if State.Steps >= State.Bounds.Instructions then
         Fail (State, "instruction limit exceeded", Resource => True);
      elsif State.Policy = Bounded then
         State.Steps := State.Steps + 1;
      end if;
   end Work;

   function File_Argument (State : in out World; Item : Value;
                           Opened : Boolean := True) return Value is
   begin
      if not Files.Is_File (State, Item) then
         Diagnostics.Type_Error (State, 1, "FILE*", Item);
      elsif Opened and then Files.Header (Item).Closer = null then
         Fail (State, "attempt to use a closed file");
      elsif Opened and then Files.Header (Item).File = Streams.No_Stream then
         --  A user __gc can resurrect an unsuccessful native-open prefile.
         --  Its C-visible state is retained, but do not dereference null FILE.
         Fail (State, "attempt to use an incompletely opened file");
      end if;
      return Item;
   end File_Argument;

   function Close_Primitive
     (State : in out World; Item : Value; Kind : Foreign.IO_Close_Kind)
      return Values.Vector
   is
      Checked : constant Value := File_Argument (State, Item, False);
      Native_Kind : constant Files.File_Kind :=
        (case Kind is
            when Foreign.Regular_File_Close => Files.Regular_File,
            when Foreign.Pipe_File_Close => Files.Pipe_File,
            when Foreign.Borrowed_File_Close => Files.Borrowed_File);
      Status, Error : C.int;
      Result : Values.Vector := Owned_Values (State);
   begin
      --  This is also the C trampoline's op49 path. No Lua call is made:
      --  aux_close's current native activation remains the visible frame.
      Files.Close_Native
        (Checked, Native_Kind, Foreign.IO_Close_Handler (Kind), Status, Error);
      if Kind = Foreign.Borrowed_File_Close then
         Result.Reserve_Capacity (2);
         Result.Append (Nil_Value);
         Result.Append (New_String (State, "cannot close standard file"));
         return Result;
      elsif Kind = Foreign.Pipe_File_Close then
         return System_Results.Process_Result (State, Status, Error);
      else
         return System_Results.File_Result (State, Status = 0, Error);
      end if;
   end Close_Primitive;

   function Open_Module (State : in out World) return Value is
      Module, Metatable, Methods : Value;
      procedure Field (Table : Value; Key : String; Item : Value);
      procedure Exports (Table : Value; Prefix, Names : String);
      procedure Standard
        (Which : Streams.Standard_Stream; Name : String;
         Registry_Key : String := "");

      procedure Field (Table : Value; Key : String; Item : Value) is
      begin
         Pin (State, Item);
         Set (State, Table, New_String (State, Key), Item);
      end Field;

      procedure Exports (Table : Value; Prefix, Names : String) is
         First : Positive := Names'First;
         Last : Natural;
      begin
         while First <= Names'Last loop
            Last := First;
            while Last < Names'Last and then Names (Last + 1) /= ' ' loop
               Last := Last + 1;
            end loop;
            Field (Table, Names (First .. Last),
                   New_Native (State, Prefix & Names (First .. Last)));
            First := Last + 2;
         end loop;
      end Exports;

      procedure Standard
        (Which : Streams.Standard_Stream; Name : String;
         Registry_Key : String := "")
      is
         Item : constant Value :=
           Files.New_Closed (State, Files.Borrowed_File);
      begin
         Files.Publish
           (Item, Streams.Standard (Which),
            Foreign.IO_Close_Handler (Foreign.Borrowed_File_Close));
         Field (Module, Name, Item);
         if Registry_Key'Length > 0 then
            Field ((Table_Kind, State.Foreign_Registry), Registry_Key, Item);
         end if;
      end Standard;
   begin
      --  Publish all roots before further library allocation. Real standard
      --  streams are borrowed, while defaults and metatable are per-world.
      Module := New_Table (State);
      Pin (State, Module);
      --  Like luaL_newmetatable, reopening preserves existing file identity.
      --  Old file objects must still satisfy checks against registry FILE*.
      Metatable := Tables.Raw_Field (State.Foreign_Registry, "FILE*");
      if Metatable.Kind = Nil_Kind then
         Metatable := New_Table (State);
      end if;
      Pin (State, Metatable);
      Methods := New_Table (State);
      Pin (State, Methods);
      Field ((Table_Kind, State.Foreign_Registry), "FILE*", Metatable);
      Field (Metatable, "__name", New_String (State, "FILE*"));
      Field (Metatable, "__index", Methods);
      Field (Metatable, "__gc", New_Native (State, "io.file.gc"));
      Field (Metatable, "__close", New_Native (State, "io.file.gc"));
      Field (Metatable, "__tostring", New_Native (State, "io.file.tostring"));
      Exports (Module, "io.",
               "close flush input lines open output popen read tmpfile " &
               "type write");
      Exports (Methods, "io.file.",
               "read write lines flush seek close setvbuf");
      Standard (Streams.Standard_Input, "stdin", "_IO_input");
      Standard (Streams.Standard_Output, "stdout", "_IO_output");
      Standard (Streams.Standard_Error, "stderr");
      return Module;
   end Open_Module;

   procedure Install (State : in out World) is
      Module : constant Value := Open_Module (State);
   begin
      Set (State, Global_Environment (State), New_String (State, "io"),
           Module);
      Set (State, (Table_Kind, State.Loaded_Modules),
           New_String (State, "io"), Module);
   end Install;

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action
   is
      Name : constant String := Native_Operation_Name (Activation);
      Result : Native_Action := New_Action (State);
      First_Text, Second_Text : Managed.Buffer;
      Item : Value;
      Error : aliased C.int := 0;
      Status : C.int;
      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Activation.Native_Arguments.Length) then
            Activation.Native_Arguments (Index) else Nil_Value);
      procedure Copy_Text (Value : Lua.Engine.Value;
                           Output : in out Managed.Buffer);
      function Default_File (Input : Boolean) return Value;
      function Open_File (Filename : Value; Mode : String;
                          Raising : Boolean) return Value;
      function Failure (Code : C.int; Include_Name : Boolean := False)
                        return Values.Vector;
      function Close (File : Value; Ignore_Result : Boolean := False)
                      return Native_Action;
      procedure Read_Formats
        (File : Value; Formats : Values.Vector; First : Positive;
         Last : Natural);
      procedure Write_Arguments (File : Value; First : Positive);
      procedure Iterator;

      procedure Copy_Text (Value : Lua.Engine.Value;
                           Output : in out Managed.Buffer) is
         procedure Copy (Text : String);
         procedure Copy (Text : String) is
         begin
            Managed.Set_Value (Output, Text);
         end Copy;
      begin
         Strings.Query_Argument (State, Value, Copy'Access);
      end Copy_Text;

      function Default_File (Input : Boolean) return Value is
         Key : constant String :=
           (if Input then "_IO_input" else "_IO_output");
         File : constant Value :=
           Tables.Raw_Field (State.Foreign_Registry, Key);
      begin
         if not Files.Is_File (State, File) then
            Fail (State, "invalid default IO file");
         elsif Files.Header (File).Closer = null then
            Fail (State, "default " & (if Input then "input" else "output") &
                  " file is closed");
         end if;
         return File;
      end Default_File;

      function Failure (Code : C.int; Include_Name : Boolean := False)
                        return Values.Vector
      is
         Packet : Values.Vector := Owned_Values (State);
         procedure Format (Filename : String);
         procedure Format (Filename : String) is
         begin
            Packet := System_Results.File_Result
              (State, False, Code, Filename, Include_Name);
         end Format;
      begin
         Managed.Query (First_Text, Format'Access);
         return Packet;
      end Failure;

      function Open_File (Filename : Value; Mode : String;
                          Raising : Boolean) return Value
      is
         File : Value;
         Mode_Text : constant String := Mode & Character'Val (0);
         Handle : Streams.Handle;
      begin
         Copy_Text (Filename, First_Text);
         File := Files.New_Closed (State, Files.Regular_File);
         Files.Prepare
           (File, Foreign.IO_Close_Handler (Foreign.Regular_File_Close));
         Handle := Streams.Open
           (Managed.C_Address (First_Text), Mode_Text'Address, Error'Access);
         if Handle = Streams.No_Stream then
            if Raising then
               --  Format the error only after preserving the actual errno.
               --  The raw prefile remains closed and owns no native handle.
               declare
                  Error_Packet : constant Values.Vector := Failure (Error);
                  procedure Raise_Open (Text : String);
                  procedure Raise_Open (Text : String) is
                  begin
                     Fail (State, "cannot open file '" & C_Option (Text) &
                           "' (" & To_String
                             (Error_Packet (2).Reference.Bytes) & ")");
                  end Raise_Open;
               begin
                  Managed.Query (First_Text, Raise_Open'Access);
               end;
            end if;
            return Nil_Value;
         end if;
         Files.Publish
           (File, Handle,
            Foreign.IO_Close_Handler (Foreign.Regular_File_Close));
         return File;
      end Open_File;

      function Close (File : Value; Ignore_Result : Boolean := False)
                      return Native_Action
      is
         View : constant Files.Header_Access := Files.Header (File);
         Handler : Foreign.C_Function;
         Packet : Values.Vector := Owned_Values (State);
         Answer : Native_Action := New_Action (State);
      begin
         if Activation.Native_Stage = 1 then
            if not Ignore_Result then
               Answer.Results := Activation.Native_Results;
            end if;
            return Answer;
         end if;
         if Ignore_Result and then
           (View.Closer = null or else View.File = Streams.No_Stream)
         then
            return Answer;
         end if;
         Handler := Files.Take_Closer (File);
         if Handler = null then
            Fail (State, "attempt to use a closed file");
         end if;
         for Kind in Foreign.IO_Close_Kind loop
            if Handler = Foreign.IO_Close_Handler (Kind) then
               Packet := Close_Primitive (State, File, Kind);
               if not Ignore_Result then
                  Values.Move (Answer.Results, Packet);
               end if;
               return Answer;
            end if;
         end loop;
         --  A C module may replace the public closef. Request that actual
         --  callback through the C-owned portal; never call its pointer while
         --  an Ada stack could be crossed by lua_error's nonlocal transfer.
         Activation.Native_Stage := 1;
         Answer.Kind := Invoke;
         Answer.Function_Value :=
           (Foreign_Function_Kind, Function_Address (Handler));
         Answer.Arguments := Activation.Native_Arguments;
         return Answer;
      end Close;

      procedure Read_Formats
        (File : Value; Formats : Values.Vector; First : Positive;
         Last : Natural)
      is
         Handle : constant Streams.Handle := Files.Header (File).File;
         Chunk_Size : constant Positive :=
           Lua.Runtime_Configuration.Auxiliary_Buffer_Bytes;
         Byte : C.int;
         Count : C.size_t;
         Succeeded : Boolean;
         Format_Count : constant Natural :=
           (if Last < First then 0 else Last - First + 1);
         function Read_One
           (Format : Value; Default_Format : Boolean := False) return Value;
         procedure Reserve (Additional : Natural);
         procedure Append_Read (Text : String);

         procedure Reserve (Additional : Natural) is
            Used : constant Natural := Managed.Length
              (Activation.Native_Buffer);
         begin
            if Additional > Natural'Last - Used then
               raise Lua.Storage.Allocation_Error;
            end if;
            Managed.Reserve_Capacity
              (Activation.Native_Buffer, Used + Additional);
         end Reserve;

         procedure Append_Read (Text : String) is
            Used : constant Natural :=
              Managed.Length (Activation.Native_Buffer);
         begin
            --  Capacity reservation does not imply a Lua string of that
            --  length: a tiny line must still fit a tiny logical byte quota.
            if State.Policy = Bounded and then
              (Used > State.Bounds.String_Bytes or else
                 Text'Length > State.Bounds.String_Bytes - Used)
            then
               Fail (State, "string byte limit exceeded", Resource => True);
            end if;
            Managed.Append (Activation.Native_Buffer, Text);
         end Append_Read;

         function Read_Number return Value;
         function Read_Number return Value is
            Numeral : String (1 .. 200);
            Used : Natural := 0;
            Current : C.int;
            Digit_Count : Natural := 0;
            Hexadecimal : Boolean := False;
            Overflow : Boolean := False;
            Parsed : Lua.Numbers.Number;
            function Consume return Boolean;
            function One_Of (First, Second : C.int) return Boolean;
            procedure Read_Digits (Hex : Boolean);

            function Consume return Boolean is
            begin
               if Used = Numeral'Length then
                  Overflow := True;
                  return False;
               end if;
               Used := Used + 1;
               Numeral (Used) := Character'Val (Current);
               Current := Streams.Get_Byte (Handle, Error'Access);
               return True;
            end Consume;

            function One_Of (First, Second : C.int) return Boolean is
            begin
               return (Current = First or else Current = Second) and then
                 Consume;
            end One_Of;

            procedure Read_Digits (Hex : Boolean) is
               Class : constant Locales.Character_Class :=
                 (if Hex then Locales.Hexadecimal else Locales.Decimal);
            begin
               while Current /= Streams.End_Marker and then
                 Locales.Matches (C.unsigned_char (Current), Class) /= 0
               loop
                  exit when not Consume;
                  Digit_Count := Digit_Count + 1;
               end loop;
            end Read_Digits;
         begin
            --  Bounded numeral lookahead is separate from the general line
            --  buffer. No allocation occurs while consuming its prefix, and
            --  precisely the first unaccepted byte is put back afterwards.
            loop
               Work (State);
               Current := Streams.Get_Byte (Handle, Error'Access);
               exit when Current = Streams.End_Marker or else
                 Locales.Matches
                   (C.unsigned_char (Current), Locales.Whitespace) = 0;
            end loop;
            if One_Of (Character'Pos ('-'), Character'Pos ('+')) then
               null;
            end if;
            if One_Of (Character'Pos ('0'), Character'Pos ('0')) then
               if One_Of (Character'Pos ('x'), Character'Pos ('X')) then
                  Hexadecimal := True;
               else
                  Digit_Count := 1;
               end if;
            end if;
            Read_Digits (Hexadecimal);
            if One_Of (C.int (Locales.Decimal_Point), Character'Pos ('.'))
            then
               Read_Digits (Hexadecimal);
            end if;
            if Digit_Count > 0 and then One_Of
              ((if Hexadecimal then Character'Pos ('p') else
                   Character'Pos ('e')),
               (if Hexadecimal then Character'Pos ('P') else
                   Character'Pos ('E')))
            then
               if One_Of (Character'Pos ('-'), Character'Pos ('+')) then
                  null;
               end if;
               Read_Digits (False);
            end if;
            Streams.Unread_Byte (Handle, Current);
            if Overflow then
               return Nil_Value;
            end if;
            Parsed := Lua.Engine.Read_Number (State, Numeral (1 .. Used));
            case Parsed.Kind is
               when Lua.Numbers.Integer_Number =>
                  return (Integer_Kind, Parsed.Integer_Item);
               when Lua.Numbers.Real_Number =>
                  return (Real_Kind, Parsed.Real_Item);
               when Lua.Numbers.Invalid => return Nil_Value;
            end case;
         end Read_Number;

         function Read_One
           (Format : Value; Default_Format : Boolean := False) return Value
         is
            Code : Character := 'l';
            Keep_Newline : Boolean := False;
            Numeric_Count : Integer_Value;
            Requested : Natural;
            Fixed : Boolean := False;
            All_Bytes : Boolean := False;
         begin
            Managed.Clear (Activation.Native_Buffer);
            Succeeded := True;
            if Format.Kind in Integer_Kind | Real_Kind then
               Numeric_Count := Strings.Integer_Argument (State, Format);
               --  size_t conversion is semantically unsigned. Negative
               --  counts exceed Lua's signed MAX_SIZE after that conversion;
               --  an exact MAX_SIZE request also leaves no terminating byte.
               --  Diagnose this mathematical limit before allocation quotas.
               if Numeric_Count < 0 or else
                 Numeric_Count = Integer_Value'Last
               then
                  Fail (State, "resulting string too large");
               elsif Numeric_Count > Integer_Value (Natural'Last)
               then
                  raise Lua.Storage.Allocation_Error;
               end if;
               Requested := Natural (Numeric_Count);
               Fixed := True;
            elsif not Default_Format then
               Copy_Text (Format, Second_Text);
               declare
                  Index : Positive := 1;
               begin
                  if Managed.Length (Second_Text) > 0 and then
                    Managed.Element (Second_Text, 1) = '*'
                  then
                     Index := 2;
                  end if;
                  if Index > Managed.Length (Second_Text) then
                     Fail (State, "invalid format");
                  end if;
                  --  The C interface dispatches on the first format byte;
                  --  suffixes are intentionally ignored, not overvalidated.
                  Code := Managed.Element (Second_Text, Index);
               end;
            end if;
            if Fixed then
               if Requested = 0 then
                  Byte := Streams.Get_Byte (Handle, Error'Access);
                  Streams.Unread_Byte (Handle, Byte);
                  Succeeded := Byte /= Streams.End_Marker;
               else
                  if State.Policy = Bounded and then
                    Requested > State.Bounds.String_Bytes
                  then
                     Fail (State, "string byte limit exceeded",
                           Resource => True);
                  end if;
                  Reserve (Requested);
                  Count := Streams.Read
                    (Handle, Managed.C_Address (Activation.Native_Buffer),
                     C.size_t (Requested), Error'Access);
                  declare
                     View : constant String (1 .. Natural (Count))
                       with Import,
                         Address => Managed.Address (Activation.Native_Buffer);
                  begin
                     Managed.Set_Value (Activation.Native_Buffer, View);
                  end;
                  Succeeded := Count > 0;
               end if;
            elsif Code = 'n' then
               return Read_Number;
            elsif Code in 'l' | 'L' | 'a' then
               Keep_Newline := Code = 'L';
               All_Bytes := Code = 'a';
               loop
                  Work (State);
                  Reserve (Chunk_Size);
                  if All_Bytes then
                     declare
                        Data : String (1 .. Chunk_Size);
                     begin
                        Count := Streams.Read
                          (Handle, Data'Address, C.size_t (Chunk_Size),
                           Error'Access);
                        Append_Read (Data (1 .. Natural (Count)));
                     end;
                     exit when Count < C.size_t (Chunk_Size);
                  else
                     for Index in 1 .. Chunk_Size loop
                        Byte := Streams.Get_Byte (Handle, Error'Access);
                        exit when Byte = Streams.End_Marker or else
                          Byte = Character'Pos (ASCII.LF);
                        Append_Read ([Character'Val (Byte)]);
                     end loop;
                     exit when Byte = Streams.End_Marker or else
                       Byte = Character'Pos (ASCII.LF);
                  end if;
               end loop;
               if not All_Bytes then
                  Succeeded := Byte = Character'Pos (ASCII.LF) or else
                    Managed.Length (Activation.Native_Buffer) > 0;
                  if Keep_Newline and then Byte = Character'Pos (ASCII.LF)
                  then
                     Reserve (1);
                     Append_Read ([ASCII.LF]);
                  end if;
               end if;
            else
               Fail (State, "invalid format");
            end if;
            return (if Succeeded then
                       New_String (State, Activation.Native_Buffer) else
                       Nil_Value);
         end Read_One;
      begin
         --  Flags/errno are reset once for the whole operation. Formats are
         --  validated only when reached, preserving earlier stream effects
         --  if a later argument is malformed. Every result is rooted before
         --  the next format can allocate or perform a collector safe point.
         if Format_Count > 0 and then
           (Format_Count > Natural'Last - Minimum_C_Stack or else
              not Machine.Reserve_Native_Results
                (State, Activation, Format_Count + Minimum_C_Stack))
         then
            Fail (State, "too many arguments");
         end if;
         Result.Results.Reserve_Capacity
           (Ada.Containers.Count_Type (Natural'Max (3, Format_Count)));
         Streams.Begin_Read (Handle);
         if Format_Count = 0 then
            Result.Results.Append
              (Read_One (Nil_Value, Default_Format => True));
         else
            for Index in First .. Last loop
               Work (State);
               Item := Read_One (Formats (Index));
               Result.Results.Append (Item);
               Pin (State, Item);
               exit when Item.Kind = Nil_Kind;
            end loop;
         end if;
         if Streams.Has_Error (Handle) /= 0 then
            Result.Results := Failure (Error);
         end if;
      end Read_Formats;

      procedure Write_Arguments (File : Value; First : Positive) is
         Handle : constant Streams.Handle := Files.Header (File).File;
         Total : Interfaces.Unsigned_64 := 0;
         Failed : Boolean := False;
         procedure Write (Text : String);
         procedure Write (Text : String) is
            Written : C.size_t;
            Output : Output_Result;
         begin
            if Handle = Streams.Standard (Streams.Standard_Output) then
               Output := Emit_Output (State, Text);
               Written := C.size_t (Output.Bytes_Written);
               Error := Output.Error;
            elsif Text'Length = 0 then
               Written := 0;
            else
               Written := Streams.Write
                 (Handle, Text'Address, C.size_t (Text'Length), Error'Access);
            end if;
            Total := Total + Interfaces.Unsigned_64 (Written);
            Failed := Written < C.size_t (Text'Length);
         end Write;
      begin
         for Index in First .. Activation.Native_Arguments.Last_Index loop
            Work (State);
            if Activation.Native_Arguments (Index).Kind not in
              String_Kind | Integer_Kind | Real_Kind
            then
               Diagnostics.Type_Error
                 (State, Index, "string",
                  Activation.Native_Arguments (Index));
            end if;
            Strings.Query_Argument
              (State, Activation.Native_Arguments (Index), Write'Access);
            if Failed then
               Result.Results := Failure (Error);
               Result.Results.Append ((Integer_Kind, Signed_Total (Total)));
               return;
            end if;
         end loop;
         Result.Results.Append (File);
      end Write_Arguments;

      procedure Iterator is
         File : constant Value := Activation.Native_Captures (1);
         Auto_Close : constant Boolean :=
           Truth (Activation.Native_Captures (3));
         Count : Integer_Value := 0;
         Count_Value : Value := Activation.Native_Captures (2);
         Parsed : Lua.Numbers.Number;
      begin
         if Activation.Native_Stage = 1 then
            Result := Close (File, Ignore_Result => True);
            return;
         end if;
         if Files.Header (File).Closer = null then
            Fail (State, "file is already closed");
         end if;
         --  The iterator owns a real C-style frame: discard the old generic
         --  for control argument, retaining exactly its first supplied state
         --  (or nil). Removed scalar/packet values must cease being roots.
         Machine.Set_Native_Top (State, Activation, 1);
         --  Keep the actual count upvalue meaningful to debug.setupvalue.
         --  Like lua_tointeger, a nonnumeric/fractional replacement is zero;
         --  unreasonable native-state corruption is a controlled Lua error.
         if Count_Value.Kind = String_Kind then
            Parsed := Read_Number (State, Count_Value.Reference.Bytes);
            case Parsed.Kind is
               when Lua.Numbers.Integer_Number =>
                  Count_Value := (Integer_Kind, Parsed.Integer_Item);
               when Lua.Numbers.Real_Number =>
                  Count_Value := (Real_Kind, Parsed.Real_Item);
               when Lua.Numbers.Invalid => Count_Value := Nil_Value;
            end case;
         end if;
         if Count_Value.Kind = Integer_Kind then
            Count := Count_Value.Integer_Data;
         elsif Count_Value.Kind = Real_Kind and then
           Count_Value.Real_Data >= -2.0 ** 63 and then
           Count_Value.Real_Data < 2.0 ** 63 and then
           Real_Value'Truncation (Count_Value.Real_Data) =
             Count_Value.Real_Data
         then
            Count := Integer_Value (Count_Value.Real_Data);
         end if;
         --  io_readline narrows lua_Integer to its actual C int count. Keep
         --  the target's low bits without a checked Ada narrowing exception.
         Count := Integer_Value (Signed_Native_Int
           (C.unsigned'Mod (Count)));
         if Count < 0 then
            Fail (State, "invalid line iterator argument count");
         elsif not Machine.Reserve_Native_Results
             (State, Activation, Natural (Count))
         then
            --  First reserve/publish the actual format arguments. g_read's
            --  distinct result/buffer reservation follows them, matching its
            --  source-order stack failures before any native read occurs.
            Fail (State, "too many arguments");
         end if;
         for Index in 1 .. Natural (Count) loop
            Machine.Push_Native_Value
              (State, Activation,
               (if Index + 3 <=
                    Natural (Activation.Native_Captures.Length) then
                    Activation.Native_Captures (Index + 3) else Nil_Value));
         end loop;
         Read_Formats
           (File, Activation.Native_Arguments, 2,
            Natural (Activation.Native_Arguments.Length));
         if not Result.Results.Is_Empty and then
           Result.Results.First_Element.Kind = Nil_Kind
         then
            if Result.Results.Length > 1 then
               Fail (State, To_String (Result.Results (2).Reference.Bytes));
            elsif Auto_Close then
               --  aux_close sees only the file, not iterator state/formats.
               --  An external closef can inspect this same logical frame.
               Machine.Set_Native_Top (State, Activation, 0);
               Machine.Push_Native_Value (State, Activation, File);
               Result := Close (File, Ignore_Result => True);
            else
               Result.Results.Clear;
            end if;
         end if;
      end Iterator;
   begin
      Work (State);
      Managed.Set_Owner (First_Text, State.Current.Memory);
      Managed.Set_Owner (Second_Text, State.Current.Memory);
      Result.Results.Reserve_Capacity (4);
      if Name'Length >= 8 and then
        Name (Name'First .. Name'First + 7) = "io.file." and then
        Activation.Native_Arguments.Is_Empty
      then
         Diagnostics.Type_Error
           (State, 1, "FILE*", Nil_Value, Present => False);
      end if;
      if Name = "io.type" then
         if Activation.Native_Arguments.Is_Empty then
            Fail (State, "value expected in io.type");
         elsif not Files.Is_File (State, Arg (1)) then
            Result.Results.Append (Nil_Value);
         else
            Result.Results.Append (New_String
              (State, (if Files.Header (Arg (1)).Closer = null then
                   "closed file" else "file")));
         end if;
      elsif Name = "io.iterator" then
         Iterator;
      elsif Name in "io.close" | "io.file.close" | "io.file.gc" then
         if Name = "io.close" and then
           Activation.Native_Arguments.Is_Empty
         then
            Machine.Push_Native_Value
              (State, Activation, Default_File (False));
         end if;
         Item := File_Argument
           (State, Arg (1), Opened => Name /= "io.file.gc" and then
              Activation.Native_Stage = 0);
         Result := Close (Item, Ignore_Result => Name = "io.file.gc");
      elsif Name = "io.input" or else Name = "io.output" then
         declare
            Input : constant Boolean := Name = "io.input";
         begin
            if Arg (1).Kind /= Nil_Kind then
               if Arg (1).Kind in String_Kind | Integer_Kind | Real_Kind then
                  Item := Open_File
                    (Arg (1), (if Input then "r" else "w"), True);
               else
                  Item := File_Argument (State, Arg (1));
               end if;
               Set (State, (Table_Kind, State.Foreign_Registry),
                    New_String
                      (State, (if Input then "_IO_input" else "_IO_output")),
                    Item);
            end if;
            Result.Results.Append (Default_File (Input));
         end;
      elsif Name in "io.open" | "io.popen" | "io.tmpfile" then
         declare
            Kind : constant Files.File_Kind :=
              (if Name = "io.popen" then Files.Pipe_File else
                  Files.Regular_File);
            File : Value;
            Handle : Streams.Handle;
            function Valid_Mode (Text : String) return Boolean;
            procedure Validate_Mode (Text : String);

            function Valid_Mode (Text : String) return Boolean is
               Mode : constant String := C_Option (Text);
               Index : Integer := Mode'First + 1;
            begin
               if Mode'Length = 0 then
                  return False;
               elsif Name = "io.popen" then
                  return Mode (Mode'First) in 'r' | 'w' and then
                    (Mode'Length = 1 or else
                       (Windows_Host and then
                          Mode'Length = 2 and then
                          Mode (Mode'Last) in 'b' | 't'));
               elsif Mode (Mode'First) not in 'r' | 'w' | 'a' then
                  return False;
               end if;
               if Index <= Mode'Last and then Mode (Index) = '+' then
                  Index := Index + 1;
               end if;
               for Position in Index .. Mode'Last loop
                  if Mode (Position) /= 'b' then
                     return False;
                  end if;
               end loop;
               return True;
            end Valid_Mode;

            procedure Validate_Mode (Text : String) is
            begin
               if not Valid_Mode (Text) then
                  Fail (State, "invalid mode");
               end if;
            end Validate_Mode;
         begin
            if Name = "io.tmpfile" then
               File := Files.New_Closed (State, Kind);
               Files.Prepare
                 (File, Foreign.IO_Close_Handler (Foreign.Regular_File_Close));
               Handle := Streams.Temporary (Error'Access);
            else
               Copy_Text (Arg (1), First_Text);
               if Arg (2).Kind = Nil_Kind then
                  Managed.Set_Value (Second_Text, "r");
               else
                  Copy_Text (Arg (2), Second_Text);
               end if;
               File := Files.New_Closed (State, Kind);
               if Name = "io.open" then
                  Files.Prepare
                    (File, Foreign.IO_Close_Handler
                       (Foreign.Regular_File_Close));
               end if;
               Managed.Query (Second_Text, Validate_Mode'Access);
               if Name = "io.popen" then
                  Handle := Streams.Open_Pipe
                    (Managed.C_Address (First_Text),
                     Managed.C_Address (Second_Text), Error'Access);
                  Files.Prepare
                    (File, Foreign.IO_Close_Handler (Foreign.Pipe_File_Close));
               else
                  Handle := Streams.Open
                    (Managed.C_Address (First_Text),
                     Managed.C_Address (Second_Text), Error'Access);
               end if;
            end if;
            if Handle = Streams.No_Stream then
               Result.Results := Failure
                 (Error, Include_Name => Name /= "io.tmpfile");
            else
               Files.Publish
                 (File, Handle, Foreign.IO_Close_Handler
                    ((if Name = "io.popen" then Foreign.Pipe_File_Close else
                         Foreign.Regular_File_Close)));
               Result.Results.Append (File);
            end if;
         end;
      elsif Name = "io.lines" or else Name = "io.file.lines" then
         declare
            Captures : Values.Vector := Owned_Values (State);
            First : constant Positive := 2;
            Auto_Close : constant Boolean :=
              Name = "io.lines" and then Arg (1).Kind /= Nil_Kind;
         begin
            if Name = "io.file.lines" then
               Item := File_Argument (State, Arg (1));
            elsif Auto_Close then
               Item := Open_File (Arg (1), "r", True);
            else
               Item := Default_File (True);
            end if;
            if Activation.Native_Arguments.Length > 251 then
               Fail (State, "too many arguments");
            end if;
            Captures.Append (Item);
            Captures.Append
              ((Integer_Kind, Integer_Value
                  (Natural'Max
                     (1, Natural (Activation.Native_Arguments.Length)) - 1)));
            Captures.Append ((Boolean_Kind, Auto_Close));
            for Index in First .. Activation.Native_Arguments.Last_Index loop
               Captures.Append (Activation.Native_Arguments (Index));
            end loop;
            Pin (State, Captures);
            Result.Results.Append
              (New_Native (State, "io.iterator", Captures));
            if Auto_Close then
               Result.Results.Append (Nil_Value);
               Result.Results.Append (Nil_Value);
               Result.Results.Append (Item);
            end if;
         end;
      elsif Name = "io.read" or else Name = "io.file.read" then
         Item := (if Name = "io.read" then Default_File (True) else
                     File_Argument (State, Arg (1)));
         declare
            Last_Format : constant Natural :=
              Natural (Activation.Native_Arguments.Length);
         begin
            if Name = "io.read" then
               Machine.Push_Native_Value (State, Activation, Item);
            end if;
            Read_Formats
              (Item, Activation.Native_Arguments,
               (if Name = "io.read" then 1 else 2), Last_Format);
         end;
      elsif Name = "io.write" or else Name = "io.file.write" then
         Item := (if Name = "io.write" then Default_File (False) else
                     File_Argument (State, Arg (1)));
         Write_Arguments (Item, (if Name = "io.write" then 1 else 2));
      elsif Name = "io.flush" or else Name = "io.file.flush" then
         Item := (if Name = "io.flush" then Default_File (False) else
                     File_Argument (State, Arg (1)));
         if Files.Header (Item).File =
           Streams.Standard (Streams.Standard_Output)
         then
            declare
               Output : constant Output_Result := Flush_Output (State);
            begin
               Result.Results := System_Results.File_Result
                 (State, Output.Succeeded, Output.Error);
            end;
         else
            Status := Streams.Flush (Files.Header (Item).File, Error'Access);
            Result.Results := System_Results.File_Result
              (State, Status = 0, Error);
         end if;
      elsif Name = "io.file.seek" then
         Item := File_Argument (State, Arg (1));
         declare
            Origin : Streams.Seek_Origin := Streams.From_Current;
            Offset : Integer_Value := 0;
            procedure Check_Origin (Text : String);
            procedure Check_Origin (Text : String) is
            begin
               if C_Option (Text) = "set" then
                  Origin := Streams.From_Start;
               elsif C_Option (Text) = "cur" then
                  Origin := Streams.From_Current;
               elsif C_Option (Text) = "end" then
                  Origin := Streams.From_End;
               else
                  Fail (State, "invalid option in file:seek");
               end if;
            end Check_Origin;
         begin
            if Arg (2).Kind /= Nil_Kind then
               Strings.Query_Argument (State, Arg (2), Check_Origin'Access);
            end if;
            if Arg (3).Kind /= Nil_Kind then
               Offset := Strings.Integer_Argument (State, Arg (3));
            end if;
            if Streams.Offset_Bits = 32 and then
              (Offset < -2 ** 31 or else Offset >= 2 ** 31)
            then
               Fail (State, "not an integer in proper range");
            end if;
            Status := Streams.Seek
              (Files.Header (Item).File, C.long_long (Offset), Origin,
               Error'Access);
            if Status /= 0 then
               Result.Results := Failure (Error);
            else
               Result.Results.Append
                 ((Integer_Kind, Integer_Value
                     (Streams.Position (Files.Header (Item).File))));
            end if;
         end;
      elsif Name = "io.file.setvbuf" then
         Item := File_Argument (State, Arg (1));
         declare
            Mode : Streams.Buffer_Mode := Streams.Fully_Buffered;
            Size : Integer_Value := Integer_Value
              (Lua.Runtime_Configuration.Auxiliary_Buffer_Bytes);
            procedure Check_Mode (Text : String);
            procedure Check_Mode (Text : String) is
            begin
               if C_Option (Text) = "no" then
                  Mode := Streams.Unbuffered;
               elsif C_Option (Text) = "full" then
                  Mode := Streams.Fully_Buffered;
               elsif C_Option (Text) = "line" then
                  Mode := Streams.Line_Buffered;
               else
                  Fail (State, "invalid option in file:setvbuf");
               end if;
            end Check_Mode;
         begin
            Strings.Query_Argument (State, Arg (2), Check_Mode'Access);
            if Arg (3).Kind /= Nil_Kind then
               Size := Strings.Integer_Argument (State, Arg (3));
            end if;
            --  Lua passes the low size_t bits even for a negative integer.
            --  Let stdio return its own result for that mode and size.
            Status := Streams.Set_Buffering
              (Files.Header (Item).File, Mode, C.size_t'Mod (Size),
               Error'Access);
            Result.Results := System_Results.File_Result
              (State, Status = 0, Error);
         end;
      elsif Name = "io.file.tostring" then
         Item := File_Argument (State, Arg (1), False);
         if Files.Header (Item).Closer = null then
            Result.Results.Append (New_String (State, "file (closed)"));
         else
            --  Pointer spelling is native %p; the formatter works only with
            --  this public FILE* pointer, never an interpreter object handle.
            declare
               Buffer : String (1 .. 128);
               Size : C.size_t;
            begin
               Size := Streams.Pointer_Text
                 (Files.Header (Item).File, Buffer'Address, Buffer'Length);
               Result.Results.Append
                 (New_String (State, "file (" &
                    Buffer (1 .. Natural (Size)) & ")"));
            end;
         end if;
      else
         raise Program_Error with "unknown IO library operation";
      end if;
      return Result;
   end Advance;
end Lua.Engine.IO_Libraries;
