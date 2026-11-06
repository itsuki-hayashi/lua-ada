with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Lua.Lexers;
with Lua.Prototypes;
with Lua.Numbers;
with Interfaces;
with Lua.Storage;
with Lua.Storage.Vectors;
with Lua.Storage.Buffers;
with Lua.Runtime_Configuration;
with System;

private package Lua.Engine is
   --  The engine is deliberately private to Lua's descendants. Public Ada
   --  sessions expose ownership and diagnostics, never these heap pointers,
   --  register packets, or bytecode instructions.
   use Ada.Strings.Unbounded;

   subtype Integer_Value is Lua.Numbers.Integer_Value;
   subtype Real_Value is Lua.Numbers.Real_Value;

   type Execution_Policy is (Bounded, Lua_Compatible);

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
      Syntax_Nodes  : Positive := 200_000;
      Syntax_Depth  : Positive := 200;
   end record;
   --  Bounds are per session/execution, not machine-specific compile flags.

   type Byte_String is record
      Address : System.Address := System.Null_Address;
      Size : Natural := 0;
   end record;
   --  Immutable borrowed view of a string object's managed, NUL-terminated
   --  payload. Copies do not own or extend its lifetime: retain the Lua value
   --  in traced storage whenever a view must survive a collection point.
   function To_String (Item : Byte_String) return String;
   function Length (Item : Byte_String) return Natural;
   function Element (Item : Byte_String; Index : Positive) return Character;
   function "=" (Left, Right : Byte_String) return Boolean;
   function "=" (Left : Byte_String; Right : String) return Boolean;
   function "<" (Left, Right : Byte_String) return Boolean;

   subtype Owned_Buffer is Lua.Storage.Buffers.Buffer;
   function Length (Item : Owned_Buffer) return Natural
     renames Lua.Storage.Buffers.Length;
   function To_String (Item : Owned_Buffer) return String
     renames Lua.Storage.Buffers.To_String;
   procedure Append (Item : in out Owned_Buffer; Text : String)
     renames Lua.Storage.Buffers.Append;
   procedure Append (Item : in out Owned_Buffer; Text : Character)
     renames Lua.Storage.Buffers.Append;

   type Heap_Kind is
     (String_Object, Table_Object, Environment, Closure, Native_Closure,
      Cell_Object, Thread_Object);
   type Heap_Object (Kind : Heap_Kind);
   type Object_Access is access Heap_Object;
   for Object_Access'Storage_Pool use Lua.Storage.Pool;
   type Prototype;
   type Prototype_Access is access Prototype;
   for Prototype_Access'Storage_Pool use Lua.Storage.Pool;
   type Canonical_Program;
   type Canonical_Program_Access is access Canonical_Program;
   for Canonical_Program_Access'Storage_Pool use Lua.Storage.Pool;

   type Native_Kind is
     (Print_Function, Assert_Function, Error_Function, Pcall_Function,
      Type_Function, Tonumber_Function, Tostring_Function, Select_Function,
      Next_Function, Pairs_Function, Ipairs_Function, Ipairs_Step,
      Rawequal_Function, Rawget_Function, Rawset_Function, Rawlen_Function);

   type Value_Kind is
     (Nil_Kind, Boolean_Kind, Integer_Kind, Real_Kind, String_Kind,
      Table_Kind, Closure_Kind, Native_Closure_Kind, Native_Kind_Value,
      Thread_Kind, Light_Identity_Kind);

   type Value (Kind : Value_Kind := Nil_Kind) is record
      case Kind is
         when Nil_Kind => null;
         when Boolean_Kind => Boolean_Data : Boolean;
         when Integer_Kind => Integer_Data : Integer_Value;
         when Real_Kind => Real_Data : Real_Value;
         when String_Kind | Table_Kind | Closure_Kind | Native_Closure_Kind |
           Thread_Kind =>
            Reference : Object_Access;
         when Native_Kind_Value => Native_Data : Native_Kind;
         when Light_Identity_Kind => Identity : System.Address;
      end case;
   end record;
   Nil_Value : constant Value := (Kind => Nil_Kind);

   package Values is new Ada.Containers.Vectors (Positive, Value);
   package Objects is new Ada.Containers.Vectors (Positive, Object_Access);
   package Prototypes is new Ada.Containers.Vectors
     (Positive, Prototype_Access);
   package Scalar_Values is new Lua.Storage.Vectors (Value);
   package Cell_References is new Lua.Storage.Vectors (Object_Access);
   package Canonical_Prototypes is new
     Lua.Storage.Vectors (Prototype_Access);
   package Registers is new Ada.Containers.Vectors (Positive, Positive);
   package Symbols is new Ada.Containers.Vectors (Positive, Positive);

   type Table_Entry is record
      Key  : Value;
      Item : Value;
      Next : Natural := 0;
      Free_Next : Natural := 0;
      Free_Listed : Boolean := False;
   end record;
   --  Member rows retain traversal order and deleted keys. Next links only
   --  hash collisions; dense positive keys use a separate direct index.
   package Table_Indexes is new Lua.Storage.Vectors (Natural);
   package Entries is new Lua.Storage.Vectors (Table_Entry);

   type Binding is record
      Symbol : Positive;
      Cell   : Object_Access;
   end record;
   package Bindings is new Ada.Containers.Vectors (Positive, Binding);

   type Heap_Object (Kind : Heap_Kind) is record
      Marked : Boolean := False;
      Serial : Positive := 1;
      case Kind is
         when Thread_Object => Context_Index : Positive := 1;
         when Cell_Object => Cell_Value : Value;
         when String_Object =>
            Bytes : Byte_String;
            C_Bytes : System.Address := System.Null_Address;
            --  Optional stable NUL-terminated view owned by Memory.
            String_Hash : Interfaces.Unsigned_64 := 0;
         when Table_Object =>
            Members : Entries.Vector;
            Array_Index : Table_Indexes.Vector;
            Hash_Index : Table_Indexes.Vector;
            Prefix_Length : Natural := 0;
            Free_Row : Natural := 0;
            Metatable : Object_Access;
         when Environment =>
            Parent : Object_Access;
            Locals : Bindings.Vector;
         when Closure =>
            Code    : Prototype_Access;
            Capture : Object_Access;
            Upvalues : Objects.Vector;
         when Native_Closure =>
            Native_Name : Unbounded_String;
            Captures : Objects.Vector;
      end case;
   end record;
   --  Objects never move. Pointer exposure to a future C API still requires
   --  separate allocator/layout work; nonmovement alone is not ABI parity.

   type Operation is
     (No_Operation, Clear_Registers,
      Load_Value, Load_String, Move_First, Read_Local, Write_Local,
      Declare_Local, Enter_Scope, Leave_Scope, New_Table, Get_Item,
      Set_Item, Set_Sequence, Unary, Binary, Jump, Jump_False, Jump_True,
      Jump_Nil, Check_Iterator, Goto_Label, Register_Close,
      Make_Closure, Call_Function, Tail_Call, Return_Values, Read_Varargs,
      Pick_Value, For_Initialize, For_Test, For_Advance, Check_Global);

   type Instruction is record
      Op       : Operation := Load_Value;
      A, B, C  : Natural := 0;
      D        : Natural := 0;
      Target   : Natural := 0;
      Literal  : Value;
      Text     : Unbounded_String;
      Name_Kind : Unbounded_String;
      Inputs   : Registers.Vector;
      Nested   : Prototype_Access;
      Operator : Lua.Lexers.Token_Kind := Lua.Lexers.End_Of_Input;
      Location : Lua.Lexers.Source_Location;
   end record;
   --  Each opcode owns the meaning of its register operands. Inputs is an
   --  expression list: only its last packet expands, exactly as in Lua.
   package Instructions is new Ada.Containers.Vectors
     (Positive, Instruction);

   type Symbol_Name is record
      Symbol : Positive;
      Name : Unbounded_String;
   end record;
   package Symbol_Names is new Ada.Containers.Vectors (Positive, Symbol_Name);

   type Prototype is record
      Canonical_Node : Lua.Prototypes.Prototype_Access;
      Canonical_Owner : Canonical_Program_Access;
      Canonical_Constants : Scalar_Values.Vector;
      Marked       : Boolean := False;
      Name         : Unbounded_String;
      Code         : Instructions.Vector;
      Parameters   : Symbols.Vector;
      Capture_Symbols : Symbols.Vector;
      Function_Node : Natural := 0;
      First_Line : Natural := 0;
      Last_Line : Natural := 0;
      Names : Symbol_Names.Vector;
      Uses_Closing : Boolean := False;
      Vararg       : Boolean := False;
      Is_Main      : Boolean := False;
      Vararg_Name  : Natural := 0;
      Environment_Symbol : Positive := 1;
      Register_Count     : Natural := 0;
   end record;

   type Canonical_Program is record
      Model : Lua.Prototypes.Program;
      Wrappers : Canonical_Prototypes.Vector;
      References : Natural := 0;
      Marked : Boolean := False;
   end record;
   --  Runtime wrappers retain one managed immutable canonical graph as a
   --  group. The last released wrapper destroys that owner exactly once.

   type Canonical_Pending_Kind is
     (No_Canonical_Result, Store_Canonical_Results,
      Test_Canonical_Result, Concat_Canonical_Result);

   package Packets is new Ada.Containers.Vectors
     (Positive, Values.Vector, "=" => Values."=");
   type Close_Entry is record
      Cell : Object_Access;
      Symbol : Natural := 0;
      Depth : Natural := 0;
      Frozen_Value : Value := Nil_Value;
      Frozen : Boolean := False;
      --  Snapshot only when this declaration starts leaving its scope.
      --  A close handler may mutate the shared upvalue cell, but that must
      --  not replace a later handler's already departing stack-slot value.
   end record;
   package Close_Lists is new Ada.Containers.Vectors (Positive, Close_Entry);
   type Unwind_Reason is
     (No_Unwind, Scope_Exit, Jump_Exit, Return_Exit, Error_Exit,
      Coroutine_Exit);
   type Frame;
   type Frame_Access is access Frame;
   for Frame_Access'Storage_Pool use Lua.Storage.Pool;
   package Frames is new Ada.Containers.Vectors (Positive, Frame_Access);

   type Frame is record
      Is_Native : Boolean := False;
      Native_Name : Unbounded_String;
      Native_Id : Native_Kind := Print_Function;
      Native_Arguments : Values.Vector;
      Native_Results : Values.Vector;
      Native_Captures : Values.Vector;
      Native_Self : Object_Access;
      Native_Buffer : Owned_Buffer;
      Native_Stage : Natural := 0;
      Native_Index : Natural := 0;
      Native_Aux : Natural := 0;
      Native_Operator : Lua.Lexers.Token_Kind := Lua.Lexers.End_Of_Input;
      Call_Site : Lua.Lexers.Source_Location;
      --  Native continuation storage is owned by the activation. Pending
      --  arguments/results/captures remain traced while Lua callbacks run.
      Code       : Prototype_Access;
      PC         : Positive := 1;
      Scope      : Object_Access;
      Scope_Depth : Natural := 0;
      Slots      : Packets.Vector;
      Canonical_Registers : Scalar_Values.Vector;
      Canonical_Cells : Cell_References.Vector;
      Canonical_Top : Natural := 0;
      Canonical_GC_Top : Natural := 0;
      --  Exclusive live scalar stack bound while a caller is suspended.
      Canonical_Pending : Canonical_Pending_Kind := No_Canonical_Result;
      Canonical_Base : Natural := 0;
      Canonical_Wanted : Integer := 0;
      Canonical_Test : Boolean := False;
      Canonical_Concat_Last : Natural := 0;
      Varargs    : Values.Vector;
      Vararg_Table : Object_Access;
      Return_To  : Natural := 0;
      Protection : Natural := 0;
      Slot_Cost : Natural := 0;
      Native_Charge : Boolean := False;
      Blocks_Yield : Boolean := False;
      Callee : Value;
      Is_Tail_Call : Boolean := False;
      Call_Name : Unbounded_String;
      Name_Kind : Unbounded_String;
      Transfer_Count : Natural := 0;
      Entry_Hook_Done : Boolean := False;
      Return_Hook_Done : Boolean := False;
      Hook_Line : Natural := 0;
      Hook_PC : Natural := 0;
      Last_Executed_PC : Natural := 0;
      Line_Hook_Checked : Boolean := False;
      Closers : Close_Lists.Vector;
      Unwind : Unwind_Reason := No_Unwind;
      Unwind_Owner : Frame_Access;
      Unwind_Depth : Natural := 0;
      Unwind_PC : Natural := 0;
      Unwind_Live : Registers.Vector;
      Unwind_Results : Values.Vector;
      Unwind_Error : Value;
      Unwind_Has_Error : Boolean := False;
   end record;
   --  A packet preserves all results of a call/vararg expression. Scalar
   --  consumers read its first value; parentheses explicitly collapse it.
   --  Frames are explicit so tail calls need not consume the Ada call stack.

   type Native_Action_Kind is (Finished, Invoke, Continue_Step);
   type Native_Action is record
      Kind : Native_Action_Kind := Finished;
      Results : Values.Vector;
      Function_Value : Value;
      Arguments : Values.Vector;
   end record;
   --  Native drivers request calls through the VM rather than recursing into
   --  the executor. All retained values must be stored in their activation.

   type Context_Status is
     (New_Context, Running_Context, Suspended_Context, Normal_Context,
      Dead_Context);
   type Execution_Phase is (Executing, Closing);
   type Failure_Kind is
     (No_Failure, Language_Failure, Memory_Failure, Syntax_Failure,
      Unsupported_Failure,
      Host_Abort);
   type Transfer_Kind is
     (No_Transfer, Completed, Lua_Raised, Yielded, Resume_Requested,
      Close_Requested, Host_Stopped);
   type Control_Transfer is record
      Kind : Transfer_Kind := No_Transfer;
      Results : Values.Vector;
      Target : Natural := 0;
   end record;
   --  Transfers are owned packets, not Ada-stack continuations. They remain
   --  roots until the scheduler hands them to the recipient activation.

   type Execution_Context;
   type Context_Access is access Execution_Context;
   for Context_Access'Storage_Pool use Lua.Storage.Pool;
   type Execution_Context is record
      Stack        : Frames.Vector;
      Arguments    : Values.Vector;
      Foreign_Stack : Values.Vector;
      Foreign_State : System.Address := System.Null_Address;
      Foreign_Block : System.Address := System.Null_Address;
      Foreign_Control : System.Address := System.Null_Address;
      --  The public C stack is rooted independently of initial Lua arguments.
      --  A synchronous foreign call borrows it without changing ownership.
      Failure      : Value;
      Has_Failure_Value : Boolean := False;
      Failure_Text : Unbounded_String;
      Failure_At   : Lua.Lexers.Source_Location;
      Failure_Class : Failure_Kind := No_Failure;
      Status : Context_Status := New_Context;
      Phase : Execution_Phase := Executing;
      Transfer : Control_Transfer;
      Resumer : Context_Access;
      Entry_Function : Value;
      Thread : Object_Access;
      Host_Owned : Boolean := True;
      Non_Yieldable : Natural := 0;
      Stack_Slots : Natural := 0;
      Native_Depth : Natural := 0;
      Hook : Value;
      Hook_Mask : Unbounded_String;
      Hook_Count : Natural := 0;
      Hook_Reported_Count : Integer_Value := 0;
      Hook_Remaining : Natural := 0;
      Hook_Active : Boolean := False;
      Hook_Frame : Frame_Access;
      Hook_Transfer : Boolean := False;
      Cleanup_Depth : Natural := 0;
   end record;
   --  Contexts own frames and transient argument/error roots. Referenced
   --  heap objects belong to their world and can be shared across contexts.
   package Context_Lists is new Ada.Containers.Vectors
     (Positive, Context_Access);
   type Context_Id is new Positive;
   --  IDs are relative to one owning world, not transferable object handles.

   type Random_State is array (0 .. 3) of Interfaces.Unsigned_64;

   type World is limited record
      Memory : Lua.Storage.Owner;
      --  The allocator owner outlives every typed object and buffer in this
      --  universe. Explicit subpool allocators never borrow a global owner.
      Bounds       : Limits;
      Saved_Bounds : Limits;
      Policy : Execution_Policy := Bounded;
      Random_Words : Random_State := [others => 0];
      Random_Seeded : Boolean := False;
      Random_Use_32_Bits : Boolean :=
        Lua.Runtime_Configuration.Random_32_Bits;
      Math_Compatibility : Boolean :=
        Lua.Runtime_Configuration.Compatibility_Math;
      Open_Standard_Libraries : Boolean := True;
      Contexts     : Context_Lists.Vector;
      Current      : Context_Access;
      Main_Context : Context_Access;
      Main_Thread : Object_Access;
      --  Current borrows a context owned by Contexts; it never owns it twice.
      Heap         : Objects.Vector;
      Programs     : Prototypes.Vector;
      Globals      : Object_Access;
      Foreign_Registry : Object_Access;
      Memory_Error_Value : Value;
      Entry_Code : Prototype_Access;
      Operation_Roots : Values.Vector;
      Operation_Programs : Prototypes.Vector;
      Operation_Active : Boolean := False;
      Operation_Start : Positive := 1;
      Compiling : Boolean := False;
      Memory_Ready : Boolean := False;
      Collector_Active : Boolean := False;
      String_Metatable : Object_Access;
      Loaded_Modules : Object_Access;
      Preload_Modules : Object_Access;
      Next_Symbol  : Positive := 1;
      Next_Object  : Positive := 1;
      Entry_Count  : Natural := 0;
      Collections  : Natural := 0;
      GC_Running : Boolean := True;
      Next_GC      : Positive := 256;
      Steps        : Natural := 0;
      Native_Depth : Natural := 0;
      Output       : Unbounded_String;
   end record;
   type World_Access is access World;

   function C_Option (Text : String) return String;
   --  Return the prefix before NUL for pinned Lua's C-string option fields.
   --  Lua values remain byte strings; apply this only at such option parsers.
   --  Arbitrary Ada String lower bounds are preserved by the slice.

   Language_Error : exception;
   --  Internal structured control transfer only; sessions catch it.

   procedure Fail (State : in out World; Message : String;
                   Resource : Boolean := False);
   --  Record a diagnostic before raising the internal transfer exception.

   procedure Begin_Operation (State : in out World);
   procedure End_Operation (State : in out World);
   --  Bound temporary construction roots to one atomic VM/foreign operation.
   --  Publish outgoing values in frames/stacks before ending the operation.
   procedure Pin (State : in out World; Item : Value);
   procedure Pin (State : in out World; Items : Values.Vector);
   procedure Pin (State : in out World; Code : Prototype_Access);
   --  Retain preexisting values before destructive stack/frame transitions.
   function Retry_Allocation
     (State : in out World; Retried : in out Boolean) return Boolean;
   --  Perform at most one emergency collection for a refused allocation.
   --  Bootstrap and recursive collection never retry or call Lua finalizers.

   procedure Record_Memory_Error (State : in out World);
   --  Publish the preallocated memory-error object without a new Lua
   --  allocation, and acknowledge any wrapped controlled-copy refusal.

   function Create_Context (State : in out World) return Context_Id;
   --  Register an empty context without selecting it or resetting budgets.
   --  Finalize releases all registered contexts. Host-owned inactive contexts
   --  are roots; Lua-owned contexts instead follow reachable thread objects.
   procedure Select_Context (State : in out World; Id : Context_Id);
   --  Select between driver invocations. Invalid IDs or selection while the
   --  current driver is running raise Program_Error (internal misuse).

   procedure Set_Policy (State : in out World; Policy : Execution_Policy);
   --  Preserve explicit host limits when temporarily selecting
   --  compatible work.

   procedure Release_Foreign_Context
     (State : in out World; Context : Context_Access);
   --  Release opaque foreign control/surface blocks before a context dies.
   --  Both blocks are trivially finalizable and owned by State.Memory.

   procedure Initialize (State : in out World; Bounds : Limits);
   procedure Finalize (State : in out World);
   procedure Collect
     (State : in out World; Emergency : Boolean := False);
   --  Mark/sweep sees globals, frames, packets, captures, and current failure.

   function New_Thread (State : in out World; Entry_Function : Value)
                        return Value;
   --  Allocate a Lua-owned context and its unique thread object.

   function New_Frame (State : in out World) return Frame_Access;
   function New_Program (State : in out World) return Prototype_Access;
   procedure Release_Program (Item : in out Prototype_Access);
   --  Release the wrapper and its shared canonical owner at the final edge.
   function New_Cell (State : in out World; Item : Value) return Object_Access;
   --  Allocate an actual stable lexical cell, rooted by its published owner.
   --  Bind every frame-owned managed container before any capacity grows.

   function New_String (State : in out World; Text : String) return Value;
   function New_String
     (State : in out World; Text : in out Owned_Buffer) return Value;
   --  Publish a managed builder through a borrowed view, avoiding an
   --  input-sized temporary Ada String allocation.
   function New_Table (State : in out World) return Value;
   function New_Environment
     (State : in out World; Parent : Object_Access) return Object_Access;
   function New_Closure
     (State : in out World; Code : Prototype_Access;
      Capture : Object_Access) return Value;
   function New_Native
     (State : in out World; Name : String;
      Captures : Values.Vector := Values.Empty_Vector) return Value;
   --  Allocate a stateful native callable; captures are collector roots.
   function Metafield
     (State : in out World; Item : Value; Name : String) return Value;
   --  Raw event lookup; it never invokes Lua or follows __index.

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
     (State : in out World; Scope : Object_Access;
      Symbol : Positive; Item : Value);

   function Find_Cell
     (Scope : Object_Access; Symbol : Positive) return Object_Access;
   --  Borrow the stable cell shared by lexical reads and closure captures.

   function Execute
     (State : in out World; Source, Name : String) return Boolean;
   --  Compile and execute a named text chunk. Failure leaves session globals
   --  usable; current frames are unwound and their roots released.
end Lua.Engine;
