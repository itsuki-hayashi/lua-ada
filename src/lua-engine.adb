with Ada.Exceptions;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;
with Ada.Numerics;
with Lua.Engine.Unicode;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Ada.Unchecked_Conversion;
with Lua_Ada_Config;
with Lua.Engine.Compiler;
with Lua.Engine.Tables;
with Lua.Engine.Mathematics;
with Lua.Engine.Machine;

package body Lua.Engine is
   use type Ada.Containers.Count_Type;
   use type Ada.Exceptions.Exception_Id;
   use type Integer_Value;
   use type System.Address;
   use System.Storage_Elements;
   use type Real_Value;
   use type Interfaces.Unsigned_64;
   use type Lua.Prototypes.Prototype_Access;

   package Characters is new
     System.Address_To_Access_Conversions (Character);

   function To_String (Item : Byte_String) return String is
      View : String (1 .. Item.Size)
        with Import, Address => Item.Address;
   begin
      --  The view itself borrows managed bytes. The returned Ada String is a
      --  caller-owned value; no secondary permanent cache owns Lua storage.
      return View;
   end To_String;

   function Length (Item : Byte_String) return Natural is (Item.Size);

   function Element (Item : Byte_String; Index : Positive) return Character is
   begin
      if Index > Item.Size then
         raise Constraint_Error with "Lua byte string index out of range";
      end if;
      return Characters.To_Pointer (Item.Address +
        System.Storage_Elements.Storage_Offset (Index - 1)).all;
   end Element;

   function "=" (Left, Right : Byte_String) return Boolean is
   begin
      if Left.Size /= Right.Size then
         return False;
      elsif Left.Address = Right.Address then
         return True;
      end if;
      for Index in 1 .. Left.Size loop
         if Element (Left, Index) /= Element (Right, Index) then
            return False;
         end if;
      end loop;
      return True;
   end "=";

   function "=" (Left : Byte_String; Right : String) return Boolean is
   begin
      if Left.Size /= Right'Length then
         return False;
      end if;
      for Index in 1 .. Left.Size loop
         if Element (Left, Index) /= Right (Right'First + Index - 1) then
            return False;
         end if;
      end loop;
      return True;
   end "=";

   function "<" (Left, Right : Byte_String) return Boolean is
      A, B : Character;
   begin
      for Index in 1 .. Natural'Min (Left.Size, Right.Size) loop
         A := Element (Left, Index);
         B := Element (Right, Index);
         if A /= B then
            return A < B;
         end if;
      end loop;
      return Left.Size < Right.Size;
   end "<";

   function Real_Bits is new Ada.Unchecked_Conversion
     (Real_Value, Interfaces.Unsigned_64);
   --  Read only the IEEE sign bit for diagnostic formatting. Numeric values
   --  remain IEEE doubles; no arbitrary bits are imported through this helper.

   procedure Release_Object is new Ada.Unchecked_Deallocation
     (Heap_Object, Object_Access);
   procedure Release_Prototype is new Ada.Unchecked_Deallocation
     (Prototype, Prototype_Access);
   procedure Free_Frame is new Ada.Unchecked_Deallocation
     (Frame, Frame_Access);
   --  Deallocation is confined to this owning world. Lua values themselves
   --  never free objects, which is essential for shared/cyclic graphs.

   procedure Free_Context is new Ada.Unchecked_Deallocation
     (Execution_Context, Context_Access);

   procedure Release_Canonical is new Ada.Unchecked_Deallocation
     (Canonical_Program, Canonical_Program_Access);

   procedure Release_Program (Item : in out Prototype_Access) is
      Owner : Canonical_Program_Access;
   begin
      if Item = null then return; end if;
      Owner := Item.Canonical_Owner;
      Release_Prototype (Item);
      if Owner /= null then
         Owner.References := Owner.References - 1;
         if Owner.References = 0 then
            Release_Canonical (Owner);
         end if;
      end if;
   end Release_Program;

   procedure Free_Object (State : in out World; Item : in out Object_Access);

   procedure Free_Object (State : in out World; Item : in out Object_Access) is
   begin
      --  C observes this immutable view only while the Lua string is live.
      --  Release it with the string, never through a permanent facade cache.
      if Item /= null and then Item.Kind = String_Object and then
        Item.C_Bytes /= System.Null_Address
      then
         Lua.Storage.Release (State.Memory, Item.C_Bytes);
      end if;
      Release_Object (Item);
   end Free_Object;

   function Owned_Values
     (State : in out World; Source : Values.Vector := Values.Empty_Vector)
      return Values.Vector
   is
   begin
      return Owned_Values (Lua.Storage.Reference (State.Memory), Source);
   end Owned_Values;

   function Owned_Values
     (Memory : not null Lua.Storage.Owner_Access;
      Source : Values.Vector := Values.Empty_Vector) return Values.Vector
   is
   begin
      return Result : Values.Vector do
         Result.Set_Owner (Memory);
         Result.Append (Source);
      end return;
   end Owned_Values;

   function One_Value
     (State : in out World; Item : Value;
      Count : Ada.Containers.Count_Type := 1) return Values.Vector is
   begin
      return One_Value (Lua.Storage.Reference (State.Memory), Item, Count);
   end One_Value;

   function One_Value
     (Memory : not null Lua.Storage.Owner_Access; Item : Value;
      Count : Ada.Containers.Count_Type := 1) return Values.Vector is
   begin
      return Values.To_Vector
        (Memory, Item, Count);
   end One_Value;

   function New_Action (State : in out World) return Native_Action is
   begin
      return Result : Native_Action do
         Result.Results.Set_Owner (Lua.Storage.Reference (State.Memory));
         Result.Arguments.Set_Owner (Lua.Storage.Reference (State.Memory));
      end return;
   end New_Action;

   procedure Release_Foreign_Context
     (State : in out World; Context : Context_Access)
   is
   begin
      if Context /= null then
         Lua.Storage.Release (State.Memory, Context.Foreign_Block);
         Lua.Storage.Release (State.Memory, Context.Foreign_Control);
         Context.Foreign_State := System.Null_Address;
      end if;
   end Release_Foreign_Context;

   function Create_Context (State : in out World) return Context_Id is
      Item : Context_Access;
      Retried : Boolean := False;
   begin
      loop
         begin
            Item := new (Lua.Storage.Handle (State.Memory)) Execution_Context;
            exit;
         exception
            when Lua.Storage.Allocation_Error =>
               if not Retry_Allocation (State, Retried) then
                  raise;
               end if;
         end;
      end loop;
      Item.Memory := Lua.Storage.Reference (State.Memory);
      Item.Stack.Set_Owner (Item.Memory);
      Item.Arguments.Set_Owner (Item.Memory);
      Item.Foreign_Stack.Set_Owner (Item.Memory);
      Item.Transfer.Results.Set_Owner (Item.Memory);
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

   function C_Option (Text : String) return String is
      Zero : constant Natural := Ada.Strings.Fixed.Index
        (Text, "" & Character'Val (0));
   begin
      return Text (Text'First ..
        (if Zero = 0 then Text'Last else Zero - 1));
   end C_Option;

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

   procedure Begin_Operation (State : in out World) is
   begin
      State.Operation_Roots.Clear;
      State.Operation_Programs.Clear;
      State.Operation_Start := State.Next_Object;
      State.Operation_Active := True;
   end Begin_Operation;

   procedure End_Operation (State : in out World) is
   begin
      State.Operation_Roots.Clear;
      State.Operation_Programs.Clear;
      State.Operation_Active := False;
      State.Operation_Start := State.Next_Object;
   end End_Operation;

   procedure Pin (State : in out World; Item : Value) is
   begin
      State.Operation_Roots.Append (Item);
   end Pin;

   procedure Pin (State : in out World; Items : Values.Vector) is
   begin
      for Item of Items loop
         Pin (State, Item);
      end loop;
   end Pin;

   procedure Pin (State : in out World; Code : Prototype_Access) is
   begin
      State.Operation_Programs.Append (Code);
   end Pin;

   function Retry_Allocation
     (State : in out World; Retried : in out Boolean) return Boolean
   is
   begin
      if Retried or else not State.Memory_Ready or else
        State.Collector_Active
      then
         return False;
      end if;
      Retried := True;
      Lua.Storage.Acknowledge_Refusal (State.Memory);
      Collect (State, Emergency => True);
      return True;
   end Retry_Allocation;

   procedure Record_Memory_Error (State : in out World) is
   begin
      Lua.Storage.Acknowledge_Refusal (State.Memory);
      State.Current.Failure := State.Memory_Error_Value;
      State.Current.Has_Failure_Value := True;
      State.Current.Failure_Text := To_Unbounded_String ("not enough memory");
      State.Current.Failure_Class := Memory_Failure;
   end Record_Memory_Error;

   function Allocate (State : in out World; Kind : Heap_Kind)
                      return Object_Access
   is
      Item : Object_Access;
      Retried : Boolean := False;
   begin
      --  Operation roots and construction serials protect temporary values
      --  before an emergency retry. Explicit host quotas stay hard aborts.
      if State.Heap.Length >= Ada.Containers.Count_Type
        (State.Bounds.Heap_Objects) or else State.Next_Object = Positive'Last
      then
         Fail (State, "heap object limit exceeded", Resource => True);
      end if;
      loop
         begin
            Item := new (Lua.Storage.Handle (State.Memory)) Heap_Object (Kind);
            exit;
         exception
            when Lua.Storage.Allocation_Error =>
               if not Retry_Allocation (State, Retried) then
                  raise;
               end if;
         end;
      end loop;
      --  Bind variant storage before publishing the object. Even an empty
      --  environment/closure owns its future growth policy from this point.
      case Kind is
         when Table_Object =>
            Item.Members.Set_Owner (Lua.Storage.Reference (State.Memory));
            Item.Array_Index.Set_Owner (Lua.Storage.Reference (State.Memory));
            Item.Hash_Index.Set_Owner (Lua.Storage.Reference (State.Memory));
         when Environment =>
            Item.Locals.Set_Owner (Lua.Storage.Reference (State.Memory));
         when Closure =>
            Item.Upvalues.Set_Owner (Lua.Storage.Reference (State.Memory));
         when Native_Closure =>
            Item.Captures.Set_Owner (Lua.Storage.Reference (State.Memory));
         when Cell_Object | String_Object | Thread_Object => null;
      end case;
      Item.Serial := State.Next_Object;
      State.Next_Object := State.Next_Object + 1;
      begin
         State.Heap.Append (Item);
      exception
         when others =>
            Free_Object (State, Item);
            raise;
      end;
      return Item;
   end Allocate;

   function New_Cell (State : in out World; Item : Value) return Object_Access
   is
      Cell : constant Object_Access := Allocate (State, Cell_Object);
   begin
      Cell.Cell_Value := Item;
      return Cell;
   end New_Cell;

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
            Release_Foreign_Context (State, Abandoned);
            Free_Context (Abandoned);
            State.Contexts.Replace_Element (Positive (Id), null);
         end;
         raise;
   end New_Thread;

   function New_Frame (State : in out World) return Frame_Access is
      Item : Frame_Access;
      Retried : Boolean := False;
   begin
      loop
         begin
            Item := new (Lua.Storage.Handle (State.Memory)) Frame;
            exit;
         exception
            when Lua.Storage.Allocation_Error =>
               if not Retry_Allocation (State, Retried) then
                  raise;
               end if;
         end;
      end loop;
      Item.Memory := Lua.Storage.Reference (State.Memory);
      Item.Native_Buffer.Set_Owner (Item.Memory);
      Item.Native_Arguments.Set_Owner (Item.Memory);
      Item.Native_Results.Set_Owner (Item.Memory);
      Item.Native_Captures.Set_Owner (Item.Memory);
      Item.Slots.Set_Owner (Item.Memory);
      Item.Varargs.Set_Owner (Item.Memory);
      Item.Closers.Set_Owner (Item.Memory);
      Item.Unwind_Live.Set_Owner (Item.Memory);
      Item.Unwind_Results.Set_Owner (Item.Memory);
      Item.Canonical_Registers.Set_Owner
        (Lua.Storage.Reference (State.Memory));
      Item.Canonical_Cells.Set_Owner (Lua.Storage.Reference (State.Memory));
      return Item;
   end New_Frame;

   function New_Program (State : in out World) return Prototype_Access is
      Retried : Boolean := False;
      Item : Prototype_Access;
   begin
      loop
         begin
            Item := new (Lua.Storage.Handle (State.Memory)) Prototype;
            Item.Code.Set_Owner (Lua.Storage.Reference (State.Memory));
            Item.Parameters.Set_Owner (Lua.Storage.Reference (State.Memory));
            Item.Capture_Symbols.Set_Owner
              (Lua.Storage.Reference (State.Memory));
            Item.Names.Set_Owner (Lua.Storage.Reference (State.Memory));
            Item.Canonical_Constants.Set_Owner
              (Lua.Storage.Reference (State.Memory));
            return Item;
         exception
            when Lua.Storage.Allocation_Error =>
               if not Retry_Allocation (State, Retried) then
                  raise;
               end if;
         end;
      end loop;
   end New_Program;

   function New_String
     (State : in out World; Text : in out Owned_Buffer) return Value
   is
      Result : Value;
      procedure Publish (Bytes : String);
      procedure Publish (Bytes : String) is
      begin
         Result := New_String (State, Bytes);
      end Publish;
   begin
      Text.Query (Publish'Access);
      return Result;
   end New_String;

   function New_String (State : in out World; Text : String) return Value is
      Item : Object_Access;
      Retried : Boolean := False;
   begin
      if Text'Length = Natural'Last then
         Fail (State, "string length overflow");
      elsif Text'Length > State.Bounds.String_Bytes then
         Fail (State, "string byte limit exceeded", Resource => True);
      end if;
      Item := Allocate (State, String_Object);
      loop
         begin
            Item.C_Bytes := Lua.Storage.Allocate
              (State.Memory, Lua.Storage.Byte_Count (Text'Length) + 1);
            exit;
         exception
            when Lua.Storage.Allocation_Error =>
               if not Retry_Allocation (State, Retried) then
                  raise;
               end if;
         end;
      end loop;
      Item.Bytes := (Item.C_Bytes, Text'Length);
      declare
         View : String (1 .. Text'Length + 1)
           with Import, Address => Item.C_Bytes;
      begin
         View (1 .. Text'Length) := Text;
         View (View'Last) := ASCII.NUL;
      end;
      Item.String_Hash := Tables.Hash_Bytes (Text);
      return (String_Kind, Item);
   end New_String;

   function New_Table (State : in out World) return Value is
      Item : constant Object_Access := Allocate (State, Table_Object);
      Memory : constant Lua.Storage.Owner_Access :=
        Lua.Storage.Reference (State.Memory);
   begin
      --  Empty vectors carry the same universe owner before their first
      --  capacity reservation. No table index can fall back to a host pool.
      Item.Members.Set_Owner (Memory);
      Item.Array_Index.Set_Owner (Memory);
      Item.Hash_Index.Set_Owner (Memory);
      return (Table_Kind, Item);
   end New_Table;

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
      if State.Entry_Code = Code then
         --  The just-created closure now owns the prototype edge. Its
         --  construction serial protects that edge across environment/cell
         --  allocation; the compilation bridge need not retain it forever.
         State.Entry_Code := null;
      end if;
      if Code.Canonical_Node /= null then
         --  Nested canonical closures receive descriptor-resolved cells from
         --  CLOSURE. A newly loaded main closure creates closed initial
         --  captures: the first is its actual _ENV binding, with any other
         --  imported capture cells initialized to nil.
         if Code.Is_Main then
            for Index in 1 .. Natural (Code.Canonical_Node.Upvalues.Length)
            loop
               Item.Upvalues.Append
                 ((if Index = 1 and then Capture /= null then
                     Find_Cell (Capture, Code.Environment_Symbol)
                   else New_Cell (State,
                     (if Index = 1 then (Table_Kind, State.Globals)
                      else Nil_Value))));
            end loop;
         end if;
         return (Closure_Kind, Item);
      elsif Capture = null and then Code.Is_Main then
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

   function Metatable_Kind (Kind : Value_Kind) return Value_Kind;
   function Metatable_Kind (Kind : Value_Kind) return Value_Kind is
     (case Kind is
         when Real_Kind => Integer_Kind,
         when Native_Closure_Kind | Native_Kind_Value |
           Foreign_Function_Kind =>
            Closure_Kind,
         when others => Kind);
   --  Lua numbers and functions each have one type metatable, although the
   --  VM has several representations for fast operations and foreign calls.

   function Raw_Metatable (State : World; Item : Value)
                           return Object_Access is
   begin
      if Item.Kind = Table_Kind then
         return Item.Reference.Metatable;
      elsif Item.Kind = String_Kind then
         return State.String_Metatable;
      end if;
      return State.Type_Metatables (Metatable_Kind (Item.Kind));
   end Raw_Metatable;

   procedure Set_Metatable
     (State : in out World; Item : Value; Meta : Object_Access) is
   begin
      --  No allocation or callback is possible while publishing this root.
      --  Debug/C callers deliberately bypass protection; base.setmetatable
      --  checks __metatable before reaching the same ownership transition.
      if Item.Kind = Table_Kind then
         Item.Reference.Metatable := Meta;
      elsif Item.Kind = String_Kind then
         State.String_Metatable := Meta;
      else
         State.Type_Metatables (Metatable_Kind (Item.Kind)) := Meta;
      end if;
   end Set_Metatable;

   function Metafield
     (State : in out World; Item : Value; Name : String) return Value
   is
      Table : constant Object_Access := Raw_Metatable (State, Item);
   begin
      if Table = null then
         return Nil_Value;
      end if;
      return Tables.Raw_Field (Table, Name);
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
         when Light_Identity_Kind | Foreign_Function_Kind =>
            return Left.Identity = Right.Identity;
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
         when Closure_Kind | Native_Closure_Kind | Native_Kind_Value |
           Foreign_Function_Kind =>
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
         when Foreign_Function_Kind =>
            return "function: " & Item.Identity'Image;
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
      Index : Natural;
   begin
      if Table.Kind /= Table_Kind then
         return Nil_Value;
      end if;
      Index := Tables.Find (Table.Reference, Key);
      return (if Index = 0 then Nil_Value
              else Table.Reference.Members (Index).Item);
   end Get;

   procedure Set (State : in out World; Table, Key, Item : Value) is
      Retried : Boolean := False;
   begin
      if Table.Kind /= Table_Kind then
         Fail (State, "attempt to index a " & Type_Name (Table) & " value");
      elsif Key.Kind = Nil_Kind then
         Fail (State, "table index is nil");
      elsif Key.Kind = Real_Kind and then Key.Real_Data /= Key.Real_Data then
         Fail (State, "table index is NaN");
      end if;
      loop
         begin
            Tables.Put (State, Table.Reference, Key, Item);
            exit;
         exception
            when Error : Lua.Storage.Allocation_Error | Program_Error =>
               if Ada.Exceptions.Exception_Identity (Error) =
                 Program_Error'Identity and then
                 not Lua.Storage.Refusal_Pending (State.Memory)
               then
                  raise;
               end if;
               if not Retry_Allocation (State, Retried) then
                  raise;
               end if;
         end;
      end loop;
   end Set;

   function Table_Length (Table : Value) return Natural is
     (if Table.Kind = Table_Kind then Table.Reference.Prefix_Length else 0);
   --  A cached contiguous-prefix border is valid for tables with holes. The
   --  table writer advances it only when its first hole is filled; deletion
   --  and weak-entry clearing shorten/rebuild it before exposing the table.

   function Next (State : in out World; Table, Key : Value)
                  return Values.Vector
   is
      Index : Natural := 0;
      Result : Values.Vector := Owned_Values (State);
   begin
      if Table.Kind /= Table_Kind then
         Fail (State, "table expected by next");
      end if;
      if Key.Kind /= Nil_Kind then
         Index := Tables.Find (Table.Reference, Key);
         if Index = 0 then
            Fail (State, "invalid key to 'next'");
         end if;
      end if;
      --  Resolve the prior key once, then advance over member rows. This
      --  keeps a complete traversal linear while permitting deletion of the
      --  current key: its tombstone remains indexed until collection.
      for Cursor in Index + 1 .. Table.Reference.Members.Last_Index loop
         declare
            Member : constant Table_Entry := Table.Reference.Members (Cursor);
         begin
            if Member.Item.Kind /= Nil_Kind then
               Result.Append (Member.Key);
               Result.Append (Member.Item);
               return Result;
            end if;
         end;
      end loop;
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
      --  Ownership indexes and temporary roots exist before bootstrap can
      --  allocate a context or heap object. No registry grows implicitly.
      State.Contexts.Set_Owner (Lua.Storage.Reference (State.Memory));
      State.Heap.Set_Owner (Lua.Storage.Reference (State.Memory));
      State.Programs.Set_Owner (Lua.Storage.Reference (State.Memory));
      State.Operation_Roots.Set_Owner (Lua.Storage.Reference (State.Memory));
      State.Operation_Programs.Set_Owner
        (Lua.Storage.Reference (State.Memory));
      --  Bootstrap needs an error root before any library allocation fails.
      Select_Context (State, Create_Context (State));
      State.Main_Context := State.Current;
      State.Main_Thread := Allocate (State, Thread_Object);
      State.Current.Thread := State.Main_Thread;
      State.Bounds := Bounds;
      State.Saved_Bounds := Bounds;
      if State.Open_Standard_Libraries then
         Mathematics.Reset (State);
      end if;
      State.Memory_Error_Value := New_String (State, "not enough memory");
      Table := New_Table (State);
      State.Globals := Table.Reference;
      State.Loaded_Modules := New_Table (State).Reference;
      State.Preload_Modules := New_Table (State).Reference;
      --  Ada and C consumers see one real registry, not debug-only mirrors.
      --  Publish it before adding its roots; bootstrap collection is disabled
      --  until initialization completes. Public package fields can later be
      --  replaced without retargeting these internal module tables.
      State.Foreign_Registry := New_Table (State).Reference;
      Set (State, (Table_Kind, State.Foreign_Registry),
           (Integer_Kind, 2), (Table_Kind, State.Globals));
      Set (State, (Table_Kind, State.Foreign_Registry),
           (Integer_Kind, 3), (Thread_Kind, State.Main_Thread));
      Set (State, (Table_Kind, State.Foreign_Registry),
           New_String (State, "_LOADED"),
           (Table_Kind, State.Loaded_Modules));
      Set (State, (Table_Kind, State.Foreign_Registry),
           New_String (State, "_PRELOAD"),
           (Table_Kind, State.Preload_Modules));

      if not State.Open_Standard_Libraries then
         State.Memory_Ready := True;
         --  C-created states start with an empty global table. Opening base
         --  or other libraries is a separate explicit public C operation.
         return;
      end if;
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
                 "upvalueid upvaluejoin getregistry " &
                 "getmetatable setmetatable " &
                 "sethook gethook traceback");
      Library ("coroutine",
               "create resume yield wrap status running isyieldable close");
      Library ("string", "byte char len lower upper sub reverse rep dump " &
               "format find match gmatch gsub pack packsize unpack");
      Library ("utf8", "char len codepoint offset codes");
      Library ("table", "concat insert remove move pack unpack");
      Library ("math",
        "abs ceil floor fmod max min modf tointeger type ult " &
        "acos asin atan cos deg exp frexp ldexp log rad sin sqrt tan " &
        "random randomseed" &
        (if State.Math_Compatibility then
           " atan2 cosh sinh tanh pow log10" else ""));
      declare
         Math : constant Value := Get (Table, New_String (State, "math"));
         Package_Value : constant Value := New_Table (State);
         Searchers : constant Value := New_Table (State);
         Captures : constant Values.Vector :=
           One_Value (State, Package_Value);
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
      State.Memory_Ready := True;
   end Initialize;

   procedure Collect
     (State : in out World; Emergency : Boolean := False)
   is
      Pending : Object_Access;
      Code_Pending : Prototype_Access;
      procedure Mark (Item : Object_Access);
      procedure Mark_Value (Item : Value);
      procedure Mark_Code (Item : Prototype_Access);
      procedure Mark_Context (Context : Context_Access);
      type Weak_Flags is record
         Keys, Items : Boolean := False;
      end record;
      function Weak_Mode (Item : Object_Access) return Weak_Flags;
      function Alive (Item : Value) return Boolean;

      procedure Mark (Item : Object_Access) is
      begin
         if Item /= null and then not Item.Marked then
            Item.Marked := True;
            --  The mark bit prevents duplicate links and terminates cycles.
            --  Intrusive worklists need no growth when the allocator has
            --  already refused the allocation which triggered emergency GC.
            Item.Mark_Next := Pending;
            Pending := Item;
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
            Item.Mark_Next := Code_Pending;
            Code_Pending := Item;
            for Constant_Value of Item.Canonical_Constants loop
               Mark_Value (Constant_Value);
            end loop;
            if Item.Canonical_Owner /= null and then
              not Item.Canonical_Owner.Marked
            then
               Item.Canonical_Owner.Marked := True;
               for Sibling of Item.Canonical_Owner.Wrappers loop
                  Mark_Code (Sibling);
               end loop;
            end if;
         end if;
      end Mark_Code;

      function Weak_Mode (Item : Object_Access) return Weak_Flags is
         Mode : constant Value := Tables.Raw_Field (Item.Metatable, "__mode");
         Result : Weak_Flags;
         Byte : Character;
      begin
         --  Read raw managed bytes without allocating a lookup key or an
         --  input-sized snapshot. Pinned strchr semantics stop at the first
         --  NUL even though ordinary Lua strings retain all later bytes.
         if Mode.Kind = String_Kind then
            for Index in 1 .. Length (Mode.Reference.Bytes) loop
               Byte := Element (Mode.Reference.Bytes, Index);
               exit when Byte = ASCII.NUL;
               Result.Keys := Result.Keys or Byte = 'k';
               Result.Items := Result.Items or Byte = 'v';
               exit when Result.Keys and Result.Items;
            end loop;
         end if;
         return Result;
      end Weak_Mode;

      function Alive (Item : Value) return Boolean is
        (Item.Kind not in Table_Kind | Closure_Kind | Native_Closure_Kind |
           Thread_Kind or else Item.Reference.Marked);
      --  Lua strings have value semantics and are never removed solely by a
      --  weak reference. Other heap identities participate in weak liveness.

      procedure Mark_Context (Context : Context_Access) is
      begin
         for Item of Context.Foreign_Stack loop
            Mark_Value (Item);
         end loop;
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
               if Closing.Frozen then
                  Mark_Value (Closing.Frozen_Value);
               end if;
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
            for Index in Activation.Canonical_Registers.First_Index ..
              Activation.Canonical_Registers.Last_Index
            loop
               if Index > Activation.Canonical_GC_Top then
                  --  C traversethread clears unused stack space beyond top.
                  --  A suspended CALL excludes dead high temporaries; leaving
                  --  them as roots would change observable weak references.
                  Activation.Canonical_Registers.Replace_Element
                    (Index, Nil_Value);
                  Activation.Canonical_Cells.Replace_Element (Index, null);
               elsif Activation.Canonical_Cells (Index) = null then
                  Mark_Value (Activation.Canonical_Registers (Index));
               else
                  --  Debug writes can replace a captured value without
                  --  touching its cached scalar. The cell is authoritative.
                  Mark (Activation.Canonical_Cells (Index));
               end if;
            end loop;
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
      State.Collector_Active := True;
      --  Intrusive worklists avoid both allocation and Ada-stack traversal
      --  of user graphs. Their links are private scratch, cleared on removal.
      Mark (State.Main_Thread);
      Mark (State.Globals);
      Mark (State.Foreign_Registry);
      Mark_Value (State.Memory_Error_Value);
      Mark_Code (State.Entry_Code);
      for Code of State.Operation_Programs loop
         Mark_Code (Code);
      end loop;
      for Item of State.Operation_Roots loop
         Mark_Value (Item);
      end loop;
      if State.Operation_Active or else Emergency then
         --  New objects can be midway through construction and not yet in
         --  their final frame/table. Their monotonic serials avoid allocating
         --  a root-list node while handling allocator exhaustion itself.
         for Item of State.Heap loop
            if Item.Serial >= State.Operation_Start then
               Mark (Item);
            end if;
         end loop;
      end if;
      if State.Compiling then
         --  The transitional compiler indexes its partial program registry.
         --  Keep those entries stable throughout compilation; the canonical
         --  owned program graph removes this temporary registry constraint.
         for Item of State.Programs loop
            Mark_Code (Item);
         end loop;
      end if;
      Mark (State.String_Metatable);
      for Meta of State.Type_Metatables loop
         Mark (Meta);
      end loop;
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
         while Pending /= null loop
            declare
               Item : constant Object_Access := Pending;
            begin
               Pending := Item.Mark_Next;
               Item.Mark_Next := null;
               case Item.Kind is
                  when Thread_Object =>
                     Mark_Context (State.Contexts (Item.Context_Index));
                  when Cell_Object => Mark_Value (Item.Cell_Value);
                  when String_Object => null;
                  when Table_Object =>
                     Mark (Item.Metatable);
                     declare
                        Mode : constant Weak_Flags := Weak_Mode (Item);
                        Keys : constant Boolean :=
                          Mode.Keys;
                        Vals : constant Boolean :=
                          Mode.Items;
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
                     --  Canonical closures retain ordered cells directly;
                     --  they have no private-backend environment container.
                     for Cell of Item.Upvalues loop
                        Mark (Cell);
                     end loop;
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
                  Mode : constant Weak_Flags := Weak_Mode (Item);
               begin
                  if Mode.Keys and then not Mode.Items
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
         exit when Pending = null;
      end loop;
      while Code_Pending /= null loop
         declare
            Item : constant Prototype_Access := Code_Pending;
         begin
            Code_Pending := Item.Mark_Next;
            Item.Mark_Next := null;
            for Code of Item.Code loop
               Mark_Code (Code.Nested);
            end loop;
         end;
      end loop;

      --  Clear weak entries and dead tombstone keys before sweeping. No
      --  table may retain an address which the subsequent sweep releases.
      for Item of State.Heap loop
         if Item.Kind = Table_Object and then Item.Marked then
            declare
               Mode : constant Weak_Flags := Weak_Mode (Item);
            begin
               for Index in Item.Members.First_Index ..
                 Item.Members.Last_Index
               loop
                  declare
                     Member : Table_Entry := Item.Members (Index);
                  begin
                     if (Mode.Keys and then not Alive (Member.Key)) or else
                       (Mode.Items and then not Alive (Member.Item))
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
               Tables.Rebuild (Item);
            end;
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
               State.Contexts.Replace_Element (Index, null);
               Release_Foreign_Context (State, Context);
               Free_Context (Context);
            end if;
         end;
      end loop;
      declare
         Kept : Natural := 0;
      begin
         --  Compact ownership indexes in one pass. Repeated vector deletion
         --  would shift surviving tails for every dead object and make a
         --  mixed live/dead heap quadratic; object addresses never move here.
         for Index in State.Heap.First_Index .. State.Heap.Last_Index loop
            declare
               Item : Object_Access := State.Heap (Index);
            begin
               --  Remove the old slot before releasing an object. If cleanup
               --  raises, the registry cannot retain its deallocated address;
               --  the handler compacts only surviving, non-null entries.
               State.Heap.Replace_Element (Index, null);
               if Item.Marked then
                  Item.Marked := False;
                  Kept := Kept + 1;
                  State.Heap.Replace_Element (Kept, Item);
               else
                  if Item.Kind = Table_Object then
                     State.Entry_Count := State.Entry_Count -
                       Natural (Item.Members.Length);
                  end if;
                  Free_Object (State, Item);
               end if;
            end;
         end loop;
         State.Heap.Set_Length (Ada.Containers.Count_Type (Kept));
      end;
      declare
         Kept : Natural := 0;
      begin
         for Index in State.Programs.First_Index .. State.Programs.Last_Index
         loop
            declare
               Item : Prototype_Access := State.Programs (Index);
            begin
               State.Programs.Replace_Element (Index, null);
               if Item.Marked then
                  Item.Marked := False;
                  if Item.Canonical_Owner /= null then
                     Item.Canonical_Owner.Marked := False;
                  end if;
                  Kept := Kept + 1;
                  State.Programs.Replace_Element (Kept, Item);
               else
                  Release_Program (Item);
               end if;
            end;
         end loop;
         State.Programs.Set_Length (Ada.Containers.Count_Type (Kept));
      end;
      if State.Collections < Natural'Last then
         State.Collections := State.Collections + 1;
      end if;
      State.Next_GC := Positive'Min
        (State.Bounds.Heap_Objects,
         Positive'Max (64,
           (if Natural (State.Heap.Length) >= (Positive'Last - 1) / 2 then
              Positive'Last
            else Natural (State.Heap.Length) * 2 + 1)));
      State.Collector_Active := False;
   exception
      when others =>
         --  Discard partial queues and colors without allocating. Null slots
         --  identify objects already released by an interrupted sweep; live
         --  prefixes were moved, never duplicated, before cleanup could raise.
         Pending := null;
         Code_Pending := null;
         declare
            Kept : Natural := 0;
         begin
            for Index in State.Heap.First_Index .. State.Heap.Last_Index loop
               declare
                  Item : constant Object_Access := State.Heap (Index);
               begin
                  if Item /= null then
                     Item.Marked := False;
                     Item.Mark_Next := null;
                     Kept := Kept + 1;
                     State.Heap.Replace_Element (Kept, Item);
                  end if;
               end;
            end loop;
            State.Heap.Set_Length (Ada.Containers.Count_Type (Kept));
         end;
         declare
            Kept : Natural := 0;
         begin
            for Index in State.Programs.First_Index ..
              State.Programs.Last_Index
            loop
               declare
                  Item : constant Prototype_Access := State.Programs (Index);
               begin
                  if Item /= null then
                     Item.Marked := False;
                     Item.Mark_Next := null;
                     if Item.Canonical_Owner /= null then
                        Item.Canonical_Owner.Marked := False;
                     end if;
                     Kept := Kept + 1;
                     State.Programs.Replace_Element (Kept, Item);
                  end if;
               end;
            end loop;
            State.Programs.Set_Length (Ada.Containers.Count_Type (Kept));
         end;
         State.Collector_Active := False;
         raise;
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
               Release_Foreign_Context (State, Owned);
               Free_Context (Owned);
            end if;
         end;
      end loop;
      State.Contexts.Release;
      State.Current := null;
      State.Main_Context := null;
      State.Main_Thread := null;
      for Object of State.Heap loop
         declare
            Item : Object_Access := Object;
         begin
            Free_Object (State, Item);
         end;
      end loop;
      State.Heap.Release;
      for Program of State.Programs loop
         declare
            Item : Prototype_Access := Program;
         begin
            Release_Program (Item);
         end;
      end loop;
      State.Programs.Release;
      State.Globals := null;
      State.Foreign_Registry := null;
      State.String_Metatable := null;
      State.Type_Metatables := [others => null];
      State.Memory_Error_Value := Nil_Value;
      State.Entry_Code := null;
      End_Operation (State);
      State.Operation_Roots.Release;
      State.Operation_Programs.Release;
      State.Memory_Ready := False;
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
      Begin_Operation (State);
      Code := Compiler.Compile (State, Source, Name);
      State.Entry_Code := Code;
      Machine.Run (State, Code);
      State.Entry_Code := null;
      End_Operation (State);
      State.Current.Arguments.Clear;
      if State.GC_Running then
         Collect (State);
      end if;
      State.Current.Status := Suspended_Context;
      return True;
   exception
      when Language_Error =>
         State.Entry_Code := null;
         End_Operation (State);
         State.Current.Status := Suspended_Context;
         State.Current.Arguments.Clear;
         Machine.Clear_Frames (State);
         if State.GC_Running then
            Collect (State);
         end if;
         return False;
      when Lua.Storage.Allocation_Error =>
         State.Entry_Code := null;
         End_Operation (State);
         Record_Memory_Error (State);
         State.Current.Status := Suspended_Context;
         State.Current.Arguments.Clear;
         Machine.Clear_Frames (State);
         return False;
      when Storage_Error =>
         State.Entry_Code := null;
         End_Operation (State);
         State.Current.Status := Suspended_Context;
         Machine.Clear_Frames (State);
         State.Current.Failure_Class := Host_Abort;
         State.Current.Transfer := (Kind => Host_Stopped, others => <>);
         State.Current.Failure_Text := To_Unbounded_String
           ("host storage exhausted");
         return False;
      when Error : Constraint_Error | Program_Error =>
         State.Entry_Code := null;
         End_Operation (State);
         State.Current.Status := Suspended_Context;
         if Lua.Storage.Refusal_Pending (State.Memory) then
            Record_Memory_Error (State);
            Machine.Clear_Frames (State);
            return False;
         end if;
         --  Keep the embedding boundary exception-safe, but make an internal
         --  check failure explicit so tests cannot mistake it for Lua parity.
         Machine.Clear_Frames (State);
         State.Current.Failure_Text := To_Unbounded_String
           ("internal Ada check: " & Ada.Exceptions.Exception_Message (Error));
         return False;
   end Execute;
end Lua.Engine;
