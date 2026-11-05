with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Lua.Lexers;
with Lua.Numbers;

private package Lua.Engine is
   --  The engine is deliberately private to Lua's descendants. Public Ada
   --  sessions expose ownership and diagnostics, never these heap pointers,
   --  register packets, or bytecode instructions.
   use Ada.Strings.Unbounded;

   subtype Integer_Value is Lua.Numbers.Integer_Value;
   subtype Real_Value is Lua.Numbers.Real_Value;

   type Limits is record
      Source_Bytes  : Positive := 1_000_000;
      Tokens        : Positive := 100_000;
      Instructions  : Positive := 1_000_000;
      Call_Depth    : Positive := 1_024;
      Heap_Objects  : Positive := 100_000;
      Table_Entries : Positive := 100_000;
      String_Bytes  : Positive := 1_000_000;
      Output_Bytes  : Positive := 1_000_000;
      Registers     : Positive := 4_096;
   end record;
   --  Bounds are per session/execution, not machine-specific compile flags.

   type Heap_Kind is (String_Object, Table_Object, Environment, Closure);
   type Heap_Object (Kind : Heap_Kind);
   type Object_Access is access Heap_Object;
   type Prototype;
   type Prototype_Access is access Prototype;

   type Native_Kind is
     (Print_Function, Assert_Function, Error_Function, Pcall_Function,
      Type_Function, Tonumber_Function, Tostring_Function, Select_Function,
      Next_Function, Pairs_Function, Ipairs_Function, Ipairs_Step,
      Rawequal_Function, Rawget_Function, Rawset_Function, Rawlen_Function);

   type Value_Kind is
     (Nil_Kind, Boolean_Kind, Integer_Kind, Real_Kind, String_Kind,
      Table_Kind, Closure_Kind, Native_Kind_Value);

   type Value (Kind : Value_Kind := Nil_Kind) is record
      case Kind is
         when Nil_Kind => null;
         when Boolean_Kind => Boolean_Data : Boolean;
         when Integer_Kind => Integer_Data : Integer_Value;
         when Real_Kind => Real_Data : Real_Value;
         when String_Kind | Table_Kind | Closure_Kind =>
            Reference : Object_Access;
         when Native_Kind_Value => Native_Data : Native_Kind;
      end case;
   end record;
   Nil_Value : constant Value := (Kind => Nil_Kind);

   package Values is new Ada.Containers.Vectors (Positive, Value);
   package Objects is new Ada.Containers.Vectors (Positive, Object_Access);
   package Prototypes is new Ada.Containers.Vectors
     (Positive, Prototype_Access);
   package Registers is new Ada.Containers.Vectors (Positive, Positive);
   package Symbols is new Ada.Containers.Vectors (Positive, Positive);

   type Table_Entry is record
      Key  : Value;
      Item : Value;
   end record;
   package Entries is new Ada.Containers.Vectors (Positive, Table_Entry);

   type Binding is record
      Symbol : Positive;
      Item   : Value;
   end record;
   package Bindings is new Ada.Containers.Vectors (Positive, Binding);

   type Heap_Object (Kind : Heap_Kind) is record
      Marked : Boolean := False;
      Serial : Positive := 1;
      case Kind is
         when String_Object => Bytes : Unbounded_String;
         when Table_Object => Members : Entries.Vector;
         when Environment =>
            Parent : Object_Access;
            Locals : Bindings.Vector;
         when Closure =>
            Code    : Prototype_Access;
            Capture : Object_Access;
      end case;
   end record;
   --  Objects never move. Pointer exposure to a future C API still requires
   --  separate allocator/layout work; nonmovement alone is not ABI parity.

   type Operation is
     (No_Operation, Clear_Registers,
      Load_Value, Load_String, Move_First, Read_Local, Write_Local,
      Declare_Local, Enter_Scope, Leave_Scope, New_Table, Get_Item,
      Set_Item, Set_Sequence, Unary, Binary, Jump, Jump_False, Jump_True,
      Jump_Nil, Check_Iterator,
      Make_Closure, Call_Function, Tail_Call, Return_Values, Read_Varargs,
      Pick_Value, For_Initialize, For_Test, For_Advance, Check_Global);

   type Instruction is record
      Op       : Operation := Load_Value;
      A, B, C  : Natural := 0;
      D        : Natural := 0;
      Target   : Natural := 0;
      Literal  : Value;
      Text     : Unbounded_String;
      Inputs   : Registers.Vector;
      Nested   : Prototype_Access;
      Operator : Lua.Lexers.Token_Kind := Lua.Lexers.End_Of_Input;
      Location : Lua.Lexers.Source_Location;
   end record;
   --  Each opcode owns the meaning of its register operands. Inputs is an
   --  expression list: only its last packet expands, exactly as in Lua.
   package Instructions is new Ada.Containers.Vectors
     (Positive, Instruction);

   type Prototype is record
      Marked       : Boolean := False;
      Name         : Unbounded_String;
      Code         : Instructions.Vector;
      Parameters   : Symbols.Vector;
      Vararg       : Boolean := False;
      Is_Main      : Boolean := False;
      Vararg_Name  : Natural := 0;
      Environment_Symbol : Positive := 1;
      Register_Count     : Natural := 0;
   end record;

   package Packets is new Ada.Containers.Vectors
     (Positive, Values.Vector, "=" => Values."=");
   type Frame;
   type Frame_Access is access Frame;
   package Frames is new Ada.Containers.Vectors (Positive, Frame_Access);

   type Frame is record
      Code       : Prototype_Access;
      PC         : Positive := 1;
      Scope      : Object_Access;
      Slots      : Packets.Vector;
      Varargs    : Values.Vector;
      Vararg_Table : Object_Access;
      Return_To  : Natural := 0;
      Protection : Natural := 0;
   end record;
   --  A packet preserves all results of a call/vararg expression. Scalar
   --  consumers read its first value; parentheses explicitly collapse it.
   --  Frames are explicit so tail calls need not consume the Ada call stack.

   type World is record
      Bounds       : Limits;
      Heap         : Objects.Vector;
      Programs     : Prototypes.Vector;
      Stack        : Frames.Vector;
      Arguments    : Values.Vector;
      Globals      : Object_Access;
      Next_Symbol  : Positive := 1;
      Next_Object  : Positive := 1;
      Entry_Count  : Natural := 0;
      Collections  : Natural := 0;
      Next_GC      : Positive := 256;
      Steps        : Natural := 0;
      Output       : Unbounded_String;
      Failure      : Value;
      Has_Failure_Value : Boolean := False;
      Failure_Text : Unbounded_String;
      Failure_At   : Lua.Lexers.Source_Location;
      Is_Resource  : Boolean := False;
      Is_Syntax    : Boolean := False;
   end record;
   type World_Access is access World;

   Language_Error : exception;
   --  Internal structured control transfer only; sessions catch it.

   procedure Fail (State : in out World; Message : String;
                   Resource : Boolean := False);
   --  Record a diagnostic before raising the internal transfer exception.

   procedure Initialize (State : in out World; Bounds : Limits);
   procedure Finalize (State : in out World);
   procedure Collect (State : in out World);
   --  Mark/sweep sees globals, frames, packets, captures, and current failure.

   function New_String (State : in out World; Text : String) return Value;
   function New_Table (State : in out World) return Value;
   function New_Environment
     (State : in out World; Parent : Object_Access) return Object_Access;
   function New_Closure
     (State : in out World; Code : Prototype_Access;
      Capture : Object_Access) return Value;

   function Equal (Left, Right : Value) return Boolean;
   function Truth (Item : Value) return Boolean;
   function Type_Name (Item : Value) return String;
   function Image (Item : Value) return String;
   function Get (Table : Value; Key : Value) return Value;
   procedure Set (State : in out World; Table, Key, Item : Value);
   function Table_Length (Table : Value) return Natural;
   function Next (State : in out World; Table, Key : Value)
                  return Values.Vector;

   function Read_Local (Scope : Object_Access; Symbol : Positive)
                        return Value;
   procedure Write_Local
     (Scope : Object_Access; Symbol : Positive; Item : Value);
   procedure Declare_Local
     (Scope : Object_Access; Symbol : Positive; Item : Value);

   function Execute
     (State : in out World; Source, Name : String) return Boolean;
   --  Compile and execute a named text chunk. Failure leaves session globals
   --  usable; current frames are unwound and their roots released.
end Lua.Engine;
