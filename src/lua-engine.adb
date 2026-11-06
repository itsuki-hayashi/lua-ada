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

   procedure Free_Context is new Ada.Unchecked_Deallocation
     (Execution_Context, Context_Access);

   function Create_Context (State : in out World) return Context_Id is
      Item : Context_Access := new Execution_Context;
   begin
      --  Registration transfers ownership. Failed vector growth leaves the
      --  allocation local, so release it before propagating Storage_Error.
      begin
         --  Empty registry slots are reused without shifting live identities.
         for Index in State.Contexts.First_Index .. State.Contexts.Last_Index
         loop
            if State.Contexts (Index) = null then
               State.Contexts.Replace_Element (Index, Item);
               return Context_Id (Index);
            end if;
         end loop;
         State.Contexts.Append (Item);
      exception
         when others =>
            Free_Context (Item);
            raise;
      end;
      return Context_Id (State.Contexts.Last_Index);
   end Create_Context;

   procedure Select_Context (State : in out World; Id : Context_Id) is
   begin
      if (State.Current /= null and then (State.Current.Status =
        Running_Context)) or else
        Natural (Id) > State.Contexts.Last_Index or else
        State.Contexts (Positive (Id)) = null
      then
         raise Program_Error with "invalid execution context selection";
      end if;
      State.Current := State.Contexts (Positive (Id));
   end Select_Context;

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
      State.Current.Failure_Text := To_Unbounded_String (Message);
      State.Current.Failure := Nil_Value;
      State.Current.Has_Failure_Value := False;
      State.Current.Failure_Class :=
        (if Resource then Host_Abort
         elsif State.Current.Failure_Class in Syntax_Failure |
           Unsupported_Failure then State.Current.Failure_Class
         else Language_Failure);
      if Resource then
         State.Current.Transfer := (Kind => Host_Stopped, others => <>);
      end if;
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
      begin
         State.Heap.Append (Item);
      exception
         when others =>
            Free_Object (Item);
            raise;
      end;
      return Item;
   end Allocate;

   function New_Thread (State : in out World; Entry_Function : Value)
                        return Value
   is
      Id : constant Context_Id := Create_Context (State);
      Thread : Object_Access;
      Context : constant Context_Access := State.Contexts (Positive (Id));
   begin
      Thread := Allocate (State, Thread_Object);
      Thread.Context_Index := Positive (Id);
      Context.Thread := Thread;
      Context.Entry_Function := Entry_Function;
      Context.Host_Owned := False;
      return (Thread_Kind, Thread);
   exception
      when others =>
         --  Until publication there is no Lua owner for this registry slot.
         --  Failed allocation must not leave an immortal host-owned context.
         declare
            Abandoned : Context_Access := Context;
         begin
            Free_Context (Abandoned);
            State.Contexts.Replace_Element (Positive (Id), null);
         end;
         raise;
   end New_Thread;

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
      if Capture = null and then Code.Is_Main then
         --  A chunk's _ENV is an actual ordered upvalue, including host
         --  chunks. Debug updates and nested closures share this same cell.
         Item.Capture := New_Environment (State, null);
         Declare_Local (State, Item.Capture, Code.Environment_Symbol,
                        (Table_Kind, State.Globals));
         Item.Upvalues.Append
           (Find_Cell (Item.Capture, Code.Environment_Symbol));
      elsif Capture /= null then
         --  Snapshot only referenced bindings, not the mutable environment
         --  container. Cells are shared, but later declarations cannot replace
         --  the identity observed by an earlier closure at a backward goto.
         Item.Capture := New_Environment (State, null);
         if Code.Is_Main then
            Item.Capture.Locals.Append
              (Binding'(Code.Environment_Symbol,
                        Find_Cell (Capture, Code.Environment_Symbol)));
            Item.Upvalues.Append
              (Find_Cell (Capture, Code.Environment_Symbol));
         end if;
         for Symbol of Code.Capture_Symbols loop
            declare
               Cell : constant Object_Access := Find_Cell (Capture, Symbol);
            begin
               Item.Upvalues.Append (Cell);
               Item.Capture.Locals.Append (Binding'(Symbol, Cell));
            end;
         end loop;
      end if;
      return (Closure_Kind, Item);
   end New_Closure;

   function New_Native
     (State : in out World; Name : String;
      Captures : Values.Vector := Values.Empty_Vector) return Value
   is
      Item : constant Object_Access := Allocate (State, Native_Closure);
   begin
      Item.Native_Name := To_Unbounded_String (Name);
      for Capture of Captures loop
         declare
            Cell : constant Object_Access := Allocate (State, Cell_Object);
         begin
            --  Native upvalues also have stable cells. Stateful iterator
            --  writes and debug identities refer to this same owned storage.
            Cell.Cell_Value := Capture;
            Item.Captures.Append (Cell);
         end;
      end loop;
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
         when Light_Identity_Kind => return Left.Identity = Right.Identity;
         when Boolean_Kind => return Left.Boolean_Data = Right.Boolean_Data;
         when Integer_Kind => return Left.Integer_Data = Right.Integer_Data;
         when Real_Kind => return Left.Real_Data = Right.Real_Data;
         when String_Kind =>
            return Left.Reference.Bytes = Right.Reference.Bytes;
         when Table_Kind | Closure_Kind | Native_Closure_Kind | Thread_Kind =>
            return Left.Reference = Right.Reference;
         when Native_Kind_Value => return Left.Native_Data = Right.Native_Data;
      end case;
   end Equal;

   function Truth (Item : Value) return Boolean is
     (Item.Kind /= Nil_Kind and then
        (Item.Kind /= Boolean_Kind or else Item.Boolean_Data));

   function Type_Name (Item : Value) return String is
     (case Item.Kind is
         when Thread_Kind => "thread",
         when Light_Identity_Kind => "userdata",
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
         when Light_Identity_Kind =>
            return "userdata: " & Item.Identity'Image;
         when Nil_Kind => return "nil";
         when Boolean_Kind =>
            return (if Item.Boolean_Data then "true" else "false");
         when Integer_Kind =>
            return Ada.Strings.Fixed.Trim
              (Item.Integer_Data'Image, Ada.Strings.Both);
         when Real_Kind => return Real_Image (Item.Real_Data);
         when String_Kind => return To_String (Item.Reference.Bytes);
         when Table_Kind | Closure_Kind | Native_Closure_Kind | Thread_Kind =>
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

   function Find_Cell
     (Scope : Object_Access; Symbol : Positive) return Object_Access
   is
      Current : Object_Access := Scope;
   begin
      while Current /= null loop
         for Local of Current.Locals loop
            if Local.Symbol = Symbol then
               return Local.Cell;
            end if;
         end loop;
         Current := Current.Parent;
      end loop;
      raise Program_Error with "compiler referenced a missing lexical cell";
   end Find_Cell;

   function Read_Local (Scope : Object_Access; Symbol : Positive)
                        return Value is
     (Find_Cell (Scope, Symbol).Cell_Value);

   procedure Write_Local
     (Scope : Object_Access; Symbol : Positive; Item : Value) is
   begin
      Find_Cell (Scope, Symbol).Cell_Value := Item;
   end Write_Local;

   procedure Declare_Local
     (State : in out World; Scope : Object_Access;
      Symbol : Positive; Item : Value)
   is
      Cell : constant Object_Access := Allocate (State, Cell_Object);
   begin
      --  Each dynamic declaration gets a new identity. It is published in the
      --  owning environment before the VM reaches another collection point.
      Cell.Cell_Value := Item;
      Scope.Locals.Append (Binding'(Symbol, Cell));
   end Declare_Local;

   procedure Set_Policy (State : in out World; Policy : Execution_Policy) is
   begin
      --  Ada embedding retains its configured bounds. Compatible execution
      --  removes project quotas; representational failures remain checked.
      State.Policy := Policy;
      if Policy = Bounded then
         State.Bounds := State.Saved_Bounds;
      else
         State.Bounds := (Syntax_Depth => 200, others => Positive'Last);
      end if;
   end Set_Policy;

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
      --  Bootstrap needs an error root before any library allocation fails.
      Select_Context (State, Create_Context (State));
      State.Main_Context := State.Current;
      State.Main_Thread := Allocate (State, Thread_Object);
      State.Current.Thread := State.Main_Thread;
      State.Bounds := Bounds;
      State.Saved_Bounds := Bounds;
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
      Set (State, Table, New_String (State, "collectgarbage"),
           New_Native (State, "base.collectgarbage"));
      Library ("debug", "getinfo getlocal setlocal getupvalue setupvalue " &
                 "upvalueid sethook gethook traceback");
      Library ("coroutine",
               "create resume yield wrap status running isyieldable close");
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
      procedure Mark_Context (Context : Context_Access);
      function Weak_Mode (Item : Object_Access) return String;
      function Alive (Item : Value) return Boolean;

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
           Native_Closure_Kind | Thread_Kind
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

      function Weak_Mode (Item : Object_Access) return String is
      begin
         --  Metamethod lookup during collection must neither allocate nor
         --  execute Lua. Read the raw mode directly from the metatable.
         if Item.Metatable /= null then
            for Member of Item.Metatable.Members loop
               if Member.Key.Kind = String_Kind and then
                 Member.Key.Reference.Bytes = "__mode" and then
                 Member.Item.Kind = String_Kind
               then
                  declare
                     Mode : constant String :=
                       To_String (Member.Item.Reference.Bytes);
                     Zero : constant Natural := Ada.Strings.Fixed.Index
                       (Mode, "" & Character'Val (0));
                  begin
                     --  Pinned Lua uses strchr for mode flags. Match its
                     --  C-string boundary even though Lua strings are bytes.
                     return Mode (Mode'First ..
                       (if Zero = 0 then Mode'Last else Zero - 1));
                  end;
               end if;
            end loop;
         end if;
         return "";
      end Weak_Mode;

      function Alive (Item : Value) return Boolean is
        (Item.Kind not in Table_Kind | Closure_Kind | Native_Closure_Kind |
           Thread_Kind or else Item.Reference.Marked);
      --  Lua strings have value semantics and are never removed solely by a
      --  weak reference. Other heap identities participate in weak liveness.

      procedure Mark_Context (Context : Context_Access) is
      begin
         Mark_Value (Context.Hook);
         Mark_Value (Context.Entry_Function);
         for Item of Context.Transfer.Results loop
            Mark_Value (Item);
         end loop;
         Mark_Value (Context.Failure);
         for Item of Context.Arguments loop
            Mark_Value (Item);
         end loop;
         for Activation of Context.Stack loop
            Mark_Value (Activation.Callee);
            for Closing of Activation.Closers loop
               Mark (Closing.Cell);
            end loop;
            Mark_Value (Activation.Unwind_Error);
            for Item of Activation.Unwind_Results loop
               Mark_Value (Item);
            end loop;
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
      end Mark_Context;
   begin
      --  Explicit worklists avoid using the Ada stack to traverse arbitrary
      --  user graphs. Marking before enqueueing also terminates on cycles.
      Mark (State.Main_Thread);
      Mark (State.Globals);
      Mark (State.String_Metatable);
      Mark (State.Loaded_Modules);
      Mark (State.Preload_Modules);
      for Context of State.Contexts loop
         if Context /= null and then
           (Context.Host_Owned or else Context.Status in
              Running_Context | Normal_Context)
         then
            Mark (Context.Thread);
            --  Private host-owned contexts may have no Lua thread object.
            if Context.Thread = null then
               Mark_Context (Context);
            end if;
         end if;
      end loop;
      loop
         while not Pending.Is_Empty loop
            declare
               Item : constant Object_Access := Pending.Last_Element;
            begin
               Pending.Delete_Last;
               case Item.Kind is
                  when Thread_Object =>
                     Mark_Context (State.Contexts (Item.Context_Index));
                  when Cell_Object => Mark_Value (Item.Cell_Value);
                  when String_Object => null;
                  when Table_Object =>
                     Mark (Item.Metatable);
                     declare
                        Mode : constant String := Weak_Mode (Item);
                        Keys : constant Boolean :=
                          Ada.Strings.Fixed.Index (Mode, "k") /= 0;
                        Vals : constant Boolean :=
                          Ada.Strings.Fixed.Index (Mode, "v") /= 0;
                     begin
                        for Member of Item.Members loop
                           if Member.Item.Kind /= Nil_Kind then
                              if not Keys or else Member.Key.Kind = String_Kind
                              then
                                 Mark_Value (Member.Key);
                              end if;
                              if Member.Item.Kind = String_Kind or else
                                (not Vals and then
                                 (not Keys or else Alive (Member.Key)))
                              then
                                 Mark_Value (Member.Item);
                              end if;
                           end if;
                        end loop;
                     end;
                  when Environment =>
                     Mark (Item.Parent);
                     for Local of Item.Locals loop
                        Mark (Local.Cell);
                     end loop;
                  when Closure =>
                     Mark (Item.Capture);
                     Mark_Code (Item.Code);
                  when Native_Closure =>
                     for Capture of Item.Captures loop
                        Mark (Capture);
                     end loop;
               end case;
            end;
         end loop;
         --  Ephemerons need a fixed point: a newly reachable key can expose
         --  its value, which may in turn expose a key in another weak table.
         for Item of State.Heap loop
            if Item.Marked and then Item.Kind = Table_Object then
               declare
                  Mode : constant String := Weak_Mode (Item);
               begin
                  if Ada.Strings.Fixed.Index (Mode, "k") /= 0 and then
                    Ada.Strings.Fixed.Index (Mode, "v") = 0
                  then
                     for Member of Item.Members loop
                        if Alive (Member.Key) then
                           Mark_Value (Member.Item);
                        end if;
                     end loop;
                  end if;
               end;
            end if;
         end loop;
         exit when Pending.Is_Empty;
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

      --  Clear weak entries and dead tombstone keys before sweeping. No
      --  table may retain an address which the subsequent sweep releases.
      for Item of State.Heap loop
         if Item.Kind = Table_Object and then Item.Marked then
            for Index in Item.Members.First_Index .. Item.Members.Last_Index
            loop
               declare
                  Member : Table_Entry := Item.Members (Index);
                  Mode : constant String := Weak_Mode (Item);
               begin
                  if (Ada.Strings.Fixed.Index (Mode, "k") /= 0 and then
                        not Alive (Member.Key)) or else
                    (Ada.Strings.Fixed.Index (Mode, "v") /= 0 and then
                        not Alive (Member.Item))
                  then
                     Member.Item := Nil_Value;
                  end if;
                  if Member.Item.Kind = Nil_Kind and then
                    Member.Key.Kind in String_Kind | Table_Kind |
                      Closure_Kind | Native_Closure_Kind | Thread_Kind
                    and then not Member.Key.Reference.Marked
                  then
                     Member.Key := Nil_Value;
                  end if;
                  Item.Members.Replace_Element (Index, Member);
               end;
            end loop;
         end if;
      end loop;
      --  The registry is an ownership index, not a root. Abandoned coroutine
      --  frames are released without running __close; live captured cells
      --  remain independently reachable from surviving closures.
      for Index in State.Contexts.First_Index .. State.Contexts.Last_Index loop
         declare
            Context : Context_Access := State.Contexts (Index);
         begin
            if Context /= null and then not Context.Host_Owned and then
              not Context.Thread.Marked
            then
               for Activation of Context.Stack loop
                  declare
                     Owned : Frame_Access := Activation;
                  begin
                     Free_Frame (Owned);
                  end;
               end loop;
               Free_Context (Context);
               State.Contexts.Replace_Element (Index, null);
            end if;
         end;
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
      if State.Collections < Natural'Last then
         State.Collections := State.Collections + 1;
      end if;
      State.Next_GC := Positive'Min
        (State.Bounds.Heap_Objects,
         Positive'Max (64, Natural (State.Heap.Length) * 2 + 1));
   end Collect;

   procedure Finalize (State : in out World) is
   begin
      --  A session is the unique allocator owner, so finalization can release
      --  all remaining objects without tracing or invoking user code.
      for Context of State.Contexts loop
         declare
            Owned : Context_Access := Context;
         begin
            if Owned /= null then
               for Activation of Owned.Stack loop
                  declare
                     Item : Frame_Access := Activation;
                  begin
                     Free_Frame (Item);
                  end;
               end loop;
               Free_Context (Owned);
            end if;
         end;
      end loop;
      State.Contexts.Clear;
      State.Current := null;
      State.Main_Context := null;
      State.Main_Thread := null;
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
      State.Current.Status := Running_Context;
      State.Current.Failure := Nil_Value;
      State.Current.Has_Failure_Value := False;
      State.Current.Failure_Text := Null_Unbounded_String;
      State.Current.Failure_Class := No_Failure;
      State.Output := Null_Unbounded_String;
      State.Steps := 0;
      State.Current.Failure_At := (others => 1);
      if State.GC_Running then
         Collect (State);
      end if;
      if Source'Length > State.Bounds.Source_Bytes then
         Fail (State, "source byte limit exceeded", Resource => True);
      end if;
      Code := Compiler.Compile (State, Source, Name);
      Machine.Run (State, Code);
      State.Current.Arguments.Clear;
      if State.GC_Running then
         Collect (State);
      end if;
      State.Current.Status := Suspended_Context;
      return True;
   exception
      when Language_Error =>
         State.Current.Status := Suspended_Context;
         State.Current.Arguments.Clear;
         Machine.Clear_Frames (State);
         if State.GC_Running then
            Collect (State);
         end if;
         return False;
      when Storage_Error =>
         State.Current.Status := Suspended_Context;
         Machine.Clear_Frames (State);
         State.Current.Failure_Class := Host_Abort;
         State.Current.Transfer := (Kind => Host_Stopped, others => <>);
         State.Current.Failure_Text := To_Unbounded_String
           ("host storage exhausted");
         return False;
      when Error : Constraint_Error | Program_Error =>
         State.Current.Status := Suspended_Context;
         --  Keep the embedding boundary exception-safe, but make an internal
         --  check failure explicit so tests cannot mistake it for Lua parity.
         Machine.Clear_Frames (State);
         State.Current.Failure_Text := To_Unbounded_String
           ("internal Ada check: " & Ada.Exceptions.Exception_Message (Error));
         return False;
   end Execute;
end Lua.Engine;
