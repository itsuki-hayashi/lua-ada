with Ada.Unchecked_Conversion;
with Interfaces.C;
with Lua.Engine.Machine;
with Lua.Engine.Strings;
with Lua.Engine.System_Results;
with Lua.Platform_Locales;
with Lua.Platform_OS;
with Lua.Storage.Buffers;
with Lua_Ada_Config;
with System;

package body Lua.Engine.Operating_System is
   package C renames Interfaces.C;
   package OS renames Lua.Platform_OS;
   package Locales renames Lua.Platform_Locales;
   package Managed renames Lua.Storage.Buffers;
   use type C.int;
   use type C.size_t;
   use type Integer_Value;
   use type System.Address;

   function Signed_Code is new Ada.Unchecked_Conversion (C.unsigned, C.int);
   function Windows_Host
     (Host : String := Lua_Ada_Config.Alire_Host_OS) return Boolean is
     (Host = "windows");

   function Open_Module (State : in out World) return Value is
      Names : constant String :=
        "clock date difftime execute exit getenv remove rename " &
        "setlocale time tmpname";
      Module : constant Value := New_Table (State);
      First : Positive := Names'First;
      Last : Natural;
      Item : Value;
   begin
      --  Keep each export rooted before allocating its key. Both embedding
      --  and the C opener use these same Ada native continuations.
      Pin (State, Module);
      while First <= Names'Last loop
         Last := First;
         while Last < Names'Last and then Names (Last + 1) /= ' ' loop
            Last := Last + 1;
         end loop;
         Item := New_Native (State, "os." & Names (First .. Last));
         Pin (State, Item);
         Set (State, Module, New_String (State, Names (First .. Last)),
              Item);
         First := Last + 2;
      end loop;
      return Module;
   end Open_Module;

   function Advance
     (State : in out World; Activation : Frame_Access) return Native_Action
   is
      Name : constant String := To_String (Activation.Native_Name);
      Result : Native_Action := New_Action (State);
      First_Text, Second_Text, Buffer : Managed.Buffer;
      Error : aliased C.int := 0;
      Valid : aliased C.int := 0;
      Native_Status : C.int;
      Stamp : C.long_long;
      Date : aliased OS.Broken_Down_Time;

      function Arg (Index : Positive) return Value is
        (if Index <= Natural (Activation.Native_Arguments.Length) then
            Activation.Native_Arguments (Index) else Nil_Value);
      function Returned return Value is
        (if Activation.Native_Results.Is_Empty then Nil_Value else
            Activation.Native_Results.First_Element);
      function Capture (Index : Positive) return Value is
        (Activation.Native_Captures (Index));
      procedure Save (Index : Positive; Item : Value);
      procedure Work;
      procedure Copy_Text (Item : Value; Output : in out Managed.Buffer);
      procedure Copy_C_Text
        (Address : System.Address; Output : in out Managed.Buffer);
      procedure File_Result
        (Succeeded : Boolean; Code : C.int;
         Filename : in out Managed.Buffer; Include_Name : Boolean := False);
      function Integral_Time (Item : Value) return C.long_long;
      function Read_Field_Name (Index : Positive) return String;
      function Write_Field_Name (Index : Positive) return String;
      function Request_Field (Writing : Boolean) return Native_Action;
      procedure Save_Read_Field (Item : Value);
      procedure Normalize;
      procedure Advance_Time;
      procedure Produce_Date;

      procedure Save (Index : Positive; Item : Value) is
      begin
         Activation.Native_Captures.Replace_Element (Index, Item);
      end Save;

      procedure Work is
      begin
         if State.Steps >= State.Bounds.Instructions then
            Fail (State, "instruction limit exceeded", Resource => True);
         elsif State.Policy = Bounded then
            State.Steps := State.Steps + 1;
         end if;
      end Work;

      procedure Copy_Text (Item : Value; Output : in out Managed.Buffer) is
         procedure Copy (Text : String);
         procedure Copy (Text : String) is
         begin
            Managed.Set_Value (Output, Text);
         end Copy;
      begin
         Strings.Query_Argument (State, Item, Copy'Access);
      end Copy_Text;

      procedure Copy_C_Text
        (Address : System.Address; Output : in out Managed.Buffer)
      is
         Size : C.size_t;
      begin
         if Address = System.Null_Address then
            Managed.Clear (Output);
            return;
         end if;
         Size := OS.Text_Length (Address);
         if Size > C.size_t (Natural'Last) then
            raise Lua.Storage.Allocation_Error;
         end if;
         declare
            View : constant String (1 .. Natural (Size))
              with Import, Address => Address;
         begin
            --  Managed buffer growth performs no Lua callbacks. The libc
            --  borrow is copied before a string publication can collect/run
            --  finalizers which might call getenv/setlocale/strerror again.
            Managed.Set_Value (Output, View);
         end;
      end Copy_C_Text;

      procedure File_Result
        (Succeeded : Boolean; Code : C.int;
         Filename : in out Managed.Buffer; Include_Name : Boolean := False)
      is
         procedure With_Name (Text : String);
         procedure With_Name (Text : String) is
         begin
            Result.Results := System_Results.File_Result
              (State, Succeeded, Code, Text, Include_Name => True);
         end With_Name;
      begin
         if Include_Name then
            Managed.Query (Filename, With_Name'Access);
         else
            Result.Results := System_Results.File_Result
              (State, Succeeded, Code);
         end if;
      end File_Result;

      function Integral_Time (Item : Value) return C.long_long is
         Value : constant Integer_Value :=
           Strings.Integer_Argument (State, Item);
      begin
         if OS.Time_Representable (C.long_long (Value)) = 0 then
            Fail (State, "time out-of-bounds");
         end if;
         return C.long_long (Value);
      end Integral_Time;

      function Read_Field_Name (Index : Positive) return String is
      begin
         case Index is
            when 1 => return "year";
            when 2 => return "month";
            when 3 => return "day";
            when 4 => return "hour";
            when 5 => return "min";
            when 6 => return "sec";
            when 7 => return "isdst";
            when others => raise Program_Error with "invalid date read phase";
         end case;
      end Read_Field_Name;

      function Write_Field_Name (Index : Positive) return String is
      begin
         case Index is
            when 1 => return "year";
            when 2 => return "month";
            when 3 => return "day";
            when 4 => return "hour";
            when 5 => return "min";
            when 6 => return "sec";
            when 7 => return "yday";
            when 8 => return "wday";
            when 9 => return "isdst";
            when others => raise Program_Error with "invalid date write phase";
         end case;
      end Write_Field_Name;

      function Request_Field (Writing : Boolean) return Native_Action is
         Arguments : Values.Vector := Owned_Values (State);
         Index : constant Positive := Activation.Native_Index;
      begin
         Arguments.Append (Capture (1));
         Arguments.Append
           (New_String
              (State, (if Writing then Write_Field_Name (Index) else
                   Read_Field_Name (Index))));
         if Writing then
            Arguments.Append (Capture (Index + 1));
         end if;
         Pin (State, Arguments);
         return
           (Kind => Invoke,
            Function_Value => New_Native
              (State, (if Writing then "@set" else "@get")),
            Arguments => Arguments, others => <>);
      end Request_Field;

      procedure Save_Read_Field (Item : Value) is
         Index : constant Positive := Activation.Native_Index;
         Adjustment : constant Integer_Value :=
           (if Index = 1 then 1900 elsif Index = 2 then 1 else 0);
         Number : Integer_Value;
      begin
         if Index = 7 then
            Save (10, (Integer_Kind,
                       (if Item.Kind = Nil_Kind then -1 else
                           Boolean'Pos (Truth (Item)))));
            return;
         end if;
         if Item.Kind = Nil_Kind then
            if Index <= 3 then
               Fail (State, "field '" & Read_Field_Name (Index) &
                     "' missing in date table");
            end if;
            Number := (if Index = 4 then 12 else 0);
         else
            --  Numeric strings follow lua_tointegerx, but fractional values
            --  and nonnumeric types report the actual field name. Catch only
            --  this validation failure, never an allocator/host quota abort.
            begin
               Number := Strings.Integer_Argument (State, Item);
            exception
               when Language_Error =>
                  if State.Current.Failure_Class = Host_Abort or else
                    State.Current.Failure_Class = Memory_Failure
                  then
                     raise;
                  end if;
                  Fail (State, "field '" & Read_Field_Name (Index) &
                        "' is not an integer");
            end;
            --  Compare in int64 before applying C tm's small signed offset.
            --  Never narrow or subtract until representability is proved.
            if Number < Integer_Value (C.int'First) + Adjustment or else
              Number > Integer_Value (C.int'Last) + Adjustment
            then
               Fail (State, "field '" & Read_Field_Name (Index) &
                     "' is out-of-bound");
            end if;
            Number := Number - Adjustment;
         end if;
         Save (Index + 1, (Integer_Kind, Number));
      end Save_Read_Field;

      procedure Normalize is
      begin
         Date.Year := C.int (Capture (2).Integer_Data);
         Date.Month := C.int (Capture (3).Integer_Data);
         Date.Day := C.int (Capture (4).Integer_Data);
         Date.Hour := C.int (Capture (5).Integer_Data);
         Date.Minute := C.int (Capture (6).Integer_Data);
         Date.Second := C.int (Capture (7).Integer_Data);
         Date.Daylight := C.int (Capture (10).Integer_Data);
         Stamp := OS.Normalize_Time (Date'Access, Valid'Access);
         --  Publication uses pre-reserved traced scalar captures. mktime is
         --  executed once: later field metamethods and allocator failures do
         --  not restart normalization or discard already completed writes.
         Save (2, (Integer_Kind, Integer_Value (Date.Year) + 1900));
         Save (3, (Integer_Kind, Integer_Value (Date.Month) + 1));
         Save (4, (Integer_Kind, Integer_Value (Date.Day)));
         Save (5, (Integer_Kind, Integer_Value (Date.Hour)));
         Save (6, (Integer_Kind, Integer_Value (Date.Minute)));
         Save (7, (Integer_Kind, Integer_Value (Date.Second)));
         Save (8, (Integer_Kind, Integer_Value (Date.Yearday) + 1));
         Save (9, (Integer_Kind, Integer_Value (Date.Weekday) + 1));
         Save (10, (if Date.Daylight < 0 then Nil_Value else
                      (Boolean_Kind, Date.Daylight /= 0)));
         Save (11, (Integer_Kind, Integer_Value (Stamp)));
         Save (12, (Boolean_Kind, Valid /= 0));
      end Normalize;

      procedure Advance_Time is
      begin
         if Activation.Native_Stage = 0 then
            if Arg (1).Kind = Nil_Kind then
               Stamp := OS.Time_Current (Valid'Access);
               if Valid = 0 then
                  Fail (State, "time result cannot be represented in " &
                        "this installation");
               end if;
               Result.Results.Append ((Integer_Kind, Integer_Value (Stamp)));
               return;
            elsif Arg (1).Kind /= Table_Kind then
               Fail (State, "table expected in os.time");
            end if;
            --  The C function explicitly discards extra arguments before
            --  invoking date-table metamethods. Clear both actual slots and
            --  packet roots, so those callbacks see the same live frame.
            Machine.Set_Native_Top (State, Activation, 1);
            Activation.Native_Captures.Reserve_Capacity (12);
            Activation.Native_Captures.Append (Arg (1));
            for Index in 2 .. 12 loop
               Activation.Native_Captures.Append (Nil_Value);
            end loop;
            Activation.Native_Index := 1;
            Activation.Native_Stage := 1;
         elsif Activation.Native_Stage = 1 then
            Save_Read_Field (Returned);
            Activation.Native_Results.Clear;
            Activation.Native_Index := Activation.Native_Index + 1;
            if Activation.Native_Index = 8 then
               Normalize;
               Activation.Native_Stage := 2;
               Activation.Native_Index := 1;
            end if;
         elsif Activation.Native_Stage = 2 then
            Activation.Native_Index := Activation.Native_Index + 1;
         else
            raise Program_Error with "invalid os.time continuation";
         end if;
         if Activation.Native_Stage = 1 then
            Result := Request_Field (Writing => False);
         elsif Activation.Native_Index <= 9 and then
           (Activation.Native_Index /= 9 or else
              Capture (10).Kind /= Nil_Kind)
         then
            Result := Request_Field (Writing => True);
         else
            --  Like C Lua, all normalized table writes precede reporting a
            --  failed mktime. A missing/raising setter has its natural earlier
            --  error precedence, and a successful call returns one integer.
            if not Capture (12).Boolean_Data then
               Fail (State, "time result cannot be represented in " &
                     "this installation");
            end if;
            Result.Results.Append (Capture (11));
         end if;
      end Advance_Time;

      procedure Produce_Date is
         Universal : C.int := 0;
         Table : Value;
         procedure Field (Key : String; Item : Value);
         procedure Format (Text : String);

         procedure Field (Key : String; Item : Value) is
         begin
            Set (State, Table, New_String (State, Key), Item);
         end Field;

         procedure Format (Text : String) is
            Index : Integer := Text'First;
            Conversion : String (1 .. 4) := [others => Character'Val (0)];
            Output : String (1 .. 250);
            Size : C.size_t;
            Single_Options : constant String :=
              (if Windows_Host then
                  "aAbBcdHIjmMpSUwWxXyYzZ%" else
                  "aAbBcCdDeFgGhHIjmMnprRStTuUVwWxXyYzZ%");
            Double_Options : constant String :=
              (if Windows_Host then
                  "#c#x#d#H#I#j#m#M#S#U#w#W#y#Y" else
                  "EcECExEXEyEYOdOeOHOIOmOMOSOuOUOVOwOWOy");
            Matched : Boolean;
         begin
            --  Query_Argument has already validated/converted the first
            --  argument. Timestamp validation follows it, preserving pinned
            --  argument-error precedence even when both inputs are invalid.
            Stamp := (if Arg (2).Kind = Nil_Kind then
                         OS.Time_Current (Valid'Access) else
                         Integral_Time (Arg (2)));
            if Index <= Text'Last and then Text (Index) = '!' then
               Universal := 1;
               Index := Index + 1;
            end if;
            if OS.Calendar_Time (Stamp, Universal, Date'Access) = 0 then
               Fail (State, "date result cannot be represented in " &
                     "this installation");
            end if;
            if C_Option (Text (Index .. Text'Last)) = "*t" then
               Table := New_Table (State);
               Pin (State, Table);
               Reserve_Table (State, Table, 0, 9);
               Field
                 ("year", (Integer_Kind, Integer_Value (Date.Year) + 1900));
               Field ("month", (Integer_Kind, Integer_Value (Date.Month) + 1));
               Field ("day", (Integer_Kind, Integer_Value (Date.Day)));
               Field ("hour", (Integer_Kind, Integer_Value (Date.Hour)));
               Field ("min", (Integer_Kind, Integer_Value (Date.Minute)));
               Field ("sec", (Integer_Kind, Integer_Value (Date.Second)));
               Field
                 ("yday", (Integer_Kind, Integer_Value (Date.Yearday) + 1));
               Field
                 ("wday", (Integer_Kind, Integer_Value (Date.Weekday) + 1));
               if Date.Daylight >= 0 then
                  Field ("isdst", (Boolean_Kind, Date.Daylight /= 0));
               end if;
               Result.Results.Append (Table);
               return;
            end if;
            while Index <= Text'Last loop
               Work;
               if Text (Index) /= '%' then
                  Managed.Append (Buffer, Text (Index));
                  Index := Index + 1;
               else
                  Index := Index + 1;
                  Conversion := [others => Character'Val (0)];
                  Conversion (1) := '%';
                  Matched := False;
                  if Index <= Text'Last then
                     for Option of Single_Options loop
                        if Text (Index) = Option then
                           Conversion (2) := Option;
                           Matched := True;
                           Index := Index + 1;
                           exit;
                        end if;
                     end loop;
                     if not Matched and then Index < Text'Last then
                        for Offset in 0 .. Double_Options'Length / 2 - 1 loop
                           if Text (Index .. Index + 1) =
                             Double_Options
                               (2 * Offset + 1 .. 2 * Offset + 2)
                           then
                              Conversion (2 .. 3) :=
                                Text (Index .. Index + 1);
                              Matched := True;
                              Index := Index + 2;
                              exit;
                           end if;
                        end loop;
                     end if;
                  end if;
                  if not Matched then
                     Fail (State, "invalid conversion specifier '%" &
                           C_Option (Text (Index .. Text'Last)) & "'");
                  end if;
                  Size := OS.Format_Time
                    (Output'Address, Output'Length, Conversion'Address,
                     Stamp, Universal);
                  Managed.Append (Buffer, Output (1 .. Natural (Size)));
               end if;
            end loop;
            Result.Results.Append (New_String (State, Buffer));
         end Format;
      begin
         if Arg (1).Kind = Nil_Kind then
            Format ("%c");
         else
            Strings.Query_Argument (State, Arg (1), Format'Access);
         end if;
      end Produce_Date;
   begin
      Managed.Set_Owner (First_Text, State.Current.Memory);
      Managed.Set_Owner (Second_Text, State.Current.Memory);
      Managed.Set_Owner (Buffer, State.Current.Memory);
      --  Reserve scalar result capacity before an irreversible native call;
      --  every later published string owns its bytes through this universe.
      Result.Results.Reserve_Capacity (3);
      Work;
      if Name = "os.clock" then
         Result.Results.Append ((Real_Kind, Real_Value (OS.Clock)));
      elsif Name = "os.time" then
         Advance_Time;
      elsif Name = "os.date" then
         Produce_Date;
      elsif Name = "os.difftime" then
         declare
            Left : constant C.long_long := Integral_Time (Arg (1));
            Right : constant C.long_long := Integral_Time (Arg (2));
         begin
            --  Ada actual-parameter evaluation order is unspecified. Keep
            --  the two language argument checks explicitly source-ordered.
            Result.Results.Append
              ((Real_Kind, Real_Value (OS.Difference (Left, Right))));
         end;
      elsif Name = "os.execute" then
         if Arg (1).Kind = Nil_Kind then
            Native_Status := OS.Execute (System.Null_Address, Error'Access);
            Result.Results.Append ((Boolean_Kind, Native_Status /= 0));
         else
            Copy_Text (Arg (1), First_Text);
            Native_Status := OS.Execute
              (Managed.C_Address (First_Text), Error'Access);
            Result.Results := System_Results.Process_Result
              (State, Native_Status, Error);
         end if;
      elsif Name = "os.remove" or else Name = "os.rename" then
         Copy_Text (Arg (1), First_Text);
         if Name = "os.remove" then
            Native_Status := OS.Remove
              (Managed.C_Address (First_Text), Error'Access);
         else
            Copy_Text (Arg (2), Second_Text);
            Native_Status := OS.Rename
              (Managed.C_Address (First_Text),
               Managed.C_Address (Second_Text), Error'Access);
         end if;
         File_Result
           (Native_Status = 0, Error, First_Text,
            Include_Name => Name = "os.remove");
      elsif Name = "os.getenv" then
         Copy_Text (Arg (1), First_Text);
         declare
            Address : constant System.Address :=
              OS.Environment (Managed.C_Address (First_Text));
         begin
            if Address = System.Null_Address then
               Result.Results.Append (Nil_Value);
            else
               Copy_C_Text (Address, Buffer);
               Result.Results.Append (New_String (State, Buffer));
            end if;
         end;
      elsif Name = "os.tmpname" then
         declare
            Capacity : constant C.size_t := OS.Temporary_Name_Capacity;
         begin
            if Capacity = 0 or else Capacity > C.size_t (Natural'Last) then
               raise Lua.Storage.Allocation_Error;
            end if;
            Managed.Reserve_Capacity (First_Text, Natural (Capacity));
            Native_Status := OS.Temporary_Name
              (Managed.C_Address (First_Text), Error'Access);
            if Native_Status /= 0 then
               Fail (State, "unable to generate a unique filename");
            end if;
            Copy_C_Text (Managed.Address (First_Text), Buffer);
            Result.Results.Append (New_String (State, Buffer));
         end;
      elsif Name = "os.setlocale" then
         declare
            Category : Locales.Locale_Category := Locales.All_Categories;
            Address : System.Address := System.Null_Address;
         begin
            --  Validate the locale value before its category, as the C API
            --  checks argument one first. Retain the bytes through the
            --  separate second-argument conversion and native locale call.
            if Arg (1).Kind /= Nil_Kind then
               Copy_Text (Arg (1), First_Text);
               Address := Managed.C_Address (First_Text);
            end if;
            if Arg (2).Kind /= Nil_Kind then
               Copy_Text (Arg (2), Second_Text);
               declare
                  Text : constant String :=
                    C_Option (Managed.To_String (Second_Text));
               begin
                  if Text = "all" then
                     Category := Locales.All_Categories;
                  elsif Text = "collate" then
                     Category := Locales.Collation;
                  elsif Text = "ctype" then
                     Category := Locales.Character_Classes;
                  elsif Text = "monetary" then
                     Category := Locales.Monetary;
                  elsif Text = "numeric" then
                     Category := Locales.Numeric;
                  elsif Text = "time" then
                     Category := Locales.Time;
                  else
                     Fail (State, "invalid option in os.setlocale");
                  end if;
               end;
            end if;
            Address := Locales.Set_Locale (Category, Address);
            if Address = System.Null_Address then
               Result.Results.Append (Nil_Value);
            else
               Copy_C_Text (Address, Buffer);
               Result.Results.Append (New_String (State, Buffer));
            end if;
         end;
      elsif Name = "os.exit" then
         declare
            Code : C.int := OS.Exit_Success;
         begin
            if Arg (1).Kind = Boolean_Kind then
               Code := (if Arg (1).Boolean_Data then OS.Exit_Success else
                           OS.Exit_Failure);
            elsif Arg (1).Kind /= Nil_Kind then
               --  C's explicit int cast retains its native low bits; a large
               --  valid lua_Integer must not become an Ada range exception.
               Code := Signed_Code
                 (C.unsigned'Mod (Strings.Integer_Argument (State, Arg (1))));
            end if;
            Request_Process_Exit (State, Code, Truth (Arg (2)));
         end;
      else
         raise Program_Error with "unknown os library operation";
      end if;
      return Result;
   end Advance;
end Lua.Engine.Operating_System;
