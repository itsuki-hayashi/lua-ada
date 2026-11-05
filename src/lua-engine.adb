with Ada.Containers;
with Ada.Exceptions;
with Ada.Numerics;
with Lua.Engine.Unicode;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Ada.Unchecked_Conversion;
with Interfaces;
with Lua_Ada_Config;
with Lua.Engine.Compiler;
with Lua.Engine.Machine;

package body Lua.Engine is
   use type Ada.Containers.Count_Type;
   use type Integer_Value;
   use type Real_Value;
   use type Interfaces.Unsigned_64;

   function Real_Bits is new Ada.Unchecked_Conversion
     (Real_Value, Interfaces.Unsigned_64);
   --  Read only the IEEE sign bit for diagnostic formatting. Numeric values
   --  remain IEEE doubles; no arbitrary bits are imported through this helper.

   procedure Free_Object is new Ada.Unchecked_Deallocation
     (Heap_Object, Object_Access);
   procedure Free_Program is new Ada.Unchecked_Deallocation
     (Prototype, Prototype_Access);
   procedure Free_Frame is new Ada.Unchecked_Deallocation
     (Frame, Frame_Access);
   --  Deallocation is confined to this owning world. Lua values themselves
   --  never free objects, which is essential for shared/cyclic graphs.

   function Allocate (State : in out World; Kind : Heap_Kind)
                      return Object_Access;
   function Real_Image (Item : Real_Value) return String;
   function NaN_Image (Item : Real_Value; Host : String) return String;
   --  Keep host formatting policy separate from arithmetic and test values.

   function NaN_Image (Item : Real_Value; Host : String) return String is
   begin
      if Host in "windows" | "macos" then
         return "nan";
      end if;
      return (if (Real_Bits (Item) and 2 ** 63) /= 0 then "-nan" else "nan");
   end NaN_Image;

   procedure Fail (State : in out World; Message : String;
                   Resource : Boolean := False)
   is
   begin
      State.Failure_Text := To_Unbounded_String (Message);
      State.Failure := Nil_Value;
      State.Has_Failure_Value := False;
      State.Is_Resource := Resource;
      raise Language_Error;
   end Fail;

   function Allocate (State : in out World; Kind : Heap_Kind)
                      return Object_Access
   is
      Item : Object_Access;
   begin
      --  Collection happens at VM safe points, not in this allocator: the
      --  instruction's temporary Ada locals are not GC roots. Exhaustion
      --  here is reported, never handled by collecting unrooted temporaries.
      if State.Heap.Length >= Ada.Containers.Count_Type
        (State.Bounds.Heap_Objects) or else State.Next_Object = Positive'Last
      then
         Fail (State, "heap object limit exceeded", Resource => True);
      end if;
      Item := new Heap_Object (Kind);
      Item.Serial := State.Next_Object;
      State.Next_Object := State.Next_Object + 1;
      State.Heap.Append (Item);
      return Item;
   end Allocate;

   function New_String (State : in out World; Text : String) return Value is
      Item : Object_Access;
   begin
      if Text'Length > State.Bounds.String_Bytes then
         Fail (State, "string byte limit exceeded", Resource => True);
      end if;
      Item := Allocate (State, String_Object);
      Item.Bytes := To_Unbounded_String (Text);
      return (String_Kind, Item);
   end New_String;

   function New_Table (State : in out World) return Value is
     (Table_Kind, Allocate (State, Table_Object));

   function New_Environment
     (State : in out World; Parent : Object_Access) return Object_Access
   is
      Item : constant Object_Access := Allocate (State, Environment);
   begin
      Item.Parent := Parent;
      return Item;
   end New_Environment;

   function New_Closure
     (State : in out World; Code : Prototype_Access;
      Capture : Object_Access) return Value
   is
      Item : constant Object_Access := Allocate (State, Closure);
   begin
      Item.Code := Code;
      Item.Capture := Capture;
      return (Closure_Kind, Item);
   end New_Closure;

   function New_Native
     (State : in out World; Name : String;
      Captures : Values.Vector := Values.Empty_Vector) return Value
   is
      Item : constant Object_Access := Allocate (State, Native_Closure);
   begin
      Item.Native_Name := To_Unbounded_String (Name);
      Item.Captures := Captures;
      return (Native_Closure_Kind, Item);
   end New_Native;

   function Metafield
     (State : in out World; Item : Value; Name : String) return Value
   is
      Table : Object_Access;
   begin
      if Item.Kind = Table_Kind then
         Table := Item.Reference.Metatable;
      elsif Item.Kind = String_Kind then
         Table := State.String_Metatable;
      end if;
      if Table = null then
         return Nil_Value;
      end if;
      return Get ((Table_Kind, Table), New_String (State, Name));
   end Metafield;

   function Equal (Left, Right : Value) return Boolean is
      function Numeric (Item : Value) return Lua.Numbers.Number is
        (if Item.Kind = Integer_Kind then
           (Lua.Numbers.Integer_Number, Item.Integer_Data)
         else (Lua.Numbers.Real_Number, Item.Real_Data));
   begin
      if Left.Kind in Integer_Kind | Real_Kind and then
        Right.Kind in Integer_Kind | Real_Kind
      then
         return Lua.Numbers.Equal (Numeric (Left), Numeric (Right));
      elsif Left.Kind /= Right.Kind then
         return False;
      end if;
      case Left.Kind is
         when Nil_Kind => return True;
         when Boolean_Kind => return Left.Boolean_Data = Right.Boolean_Data;
         when Integer_Kind => return Left.Integer_Data = Right.Integer_Data;
         when Real_Kind => return Left.Real_Data = Right.Real_Data;
         when String_Kind =>
            return Left.Reference.Bytes = Right.Reference.Bytes;
         when Table_Kind | Closure_Kind | Native_Closure_Kind =>
            return Left.Reference = Right.Reference;
         when Native_Kind_Value => return Left.Native_Data = Right.Native_Data;
      end case;
   end Equal;

   function Truth (Item : Value) return Boolean is
     (Item.Kind /= Nil_Kind and then
        (Item.Kind /= Boolean_Kind or else Item.Boolean_Data));

   function Type_Name (Item : Value) return String is
     (case Item.Kind is
         when Nil_Kind => "nil",
         when Boolean_Kind => "boolean",
         when Integer_Kind | Real_Kind => "number",
         when String_Kind => "string",
         when Table_Kind => "table",
         when Closure_Kind | Native_Closure_Kind | Native_Kind_Value =>
            "function");

   function Real_Image (Item : Real_Value) return String is
      package Real_IO is new Ada.Text_IO.Float_IO (Real_Value);
      Buffer : String (1 .. 64);
      Precision : Positive := 15;
   begin
      if Item /= Item then
         --  Windows and macOS printf omit NaN's sign; Linux retains it.
         --  Three-platform differential runs established this distinction.
         --  Numeric comparisons still use the original IEEE representation.
         return NaN_Image (Item, Lua_Ada_Config.Alire_Host_OS);
      elsif Item > Real_Value'Last then
         return "inf";
      elsif Item < -Real_Value'Last then
         return "-inf";
      end if;
      --  Lua 5.5 first formats fifteen significant digits, then uses
      --  seventeen when that text would not round-trip to the same double.
      --  Ada supplies rounded digits; we implement general-format selection
      --  and Lua's integer-looking .0 suffix without importing printf.
      loop
         Real_IO.Put (Buffer, Item, Aft => Precision - 1, Exp => 3);
         exit when Precision = 17 or else Lua.Numbers.To_Real
           (Lua.Numbers.Read
              (Ada.Strings.Fixed.Trim (Buffer, Ada.Strings.Both))) = Item;
         Precision := 17;
      end loop;
      declare
         Text : constant String :=
           Ada.Strings.Fixed.Trim (Buffer, Ada.Strings.Both);
         E : constant Positive := Ada.Strings.Fixed.Index (Text, "E");
         Power : constant Integer := Integer'Value (Text (E + 1 .. Text'Last));
         Negative : constant Boolean := Text (Text'First) = '-';
         First : constant Positive := (if Negative then 2 else 1);
         Digits_Text : Unbounded_String;
         Result : Unbounded_String;
         Point : constant Integer := Power + 1;
      begin
         for Index in First .. E - 1 loop
            if Text (Index) /= '.' then
               Append (Digits_Text, Text (Index));
            end if;
         end loop;
         while Length (Digits_Text) > 1 and then
           Element (Digits_Text, Length (Digits_Text)) = '0'
         loop
            Delete (Digits_Text, Length (Digits_Text), Length (Digits_Text));
         end loop;
         if Negative then
            Append (Result, '-');
         end if;
         if Power < -4 or else Power >= Precision then
            Append (Result, Element (Digits_Text, 1));
            if Length (Digits_Text) > 1 then
               Append (Result, '.' & Slice (Digits_Text, 2,
                                           Length (Digits_Text)));
            end if;
            declare
               Magnitude : constant String := Ada.Strings.Fixed.Trim
                 (Integer'Image (abs Power), Ada.Strings.Both);
            begin
               Append (Result, 'e');
               Append (Result, (if Power < 0 then '-' else '+'));
               if Magnitude'Length < 2 then
                  Append (Result, '0');
               end if;
               Append (Result, Magnitude);
            end;
         elsif Point <= 0 then
            Append (Result, "0.");
            for Index in 1 .. -Point loop
               Append (Result, '0');
            end loop;
            Append (Result, Digits_Text);
         elsif Point >= Length (Digits_Text) then
            Append (Result, Digits_Text);
            for Index in Length (Digits_Text) + 1 .. Point loop
               Append (Result, '0');
            end loop;
            Append (Result, ".0");
         else
            Append (Result, Slice (Digits_Text, 1, Point) & '.' &
                    Slice (Digits_Text, Point + 1, Length (Digits_Text)));
         end if;
         return To_String (Result);
      end;
   end Real_Image;

   function Image (Item : Value) return String is
   begin
      case Item.Kind is
         when Nil_Kind => return "nil";
         when Boolean_Kind =>
            return (if Item.Boolean_Data then "true" else "false");
         when Integer_Kind =>
            return Ada.Strings.Fixed.Trim
              (Item.Integer_Data'Image, Ada.Strings.Both);
         when Real_Kind => return Real_Image (Item.Real_Data);
         when String_Kind => return To_String (Item.Reference.Bytes);
         when Table_Kind | Closure_Kind | Native_Closure_Kind =>
            return Type_Name (Item) & ": " &
              Ada.Strings.Fixed.Trim
                (Item.Reference.Serial'Image, Ada.Strings.Both);
         when Native_Kind_Value => return "function: native";
      end case;
   end Image;

   function Get (Table : Value; Key : Value) return Value is
   begin
      if Table.Kind /= Table_Kind then
         return Nil_Value;
      end if;
      for Member of Table.Reference.Members loop
         if Member.Item.Kind /= Nil_Kind and then Equal (Member.Key, Key) then
            return Member.Item;
         end if;
      end loop;
      return Nil_Value;
   end Get;

   procedure Set (State : in out World; Table, Key, Item : Value) is
   begin
      if Table.Kind /= Table_Kind then
         Fail (State, "attempt to index a " & Type_Name (Table) & " value");
      elsif Key.Kind = Nil_Kind then
         Fail (State, "table index is nil");
      elsif Key.Kind = Real_Kind and then Key.Real_Data /= Key.Real_Data then
         Fail (State, "table index is NaN");
      end if;
      for Index in Table.Reference.Members.First_Index ..
        Table.Reference.Members.Last_Index
      loop
         if Equal (Table.Reference.Members (Index).Key, Key) then
            --  Equality handles integer/float-equivalent keys. A nil value
            --  leaves a tombstone for next(t, removed_key); that storage
            --  remains charged until the table itself is freed.
            Table.Reference.Members.Replace_Element (Index, (Key, Item));
            return;
         end if;
      end loop;
      if Item.Kind /= Nil_Kind then
         if State.Entry_Count >= State.Bounds.Table_Entries then
            Fail (State, "table entry limit exceeded", Resource => True);
         end if;
         Table.Reference.Members.Append (Table_Entry'(Key, Item));
         State.Entry_Count := State.Entry_Count + 1;
      end if;
   end Set;

   function Table_Length (Table : Value) return Natural is
      Result : Natural := 0;
   begin
      --  A contiguous-prefix border is valid even for tables with holes.
      --  Do not confuse the number of hash members with Lua's sequence border.
      while Get (Table, (Integer_Kind, Integer_Value (Result) + 1)).Kind /=
        Nil_Kind
      loop
         Result := Result + 1;
      end loop;
      return Result;
   end Table_Length;

   function Next (State : in out World; Table, Key : Value)
                  return Values.Vector
   is
      Found : Boolean := Key.Kind = Nil_Kind;
      Result : Values.Vector;
   begin
      if Table.Kind /= Table_Kind then
         Fail (State, "table expected by next");
      end if;
      for Member of Table.Reference.Members loop
         if Found and then Member.Item.Kind /= Nil_Kind then
            Result.Append (Member.Key);
            Result.Append (Member.Item);
            return Result;
         elsif not Found and then Equal (Member.Key, Key) then
            Found := True;
         end if;
      end loop;
      if not Found then
         Fail (State, "invalid key to 'next'");
      end if;
      Result.Append (Nil_Value);
      return Result;
   end Next;

   function Read_Local (Scope : Object_Access; Symbol : Positive)
                        return Value
   is
      Current : Object_Access := Scope;
   begin
      while Current /= null loop
         for Local of Current.Locals loop
            if Local.Symbol = Symbol then
               return Local.Item;
            end if;
         end loop;
         Current := Current.Parent;
      end loop;
      raise Program_Error with "compiler referenced a missing lexical cell";
   end Read_Local;

   procedure Write_Local
     (Scope : Object_Access; Symbol : Positive; Item : Value)
   is
      Current : Object_Access := Scope;
   begin
      while Current /= null loop
         for Index in Current.Locals.First_Index .. Current.Locals.Last_Index
         loop
            if Current.Locals (Index).Symbol = Symbol then
               Current.Locals.Replace_Element (Index, (Symbol, Item));
               return;
            end if;
         end loop;
         Current := Current.Parent;
      end loop;
      raise Program_Error with "compiler wrote a missing lexical cell";
   end Write_Local;

   procedure Declare_Local
     (Scope : Object_Access; Symbol : Positive; Item : Value)
   is
   begin
      Scope.Locals.Append (Binding'(Symbol, Item));
   end Declare_Local;

   procedure Initialize (State : in out World; Bounds : Limits) is
      Table : Value;
      procedure Install (Name : String; Native : Native_Kind);
      procedure Library (Name, Members : String);
      procedure Arithmetic (Meta : Value; Name : String);
      function Directory_Separator (Host : String) return String;
      function Directory_Separator (Host : String) return String is
        (if Host = "windows" then "\" else "/");
      procedure Arithmetic (Meta : Value; Name : String) is
      begin
         Set (State, Meta, New_String (State, Name),
              New_Native (State, "arith." & Name));
      end Arithmetic;
      procedure Library (Name, Members : String) is
         Module : constant Value := New_Table (State);
         First : Positive := Members'First;
         Last : Natural;
      begin
         Set (State, Table, New_String (State, Name), Module);
         Set (State, (Table_Kind, State.Loaded_Modules),
              New_String (State, Name), Module);
         while First <= Members'Last loop
            Last := First;
            while Last < Members'Last and then Members (Last + 1) /= ' ' loop
               Last := Last + 1;
            end loop;
            Set (State, Module,
                 New_String (State, Members (First .. Last)),
                 New_Native (State, Name & "." & Members (First .. Last)));
            First := Last + 2;
         end loop;
      end Library;

      procedure Install (Name : String; Native : Native_Kind) is
         Key : constant Value := New_String (State, Name);
      begin
         Set (State, Table, Key, (Native_Kind_Value, Native));
      end Install;
   begin
      State.Bounds := Bounds;
      Table := New_Table (State);
      State.Globals := Table.Reference;
      State.Loaded_Modules := New_Table (State).Reference;
      State.Preload_Modules := New_Table (State).Reference;
      --  Bootstrap performs no collection. The globals table becomes the
      --  permanent root before any builtins or version strings are installed.
      Install ("print", Print_Function);
      Install ("assert", Assert_Function);
      Install ("error", Error_Function);
      Install ("pcall", Pcall_Function);
      Install ("type", Type_Function);
      Install ("tonumber", Tonumber_Function);
      Install ("tostring", Tostring_Function);
      Install ("select", Select_Function);
      Install ("next", Next_Function);
      Install ("pairs", Pairs_Function);
      Install ("ipairs", Ipairs_Function);
      Install ("rawequal", Rawequal_Function);
      Install ("rawget", Rawget_Function);
      Install ("rawset", Rawset_Function);
      Install ("rawlen", Rawlen_Function);
      declare
         Key : Value := New_String (State, "_G");
         Version : constant Value := New_String (State, Language_Version);
      begin
         Set (State, Table, Key, Table);
         Key := New_String (State, "_VERSION");
         Set (State, Table, Key, Version);
      end;
      Library ("string", "byte char len lower upper sub reverse rep " &
               "format find match gmatch gsub pack packsize unpack");
      Library ("utf8", "char len codepoint offset codes");
      Library ("table", "concat insert remove move pack unpack");
      Library ("math", "abs ceil floor fmod max min modf tointeger type ult");
      declare
         Math : constant Value := Get (Table, New_String (State, "math"));
         Package_Value : constant Value := New_Table (State);
         Searchers : constant Value := New_Table (State);
         Captures : constant Values.Vector :=
           Values.To_Vector (Package_Value, 1);
      begin
         --  Capture the original package object. Public field replacement
         --  must not retarget the registry roots used by require/preload.
         Set (State, Table, New_String (State, "package"), Package_Value);
         Set (State, (Table_Kind, State.Loaded_Modules),
              New_String (State, "package"), Package_Value);
         Set (State, Package_Value, New_String (State, "loaded"),
              (Table_Kind, State.Loaded_Modules));
         Set (State, Package_Value, New_String (State, "preload"),
              (Table_Kind, State.Preload_Modules));
         Set (State, Package_Value, New_String (State, "path"),
              New_String (State, "./?.lua;./?/init.lua"));
         Set (State, Package_Value, New_String (State, "config"),
              New_String (State,
                Directory_Separator (Lua_Ada_Config.Alire_Host_OS) &
                Character'Val (10) & ";" &
                Character'Val (10) & "?" & Character'Val (10) & "!" &
                Character'Val (10) & "-" & Character'Val (10)));
         Set (State, Package_Value,
              New_String (State, "searchers"), Searchers);
         Set (State, Package_Value, New_String (State, "searchpath"),
              New_Native (State, "package.searchpath", Captures));
         Set (State, Searchers, (Integer_Kind, 1),
              New_Native (State, "package.preload_searcher", Captures));
         Set (State, Searchers, (Integer_Kind, 2),
              New_Native (State, "package.lua_searcher", Captures));
         Set (State, Table, New_String (State, "require"),
              New_Native (State, "base.require", Captures));
         Set (State, Table, New_String (State, "load"),
              New_Native (State, "base.load"));
         Set (State, Table, New_String (State, "xpcall"),
              New_Native (State, "base.xpcall"));
         Set (State, Table, New_String (State, "loadfile"),
              New_Native (State, "base.loadfile"));
         Set (State, Table, New_String (State, "dofile"),
              New_Native (State, "base.dofile"));
         Set (State, Math, New_String (State, "maxinteger"),
              (Integer_Kind, Integer_Value'Last));
         Set (State, Math, New_String (State, "mininteger"),
              (Integer_Kind, Integer_Value'First));
         Set (State, Math, New_String (State, "pi"),
              (Real_Kind, Ada.Numerics.Pi));
         Set (State, Math, New_String (State, "huge"),
              (Real_Kind, Lua.Numbers.Read ("1e999").Real_Item));
      end;
      declare
         Strings : constant Value := Get (Table, New_String (State, "string"));
         Unicode : constant Value := Get (Table, New_String (State, "utf8"));
         Meta : constant Value := New_Table (State);
      begin
         State.String_Metatable := Meta.Reference;
         Set (State, Meta, New_String (State, "__index"), Strings);
         Arithmetic (Meta, "__add");
         Arithmetic (Meta, "__sub");
         Arithmetic (Meta, "__mul");
         Arithmetic (Meta, "__mod");
         Arithmetic (Meta, "__pow");
         Arithmetic (Meta, "__div");
         Arithmetic (Meta, "__idiv");
         Arithmetic (Meta, "__unm");
         Set (State, Unicode, New_String (State, "charpattern"),
              New_String (State, Lua.Engine.Unicode.Charpattern));
         Set (State, Table, New_String (State, "getmetatable"),
              New_Native (State, "base.getmetatable"));
         Set (State, Table, New_String (State, "setmetatable"),
              New_Native (State, "base.setmetatable"));
         Set (State, Table, New_String (State, "tostring"),
              New_Native (State, "base.tostring"));
         Set (State, Table, New_String (State, "print"),
              New_Native (State, "base.print"));
         Set (State, Table, New_String (State, "pairs"),
              New_Native (State, "base.pairs"));
         Set (State, Table, New_String (State, "ipairs"),
              New_Native (State, "base.ipairs"));
      end;
      --  Bootstrap replaces several M1 bindings and creates temporary lookup
      --  keys. Publish a stable live baseline before returning the session;
      --  later heap quotas and collection statistics must describe its owned
      --  environment, not abandoned initialization temporaries.
      Collect (State);
   end Initialize;

   procedure Collect (State : in out World) is
      Pending : Objects.Vector;
      Code_Pending : Prototypes.Vector;
      procedure Mark (Item : Object_Access);
      procedure Mark_Value (Item : Value);
      procedure Mark_Code (Item : Prototype_Access);

      procedure Mark (Item : Object_Access) is
      begin
         if Item /= null and then not Item.Marked then
            Item.Marked := True;
            Pending.Append (Item);
         end if;
      end Mark;

      procedure Mark_Value (Item : Value) is
      begin
         if Item.Kind in String_Kind | Table_Kind | Closure_Kind |
           Native_Closure_Kind
         then
            Mark (Item.Reference);
         end if;
      end Mark_Value;

      procedure Mark_Code (Item : Prototype_Access) is
      begin
         if Item /= null and then not Item.Marked then
            Item.Marked := True;
            Code_Pending.Append (Item);
         end if;
      end Mark_Code;
   begin
      --  Explicit worklists avoid using the Ada stack to traverse arbitrary
      --  user graphs. Marking before enqueueing also terminates on cycles.
      Mark (State.Globals);
      Mark (State.String_Metatable);
      Mark (State.Loaded_Modules);
      Mark (State.Preload_Modules);
      Mark_Value (State.Failure);
      for Item of State.Arguments loop
         Mark_Value (Item);
      end loop;
      for Activation of State.Stack loop
         Mark (Activation.Native_Self);
         for Item of Activation.Native_Arguments loop
            Mark_Value (Item);
         end loop;
         for Item of Activation.Native_Results loop
            Mark_Value (Item);
         end loop;
         for Item of Activation.Native_Captures loop
            Mark_Value (Item);
         end loop;
         Mark (Activation.Scope);
         Mark_Code (Activation.Code);
         Mark (Activation.Vararg_Table);
         for Packet of Activation.Slots loop
            for Item of Packet loop
               Mark_Value (Item);
            end loop;
         end loop;
         for Item of Activation.Varargs loop
            Mark_Value (Item);
         end loop;
      end loop;
      while not Pending.Is_Empty loop
         declare
            Item : constant Object_Access := Pending.Last_Element;
         begin
            Pending.Delete_Last;
            case Item.Kind is
               when String_Object => null;
               when Table_Object =>
                  Mark (Item.Metatable);
                  for Member of Item.Members loop
                     if Member.Item.Kind /= Nil_Kind then
                        Mark_Value (Member.Key);
                        Mark_Value (Member.Item);
                     end if;
                  end loop;
               when Environment =>
                  Mark (Item.Parent);
                  for Local of Item.Locals loop
                     Mark_Value (Local.Item);
                  end loop;
               when Closure =>
                  Mark (Item.Capture);
                  Mark_Code (Item.Code);
               when Native_Closure =>
                  for Capture of Item.Captures loop
                     Mark_Value (Capture);
                  end loop;
            end case;
         end;
      end loop;
      while not Code_Pending.Is_Empty loop
         declare
            Item : constant Prototype_Access := Code_Pending.Last_Element;
         begin
            Code_Pending.Delete_Last;
            for Code of Item.Code loop
               Mark_Code (Code.Nested);
            end loop;
         end;
      end loop;

      --  Tombstones preserve next(t, removed_key) while the key is alive.
      --  They must not retain removed object keys forever or leave dangling
      --  pointers after sweep. Scalar tombstones require no special handling.
      for Item of State.Heap loop
         if Item.Kind = Table_Object and then Item.Marked then
            for Index in Item.Members.First_Index .. Item.Members.Last_Index
            loop
               declare
                  Member : Table_Entry := Item.Members (Index);
               begin
                  if Member.Item.Kind = Nil_Kind and then Member.Key.Kind in
                    String_Kind | Table_Kind | Closure_Kind |
                    Native_Closure_Kind and then
                    not Member.Key.Reference.Marked
                  then
                     Member.Key := Nil_Value;
                     Item.Members.Replace_Element (Index, Member);
                  end if;
               end;
            end loop;
         end if;
      end loop;
      for Index in reverse State.Heap.First_Index .. State.Heap.Last_Index loop
         declare
            Item : Object_Access := State.Heap (Index);
         begin
            if Item.Marked then
               Item.Marked := False;
            else
               if Item.Kind = Table_Object then
                  State.Entry_Count := State.Entry_Count -
                    Natural (Item.Members.Length);
               end if;
               Free_Object (Item);
               State.Heap.Delete (Index);
            end if;
         end;
      end loop;
      for Index in reverse State.Programs.First_Index ..
        State.Programs.Last_Index
      loop
         declare
            Item : Prototype_Access := State.Programs (Index);
         begin
            if Item.Marked then
               Item.Marked := False;
            else
               Free_Program (Item);
               State.Programs.Delete (Index);
            end if;
         end;
      end loop;
      State.Collections := State.Collections + 1;
      State.Next_GC := Positive'Min
        (State.Bounds.Heap_Objects,
         Positive'Max (64, Natural (State.Heap.Length) * 2 + 1));
   end Collect;

   procedure Finalize (State : in out World) is
   begin
      --  A session is the unique allocator owner, so finalization can release
      --  all remaining objects without tracing or invoking user code.
      for Activation of State.Stack loop
         declare
            Item : Frame_Access := Activation;
         begin
            Free_Frame (Item);
         end;
      end loop;
      State.Stack.Clear;
      for Object of State.Heap loop
         declare
            Item : Object_Access := Object;
         begin
            Free_Object (Item);
         end;
      end loop;
      State.Heap.Clear;
      for Program of State.Programs loop
         declare
            Item : Prototype_Access := Program;
         begin
            Free_Program (Item);
         end;
      end loop;
      State.Programs.Clear;
      State.Globals := null;
   end Finalize;

   function Execute
     (State : in out World; Source, Name : String) return Boolean
   is
      Code : Prototype_Access;
   begin
      State.Failure := Nil_Value;
      State.Has_Failure_Value := False;
      State.Failure_Text := Null_Unbounded_String;
      State.Is_Resource := False;
      State.Is_Syntax := False;
      State.Is_Unsupported := False;
      State.Output := Null_Unbounded_String;
      State.Steps := 0;
      State.Failure_At := (others => 1);
      Collect (State);
      if Source'Length > State.Bounds.Source_Bytes then
         Fail (State, "source byte limit exceeded", Resource => True);
      end if;
      Code := Compiler.Compile (State, Source, Name);
      Machine.Run (State, Code);
      State.Arguments.Clear;
      Collect (State);
      return True;
   exception
      when Language_Error =>
         State.Arguments.Clear;
         Machine.Clear_Frames (State);
         Collect (State);
         return False;
      when Storage_Error =>
         Machine.Clear_Frames (State);
         State.Is_Resource := True;
         State.Failure_Text := To_Unbounded_String ("host storage exhausted");
         return False;
      when Error : Constraint_Error | Program_Error =>
         --  Keep the embedding boundary exception-safe, but make an internal
         --  check failure explicit so tests cannot mistake it for Lua parity.
         Machine.Clear_Frames (State);
         State.Failure_Text := To_Unbounded_String
           ("internal Ada check: " & Ada.Exceptions.Exception_Message (Error));
         return False;
   end Execute;
end Lua.Engine;
