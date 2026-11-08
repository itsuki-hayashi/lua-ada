with Interfaces.C;
with Lua.Engine.Machine;
with Lua.Storage;
with System;

package Lua.Engine.Foreign is
   function Auxiliary_Buffer_Size return Interfaces.C.size_t
     with Export, Convention => C,
          External_Name => "lua_ada_auxiliary_buffer_size";
   --  Borrow the selected configuration's initial scratch capacity without
   --  a state access or allocation. C buffer callers can use the ordinary
   --  SDK layout or the pinned tiny T layout at their common public prefix.
   use type Interfaces.C.int;
   --  C entrypoints belong to the small C-owned boundary in c_api/. This
   --  package performs state operations and returns a typed result before
   --  that boundary raises an error or resumes any foreign callback. No
   --  nonlocal transfer is permitted while these Ada frames are active.
   type C_Function is access function
     (State : System.Address) return Interfaces.C.int
     with Convention => C;

   type C_Warning_Function is access procedure
     (Data, Message : System.Address; To_Continue : Interfaces.C.int)
     with Convention => C;

   type C_Continuation is access function
     (State : System.Address; Status : Interfaces.C.int;
      Context : Interfaces.C.ptrdiff_t) return Interfaces.C.int
     with Convention => C;

   type C_Reader is access function
     (State, Data : System.Address;
      Size : not null access Interfaces.C.size_t) return System.Address
     with Convention => C;

   type IO_Close_Kind is
     (Regular_File_Close, Pipe_File_Close, Borrowed_File_Close);
   function IO_Close_Handler (Kind : IO_Close_Kind) return C_Function;
   --  Return actual callable C trampolines for public luaL_Stream.closef.
   --  The stream owns no pointer marker or fabricated native-function token.
   --  Direct C invocation shares the current logical activation and delegates
   --  its real result/error construction to the Ada IO library.

   type Operation_Code is
     (Create_State, Create_Default_State, Close_State, Create_Thread,
      Get_Top, Set_Top, Absolute_Index, Check_Stack, Push_Value,
      Copy_Value, Rotate_Values, Move_Values, Get_Type, To_Boolean,
      To_Integer, To_Number, To_String, Raw_Length, To_Pointer,
      To_Thread, Push_Nil, Push_Boolean, Push_Integer, Push_Number,
      Push_String, Push_Pointer, Push_Thread, Create_Table,
      Raw_Get, Raw_Set, Raw_Get_Integer, Raw_Set_Integer,
      Raw_Get_Pointer, Raw_Set_Pointer, Raw_Equal, Next_Item,
      Get_Allocator, Set_Allocator, Push_C_Closure, To_C_Function,
      Begin_Call, Complete_Callback, Raise_Error, Load_Buffer,
      Create_Userdata, Get_Uservalue, Set_Uservalue,
      Get_Metatable, Set_Metatable, Close_IO_Primitive, Get_Yieldability,
      Set_Warning_Function, Issue_Warning, Complete_Warning,
      Open_IO_Module, Open_OS_Module, Collector_Control, Push_Collector_Drain,
      Yield_Call, Get_Status, Begin_Resume, Open_Standard_Module,
      Prepare_Index, Mark_Close, Close_Slot,
      Release_Buffer, Dump_Function,
      Reader_Barrier, Restore_Load_Stack, Prepare_Reader_Error,
      Load_Reader,
      Set_Hook, Get_Hook, Get_Hook_Mask, Get_Hook_Count,
      Get_Debug_Frame, Get_Debug_Line, Get_Debug_Info,
      Get_Local, Set_Local, Get_Upvalue, Set_Upvalue,
      Upvalue_Id, Join_Upvalues, Begin_Builtin, Push_External_String,
      Prepare_External_Release, Complete_External_Release,
      Prepare_Length, Prepare_Concatenation, Number_To_C_String,
      Prepare_Arithmetic, Prepare_Comparison,
      Close_Thread, String_To_Number, Complete_Self_Close, Prepare_Panic,
      Begin_Hook_View, End_Hook_View,
      Prepare_Lua_Reader, Observe_Lua_Reader_Piece, Finish_Lua_Reader,
      Create_Formatter, Append_Format_Value, Append_Format_UTF8,
      Finish_Formatter, Release_Formatter, Charge_Aux_Work,
      Create_Aux_Box, Resize_Aux_Box, Release_Aux_Box, Publish_Aux_Box,
      Load_File, Build_Traceback);
   for Operation_Code use
     (Create_State => 0, Create_Default_State => 1, Close_State => 2,
      Create_Thread => 3, Get_Top => 4, Set_Top => 5,
      Absolute_Index => 6, Check_Stack => 7, Push_Value => 8,
      Copy_Value => 9, Rotate_Values => 10, Move_Values => 11,
      Get_Type => 12, To_Boolean => 13, To_Integer => 14,
      To_Number => 15, To_String => 16, Raw_Length => 17,
      To_Pointer => 18, To_Thread => 19, Push_Nil => 20,
      Push_Boolean => 21, Push_Integer => 22, Push_Number => 23,
      Push_String => 24, Push_Pointer => 25, Push_Thread => 26,
      Create_Table => 27, Raw_Get => 28, Raw_Set => 29,
      Raw_Get_Integer => 30, Raw_Set_Integer => 31,
      Raw_Get_Pointer => 32, Raw_Set_Pointer => 33,
      Raw_Equal => 34, Next_Item => 35, Get_Allocator => 36,
      Set_Allocator => 37, Push_C_Closure => 38, To_C_Function => 39,
      Begin_Call => 40, Complete_Callback => 41, Raise_Error => 42,
      Load_Buffer => 43, Create_Userdata => 44,
      Get_Uservalue => 45, Set_Uservalue => 46,
      Get_Metatable => 47, Set_Metatable => 48, Close_IO_Primitive => 49,
      Get_Yieldability => 50, Set_Warning_Function => 51,
      Issue_Warning => 52, Complete_Warning => 53,
      Open_IO_Module => 54, Open_OS_Module => 55,
      Collector_Control => 56, Push_Collector_Drain => 57,
      Yield_Call => 58, Get_Status => 59, Begin_Resume => 60,
      Open_Standard_Module => 61,
      Prepare_Index => 62, Mark_Close => 63,
      Close_Slot => 64, Release_Buffer => 66,
      Dump_Function => 67, Reader_Barrier => 68, Restore_Load_Stack => 69,
      Prepare_Reader_Error => 70, Load_Reader => 71,
      Set_Hook => 80, Get_Hook => 81, Get_Hook_Mask => 82,
      Get_Hook_Count => 83, Get_Debug_Frame => 84, Get_Debug_Line => 85,
      Get_Debug_Info => 86, Get_Local => 87, Set_Local => 88,
      Get_Upvalue => 89, Set_Upvalue => 90, Upvalue_Id => 91,
      Join_Upvalues => 92, Begin_Builtin => 93, Push_External_String => 94,
      Prepare_External_Release => 95, Complete_External_Release => 96,
      Prepare_Length => 100, Prepare_Concatenation => 101,
      Number_To_C_String => 102,
      Prepare_Arithmetic => 103, Prepare_Comparison => 104,
      Close_Thread => 105, String_To_Number => 106,
      Complete_Self_Close => 107,
      Prepare_Panic => 108,
      Begin_Hook_View => 109, End_Hook_View => 110,
      Prepare_Lua_Reader => 111, Observe_Lua_Reader_Piece => 112,
      Finish_Lua_Reader => 113,
      Create_Formatter => 120, Append_Format_Value => 121,
      Append_Format_UTF8 => 122, Finish_Formatter => 123,
      Release_Formatter => 124, Charge_Aux_Work => 125,
      Create_Aux_Box => 126, Resize_Aux_Box => 127,
      Release_Aux_Box => 128, Publish_Aux_Box => 129, Load_File => 130,
      Build_Traceback => 131);
   for Operation_Code'Size use Interfaces.C.int'Size;
   pragma Convention (C, Operation_Code);

   type Debug_Information is record
      Name : System.Address := System.Null_Address;
      Source : System.Address := System.Null_Address;
      Source_Length : Interfaces.C.size_t := 0;
      Name_Kind : Interfaces.C.int := 0;
      What : Interfaces.C.int := 0;
      Current_Line : Interfaces.C.int := -1;
      First_Line : Interfaces.C.int := -1;
      Last_Line : Interfaces.C.int := -1;
      Upvalues : Interfaces.C.int := 0;
      Parameters : Interfaces.C.int := 0;
      Vararg : Interfaces.C.int := 1;
      Tail : Interfaces.C.int := 0;
      Extra_Arguments : Interfaces.C.int := 0;
      First_Transfer : Interfaces.C.int := 0;
      Transfer_Count : Interfaces.C.int := 0;
      Short_Source : Interfaces.C.char_array (0 .. 59) :=
        [others => Interfaces.C.nul];
   end record with Convention => C;
   --  Metadata crosses an ordinary checked C record. Its borrowed byte
   --  addresses belong to actual frozen code/constants, never query scratch.

   type Request is record
      Operation : Operation_Code;
      Index : Interfaces.C.int := 0;
      Count : Interfaces.C.int := 0;
      Error_Index : Interfaces.C.int := 0;
      Integer_Data : Interfaces.C.long_long := 0;
      Number_Data : Interfaces.C.double := 0.0;
      Pointer : System.Address := System.Null_Address;
      Length : Interfaces.C.size_t := 0;
      Allocator : Lua.Storage.Allocation_Function := null;
      Seed : Interfaces.C.unsigned := 0;
      Function_Data : C_Function := null;
      Name : System.Address := System.Null_Address;
      Mode : System.Address := System.Null_Address;
      Error_Handled : Interfaces.C.int := 0;
      Callback_Token : Callback_Identity;
      Warning_Function : C_Warning_Function := null;
      Warning_Data : System.Address := System.Null_Address;
      Warning_Message : System.Address := System.Null_Address;
      Warning_Continuation : Interfaces.C.int := 0;
      Continuation : C_Continuation := null;
      KContext : Interfaces.C.ptrdiff_t := 0;
      Reader : C_Reader := null;
      Debug_Data : System.Address := System.Null_Address;
   end record with Convention => C;

   type Response is record
      Integer_Data : Interfaces.C.long_long := 0;
      Number_Data : Interfaces.C.double := 0.0;
      Pointer : System.Address := System.Null_Address;
      Length : Interfaces.C.size_t := 0;
      Allocator : Lua.Storage.Allocation_Function := null;
      Function_Data : C_Function := null;
      Error_Handled : Interfaces.C.int := 0;
      Callback_Token : Callback_Identity;
      Warning_Function : C_Warning_Function := null;
      Warning_Data : System.Address := System.Null_Address;
      Warning_Message : System.Address := System.Null_Address;
      Warning_Continuation : Interfaces.C.int := 0;
      Continuation : C_Continuation := null;
      KContext : Interfaces.C.ptrdiff_t := 0;
      KStatus : Interfaces.C.int := 0;
      Abort_State : System.Address := System.Null_Address;
      --  Actual saved C caller surface for a host stop on a different
      --  addressed context. It names no saved Ada stack or fabricated guard.
   end record with Convention => C;

   type Action_Status is
     (Action_Done, Action_Call, Action_Raise, Action_Memory,
      Action_Handling, Action_Abort, Action_Warning, Action_Suspend,
      Action_External_Release, Action_Self_Close);
   for Action_Status use
     (Action_Done => 0, Action_Call => 1,
      Action_Raise => 2, Action_Memory => 4,
      Action_Handling => 5,
      Action_Abort => 6, Action_Warning => 7, Action_Suspend => 8,
      Action_External_Release => 9, Action_Self_Close => 10);
   for Action_Status'Size use Interfaces.C.int'Size;
   pragma Convention (C, Action_Status);

   function Dispatch
     (State : System.Address; Input : not null access constant Request;
      Output : not null access Response) return Action_Status
     with Export, Convention => C, External_Name => "ada_lua_dispatch";
   --  Return LUA_OK, LUA_ERRRUN or LUA_ERRMEM after releasing the Ada stack.
   --  Output owns no value: any returned pointer borrows the owning universe.
   --  @param State Stable C surface, null only for a state constructor.
   --  @param Input One operation; indices obey the pinned public C API.
   --  @param Output Scalar results or a borrowed stable string/state pointer.
   --  @return A control action for the C boundary, never an Ada exception.

   procedure Invoke_Borrowed
     (State : in out World; Driver : in out Lua.Engine.Machine.Driver);
   --  Invoke one requested C function/warning above a C-owned guard, borrowing
   --  this actual Ada driver's lifetime. Host abort returns to the Ada host;
   --  it never becomes a protected Lua error or terminates that host process.

   procedure Initialize_Bridge;
   --  Verify the C/Ada surface contract during library elaboration.

   procedure Set_Concatenation_Top (State : in out World; Top : Natural);
   --  Shrink the actual current C/borrowed API view after a completed fold.
   --  Top is absolute and stays above its retained prefix. This invokes no
   --  closer; lua_concat's free-operand precondition excludes closing slots.

   procedure Prepare_Thread_Surface
     (State : in out World; Context : Context_Id);
   --  Reserve the addressed thread's C surface while thread construction
   --  may allocate. An Ada-only world without a C main surface does nothing;
   --  its first borrowed C entry prepares existing threads before invocation.
   --  Public thread-pointer queries subsequently borrow without allocation.

   function Thread_Identity
     (State : in out World; Context : Context_Id) return System.Address;
   --  Borrow the actual stable C thread pointer. An Ada-only world lazily
   --  materializes its main/selected surfaces before publishing an identity,
   --  so a later first C callback cannot change a saved Lua %p/tostring.

   procedure Release_Context_Control (State : in out World;
                                      Context : not null Context_Access);
   --  Release reserved idle reset-driver/record ownership before freeing the
   --  context's raw C control block. No callback or execution occurs here.

   function Contract_Size (Part : Interfaces.C.int)
                          return Interfaces.C.size_t
     with Export, Convention => C, External_Name => "ada_lua_contract";
   --  Compare ordinary C record sizes at the C startup boundary. Part zero
   --  selects Request, one Response, and two the opaque state surface.
end Lua.Engine.Foreign;
