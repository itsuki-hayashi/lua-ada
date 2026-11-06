with Interfaces.C;
with Lua.Storage;
with System;

package Lua.Engine.Foreign is
   --  C entrypoints belong to the small C-owned boundary in c_api/. This
   --  package performs state operations and returns a typed result before
   --  that boundary raises an error or resumes any foreign callback. No
   --  nonlocal transfer is permitted while these Ada frames are active.
   type C_Function is access function
     (State : System.Address) return Interfaces.C.int
     with Convention => C;

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
      Begin_Call, Complete_Callback, Raise_Error, Load_Buffer);
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
      Load_Buffer => 43);
   for Operation_Code'Size use Interfaces.C.int'Size;
   pragma Convention (C, Operation_Code);

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
   end record with Convention => C;

   type Response is record
      Integer_Data : Interfaces.C.long_long := 0;
      Number_Data : Interfaces.C.double := 0.0;
      Pointer : System.Address := System.Null_Address;
      Length : Interfaces.C.size_t := 0;
      Allocator : Lua.Storage.Allocation_Function := null;
      Function_Data : C_Function := null;
      Error_Handled : Interfaces.C.int := 0;
   end record with Convention => C;

   type Action_Status is
     (Action_Done, Action_Call, Action_Raise, Action_Memory,
      Action_Handling, Action_Abort);
   for Action_Status use
     (Action_Done => 0, Action_Call => 1,
      Action_Raise => 2, Action_Memory => 4,
      Action_Handling => 5,
      Action_Abort => 6);
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

   procedure Initialize_Bridge;
   --  Verify the C/Ada surface contract during library elaboration.

   function Contract_Size (Part : Interfaces.C.int)
                          return Interfaces.C.size_t
     with Export, Convention => C, External_Name => "ada_lua_contract";
   --  Compare ordinary C record sizes at the C startup boundary. Part zero
   --  selects Request, one Response, and two the opaque state surface.
end Lua.Engine.Foreign;
