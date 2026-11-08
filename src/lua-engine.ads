with Ada.Containers;
with Ada.Strings.Unbounded;
with Lua.Builtin_Registry;
with Lua.Lexers;
with Lua.Prototypes;
with Lua.Numbers;
with Lua.Platform_Modules;
with Interfaces;
with Interfaces.C;
with Lua.Storage;
with Lua.Storage.Vectors;
with Lua.Storage.Buffers;
with Lua.Runtime_Configuration;
with Lua.Diagnostic_Text;
with System;

private package Lua.Engine is
   --  The engine is deliberately private to Lua's descendants. Public Ada
   --  sessions expose ownership and diagnostics, never these heap pointers,
   --  register packets, or bytecode instructions.
   use Ada.Strings.Unbounded;
   use type Lua.Builtin_Registry.Kind;

   subtype Integer_Value is Lua.Numbers.Integer_Value;
   subtype Real_Value is Lua.Numbers.Real_Value;

   type Callback_Identity is record
      Activation : System.Address := System.Null_Address;
      Serial : Interfaces.C.unsigned_long_long := 0;
   end record with Convention => C;
   --  A callback guard identifies its actual owning activation. The serial
   --  distinguishes subsequent uses of a cached frame's stable address.

   type Execution_Policy is (Bounded, Lua_Compatible);
   type Process_Exit_Phase is
     (No_Process_Exit, Exit_Requested, Closing_Main,
      Draining_Exit_Finalizers, Exit_Complete);

   type Warning_Mode_Kind is
     (No_Warning_Handler, Default_Warnings_Off, Default_Warnings_On,
      Default_Warning_Continuation, Custom_Warning_Handler);
   type Warning_Event_Phase is
     (No_Pending_Warning, Warning_Requested, Warning_Callback_Active);

   type Output_Policy is (Captured, Process_Streams);
   --  Captured is the embedding default. Process_Streams publishes to actual
   --  C stdout immediately; it never duplicates bytes in the result packet.

   type Output_Result is record
      Succeeded : Boolean := True;
      Bytes_Written : Natural := 0;
      Error : Interfaces.C.int := 0;
   end record;
   --  Native stream status, captured before allocating or executing Lua.
   --  Print intentionally ignores write failures, as pinned C Lua does;
   --  io.write/flush use the result to construct their actual failure tuple.

   Minimum_C_Stack : constant := 20;
   Initial_Stack_Size : constant := 2 * Minimum_C_Stack;
   Extra_Stack : constant := 5;
   Error_Stack_Reserve : constant := 200;
   --  Pinned lstate.h/ldo.c stack policy. Arena indices are native offsets:
   --  the dummy base function slot zero is omitted. Stored live/reserved tops
   --  are inclusive (native pointer minus one); an allocated semantic bound
   --  excludes Extra_Stack and requires last inclusive offset < bound.
   type Stack_Space_Phase is (Normal_Stack, Error_Stack);
   type Completion_Policy is (Deliver_Results, Resume_Caller);
   type Finalizer_Drive_Phase is
     (Choosing_Finalizer, Waiting_Finalizer_Handler, Warning_Where,
      Warning_Open, Warning_Error, Warning_Close);

   type Native_Tail_Phase is
     (No_Native_Tail, Waiting_Native_Tail, Ready_Native_Tail);

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
   --  Immutable borrowed view of a string object's owned/external payload,
   --  always NUL-terminated. Copies do not extend it: retain the Lua value
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

   type Native_Library_Node;
   type Native_Library_Access is access Native_Library_Node;
   for Native_Library_Access'Storage_Pool use Lua.Storage.Pool;
   type Native_Library_Node is record
      Previous : Native_Library_Access;
      Path : Owned_Buffer;
      Handle : System.Address := System.Null_Address;
   end record;
   --  Loader references belong to the world, outside the tracing heap.
   --  Their selected-provider paths/records survive every finalizer and
   --  external-string release; shutdown unloads them in reverse open order.

   type Heap_Kind is
     (String_Object, Table_Object, Environment, Closure, Native_Closure,
      Cell_Object, Thread_Object, Userdata_Object);
   type Heap_Object
     (Kind : Heap_Kind; Payload_Length : Lua.Storage.Byte_Count);
   type Object_Access is access Heap_Object;
   for Object_Access'Storage_Pool use Lua.Storage.Pool;
   type Execution_Context;
   type Context_Access is access Execution_Context;
   for Context_Access'Storage_Pool use Lua.Storage.Pool;
   type Frame;
   type Frame_Access is access Frame;
   for Frame_Access'Storage_Pool use Lua.Storage.Pool;
   type Prototype;
   type Prototype_Access is access Prototype;
   for Prototype_Access'Storage_Pool use Lua.Storage.Pool;
   type Canonical_Program;
   type Canonical_Program_Access is access Canonical_Program;
   for Canonical_Program_Access'Storage_Pool use Lua.Storage.Pool;

   type Stack_View_Kind is (Callback_View, Hook_View);
   type Stack_View_Lease is record
      Context : Context_Access;
      Window, Previous_Frame, Previous_View : Frame_Access;
      Kind : Stack_View_Kind := Callback_View;
      Previous_Base, Previous_Top : Natural := 0;
      Window_Length, Live_Top, GC_Top, Stack_Used : Natural := 0;
      Caller_Base, Caller_Top : Natural := 0;
      Argument_Count : Natural := 0;
      Restore_Arguments, Restore_Captures : Boolean := False;
   end record;
   --  Embedded, allocation-free ownership of one synchronous C stack view.
   --  Context=null means inactive. Window remains a real active frame; the
   --  lease borrows its scalar cells without creating a public call level.

   type Object_Color is (White_0, White_1, Gray, Black);
   subtype White_Color is Object_Color range White_0 .. White_1;
   type Object_Age is
     (New_Age, Survival_Age, Old_0_Age, Old_1_Age, Old_Age,
      Touched_1_Age, Touched_2_Age);
   type Gray_Membership is (Not_Queued, Primary_Gray, Revisit_Gray);
   type Collector_Mode is
     (Incremental_Mode, Generational_Minor_Mode, Generational_Major_Mode);
   type Collector_Phase is
     (Paused, Propagating, Enter_Atomic, Sweeping_Objects,
      Sweeping_Programs, Finishing_Sweep, Finalizers_Ready);
   type Collector_Parameter is
     (Minor_Multiplier, Major_To_Minor, Minor_To_Major,
      Pause_Ratio, Step_Multiplier, Step_Size);
   type Collector_Parameters is array (Collector_Parameter) of
     Interfaces.Unsigned_8;
   type Age_Heads is array (Object_Age) of Object_Access;
   type Collector_State is record
      Mode : Collector_Mode := Incremental_Mode;
      Phase : Collector_Phase := Paused;
      Current_White : White_Color := White_0;
      Gray_Head : Object_Access;
      Gray_Again : Object_Access;
      Code_Gray : Prototype_Access;
      Remembered_Head : Object_Access;
      Generations : Age_Heads := [others => null];
      Sweep_Index : Natural := 0;
      Sweep_End : Natural := 0;
      Program_Index : Natural := 0;
      Program_End : Natural := 0;
      Young_Sweep : Object_Access;
      Cycle_Is_Minor : Boolean := False;
      Atomic_Completed : Boolean := False;
      Emergency : Boolean := False;
      Cycle_Started_Bytes : Lua.Storage.Byte_Count := 0;
      Last_Completed_Bytes : Lua.Storage.Byte_Count := 0;
      Last_Sampled_Bytes : Lua.Storage.Byte_Count := 0;
      Promoted_Bytes : Lua.Storage.Byte_Count := 0;
      Major_Baseline_Bytes : Lua.Storage.Byte_Count := 0;
      Cycle_Marked_Bytes : Lua.Storage.Byte_Count := 0;
      Work_Units : Lua.Storage.Byte_Count := 0;
      Parameters : Collector_Parameters := [others => 0];
      Parameters_Ready : Boolean := False;
      Debt_Remaining : Long_Long_Integer := 0;
   end record;


   subtype Native_Kind is Lua.Builtin_Registry.Kind;
   Print_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Print_Function;
   Assert_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Assert_Function;
   Error_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Error_Function;
   Pcall_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Pcall_Function;
   Type_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Type_Function;
   Tonumber_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Tonumber_Function;
   Tostring_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Tostring_Function;
   Select_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Select_Function;
   Next_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Next_Function;
   Pairs_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Pairs_Function;
   Ipairs_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Ipairs_Function;
   Ipairs_Step : constant Native_Kind :=
     Lua.Builtin_Registry.Ipairs_Step_Function;
   Rawequal_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Rawequal_Function;
   Rawget_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Rawget_Function;
   Rawset_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Rawset_Function;
   Rawlen_Function : constant Native_Kind :=
     Lua.Builtin_Registry.Rawlen_Function;
   subtype Primitive_Kind is Native_Kind range
     Print_Function .. Rawlen_Function;

   type Value_Kind is
     (Nil_Kind, Boolean_Kind, Integer_Kind, Real_Kind, String_Kind,
      Table_Kind, Closure_Kind, Native_Closure_Kind, Native_Kind_Value,
      Foreign_Function_Kind,
      Thread_Kind, Light_Identity_Kind, Userdata_Kind);

   type Type_Metatable_Array is array (Value_Kind) of Object_Access;

   type Value (Kind : Value_Kind := Nil_Kind) is record
      case Kind is
         when Nil_Kind => null;
         when Boolean_Kind => Boolean_Data : Boolean;
         when Integer_Kind => Integer_Data : Integer_Value;
         when Real_Kind => Real_Data : Real_Value;
         when String_Kind | Table_Kind | Closure_Kind | Native_Closure_Kind |
           Thread_Kind | Userdata_Kind =>
            Reference : Object_Access;
         when Native_Kind_Value => Native_Data : Native_Kind;
         when Light_Identity_Kind | Foreign_Function_Kind =>
            Identity : System.Address;
      end case;
   end record;
   Nil_Value : constant Value := (Kind => Nil_Kind);

   package Values is new Lua.Storage.Vectors (Value);
   package Objects is new Lua.Storage.Vectors (Object_Access);
   package Prototypes is new Lua.Storage.Vectors (Prototype_Access);
   package Scalar_Values is new Lua.Storage.Vectors (Value);
   package Cell_References is new Lua.Storage.Vectors (Object_Access);
   package Canonical_Prototypes is new
     Lua.Storage.Vectors (Prototype_Access);
   package Registers is new Lua.Storage.Vectors (Positive);
   package Symbols is new Lua.Storage.Vectors (Positive);

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
   package Bindings is new Lua.Storage.Vectors (Binding);

   type Payload_Alignment_Kind is
     (Real_Payload, Integer_Payload, Pointer_Payload);
   type Payload_Block
     (Kind : Payload_Alignment_Kind := Real_Payload) is record
      case Kind is
         when Real_Payload => Real_Data : Interfaces.C.long_double;
         when Integer_Payload => Integer_Data : Interfaces.C.long_long;
         when Pointer_Payload => Pointer_Data : System.Address;
      end case;
   end record with Convention => C, Unchecked_Union;
   Native_Payload_Alignment : constant Natural := Payload_Block'Alignment;
   type Userdata_Bytes is array
     (Lua.Storage.Byte_Count range <>) of
       aliased Payload_Block;
   --  A C union supplies native scalar alignment without a machine-specific
   --  representation constant. The array's first block is the payload; its
   --  extra final bytes are physical padding, never part of rawlen. Ada never
   --  interprets arbitrary client-written bytes as one of the union fields.

   type Resource_Release_Reason is
     (Collected, Lua_State_Close, Host_Disposal);
   type Resource_Cleanup is access procedure
     (Memory : not null Lua.Storage.Owner_Access;
      Payload, Data : System.Address; Reason : Resource_Release_Reason);
   --  Optional first-party host cleanup, called at actual object release.
   --  It must be idempotent, allocation-free, nonraising and never call Lua.
   --  Finalization/resurrection does not release the stable payload early.

   type Heap_Object
     (Kind : Heap_Kind; Payload_Length : Lua.Storage.Byte_Count)
   is record
      Marked : Boolean := False;
      Mark_Next : Object_Access;
      Finalizer_Next : Object_Access;
      Finalizer_Registered : Boolean := False;
      --  Finalizer ownership links are independent of collector work lists.
      --  Registration is not reachability; pending/current targets are roots.
      Color : Object_Color := White_0;
      Age : Object_Age := New_Age;
      Gray_List : Gray_Membership := Not_Queued;
      Remembered : Boolean := False;
      Remembered_Next, Remembered_Previous : Object_Access;
      Generation_Next, Generation_Previous : Object_Access;
      Registry_Slot : Natural := 0;
      Allocation_Bytes : Lua.Storage.Byte_Count := 0;
      Weak_Seen : Boolean := False;
      Serial : Positive := 1;
      case Kind is
         when Userdata_Object =>
            Userdata_Size : Lua.Storage.Byte_Count := 0;
            Userdata_Metatable : Object_Access;
            Uservalues : Values.Vector;
            Finalization_Aborted : Boolean := False;
            --  A host-aborted callback leaves owned native cleanup deferred
            --  until actual release; globally resurrected objects stay usable.
            Resource_Data : System.Address := System.Null_Address;
            Cleanup_Resource : Resource_Cleanup;
            Payload : Userdata_Bytes (1 .. Payload_Length);
            --  Physical block count is at least one for logical size zero.
            --  The inline payload never moves before Release_Object frees
            --  this single managed allocation. Uservalues are traced edges.
         when Thread_Object => Context_Index : Positive := 1;
         when Cell_Object => Cell_Value : Value;
         when String_Object =>
            Bytes : Byte_String;
            C_Bytes : System.Address := System.Null_Address;
            --  The immutable NUL-terminated payload is either selected-owner
            --  storage or an external borrow. A nonnull external allocator
            --  releases the original pointer/length exactly once through a
            --  guarded C portal. Lua API reentry uses the same active driver.
            External_String : Boolean := False;
            String_Allocator : Lua.Storage.Allocation_Function := null;
            String_Allocator_Data : System.Address := System.Null_Address;
            String_Hash : Interfaces.Unsigned_64 := 0;
            Intern_Next : Object_Access;
            Interned : Boolean := False;
            String_Root_Next : Object_Access;
            String_Rooted : Boolean := False;
            Release_Queued : Boolean := False;
            Release_Next, Release_Active_Previous : Object_Access;
            Release_View : Stack_View_Lease;
            --  Bucket membership is weak. The second intrusive list roots
            --  reused strings during one API/compiler operation without an
            --  allocation on a successful short-string lookup.
         when Table_Object =>
            Members : Entries.Vector;
            Array_Index : Table_Indexes.Vector;
            Hash_Index : Table_Indexes.Vector;
            Prefix_Length : Natural := 0;
            Hash_Rows : Natural := 0;
            --  Chained rows, including retained tombstones. Dense rows do
            --  not consume hash capacity or trigger unrelated hash growth.
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
            Foreign_Handler : System.Address := System.Null_Address;
            --  Non-null only for a real C closure. Zero-upvalue C functions
            --  use scalar pointer identity instead of a fresh heap object.
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
   package Instructions is new Lua.Storage.Vectors (Instruction);

   type Symbol_Name is record
      Symbol : Positive;
      Name : Unbounded_String;
   end record;
   package Symbol_Names is new Lua.Storage.Vectors (Symbol_Name);

   type Prototype is record
      Color : Object_Color := White_0;
      Registry_Slot : Natural := 0;
      Canonical_Node : Lua.Prototypes.Prototype_Access;
      Canonical_Owner : Canonical_Program_Access;
      Canonical_Constants : Scalar_Values.Vector;
      Marked       : Boolean := False;
      Mark_Next : Prototype_Access;
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
      Color : Object_Color := White_0;
      Model : Lua.Prototypes.Program;
      Wrappers : Canonical_Prototypes.Vector;
      References : Natural := 0;
      Marked : Boolean := False;
   end record;
   --  Runtime wrappers retain one managed immutable canonical graph as a
   --  group. The last released wrapper destroys that owner exactly once.

   type Canonical_Pending_Kind is
     (No_Canonical_Result, Store_Canonical_Results, Store_Call_Results,
      Test_Canonical_Result, Concat_Canonical_Result);

   package Packets is new Lua.Storage.Vectors
     (Values.Vector, "=" => Values."=");
   type Close_Entry is record
      Cell : Object_Access;
      Stack_Level : Natural := 0;
      --  A C temporary closes the actual absolute scalar slot without
      --  allocating an upvalue. Zero retains the private backend cell path.
      Symbol : Natural := 0;
      Depth : Natural := 0;
      Frozen_Value : Value := Nil_Value;
      Frozen : Boolean := False;
      --  Snapshot only when this declaration starts leaving its scope.
      --  A close handler may mutate the shared upvalue cell, but that must
      --  not replace a later handler's already departing stack-slot value.
   end record;
   package Close_Lists is new Lua.Storage.Vectors (Close_Entry);
   type Closing_Link is record
      Previous : Natural := 0;
   end record;
   package Closing_Links is new Lua.Storage.Vectors (Closing_Link);
   type Unwind_Reason is
     (No_Unwind, Scope_Exit, C_Slot_Exit, Jump_Exit, Return_Exit, Error_Exit,
      Coroutine_Exit);
   type Failure_Kind is
     (No_Failure, Language_Failure, Memory_Failure, Handling_Failure,
      Syntax_Failure, Unsupported_Failure, Host_Abort);
   type Frame_Lifecycle is (Available, Active, Retiring);
   package Frames is new Lua.Storage.Vectors (Frame_Access);

   type Frame is record
      Context : Context_Access;
      Cache_Next : Frame_Access;
      Reset_Reserve : Boolean := False;
      --  Dedicated empty continuation metadata, preserved across Clear_Frame
      --  and loaned only during an actual reset. It owns no inactive values.
      Lifecycle : Frame_Lifecycle := Active;
      Stack_Base : Natural := 0;
      Stack_Window_Length : Natural := 0;
      Saved_Stack_Used : Natural := 0;
      Call_Base : Natural := 0;
      Has_Stack_Window : Boolean := False;
      Hidden_Varargs : Boolean := False;
      Vararg_Base : Natural := 0;
      Vararg_Count : Natural := 0;
      Stack_Live_Top : Natural := 0;
      Saved_Foreign_Top : Natural := 0;
      Previous_Stack_Window : Frame_Access;
      --  Indices survive arena growth. Current real-window linkage is
      --  borrowed metadata, never another owner or a hidden GC root.
      Memory : Lua.Storage.Owner_Access;
      Is_Native : Boolean := False;
      Native_Name : Unbounded_String;
      Native_Id : Native_Kind := Print_Function;
      Native_Builtin_Direct : Boolean := False;
      Return_Window_Published : Boolean := False;
      --  The scalar source range and Transfer_First/Count are authoritative
      --  through return closing/hooks, independently of copied result packets.
      Native_Return_First : Natural := 0;
      --  A finishing Ada builtin publishes its real result range once,
      --  before return hooks. Zero means ordinary append placement; a phase
      --  that normalizes its argument top records its actual first slot.
      --  A real C function-pointer invocation borrows its original C frame.
      --  The hidden continuation's Native_Id selects the same Ada library;
      --  Native_Name stays @builtin.direct for logical-frame filtering.
      Native_Arguments : Values.Vector;
      Native_Results : Values.Vector;
      Error_Packet : Values.Vector;
      Result_Failure_Class : Failure_Kind := No_Failure;
      Result_Handler_Called : Boolean := False;
      Native_Captures : Values.Vector;
      Native_Self : Object_Access;
      Native_Buffer : Owned_Buffer;
      Load_Reader_Portal : Boolean := False;
      Load_Reader_Arguments : Natural := 0;
      Load_Reader_Mode_Offset : Natural := 0;
      --  A real base.load reader call runs above a C-owned guard after Step
      --  returns. Its existing buffer owns NUL-terminated name/mode bytes;
      --  no parser state, foreign stack or callback closure is saved here.
      Argument_Error_Index : Natural := 0;
      Argument_Error_Detail : Owned_Buffer;
      Argument_Error_Origin : Frame_Access;
      --  An auxiliary name lookup can call registry __index before raising.
      --  The failing activation retains its owned detail/index; a hidden
      --  continuation borrows that still-active parent through Origin. No
      --  saved Ada activation, value snapshot or exception text is borrowed.
      Native_Stage : Natural := 0;
      Native_Index : Natural := 0;
      Native_Aux : Natural := 0;
      Native_Operator : Lua.Lexers.Token_Kind := Lua.Lexers.End_Of_Input;
      C_Closing_Level : Natural := 0;
      --  Intrusive C closing links live with their actual scalar slots.
      --  This head borrows those indices; it owns no copied value or cell.
      Foreign_Handler : System.Address := System.Null_Address;
      Foreign_Ticket : Interfaces.C.unsigned_long_long := 0;
      Foreign_Continuation : System.Address := System.Null_Address;
      Foreign_KContext : Interfaces.C.ptrdiff_t := 0;
      Foreign_KStatus : Interfaces.C.int := 0;
      Foreign_Yield_Count : Natural := 0;
      Foreign_Suspended : Boolean := False;
      Foreign_Wanted : Integer := 0;
      Foreign_Protected : Boolean := False;
      --  C continuations retain scalar metadata, never an abandoned C stack.
      --  A suspended boundary owns its result adjustment until resumption.
      Error_Guard_Owner : Frame_Access;
      Deferred_Error_Head, Deferred_Error_Next : Frame_Access;
      Deferred_Error_Count : Natural := 0;
      Deferred_Error_Traceback : Boolean := False;
      Pending_Error_Transfer : Boolean := False;
      Error_Previous_Prefix : Natural := 0;
      --  An unprotected regular C call first transfers through its exact
      --  live callback guard. Its boundary owns the abandoned scope chain
      --  until that guard acknowledges the error; no old opcode may resume.
      --  Protected cleanup retains frozen ownership after retirement. An
      --  unhandled coroutine error instead preserves its original traceback
      --  windows until reset, as recorded by Deferred_Error_Traceback.
      Warning_Phase : Warning_Event_Phase := No_Pending_Warning;
      Warning_Previous : Frame_Access;
      Warning_View : Stack_View_Lease;
      Warning_Borrow_Depth : Natural := 0;
      Hook_View_Depth : Natural := 0;
      --  A hook pauses this actual frame's argument/capture packet while C
      --  operates on its cells; nested warning/release views preserve that.
      Warning_Ticket : Interfaces.C.unsigned_long_long := 0;
      Warning_Message : Byte_String;
      Warning_Root : Value;
      Warning_To_Continue : Boolean := False;
      Warning_Handler : System.Address := System.Null_Address;
      Warning_Data : System.Address := System.Null_Address;
      Warning_Failed : Boolean := False;
      --  A warning borrows its actual current frame. Embedded event storage
      --  and the linked previous event retain roots across nested C callbacks.
      Foreign_Base : Natural := 0;
      Foreign_Previous_Base : Natural := 0;
      Foreign_Previous_Frame : Frame_Access;
      Foreign_Previous_View : Frame_Access;
      Hook_View : Stack_View_Lease;
      --  The actual C hook guard and its interrupted scalar view have
      --  distinct lifetimes. A regular C entry saves/restores that view.
      Foreign_Entered : Boolean := False;
      --  A C callback has a base-relative public stack window. The previous
      --  window is explicit frame data so reentrant calls and error unwinding
      --  never depend on an abandoned Ada or C activation.
      Call_Site : Lua.Lexers.Source_Location;
      --  Native continuation storage is owned by the activation. Pending
      --  arguments/results/captures remain traced while Lua callbacks run.
      Code       : Prototype_Access;
      PC         : Positive := 1;
      Scope      : Object_Access;
      Scope_Depth : Natural := 0;
      Slots      : Packets.Vector;
      Active_Registers : Natural := 0;
      --  Retained rows above this bound are empty cached capacity.
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
      Completion : Completion_Policy := Deliver_Results;
      Finalizer_Phase : Finalizer_Drive_Phase := Choosing_Finalizer;
      Finalizer_Charge : Boolean := False;
      Return_To  : Natural := 0;
      Protection : Natural := 0;
      Message_Handler : Value;
      Retain_On_Failure : Boolean := False;
      --  Protected holders own their dynamic handler. A foreign sentinel
      --  retains its packet until C takes it; Lua holders deliver on unwind.
      Slot_Cost : Natural := 0;
      Native_Charge : Boolean := False;
      Message_Charge : Boolean := False;
      Unwind_Charge : Boolean := False;
      Blocks_Yield : Boolean := False;
      Callee : Value;
      Is_C_Hook_Transport : Boolean := False;
      --  A native hook borrows the interrupted frame. This actual scheduler
      --  wrapper is transport even if the callback replaces/removes its hook
      --  while running; mutable callback identity cannot identify the frame.
      Is_C_Collector_Transport : Boolean := False;
      --  The real C protected collector pump is an implementation transport,
      --  not a Lua-visible call. Its identity is fixed before entry hooks.
      Is_Finalizer_Call : Boolean := False;
      --  This actual activation was entered by the finalizer controller.
      --  It has the __gc origin even without a Lua calling opcode. Reuse and
      --  Lua tail replacement clear the marker; descendants do not inherit it.
      Logically_Unwound : Boolean := False;
      --  Execution has genuinely abandoned this activation. Cells/closers
      --  remain owned until cleanup; its calls/depth/barriers cannot resume.
      Is_Tail_Call : Boolean := False;
      Call_Metamethod_Count : Natural range 0 .. 15 := 0;
      --  Receivers inserted on entry to this logical frame, independently
      --  of ordinary arguments or varargs. Suspension and Lua tail reuse
      --  retain this count; a separate native tail frame gets its own count.
      Native_Tail_State : Native_Tail_Phase := No_Native_Tail;
      Call_Name : Unbounded_String;
      Call_Name_Bytes : Owned_Buffer;
      --  Owned, trailing-NUL view of an explicit call origin for C debug
      --  inspection. Publish it when the activation is constructed, never
      --  allocate scratch bytes during a read-only lua_getinfo query. The
      --  borrow is valid until this activation is retired/reused.
      Name_Kind : Unbounded_String;
      Transfer_Count : Natural := 0;
      Transfer_First : Positive := 1;
      --  Actual first transferred slot relative to the callee function.
      --  Calls start at one; canonical/C returns retain their real offset.
      Entry_Hook_Done : Boolean := False;
      Return_Hook_Done : Boolean := False;
      External_Return_Pending : Boolean := False;
      External_Return_Independent : Boolean := False;
      --  Unwind_Results owns a completed raw packet while external release
      --  callbacks borrow this still-live actual departing activation.
      Hook_Line : Integer range -1 .. Integer'Last := -1;
      --  Minus one means unseen; zero is a checked word without line data.
      --  Keeping them distinct preserves a stripped frame's first event.
      Hook_PC : Natural := 0;
      Hook_Trace_PC : Natural := 0;
      Hook_Line_Mask : Boolean := False;
      --  Traceexec snapshots its line mask before a count callback can change
      --  hooks. The last actually traced/caller-return PC remains separate
      --  from the executed PC while count-only hooks do not trace lines.
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
      Unwind_Failure_Class : Failure_Kind := Language_Failure;
      Unwind_Handler_Called : Boolean := False;
      Unwind_Has_Error : Boolean := False;
      Unwind_Previous_Prefix : Natural := 0;
      --  An active close keeps any outer close's real scalar floor. A failed
      --  handler transfers this floor to fresh recovery before dropping its
      --  now-abandoned controller and original return temporaries.
   end record;
   --  A packet preserves all results of a call/vararg expression. Scalar
   --  consumers read its first value; parentheses explicitly collapse it.
   --  Frames are explicit so tail calls need not consume the Ada call stack.
   function Native_Operation_Name
     (Activation : not null Frame_Access) return String;
   --  Return the semantic Ada library phase. A direct C builtin invocation
   --  retains an internal transport name on its hidden activation while its
   --  scalar ID selects this same existing implementation.

   type Native_Action_Kind is
     (Finished, Invoke, Continue_Step, Drain_Finalizers, Start_Reader_Portal);
   type Native_Action is record
      Kind : Native_Action_Kind := Finished;
      Results : Values.Vector;
      Function_Value : Value;
      Arguments : Values.Vector;
      Operator : Lua.Lexers.Token_Kind := Lua.Lexers.End_Of_Input;
      --  A typed primitive helper request uses ordinary VM metamethod
      --  dispatch; it is not a hidden Lua function or another executor.
   end record;
   --  Native drivers request calls through the VM rather than recursing into
   --  the executor. All retained values must be stored in their activation.

   type Context_Status is
     (New_Context, Running_Context, Suspended_Context, Normal_Context,
      Dead_Context);
   type Execution_Phase is (Executing, Closing);
   type Transfer_Kind is
     (No_Transfer, Completed, Lua_Raised, Yielded, Resume_Requested,
      Close_Requested, Host_Stopped, Process_Stopped);
   type Control_Transfer is record
      Kind : Transfer_Kind := No_Transfer;
      Results : Values.Vector;
      Target : Natural := 0;
   end record;
   --  Transfers are owned packets, not Ada-stack continuations. They remain
   --  roots until the scheduler hands them to the recipient activation.

   type Execution_Context is record
      Cache_Head : Frame_Access;
      Cache_Count : Natural := 0;
      Reset_Frame_Head : Frame_Access;
      Reset_Frame_Count : Natural := 0;
      Memory : Lua.Storage.Owner_Access;
      Stack        : Frames.Vector;
      Arguments    : Values.Vector;
      Boundary_Results : Values.Vector;
      Foreign_Stack : Values.Vector;
      Stack_Cells : Cell_References.Vector;
      C_Close_Links : Closing_Links.Vector;
      --  Stack-reserved predecessor indices make valid lua_toclose marking
      --  allocation-free, including when a cached Lua frame becomes C.
      Stack_Used : Natural := 0;
      Closing_Stack_Prefix : Natural := 0;
      --  Actual departing slots retained while reset/error cleanup invokes
      --  closers. Cleanup owners save/restore their previous prefix floor;
      --  this is a live scalar interval, never a copied value workspace.
      Foreign_Top : Natural := 0;
      Host_Stack_Top : Natural := 0;
      Stack_Window : Frame_Access;
      --  Physical scalar/cell arenas are distinct from current-frame ci.top,
      --  logical public C top and the host prefix retained during a drive.
      Foreign_State : System.Address := System.Null_Address;
      Foreign_Block : System.Address := System.Null_Address;
      Foreign_Control : System.Address := System.Null_Address;
      Foreign_Base : Natural := 0;
      Foreign_Activation : Frame_Access;
      Foreign_View : Frame_Access;
      --  Optional physical owner of a borrowed C view. Foreign_Activation
      --  can still name the genuine callback guard/continuation owner.
      Base_C_Frame : Frame_Access;
      --  Reserved base C activation lazily owns API-level closing slots.
      --  Its real scalar window starts at zero; like Lua's base CallInfo it
      --  has no public debug frame and carries no native-call depth charge.
      Resume_Foreign_Activation : Frame_Access;
      Resume_Foreign_View : Frame_Access;
      Resume_Foreign_Base : Natural := 0;
      Resume_Foreign_Top : Natural := 0;
      Resume_Stack_Used : Natural := 0;
      Resume_Host_Stack_Top : Natural := 0;
      Resume_Return_Base : Natural := 0;
      Resume_Return_Top : Natural := 0;
      Detached_Resume_Window : Boolean := False;
      --  Suspended C-resumed threads expose results in a detached host
      --  window above their retained activation windows. Restore this real
      --  C view only after the next resume arguments have entered roots.
      --  The public C stack is rooted independently of initial Lua arguments.
      --  A synchronous foreign call borrows it without changing ownership.
      Failure      : Value;
      Has_Failure_Value : Boolean := False;
      Failure_Text : Lua.Diagnostic_Text.Text;
      Failure_At   : Lua.Lexers.Source_Location;
      Failure_Class : Failure_Kind := No_Failure;
      Failure_Handled : Boolean := False;
      Protected_Failure_Class : Failure_Kind := No_Failure;
      Protected_Handler_Called : Boolean := False;
      Message_Depth : Natural := 0;
      Status : Context_Status := New_Context;
      Phase : Execution_Phase := Executing;
      Transfer : Control_Transfer;
      Resumer : Context_Access;
      Entry_Function : Value;
      Thread : Object_Access;
      Host_Owned : Boolean := True;
      Non_Yieldable : Natural := 0;
      Stack_Slots : Natural := 0;
      Deferred_Error_Depth : Natural := 0;
      --  Detached cleanup records still consume metadata capacity. Reserving
      --  for this count makes restoration after a C guard allocation-free.
      Error_Recovery_Pending : Boolean := False;
      Error_Recovery_Floor : Natural := 0;
      --  A typed C ACK schedules recovery on this existing driver. The next
      --  step processes the error before hooks, collection or an abandoned PC.
      Stack_Error_Phase : Stack_Space_Phase := Normal_Stack;
      Stack_Allocated_Bound : Natural := Initial_Stack_Size;
      --  The semantic allocated bound is independent of a backing vector's
      --  retained geometric capacity and the current real frame's ci.top.
      Native_Depth : Natural := 0;
      Hook : Value;
      --  Only a foreign trampoline lives here. Lua callbacks belong to the
      --  weak-key registry table, so replacing a public entry releases its
      --  former callback instead of keeping a hidden strong context copy.
      Lua_Hook_Installed : Boolean := False;
      --  Installation is independent of the table entry, which Lua code may
      --  replace or remove. A new thread inherits this flag/mask/count, but
      --  receives no callback mapping until it is explicitly registered.
      Hook_Mask : Unbounded_String;
      Foreign_Hook : System.Address := System.Null_Address;
      Foreign_Hook_Mask : Interfaces.C.int := 0;
      --  Actual low-byte installation mask, including Lua-dispatcher
      --  installations queried/restored through the public C hook API.
      Hook_Count : Natural := 0;
      Hook_Reported_Count : Integer_Value := 0;
      Hook_Remaining : Natural := 0;
      Hook_Active : Boolean := False;
      Hook_Suspended : Boolean := False;
      Hook_Yield_Pending : Boolean := False;
      --  A count hook can request a yield before the same instruction's
      --  line event. Deliver both events before publishing one suspension.
      Finalizer_Hook_Suppression : Natural := 0;
      Hook_Frame : Frame_Access;
      Hook_Transfer : Boolean := False;
      C_Resuming : Boolean := False;
      --  An explicit lua_resume boundary can drive even a fresh main thread.
      C_Reset_Requested : Boolean := False;
      C_Reset_Active : Boolean := False;
      C_Reset_Self : Boolean := False;
      C_Reset_Error : Boolean := False;
      --  A terminal reset error is already rooted by Failure and its real
      --  base stack slot; publishing it needs no newly allocating packet.
      C_Reset_From_Depth : Natural := 0;
      C_Reset_Return_Depth : Natural := 0;
      --  Self-reset first abandons real C guards through typed transfers.
      --  Only their final acknowledgment may retire this thread's frames.
      Cleanup_Depth : Natural := 0;
   end record;
   --  Contexts own frames and transient argument/error roots. Referenced
   --  heap objects belong to their world and can be shared across contexts.
   package Context_Lists is new Lua.Storage.Vectors (Context_Access);
   type Context_Id is new Positive;
   --  IDs are relative to one owning world, not transferable object handles.

   type Random_State is array (0 .. 3) of Interfaces.Unsigned_64;

   type World is limited record
      Module_Code : Lua.Platform_Modules.Code_Lease;
      --  This lease finalizes after Memory, including its residual raw frees.
      Memory : Lua.Storage.Owner;
      --  The allocator owner outlives every typed object and buffer in this
      --  universe. Explicit subpool allocators never borrow a global owner.
      Native_Libraries : Native_Library_Access;
      Bounds       : Limits;
      Saved_Bounds : Limits;
      Policy : Execution_Policy := Bounded;
      Exit_Phase : Process_Exit_Phase := No_Process_Exit;
      Exit_Code : Interfaces.C.int := 0;
      Exit_Close_State : Boolean := False;
      Random_Words : Random_State := [others => 0];
      Random_Seeded : Boolean := False;
      Random_Use_32_Bits : Boolean :=
        Lua.Runtime_Configuration.Random_32_Bits;
      Math_Compatibility : Boolean :=
        Lua.Runtime_Configuration.Compatibility_Math;
      Open_Standard_Libraries : Boolean := True;
      Canonical_Compilation : Boolean := True;
      --  The old lowerer remains available only during migration checks.
      Contexts     : Context_Lists.Vector;
      Current      : Context_Access;
      Main_Context : Context_Access;
      Main_Thread : Object_Access;
      --  Current borrows a context owned by Contexts; it never owns it twice.
      GC : Collector_State;
      Heap_Free_Next : Table_Indexes.Vector;
      Heap_Free_Head : Natural := 0;
      Live_Objects : Natural := 0;
      Program_Free_Next : Table_Indexes.Vector;
      Program_Free_Head : Natural := 0;
      Live_Programs : Natural := 0;
      Heap         : Objects.Vector;
      Short_Strings : Objects.Vector;
      Short_String_Count : Natural := 0;
      String_Root_Head : Object_Access;
      External_Release_Head, External_Release_Tail : Object_Access;
      External_Release_Active : Object_Access;
      Programs     : Prototypes.Vector;
      Foreign_Registry : Object_Access;
      Memory_Error_Value : Value;
      Handling_Error_Value : Value;
      Entry_Code : Prototype_Access;
      Operation_Roots : Values.Vector;
      Operation_Programs : Prototypes.Vector;
      Operation_Active : Boolean := False;
      Operation_Start : Positive := 1;
      Compiling : Boolean := False;
      Memory_Ready : Boolean := False;
      Collector_Active : Boolean := False;
      Finalizable_Head : Object_Access;
      Finalizer_Head : Object_Access;
      Finalizer_Tail : Object_Access;
      Finalizing_Object : Object_Access;
      Finalizing_Handler : Value;
      Finalizer_Active : Boolean := False;
      Finalizers_Requested : Boolean := False;
      --  A normal collector cycle requests one drain attempt. If minimum
      --  stack/CI space is unavailable, wait for another cycle, not a busy
      --  loop which prevents the blocked caller from making progress.
      State_Close_Phase : Boolean := False;
      String_Metatable : Object_Access;
      Type_Metatables : Type_Metatable_Array := [others => null];
      --  Actual per-universe primitive-type roots. Number/function variants
      --  are canonicalized by Raw_Metatable rather than owning extra tables.
      Loaded_Modules : Object_Access;
      Preload_Modules : Object_Access;
      Next_Symbol  : Positive := 1;
      Next_Object  : Positive := 1;
      Next_Foreign_Ticket : Interfaces.C.unsigned_long_long := 0;
      Entry_Count  : Natural := 0;
      Collections  : Natural := 0;
      GC_Running : Boolean := True;
      Next_GC      : Positive := 256;
      Steps        : Natural := 0;
      Native_Depth : Natural := 0;
      Warning_Mode : Warning_Mode_Kind := Default_Warnings_On;
      Warning_Handler : System.Address := System.Null_Address;
      Warning_Data : System.Address := System.Null_Address;
      Warning_Head : Frame_Access;
      Output_Mode : Output_Policy := Captured;
      Output_Used : Natural := 0;
      Output       : Unbounded_String;
   end record;
   type World_Access is access World;

   procedure Emit_Warning
     (State : in out World; Message : Value;
      To_Continue : Boolean := False);
   procedure Emit_Warning
     (State : in out World; Message : Byte_String;
      Root : Value := Nil_Value; To_Continue : Boolean := False);
   --  Borrow a NUL-terminated message without a forced allocation. Root
   --  retains an owned Lua string until a custom C callback acknowledges it;
   --  static fragments may use Nil_Value. Call only from a live VM frame
   --  when the custom handler requires deferred C-owned delivery.

   function Emit_Output
     (State : in out World; Bytes : String) return Output_Result;
   procedure Emit_Output (State : in out World; Bytes : String);
   --  Charge the complete bounded byte quota before any externally visible
   --  write. Arbitrary String bounds and empty slices are supported. There
   --  is no host callback while VM frames remain active.
   function Flush_Output (State : in out World) return Output_Result;
   procedure Flush_Output (State : in out World);
   --  Captured stdout has no external buffer to flush. Process streams use
   --  actual fflush(stdout), including the host's failure and errno.

   function Read_Number
     (Memory : not null Lua.Storage.Owner_Access; Text : String;
      Base : Natural := 0) return Lua.Numbers.Number;
   function Read_Number
     (Memory : not null Lua.Storage.Owner_Access; Text : Byte_String;
      Base : Natural := 0) return Lua.Numbers.Number;
   function Read_Number
     (Text : String; Base : Natural := 0) return Lua.Numbers.Number;
   function Read_Number
     (Text : Byte_String; Base : Natural := 0) return Lua.Numbers.Number;
   function Read_Number
     (State : in out World; Text : String; Base : Natural := 0)
      return Lua.Numbers.Number;
   function Read_Number
     (State : in out World; Text : Byte_String; Base : Natural := 0)
      return Lua.Numbers.Number;
   --  Explicit-owner conversions retain their selected scratch provider.
   --  No-owner/state conversions borrow source bytes and use fixed exact
   --  numeric scratch. State overloads charge the shared linear scan budget.

   function Owned_Values
     (State : in out World; Source : Values.Vector := Values.Empty_Vector)
      return Values.Vector;
   function Owned_Values
     (Memory : not null Lua.Storage.Owner_Access;
      Source : Values.Vector := Values.Empty_Vector) return Values.Vector;
   --  Frame-only helpers use their explicitly seeded owner, never a fallback.
   function One_Value
     (State : in out World; Item : Value;
      Count : Ada.Containers.Count_Type := 1) return Values.Vector;
   function One_Value
     (Memory : not null Lua.Storage.Owner_Access; Item : Value;
      Count : Ada.Containers.Count_Type := 1) return Values.Vector;
   --  Runtime packets always select their universe explicitly. The empty
   --  default is an input value, never an implicit global allocation policy.
   function New_Action (State : in out World) return Native_Action;
   --  Bind both growable packets before a driver starts constructing output.

   function C_Option (Text : String) return String;
   --  Return the prefix before NUL for pinned Lua's C-string option fields.
   --  Lua values remain byte strings; apply this only at such option parsers.
   --  Arbitrary Ada String lower bounds are preserved by the slice.

   Language_Error : exception;
   --  Internal structured control transfer only; sessions catch it.

   procedure Fail (State : in out World; Message : String;
                   Resource : Boolean := False);
   --  Record a diagnostic before raising the internal transfer exception.

   procedure Set_Failure_Text
     (State : in out World; Context : not null Context_Access;
      Message : String);
   --  Copy a diagnostic through the selected owner, charging input-sized
   --  work. Short emergency messages remain allocation-free under refusal.
   procedure Diagnostic_Work (State : in out World; Bytes : Natural);
   --  Charge an input-sized diagnostic pass before copying/scanning bytes.
   --  The fixed inline bound is covered by ordinary activation bookkeeping.
   function Failure_Image (Context : not null Context_Access) return String;
   --  Materialize a host diagnostic. An actual Lua error is authoritative
   --  and remains rooted in Context; its string is never copied for storage.
   function Ensure_Error_Object
     (State : in out World; Context : not null Context_Access) return Value;
   --  Publish an existing error value, or build it directly from a borrowed
   --  managed diagnostic. No input-sized unmanaged intermediate is created.

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
   procedure Finalize
     (State : in out World;
      Reason : Resource_Release_Reason := Host_Disposal);
   --  Release physical ownership without executing Lua. Explicit Lua-state
   --  closing first drains its callbacks, then selects Lua_State_Close; host
   --  disposal can additionally reclaim first-party native resources.
   procedure Advance_Collection
     (State : in out World; Work : Positive; Finished : out Boolean);
   procedure Step_Collection
     (State : in out World; Extra_Bytes : Lua.Storage.Byte_Count;
      Finished : out Boolean);
   procedure Poll_Collection (State : in out World);
   procedure Restart_Collection (State : in out World);
   procedure Set_Collector_Mode
     (State : in out World; Mode : Collector_Mode);
   function Encode_Collector_Parameter
     (Value : Lua.Storage.Byte_Count) return Interfaces.Unsigned_8;
   function Apply_Collector_Parameter
     (Encoded : Interfaces.Unsigned_8; Value : Lua.Storage.Byte_Count)
      return Lua.Storage.Byte_Count;
   --  Production parameter arithmetic, exposed only beneath private Engine
   --  so test inspection exercises the same codec as collector controls.
   function Collector_Parameter_Value
     (State : in out World; Name : Collector_Parameter;
      Value : Integer_Value := Integer_Value'First) return Integer_Value;
   procedure Root_Barrier (State : in out World; Item : Value);
   procedure Root_Barrier (State : in out World; Item : Object_Access);
   procedure Root_Barrier (State : in out World; Items : Values.Vector);
   procedure Root_Barrier
     (State : in out World; Items : Scalar_Values.Vector);
   procedure Root_Barrier (State : in out World; Items : Objects.Vector);
   procedure Write_Barrier
     (State : in out World; Owner : not null Object_Access; Item : Value);
   procedure Write_Barrier
     (State : in out World; Owner : not null Object_Access;
      Item : Object_Access);
   procedure Back_Barrier
     (State : in out World; Owner : not null Object_Access);
   procedure Code_Barrier
     (State : in out World; Item : Prototype_Access);
   procedure Store_Cell
     (State : in out World; Cell : not null Object_Access; Item : Value);
   --  Mutate the actual lexical/native upvalue with its forward barrier.
   --  Explicit publication barriers preserve the active color/generation
   --  invariant. Raw table writes bypass metamethods, never these barriers.
   --  Allocation/deallocation has no implicit process-global active world.

   procedure Release_Registered_Program
     (State : in out World; Item : in out Prototype_Access);
   --  Private constructor/adoption rollback only. The actual ownership slot
   --  is detached before releasing the typed prototype and its shared model.

   procedure Request_Process_Exit
     (State : in out World; Code : Interfaces.C.int;
      Close_State : Boolean);
   --  Latch the latest exit request for the iterative scheduler. This
   --  operation never executes Lua, raises an exit exception, or terminates
   --  the host process while an Ada activation remains on the native stack.

   procedure Append_Root
     (State : in out World; Target : in out Values.Vector; Item : Value);
   procedure Append_Root
     (State : in out World; Target : in out Values.Vector;
      Items : Values.Vector);
   procedure Replace_Root
     (State : in out World; Target : in out Values.Vector;
      Index : Positive; Item : Value);
   procedure Copy_Roots
     (State : in out World; Target : in out Values.Vector;
      Source : Values.Vector);
   --  Publish strong root packets with explicit State and its matching
   --  allocator. Copy_Roots reserves before clearing, retaining Target's
   --  capacity/owner; actual self-copy is an allocation-free no-op.
   procedure Move_Roots
     (State : in out World; Target, Source : in out Values.Vector);
   --  Shade before atomic ownership transfer. Source becomes empty and is
   --  explicitly rebound to State's owner, ready for subsequent growth.
   --  Buffers/values must belong to this universe; empty unbound inputs are
   --  accepted only because this call supplies their explicit owner.
   procedure Append_Object_Edge
     (State : in out World; Owner : not null Object_Access;
      Target : in out Objects.Vector; Item : Object_Access);
   procedure Replace_Object_Edge
     (State : in out World; Owner : not null Object_Access;
      Target : in out Objects.Vector; Index : Positive;
      Item : Object_Access);
   --  Target is Owner's traced cell/capture vector. Forward ownership
   --  barriers precede publication, including OLD0 generational promotion.

   procedure Shrink_Context_Storage
     (State : in out World; Context : not null Context_Access);
   --  Optional normal-GC/protected-recovery maintenance. Physical arena and
   --  cached-frame storage is really released through the chosen provider;
   --  refusal retains the original arenas, bound and overflow phase.

   procedure Collect
     (State : in out World; Emergency : Boolean := False);
   --  Mark/sweep sees globals, frames, packets, captures, and current failure.

   function New_Thread
     (State : in out World; Entry_Function : Value;
      Parent : Context_Access := null) return Value;
   --  Allocate a Lua-owned context and its unique thread object. Inherit the
   --  addressed parent's hook controls (State.Current when Parent is null),
   --  with a fresh countdown but no Lua callback registry entry.

   function New_Frame
     (State : in out World; Context : not null Context_Access)
      return Frame_Access;
   function New_Frame (State : in out World) return Frame_Access;
   --  Borrow one clean activation from its context-owned intrusive cache.
   --  A new record and every future buffer use State.Memory explicitly.
   --  Publish on Context.Stack before any later allocation can collect.

   Reset_Continuation_Frames : constant Positive := 8;
   procedure Prepare_Reset_Frames
     (State : in out World; Context : not null Context_Access);
   --  Reserve bounded reset/close/protection metadata while a C
   --  surface is constructed. Empty owned buffers retain their capacities;
   --  normal user-call frames remain independently metered and allocated.

   procedure Prepare_Private_Registers
     (Item : not null Frame_Access; Count : Natural);
   --  Activate only Count rows of a retained private packet arena. Grow and
   --  bind new rows explicitly; do not discard nested capacity on reuse.

   procedure Return_Frame (Item : in out Frame_Access);
   --  Retire a detached activation after the VM balances active charges.
   --  Clear all Lua references and continuation state without dropping
   --  reserved capacity, then cache it in Item.Context. Null is a no-op;
   --  double retirement is internal misuse and raises Program_Error.

   procedure Destroy_Frames
     (State : in out World; Context : not null Context_Access);
   --  Teardown only: destroy active and cached activations exactly once.
   --  No Lua callbacks or __close handlers are invoked. The owner and the
   --  context itself must remain live until the operation completes.

   function New_Program (State : in out World) return Prototype_Access;
   procedure Release_Program (Item : in out Prototype_Access);
   --  Release the wrapper and its shared canonical owner at the final edge.
   function New_Cell (State : in out World; Item : Value) return Object_Access;
   --  Allocate an actual stable lexical cell, rooted by its published owner.
   --  Bind every frame-owned managed container before any capacity grows.

   function New_String (State : in out World; Text : String) return Value;
   function New_External_String
     (State : in out World; Address : System.Address; Size : Natural;
      Allocator : Lua.Storage.Allocation_Function;
      Data : System.Address) return Value;
   --  Adopt an immutable external NUL-terminated payload. The allocator's
   --  address/data must outlive the string. The callback frees the original
   --  payload and returns null; it may make ordinary synchronous Lua calls.
   --  Before adoption, failure leaves ownership with the C boundary guard.
   procedure Release_Detached_String
     (State : in out World; Item : in out Object_Access);
   --  Release a detached header after its C deallocator has acknowledged the
   --  payload. The external release portal is its sole caller/owner.
   function New_String
     (State : in out World; Text : in out Owned_Buffer) return Value;
   --  Publish a managed builder through a borrowed view, avoiding an
   --  input-sized temporary Ada String allocation.
   function New_Table (State : in out World) return Value;

   function New_Userdata
     (State : in out World; Size : Lua.Storage.Byte_Count;
      Uservalue_Count : Natural := 0) return Value;
   --  Allocate one stable aligned payload and its owned Lua uservalue list.
   --  New uservalues are nil; payload bytes are intentionally unspecified.
   --  @param Size Logical bytes, independently of zero-size identity storage.
   --  @param Uservalue_Count Less than the pinned C short maximum.
   --  @exception Language_Error Invalid count; ordinary semantic Lua failure.
   --  @exception Lua.Storage.Allocation_Error Refusal/unrepresentable size.

   function Userdata_Address (Item : Value) return System.Address;
   --  Borrow the actual payload address. Nil/non-userdata yields null; C
   --  users retain a traced userdata value throughout their pointer borrow.

   procedure Attach_Resource
     (Item : Value; Data : System.Address;
      Cleanup : not null Resource_Cleanup);
   --  Attach owned first-party metadata once. Cleanup owns its release.
   --  Generic userdata has no invented native destructor. No Lua allocation
   --  or callback occurs here; Item must be a live full userdata value.
   procedure Reserve_Table
     (State : in out World; Table : Value;
      Sequence_Size, Hash_Size : Natural);
   --  Reserve actual storage in an empty table through its owning provider.
   --  Capacity publication is atomic; no keys or sequence values are added.

   function Global_Environment (State : World) return Value;
   --  Read the actual raw LUA_RIDX_GLOBALS registry entry. New chunks and
   --  public C globals observe replacement; existing _ENV cells keep their
   --  own bindings. This borrow performs no allocation or metamethod call.

   function New_Environment
     (State : in out World; Parent : Object_Access) return Object_Access;
   function New_Closure
     (State : in out World; Code : Prototype_Access;
      Capture : Object_Access) return Value;
   function New_Native
     (State : in out World; Name : String;
      Captures : Values.Vector := Values.Empty_Vector) return Value;
   --  Allocate a stateful native callable; captures are collector roots.
   function Raw_Metatable (State : World; Item : Value)
                           return Object_Access;
   --  Borrow the actual metatable without consulting __metatable. Primitive
   --  number/function representations share one Lua type entry per universe.

   procedure Set_Metatable
     (State : in out World; Item : Value; Meta : Object_Access);
   --  Change the actual object/type association. Meta is null or a table;
   --  the caller applies public protection rules before choosing this bypass.

   function Metafield
     (State : in out World; Item : Value; Name : String) return Value;
   --  Raw event lookup; it never invokes Lua or follows __index.

   function Equal (Left, Right : Value) return Boolean;
   function Truth (Item : Value) return Boolean;
   function Type_Name (Item : Value) return String;
   function Diagnostic_Type (State : World; Item : Value) return String;
   --  VM error type spelling: only table/userdata raw string __name fields
   --  override primitive type(). The rendered name ends at its first NUL.
   function Argument_Type
     (State : World; Item : Value; Present : Boolean := True) return String;
   --  Auxiliary argument spelling: any raw string __name takes priority,
   --  then light userdata receives its special name. Present=False denotes
   --  an absent slot rather than an explicit nil. Both queries invoke no
   --  handlers and allocate no Lua objects; returned Ada text is immediate.
   function Image (Memory : not null Lua.Storage.Owner_Access;
                   Item : Value) return String;
   function Image (Item : Value) return String;
   --  Host/test convenience wrapper; runtime callers provide Memory.
   function Pointer_Of
     (State : in out World; Item : Value) return System.Address;
   --  Actual public lua_topointer identity, shared by C and Lua rendering.
   --  The returned borrow is valid while Item remains traced. Thread
   --  identities may first reserve their C surface in an Ada-only world.
   function Pointer_Image
     (Pointer : System.Address; Width : Natural := 0;
      Left_Aligned : Boolean := False) return String
     with Pre => Width <= 99;
   --  Bounded native %p spelling, with no selected-allocator request.
   procedure Describe_Value
     (State : in out World; Item : Value; Output : in out Owned_Buffer);
   --  Default luaL_tolstring representation only, without invoking handlers.
   --  Named output remains selected-owner storage; raw __name ends at NUL.
   function Get (Table : Value; Key : Value) return Value;
   procedure Set (State : in out World; Table, Key, Item : Value);
   function Table_Length (Table : Value) return Natural;
   function Next (State : in out World; Table, Key : Value)
                  return Values.Vector;

   function Read_Local (Scope : Object_Access; Symbol : Positive)
                        return Value;
   procedure Write_Local
     (State : in out World; Scope : Object_Access;
      Symbol : Positive; Item : Value);
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
