with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Interfaces.C.Strings;
with Lua.Canonical_Compiler;
with Lua.Chunks;
with Lua.Engine.Canonical;
with Lua.Engine.C_Operators;
with Lua.Engine.Stacks;
with Lua.Engine.IO_Libraries;
with Lua.Engine.Garbage_Collection;
with Lua.Engine.Foreign_Hooks;
with Lua.Engine.Library_Openers;
with Lua.Engine.Operating_System;
with Lua.Engine.Warnings;
with Lua.Engine.External_Releases;
with Lua.Prototypes;
with Lua.Inputs;
with Lua.Runtime_Configuration;
with Lua.Syntax;
with Lua.Syntax_Trees;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;

package body Lua.Engine.Foreign is
   package C renames Interfaces.C;
   package Memory renames Lua.Storage;
   package VM renames Lua.Engine.Machine;
   type Formatting_Data is record
      Owner : Memory.Owner_Access;
      Bytes : Owned_Buffer;
   end record;
   type Formatting_Access is access Formatting_Data;
   for Formatting_Access'Storage_Pool use Memory.Pool;
   package Formatting_Views is new
     System.Address_To_Access_Conversions (Formatting_Data);
   function Formatting_Handle is new Ada.Unchecked_Conversion
     (Formatting_Views.Object_Pointer, Formatting_Access);
   procedure Free_Formatting is new Ada.Unchecked_Deallocation
     (Formatting_Data, Formatting_Access);
   --  A live C raw guard owns each temporary. No pointer or Lua value is
   --  retained beyond that guard; refusal/host abort releases Bytes before
   --  propagating. Its payload grows only through this world's provider.
   use System.Storage_Elements;
   use type C.long_long;
   use type C.size_t;
   use type Lua.Syntax.Check_Status;
   use type Integer_Value;
   use type Real_Value;
   use type Memory.Allocation_Function;
   use type C.unsigned_long_long;
   use type System.Address;
   use type Lua.Prototypes.Prototype_Access;

   function Close_Regular (State : System.Address) return C.int
     with Import, Convention => C,
          External_Name => "lua_ada_io_close_regular";
   function Close_Pipe (State : System.Address) return C.int
     with Import, Convention => C,
          External_Name => "lua_ada_io_close_pipe";
   function Close_Borrowed (State : System.Address) return C.int
     with Import, Convention => C,
          External_Name => "lua_ada_io_close_borrowed";

   function IO_Close_Handler (Kind : IO_Close_Kind) return C_Function is
     (case Kind is
         when Regular_File_Close => Close_Regular'Access,
         when Pipe_File_Close => Close_Pipe'Access,
         when Borrowed_File_Close => Close_Borrowed'Access);

   Registry_Index : constant C.int := -(C.int'Last / 2 + 1_000);
   Stack_Limit : constant Natural :=
     Lua.Runtime_Configuration.Maximum_Stack;
   Foreign_Error : exception;
   Debug_Native_Source : aliased constant String :=
     "=[C]" & Character'Val (0);
   Debug_Empty_Name : aliased constant String := "" & Character'Val (0);
   Debug_Temporary : aliased constant String :=
     "(temporary)" & Character'Val (0);
   Debug_C_Temporary : aliased constant String :=
     "(C temporary)" & Character'Val (0);
   Debug_Vararg_Name : aliased constant String :=
     "(vararg)" & Character'Val (0);

   type World_View is access all World;
   type Driver_View is access all VM.Driver;
   package World_Views is new System.Address_To_Access_Conversions (World);
   package Driver_Views is new
     System.Address_To_Access_Conversions (VM.Driver);
   type Control is record
      Universe : World_View;
      Owned_Universe : World_Access;
      Context : Context_Id;
      Extra : Storage_Count;
      Seed : C.unsigned;
      Driver : Driver_View;
      Owned_Driver : VM.Driver_Access;
      Driver_Borrowed : Boolean := False;
      Owns_Universe : Boolean := True;
      Calls : System.Address := System.Null_Address;
   end record;
   --  Raw ownership metadata has no Ada finalizers or hidden allocations.
   --  Engine context cleanup releases both it and the separate state block.
   package Controls is new System.Address_To_Access_Conversions (Control);
   use type Controls.Object_Pointer;

   type Call_Record is record
      Previous : System.Address := System.Null_Address;
      Base : Natural := 0;
      Wanted : C.int := 0;
      Protected_Call : Boolean := False;
      Is_Root : Boolean := False;
      Context : Context_Id := 1;
      Activation : Frame_Access;
      Is_Resume : Boolean := False;
      Direct_Builtin : Boolean := False;
      Saved_Driver : Driver_View;
      Saved_Owned_Driver : VM.Driver_Access;
      Saved_Calls : System.Address := System.Null_Address;
      Saved_Borrowed : Boolean := False;
      Saved_Context : Context_Access;
      Saved_Native_Depth : Natural := 0;
      Saved_Status : Context_Status := New_Context;
      Entry_Depth : Natural := 0;
      Original_Top : Natural := 0;
      Original_Base : Natural := 0;
   end record;
   package Calls is new System.Address_To_Access_Conversions (Call_Record);
   function Function_Address is new Ada.Unchecked_Conversion
     (C_Function, System.Address);
   function Address_Function is new Ada.Unchecked_Conversion
     (System.Address, C_Function);
   function Continuation_Address is new Ada.Unchecked_Conversion
     (C_Continuation, System.Address);
   function Address_Continuation is new Ada.Unchecked_Conversion
     (System.Address, C_Continuation);
   function Warning_Address is new Ada.Unchecked_Conversion
     (C_Warning_Function, System.Address);
   function Address_Warning is new Ada.Unchecked_Conversion
     (System.Address, C_Warning_Function);
   function C_Extra_Space return C.size_t
     with Import, Convention => C, External_Name => "lua_ada_extra_space";
   function C_Invoke_Borrowed
     (State : System.Address; Action : Action_Status;
      Pending : not null access constant Response;
      Completion : not null access Response) return C.int
     with Import, Convention => C,
          External_Name => "lua_ada_invoke_borrowed";
   function C_Read_Guarded
     (State : System.Address; Reader : C_Reader; Data : System.Address;
      Completion : not null access Response) return C.int
     with Import, Convention => C, External_Name => "lua_ada_read_guarded";

   type Reader_Capture is record
      State : System.Address;
      Universe : World_View;
      Reader : C_Reader;
      Data : System.Address;
      Status : C.int := 0;
      Error_Handled : C.int := 0;
   end record;
   package Reader_Captures is new
     System.Address_To_Access_Conversions (Reader_Capture);
   function Read_Piece (Context : System.Address) return Lua.Inputs.Piece;
   function Retry_Input
     (Context : System.Address; Retried : in out Boolean) return Boolean;

   function Read_Piece (Context : System.Address) return Lua.Inputs.Piece is
      Capture : Reader_Capture renames
        Reader_Captures.To_Pointer (Context).all;
      Result : aliased Response;
      procedure Charge (Amount : Natural);
      procedure Charge (Amount : Natural) is
         State : World renames Capture.Universe.all;
      begin
         if State.Policy = Bounded then
            if State.Steps > State.Bounds.Instructions or else
              Amount > State.Bounds.Instructions - State.Steps
            then
               Fail (State, "instruction limit exceeded", Resource => True);
            end if;
            State.Steps := State.Steps + Amount;
         end if;
      end Charge;
   begin
      --  The checkpoint lives in C above this suspended Ada frontend. Every
      --  reader API error/yield returns a typed status here; it never jumps
      --  through parser/decoder frames or abandons their controlled storage.
      Charge (1);
      pragma Assert (Capture.Universe.Operation_Roots.Is_Empty and then
        Capture.Universe.Operation_Programs.Is_Empty);
      Capture.Status := C_Read_Guarded
        (Capture.State, Capture.Reader, Capture.Data, Result'Access);
      --  Reentrant API calls own their own short transient operation lease.
      --  At a refill the waiting frontend owns raw managed syntax/model
      --  storage, never an unrooted runtime Value or adopted wrapper. Renew
      --  its empty lease after C returns, retiring the callback's allocation
      --  epoch rather than retaining all of its discarded weak temporaries.
      --  This does not restart execution, counters or the selected policy.
      Begin_Operation (Capture.Universe.all);
      Capture.Error_Handled := Result.Error_Handled;
      if Capture.Status /= 0 then
         raise Lua.Inputs.Reader_Error;
      elsif Result.Pointer = System.Null_Address or else Result.Length = 0
      then
         return (others => <>);
      elsif Result.Length > C.size_t (Natural'Last) then
         raise Memory.Allocation_Error;
      end if;
      Charge (Natural (Result.Length));
      return (Result.Pointer, Natural (Result.Length));
   end Read_Piece;

   function Retry_Input
     (Context : System.Address; Retried : in out Boolean) return Boolean
   is
      Capture : Reader_Capture renames
        Reader_Captures.To_Pointer (Context).all;
   begin
      return Retry_Allocation (Capture.Universe.all, Retried);
   end Retry_Input;

   function Characters is new Ada.Unchecked_Conversion
     (System.Address, Interfaces.C.Strings.chars_ptr);

   type Surface is record
      Owner : System.Address;
      Guard : System.Address;
      Main : System.Address;
      Panic : C_Function;
   end record with Convention => C;
   package Surfaces is new System.Address_To_Access_Conversions (Surface);

   procedure Free_World is new Ada.Unchecked_Deallocation
     (World, World_Access);

   function Context_Of (Owner : Controls.Object_Pointer)
                        return Context_Access;
   function Create_Surface
     (State : World_View; Context : Context_Id; Extra : Storage_Count;
      Seed : C.unsigned; Main : System.Address;
      Owns_Universe : Boolean := True) return System.Address;
   function New_State (Input : Request) return System.Address;
   function Position
     (Context : Context_Access; Index : C.int) return Natural;
   function At_Index
     (State : World; Context : Context_Access; Index : C.int) return Value;
   function Valid_Index (Context : Context_Access; Index : C.int)
                         return Boolean;
   function Type_Code (Item : Value) return C.int;
   function Numeric
     (Universe : in out World; Item : Value)
      return Lua.Numbers.Number;
   procedure Publish_Top (Context : not null Context_Access; Top : Natural);
   procedure Set_C_Top
     (State : in out World; Context : not null Context_Access; Top : Natural);
   procedure Pop (Context : not null Context_Access; Count : Natural := 1);
   procedure Push
     (State : in out World; Context : not null Context_Access; Item : Value);
   function Read_Bytes
     (Pointer : System.Address; Length : C.size_t) return String;
   function Read_Name (Pointer : System.Address; Default : String)
                       return String;
   procedure Discard_Pending
     (State : in out World; Owner : Controls.Object_Pointer);

   procedure Discard_Pending
     (State : in out World; Owner : Controls.Object_Pointer)
   is
      Address : System.Address := Owner.Calls;
      Pending : constant Calls.Object_Pointer := Calls.To_Pointer (Address);
      Target : constant Context_Access :=
        State.Contexts (Positive (Pending.Context));
   begin
      --  Raw pending metadata owns a driver switch, not just an allocation.
      --  Restore those fields before freeing the record on every exceptional
      --  exit, including a host abort caught by an Ada borrowed callback.
      if Pending.Is_Resume then
         VM.Cancel (Owner.Driver.all);
         VM.Free_Driver (Owner.Owned_Driver);
         Owner.Driver := Pending.Saved_Driver;
         Owner.Owned_Driver := Pending.Saved_Owned_Driver;
         Owner.Driver_Borrowed := Pending.Saved_Borrowed;
         Owner.Calls := Pending.Saved_Calls;
         State.Current := Pending.Saved_Context;
         State.Native_Depth := Pending.Saved_Native_Depth;
         Target.C_Resuming := False;
         Target.Status := Dead_Context;
      else
         Owner.Calls := Pending.Previous;
         if Pending.Is_Root then
            VM.Cancel (Owner.Driver.all);
            State.Current := Target;
            VM.Clear_Frames (State, Pending.Entry_Depth);
            if Target.Non_Yieldable > 0 then
               Target.Non_Yieldable := Target.Non_Yieldable - 1;
            end if;
            Target.Status := Pending.Saved_Status;
            Target.Foreign_Base := Pending.Original_Base;
            Target.Foreign_Top := Pending.Original_Top;
            Target.Host_Stack_Top := Pending.Original_Top;
         end if;
      end if;
      Memory.Release (State.Memory, Address);
   end Discard_Pending;

   function Read_Name (Pointer : System.Address; Default : String)
                       return String is
     (if Pointer = System.Null_Address then Default else
         Interfaces.C.Strings.Value (Characters (Pointer)));

   function Contract_Size (Part : C.int) return C.size_t is
   begin
      case Part is
         when 0 =>
            return C.size_t (Request'Object_Size / System.Storage_Unit);
         when 1 =>
            return C.size_t (Response'Object_Size / System.Storage_Unit);
         when 2 =>
            return C.size_t (Surface'Object_Size / System.Storage_Unit);
         when 3 =>
            return C.size_t
              (Debug_Information'Object_Size / System.Storage_Unit);
         when others => return 0;
      end case;
   end Contract_Size;

   procedure Initialize_Bridge is
   begin
      --  Public numeric ABI settings are checked here, while C compares the
      --  request/response/surface layouts before calling the dispatcher.
      pragma Assert (C.int'Size = 32);
      pragma Assert (C.long_long'Size = 64);
      pragma Assert (C.double'Size = 64);
      pragma Assert (Operation_Code'Size = C.int'Size);
      pragma Assert (C_Function'Size = System.Address'Size);
      Lua.Builtin_Registry.Initialize;
   end Initialize_Bridge;

   function Context_Of (Owner : Controls.Object_Pointer)
                        return Context_Access is
   begin
      return Owner.Universe.Contexts (Positive (Owner.Context));
   end Context_Of;

   function Create_Surface
     (State : World_View; Context : Context_Id; Extra : Storage_Count;
      Seed : C.unsigned; Main : System.Address;
      Owns_Universe : Boolean := True) return System.Address
   is
      Item : constant Context_Access := State.Contexts (Positive (Context));
      Header, Block : System.Address := System.Null_Address;
      Result : System.Address;
   begin
      if Item.Foreign_State /= System.Null_Address then
         return Item.Foreign_State;
      end if;
      --  Ordinary pushes preserve one free error slot. Refusal therefore can
      --  publish the preallocated memory object without growing this stack.
      Stacks.Reserve
        (State.all, Item, Natural'Max
           (Initial_Stack_Size + Extra_Stack, Item.Stack_Used));
      if Item.Stack.Is_Empty and then Item.Stack_Used = 0 then
         Item.Stack_Used := Minimum_C_Stack;
      end if;
      if Extra mod Storage_Count (Surface'Alignment) /= 0 then
         raise Foreign_Error with "unaligned configured extra space";
      end if;
      --  Object_Size includes ABI tail padding. Size can describe only the
      --  value bits; importing a typed view into that shorter allocation
      --  would permit an ordinary record assignment to overrun the payload.
      Header := Memory.Allocate
        (State.Memory, Control'Object_Size / System.Storage_Unit,
         Control'Alignment);
      Block := Memory.Allocate
        (State.Memory, Extra + Surface'Object_Size / System.Storage_Unit,
         Surface'Alignment);
      Result := Block + Storage_Offset (Extra);
      Controls.To_Pointer (Header).all :=
        (Universe => State, Context => Context, Extra => Extra,
         Seed => Seed, Driver => null,
         Owns_Universe =>
           (if Main = System.Null_Address then Owns_Universe else
              Controls.To_Pointer
                (Surfaces.To_Pointer (Main).Owner).Owns_Universe),
         others => <>);
      Surfaces.To_Pointer (Result).all :=
        (Owner => Header, Guard => System.Null_Address,
         Main => (if Main = System.Null_Address then Result else Main),
         Panic => null);
      if Extra > 0 then
         declare
            Prefix : Storage_Array (1 .. Storage_Offset (Extra))
              with Import, Address => Block;
         begin
            if Main = System.Null_Address then
               Prefix := [others => 0];
            else
               declare
                  Original : constant Storage_Array (Prefix'Range)
                    with Import,
                    Address => Main - Storage_Offset (Extra);
               begin
                  Prefix := Original;
               end;
            end if;
         end;
      end if;
      --  Publish only after both blocks and all fields are initialized. A
      --  failed allocator callback leaves no partially usable C state pointer.
      Item.Foreign_Control := Header;
      Item.Foreign_Block := Block;
      Item.Foreign_State := Result;
      return Result;
   exception
      when others =>
         Memory.Release (State.Memory, Block);
         Memory.Release (State.Memory, Header);
         raise;
   end Create_Surface;

   procedure Prepare_Thread_Surface
     (State : in out World; Context : Context_Id)
   is
      Main : System.Address;
      Owner : Controls.Object_Pointer;
      Prepared : System.Address;
   begin
      if State.Main_Context = null or else
        State.Main_Context.Foreign_State = System.Null_Address
      then
         return;
      end if;
      Main := State.Main_Context.Foreign_State;
      Owner := Controls.To_Pointer (Surfaces.To_Pointer (Main).Owner);
      Prepared := Create_Surface
        (World_View (World_Views.To_Pointer (State'Address)), Context,
         Owner.Extra, Owner.Seed, Main);
      if Prepared = System.Null_Address then
         raise Program_Error with "missing prepared C thread surface";
      end if;
   end Prepare_Thread_Surface;

   function New_State (Input : Request) return System.Address is
      State : World_Access;
      Result : System.Address;
      Operation_Active : Boolean := False;
   begin
      State := new World;
      if Input.Operation = Create_State then
         if Input.Allocator = null then
            Free_World (State);
            return System.Null_Address;
         end if;
         Memory.Set_Allocator
           (State.Memory, Input.Allocator, Input.Pointer);
      end if;
      State.Open_Standard_Libraries := False;
      Initialize (State.all, (others => <>));
      Set_Policy (State.all, Lua_Compatible);
      if Input.Operation = Create_State then
         State.Warning_Mode := No_Warning_Handler;
      end if;
      --  C-created states publish to native stdout. Ada sessions select
      --  capture by default, independently of their execution quota policy.
      State.Output_Mode := Process_Streams;
      Begin_Operation (State.all);
      Operation_Active := True;
      Result := Create_Surface
        (World_View (State), Context_Id (State.Main_Thread.Context_Index),
         Storage_Count (Input.Length), Input.Seed, System.Null_Address);
      Controls.To_Pointer (Surfaces.To_Pointer (Result).Owner).
        Owned_Universe := State;
      --  Engine.Initialize owns the one actual registry for every session.
      End_Operation (State.all);
      Operation_Active := False;
      return Result;
   exception
      when others =>
         if State /= null then
            if Operation_Active then
               End_Operation (State.all);
            end if;
            Finalize (State.all);
            Free_World (State);
         end if;
         return System.Null_Address;
   end New_State;

   procedure External_Request (State : in out World; Output : out Response);

   procedure External_Request (State : in out World; Output : out Response)
   is
      Item : constant Object_Access :=
        External_Releases.Begin_Callback (State);
   begin
      Output := (others => <>);
      Output.Allocator := Item.String_Allocator;
      Output.Warning_Data := Item.String_Allocator_Data;
      Output.Warning_Message := Item.C_Bytes;
      Output.Length := C.size_t (Item.Bytes.Size) + 1;
      Output.Callback_Token :=
        (Item.all'Address, C.unsigned_long_long (Item.Serial));
   end External_Request;

   procedure Invoke_Borrowed
     (State : in out World; Driver : in out VM.Driver)
   is
      Universe : constant World_View :=
        World_View (World_Views.To_Pointer (State'Address));
      Main_State, Callback_State : System.Address;
      Owner : Controls.Object_Pointer;
      Saved_Driver : Driver_View := null;
      Saved_Borrowed : Boolean := False;
      Input, Output : aliased Response;
      Token : Callback_Identity;
      Target : Context_Access;
      Action, Status : Action_Status;
      Raw_Status : C.int;
      Attached : Boolean := False;
      Is_Release : constant Boolean := External_Releases.Pending (State);
      Is_Warning : constant Boolean :=
        not Is_Release and then Warnings.Pending (State);

      procedure Restore;
      procedure Allocation_Failed;
      procedure Restore is
      begin
         if not Attached then return; end if;
         --  Every nested C boundary belongs to this borrow. On a host abort,
         --  its C activations have already unwound; release scalar ownership
         --  metadata without running a Lua callback or restarting a budget.
         while Owner.Calls /= System.Null_Address loop
            Discard_Pending (State, Owner);
         end loop;
         Owner.Driver := Saved_Driver;
         Owner.Driver_Borrowed := Saved_Borrowed;
         Attached := False;
      end Restore;

      procedure Allocation_Failed is
      begin
         Restore;
         Record_Memory_Error (State);
         if Is_Release then
            --  The payload remains queued if the borrowed C surface cannot
            --  be obtained. In particular, never lose/free an uncalled
            --  allocator packet while handling permanent memory refusal.
            raise Language_Error;
         elsif Is_Warning then
            State.Warning_Head.Warning_Failed := True;
            Warnings.Discard (State, State.Warning_Head);
         else
            --  Native windows reserve LUA_MINSTACK beyond their arguments.
            --  This error publication therefore needs no new stack storage,
            --  even if constructing the first opaque C surface was refused.
            Target := VM.Foreign_Context (Driver);
            Target.Foreign_Top := Target.Foreign_Top + 1;
            Stacks.Write
              (State, Target, Target.Foreign_Top, Target.Failure);
            Target.Stack_Window.Stack_Live_Top := Target.Foreign_Top;
            VM.Complete_Foreign_Call
              (Driver, 0, 4, Token => VM.Foreign_Token (Driver));
         end if;
      end Allocation_Failed;
   begin
      --  Context-owned C surfaces may retain World's stable address until
      --  that same world releases them. Their ownership flag forbids C from
      --  freeing an Ada-owned world. The Driver view lasts only through this
      --  synchronous borrow and is restored before the Run activation ends;
      --  no named access-to-nested-subprogram or abandoned stack is stored.
      Main_State := Create_Surface
        (Universe, Context_Id (State.Main_Thread.Context_Index),
         Storage_Count (C_Extra_Space), 0, System.Null_Address,
         Owns_Universe => False);
      --  An Ada session can have created coroutines before its first C
      --  callback. This entry is allowed to allocate; once native code runs,
      --  converting one of those thread values must be a pure pointer read.
      for Index in State.Contexts.First_Index .. State.Contexts.Last_Index
      loop
         if State.Contexts (Index) /= null then
            Prepare_Thread_Surface (State, Context_Id (Index));
         end if;
      end loop;
      Owner := Controls.To_Pointer (Surfaces.To_Pointer (Main_State).Owner);
      if Owner.Calls /= System.Null_Address or else Owner.Driver_Borrowed then
         raise Program_Error with "Ada execution already owns a C borrow";
      end if;
      Saved_Driver := Owner.Driver;
      Saved_Borrowed := Owner.Driver_Borrowed;
      Owner.Driver :=
        Driver_View (Driver_Views.To_Pointer (Driver'Address));
      Owner.Driver_Borrowed := True;
      Attached := True;
      if Is_Release then
         Target := State.Current;
         Action := Action_External_Release;
      elsif Is_Warning then
         Target := State.Warning_Head.Context;
         Input.Warning_Function :=
           Address_Warning (State.Warning_Head.Warning_Handler);
         Input.Warning_Data := State.Warning_Head.Warning_Data;
         Input.Warning_Message := State.Warning_Head.Warning_Message.Address;
         Input.Warning_Continuation :=
           Boolean'Pos (State.Warning_Head.Warning_To_Continue);
         Token := Warnings.Identity (State);
         Warnings.Begin_Callback (State);
         Action := Action_Warning;
      else
         Target := VM.Foreign_Context (Driver);
         Input.Function_Data := Address_Function (VM.Foreign_Handler (Driver));
         Input.Continuation :=
           Address_Continuation (VM.Foreign_Continuation (Driver));
         Input.KContext := VM.Foreign_KContext (Driver);
         Input.KStatus := VM.Foreign_KStatus (Driver);
         Token := VM.Foreign_Token (Driver);
         Action := Action_Call;
      end if;
      Callback_State := Create_Surface
        (Universe, Context_Id (Target.Thread.Context_Index),
         Owner.Extra, Owner.Seed, Main_State, Owns_Universe => False);
      if Is_Release then
         External_Request (State, Input);
         Token := Input.Callback_Token;
      end if;
      Input.Callback_Token := Token;
      Raw_Status := C_Invoke_Borrowed
        (Callback_State, Action, Input'Access, Output'Access);
      case Raw_Status is
         when 0 => Status := Action_Done;
         when 2 => Status := Action_Raise;
         when 4 => Status := Action_Memory;
         when 5 => Status := Action_Handling;
         when 6 => Status := Action_Abort;
         when 8 => Status := Action_Suspend;
         when others =>
            raise Program_Error with "invalid borrowed C callback transfer";
      end case;
      if Is_Release then
         --  Even a nonreturning, invalid allocator must not leak its header
         --  or leave a foreign stack borrow installed. The ordinary guarded
         --  status is handled only after this ownership acknowledgment.
         External_Releases.Complete (State, Token);
         if Status /= Action_Done then
            Restore;
            raise Language_Error;
         end if;
      elsif Status = Action_Abort then
         Restore;
         if State.Current.Failure_Class /= Host_Abort then
            State.Current.Failure_Class := Host_Abort;
            State.Current.Transfer.Kind := Host_Stopped;
            State.Current.Failure_Text :=
              To_Unbounded_String ("foreign host abort");
         end if;
         raise Language_Error;
      end if;
      if Is_Release then
         null;
      elsif Is_Warning then
         if Status /= Action_Done then
            Target.Failure := Stacks.Read (Target, Target.Foreign_Top);
            Root_Barrier (State, Target.Failure);
            Target.Has_Failure_Value := True;
            Target.Failure_Text := To_Unbounded_String
              (Image (Target.Memory, Target.Failure));
            Target.Failure_Class :=
              (if Status = Action_Memory then Memory_Failure
               elsif Status = Action_Handling then Handling_Failure
               else Language_Failure);
            Target.Failure_Handled := Output.Error_Handled /= 0;
            State.Warning_Head.Warning_Failed := True;
         end if;
         Warnings.Acknowledge (State, Token);
      elsif Status /= Action_Suspend then
         VM.Complete_Foreign_Call
           (Driver, Natural (Output.Integer_Data),
            Action_Status'Enum_Rep (Status), Output.Error_Handled /= 0, Token);
      end if;
      Restore;
   exception
      when Memory.Allocation_Error =>
         Allocation_Failed;
      when Program_Error =>
         if Memory.Refusal_Pending (State.Memory) then
            Allocation_Failed;
         else
            Restore;
            raise;
         end if;
      when others =>
         Restore;
         raise;
   end Invoke_Borrowed;

   function Position
     (Context : Context_Access; Index : C.int) return Natural
   is
      Number : constant Integer_Value :=
        (if Index > 0 then Integer_Value (Context.Foreign_Base) +
           Integer_Value (Index)
         else Integer_Value (Context.Foreign_Top) +
           Integer_Value (Index) + 1);
   begin
      if Index = 0 or else Index <= Registry_Index or else
        Number <= Integer_Value (Context.Foreign_Base)
        or else Number > Integer_Value (Context.Foreign_Top)
      then
         return 0;
      end if;
      return Natural (Number);
   end Position;

   function Valid_Index (Context : Context_Access; Index : C.int)
                         return Boolean
   is
      Activation : constant Frame_Access := Context.Foreign_Activation;
      Upvalue : constant C.long_long :=
        C.long_long (Registry_Index) - C.long_long (Index);
   begin
      if Index = Registry_Index then
         return True;
      elsif Index < Registry_Index then
         return Activation /= null and then Activation.Native_Self /= null
           and then Upvalue in 1 .. C.long_long
             (Activation.Native_Self.Captures.Length);
      end if;
      return Position (Context, Index) /= 0;
   end Valid_Index;

   function At_Index
     (State : World; Context : Context_Access; Index : C.int) return Value
   is
      Slot : constant Natural := Position (Context, Index);
   begin
      if Index = Registry_Index then
         return (Kind => Table_Kind, Reference => State.Foreign_Registry);
      elsif Index < Registry_Index then
         declare
            Upvalue : constant C.long_long :=
              C.long_long (Registry_Index) - C.long_long (Index);
            Activation : constant Frame_Access := Context.Foreign_Activation;
         begin
            if Activation /= null and then Activation.Native_Self /= null
              and then Upvalue in 1 .. C.long_long
                (Activation.Native_Self.Captures.Length)
            then
               return Activation.Native_Self.Captures
                 (Positive (Upvalue)).Cell_Value;
            end if;
            return Nil_Value;
         end;
      elsif Slot = 0 then
         return Nil_Value;
      end if;
      return Stacks.Read (Context, Slot);
   end At_Index;

   function Type_Code (Item : Value) return C.int is
   begin
      case Item.Kind is
         when Nil_Kind => return 0;
         when Boolean_Kind => return 1;
         when Light_Identity_Kind => return 2;
         when Integer_Kind | Real_Kind => return 3;
         when String_Kind => return 4;
         when Table_Kind => return 5;
         when Closure_Kind | Native_Closure_Kind | Native_Kind_Value |
           Foreign_Function_Kind =>
            return 6;
         when Userdata_Kind => return 7;
         when Thread_Kind => return 8;
      end case;
   end Type_Code;

   function Numeric
     (Universe : in out World; Item : Value)
      return Lua.Numbers.Number is
   begin
      case Item.Kind is
         when Integer_Kind =>
            return (Lua.Numbers.Integer_Number, Item.Integer_Data);
         when Real_Kind =>
            return (Lua.Numbers.Real_Number, Item.Real_Data);
         when String_Kind =>
            return Read_Number (Universe, Item.Reference.Bytes);
         when others => return (Kind => Lua.Numbers.Invalid);
      end case;
   end Numeric;

   procedure Ensure_Base_C_Frame
     (State : in out World; Context : not null Context_Access);
   procedure Ensure_Base_C_Frame
     (State : in out World; Context : not null Context_Access)
   is
      Item : Frame_Access;
   begin
      if Context.Foreign_Activation /= null then
         return;
      elsif not Context.Stack.Is_Empty or else Context.Stack_Window /= null
      then
         raise Foreign_Error with "C closing slot has no current C frame";
      end if;
      --  An idle C API stack already owns these scalar slots. Materialize
      --  only its missing activation metadata: no function slot is inserted,
      --  no value is copied, and no C function pointer is manufactured. The
      --  same ordinary close list/cells then serve host and callback slots.
      Item := Context.Base_C_Frame;
      if Item = null or else Item.Has_Stack_Window then
         raise Program_Error with "missing idle base C activation";
      end if;
      Context.Stack.Append (Item);
      Item.Is_Native := True;
      Item.Native_Name := To_Unbounded_String ("@host.base");
      Item.Stack_Base := 0;
      Item.Call_Base := 1;
      Item.Stack_Live_Top := Context.Foreign_Top;
      VM.Resize_Stack_Window (State, Item, Context.Stack_Used);
      --  Retiring the base must restore an empty API stack, rather than the
      --  historical top at first registration. Its window now traces the
      --  actual values; an old host prefix would retain popped weak values.
      Item.Saved_Foreign_Top := 0;
      Context.Host_Stack_Top := 0;
      Context.Foreign_Activation := Item;
   end Ensure_Base_C_Frame;

   procedure Publish_Top (Context : not null Context_Access; Top : Natural) is
   begin
      Context.Foreign_Top := Top;
      if Context.Foreign_Activation = null then
         Context.Host_Stack_Top := Top;
      else
         Context.Foreign_Activation.Stack_Live_Top := Top;
      end if;
   end Publish_Top;

   procedure Set_C_Top
     (State : in out World; Context : not null Context_Access; Top : Natural)
   is
      Old : constant Natural := Context.Foreign_Top;
   begin
      --  Reserve through a stable index before publishing a larger top. Both
      --  scalar/cell arrays grow together; their retained initialized length
      --  may exceed the visible C window and must never be truncated here.
      if Top > Context.Stack_Used then
         if not VM.Ensure_Stack (State, Context, Top) then
            raise Program_Error with "raising stack check returned false";
         end if;
         if Context.Foreign_Activation /= null then
            VM.Resize_Stack_Window
              (State, Context.Foreign_Activation, Top - Context.Foreign_Base);
         else
            Context.Stack_Used := Top;
         end if;
      end if;
      if Top < Old then
         Stacks.Clear_Range (Context, Top + 1, Old);
      else
         for Index in Old + 1 .. Top loop
            Stacks.Write (State, Context, Index, Nil_Value);
         end loop;
      end if;
      Publish_Top (Context, Top);
   end Set_C_Top;

   procedure Pop (Context : not null Context_Access; Count : Natural := 1) is
      Old : constant Natural := Context.Foreign_Top;
   begin
      if Count > Old - Context.Foreign_Base then
         raise Foreign_Error with "C stack underflow";
      end if;
      Stacks.Clear_Range (Context, Old - Count + 1, Old);
      Publish_Top (Context, Old - Count);
   end Pop;

   procedure Push
     (State : in out World; Context : not null Context_Access; Item : Value) is
      Top : constant Natural := Context.Foreign_Top;
   begin
      if Top + 1 > Context.Stack_Used then
         if not VM.Ensure_Stack (State, Context, Top + 1) then
            raise Program_Error with "raising stack check returned false";
         end if;
         if Context.Foreign_Activation /= null then
            VM.Resize_Stack_Window
              (State, Context.Foreign_Activation,
               Top + 1 - Context.Foreign_Base);
         else
            Context.Stack_Used := Top + 1;
         end if;
      end if;
      --  A completed callback publishes into a pre-reserved caller window.
      --  There is no vector Append and no allocation when capacity suffices.
      Stacks.Write (State, Context, Top + 1, Item);
      Publish_Top (Context, Top + 1);
   end Push;

   function Read_Bytes
     (Pointer : System.Address; Length : C.size_t) return String
   is
   begin
      if Length > C.size_t (Natural'Last) or else
        (Length > 0 and Pointer = System.Null_Address)
      then
         raise Foreign_Error with "invalid C string extent";
      end if;
      if Length = 0 then
         return "";
      end if;
      declare
         Bytes : constant String (1 .. Natural (Length))
           with Import, Address => Pointer;
      begin
         return Bytes;
      end;
   end Read_Bytes;

   procedure Inspect_API
     (State : in out World; Context : not null Context_Access;
      Input : Request; Output : in out Response);
   procedure Inspect_API
     (State : in out World; Context : not null Context_Access;
      Input : Request; Output : in out Response) is separate;

   procedure Format_API
     (State : in out World; Context : not null Context_Access;
      Input : Request; Output : in out Response);
   procedure Format_API
     (State : in out World; Context : not null Context_Access;
      Input : Request; Output : in out Response) is separate;

   function Dispatch
     (State : System.Address; Input : not null access constant Request;
      Output : not null access Response) return Action_Status
   is
      Owner : Controls.Object_Pointer;
      Context : Context_Access;
      Active_World : World_View;
      Previous : Context_Access;
      Operation_Active : Boolean := False;
      Keep_Scheduler : Boolean := False;
      Main_Owner : Controls.Object_Pointer;

      procedure Leave_Context;
      procedure Error_Result (Text : String);
      procedure Memory_Result;
      function Require_Table return Value;
      procedure Get_Raw (Key : Value);
      procedure Prepare_C_Slots
        (Frame : not null Frame_Access; Depth : Natural);
      function Pump (Start_Error : Boolean := False) return Action_Status;

      procedure Prepare_C_Slots
        (Frame : not null Frame_Access; Depth : Natural)
      is
         Captures : Values.Vector := Owned_Values (Owner.Universe.all);
      begin
         Append_Root (Owner.Universe.all, Captures,
                      (Light_Identity_Kind, Frame.all'Address));
         Append_Root (Owner.Universe.all, Captures,
                      (Integer_Kind, Integer_Value (Depth)));
         Push (Owner.Universe.all, Context,
               New_Native (Owner.Universe.all, "@foreign.close", Captures));
         Output.Length := 1;
      end Prepare_C_Slots;

      procedure Leave_Context is
      begin
         if Active_World /= null then
            if Operation_Active then
               End_Operation (Active_World.all);
               Operation_Active := False;
            end if;
            if not Keep_Scheduler then
               Active_World.Current := Previous;
            end if;
            Active_World := null;
         end if;
      end Leave_Context;

      procedure Error_Result (Text : String) is
         Item : Value;
      begin
         --  Error objects enter traced C stack storage before control returns
         --  to the C guard. Refusal while making the error cannot recurse.
         if Context /= null then
            Item := New_String (Owner.Universe.all, Text);
            Push (Owner.Universe.all, Context, Item);
            Output.Pointer := Item.Reference.C_Bytes;
         end if;
      exception
         when others => null;
      end Error_Result;

      procedure Memory_Result is
         Saved : Context_Access;
      begin
         if Context /= null then
            --  The actual immutable error string was allocated during state
            --  initialization. Its reserved stack slot needs no provider call.
            Saved := Owner.Universe.Current;
            Owner.Universe.Current := Context;
            Record_Memory_Error (Owner.Universe.all);
            Owner.Universe.Current := Saved;
            if Input.Operation = Begin_Resume then
               --  All setup refusal points leave one error-dead thread;
               --  no unstarted argument packet remains resumable by accident.
               Context.C_Resuming := False;
               Context.Status := Dead_Context;
               if Input.Index >= 0 then
                  Pop (Context, Natural'Min
                    (Natural (Input.Index),
                     Context.Foreign_Top - Context.Foreign_Base));
               end if;
            end if;
            Push (Owner.Universe.all, Context, Context.Failure);
            Output.Pointer := Context.Failure.Reference.C_Bytes;
         end if;
      exception
         when others => null;
      end Memory_Result;

      function Get_Value (Index : C.int) return Value is
        (At_Index (Owner.Universe.all, Context, Index));

      function Require_Table return Value is
         Item : constant Value := Get_Value (Input.Index);
      begin
         if Item.Kind /= Table_Kind then
            raise Foreign_Error with "table expected";
         end if;
         return Item;
      end Require_Table;

      procedure Get_Raw (Key : Value) is
         Item : constant Value := Get (Require_Table, Key);
      begin
         --  A retrieved weak value is no longer protected by the source
         --  table's marking policy while the destination stack grows.
         Pin (Owner.Universe.all, Item);
         Push (Owner.Universe.all, Context, Item);
         Output.Integer_Data := C.long_long (Type_Code (Item));
      end Get_Raw;

      function Pump (Start_Error : Boolean := False) return Action_Status is
         Driver : VM.Driver renames Main_Owner.Driver.all;
         Record_Address : constant System.Address := Main_Owner.Calls;
         Pending : constant Calls.Object_Pointer :=
           Calls.To_Pointer (Main_Owner.Calls);
         Is_Resume_Entry : constant Boolean := Pending.Is_Resume;
         Caller : constant Context_Access := Owner.Universe.Contexts
           (Positive (Pending.Context));
         Packet : Values.Vector renames Caller.Boundary_Results;
         Error_Status : Natural := 0;
         Handler_Called : Boolean := False;
         Count : Natural;
         Address : System.Address;
      begin
         --  Every iteration executes one explicit scheduler phase. Returning
         --  a callback action destroys this Ada activation before C invokes
         --  the foreign function or establishes a nonlocal-transfer guard.
         Keep_Scheduler := True;
         Packet.Clear;
         if Start_Error then
            if Owner.Universe.Current.Failure_Class = Host_Abort then
               return Action_Abort;
            end if;
            Error_Status :=
              (if Owner.Universe.Current.Failure_Class = Memory_Failure then 4
               elsif Owner.Universe.Current.Failure_Class = Handling_Failure
               then 5 else 2);
            Append_Root
              (Owner.Universe.all, Packet,
               (if Owner.Universe.Current.Has_Failure_Value then
                   Owner.Universe.Current.Failure else
                   New_String (Owner.Universe.all, To_String
                     (Owner.Universe.Current.Failure_Text))));
         end if;
         loop
            if External_Releases.Pending (Owner.Universe.all) then
               declare
                  Surface : constant System.Address := Create_Surface
                    (Owner.Universe, Context_Id
                       (Owner.Universe.Current.Thread.Context_Index),
                     Main_Owner.Extra, Main_Owner.Seed,
                     Surfaces.To_Pointer (State).Main);
               begin
                  External_Request (Owner.Universe.all, Output.all);
                  Output.Pointer := Surface;
                  return Action_External_Release;
               end;
            end if;
            exit when Error_Status /= 0 or else VM.Is_Complete (Driver) or else
              VM.Has_Foreign_Result (Driver);
            if Warnings.Pending (Owner.Universe.all) then
               declare
                  Event : constant Frame_Access :=
                    Owner.Universe.Warning_Head;
                  Ready : Boolean := False;
               begin
                  begin
                     Output.Pointer := Create_Surface
                       (Owner.Universe, Context_Id
                          (Event.Context.Thread.Context_Index),
                        Main_Owner.Extra, Main_Owner.Seed,
                        Surfaces.To_Pointer (State).Main);
                     Ready := True;
                  exception
                     when Memory.Allocation_Error => null;
                     when Program_Error =>
                        if not Memory.Refusal_Pending
                          (Owner.Universe.Memory)
                        then
                           raise;
                        end if;
                  end;
                  if not Ready then
                     Record_Memory_Error (Owner.Universe.all);
                     Event.Warning_Failed := True;
                     Warnings.Discard (Owner.Universe.all, Event);
                  else
                     Output.Warning_Function :=
                       Address_Warning (Event.Warning_Handler);
                     Output.Warning_Data := Event.Warning_Data;
                     Output.Warning_Message := Event.Warning_Message.Address;
                     Output.Warning_Continuation :=
                       Boolean'Pos (Event.Warning_To_Continue);
                     Output.Callback_Token :=
                       Warnings.Identity (Owner.Universe.all);
                     Warnings.Begin_Callback (Owner.Universe.all);
                     return Action_Warning;
                  end if;
               end;
            elsif VM.Needs_Foreign_Call (Driver) then
               declare
                  Target : constant Context_Access :=
                    VM.Foreign_Context (Driver);
                  Ready : Boolean := False;
               begin
                  begin
                     Output.Pointer := Create_Surface
                       (Owner.Universe,
                        Context_Id (Target.Thread.Context_Index),
                        Main_Owner.Extra, Main_Owner.Seed,
                        Surfaces.To_Pointer (State).Main);
                     Ready := True;
                  exception
                     when Memory.Allocation_Error => null;
                     when Program_Error =>
                        if not Memory.Refusal_Pending
                          (Owner.Universe.Memory)
                        then
                           raise;
                        end if;
                  end;
                  if not Ready then
                     --  Refusing a C surface is failure of this requested
                     --  callback. Feed the preallocated error through its
                     --  exact VM token, so its ordinary protected boundary
                     --  unwinds before any original caller C guard resumes.
                     Record_Memory_Error (Owner.Universe.all);
                     Push (Owner.Universe.all, Target, Target.Failure);
                     VM.Complete_Foreign_Call
                       (Driver, 0, 4, Token => VM.Foreign_Token (Driver));
                  else
                     Output.Function_Data :=
                       Address_Function (VM.Foreign_Handler (Driver));
                     Output.Continuation := Address_Continuation
                       (VM.Foreign_Continuation (Driver));
                     Output.KContext := VM.Foreign_KContext (Driver);
                     Output.KStatus := VM.Foreign_KStatus (Driver);
                     Output.Callback_Token := VM.Foreign_Token (Driver);
                     return Action_Call;
                  end if;
               end;
            end if;
            if not Pending.Is_Root and then
              Caller.Transfer.Kind = Yielded and then
              Pending.Activation /= null and then
              Pending.Activation.Foreign_Continuation /=
                System.Null_Address
            then
               --  The child suspended below a K-aware C call. Its boundary
               --  and original C activation now own the continuation; retire
               --  only this live pump's scalar call record before C unwinds.
               for Frame of reverse Caller.Stack loop
                  if Frame.Native_Name = "@foreign.boundary" and then
                    Frame.Foreign_Previous_Frame = Pending.Activation
                  then
                     Frame.Foreign_Suspended := True;
                     exit;
                  end if;
               end loop;
               Address := Main_Owner.Calls;
               Main_Owner.Calls := Pending.Previous;
               Memory.Release (Owner.Universe.Memory, Address);
               return Action_Suspend;
            end if;
            begin
               VM.Step (Driver);
            exception
               when Language_Error =>
                  if Owner.Universe.Current.Failure_Class = Host_Abort then
                     return Action_Abort;
                  end if;
                  Error_Status :=
                    (if Owner.Universe.Current.Failure_Class = Memory_Failure
                     then 4
                     elsif Owner.Universe.Current.Failure_Class =
                       Handling_Failure then 5 else 2);
                  Append_Root
                    (Owner.Universe.all, Packet,
                     (if Owner.Universe.Current.Has_Failure_Value then
                         Owner.Universe.Current.Failure else
                         New_String (Owner.Universe.all, To_String
                           (Owner.Universe.Current.Failure_Text))));
                  exit;
            end;
         end loop;
         if Error_Status = 0 then
            if Pending.Is_Root then
               if Pending.Is_Resume then
                  Error_Status :=
                    (if VM.Outcome (Driver) = Yielded then 1
                     elsif VM.Outcome (Driver) = Lua_Raised then 2 else 0);
                  VM.Take_Results (Driver, Packet);
               elsif VM.Outcome (Driver) /= Completed then
                  raise Foreign_Error with "unexpected C-call suspension";
               else
                  VM.Take_Results (Driver, Packet);
               end if;
               if not Pending.Is_Resume then
                  if Packet.Is_Empty or else
                    Packet.First_Element.Kind /= Boolean_Kind
                  then
                     raise Program_Error with "C entry lost protection packet";
                  end if;
                  if not Packet.First_Element.Boolean_Data then
                     Error_Status :=
                       (if Caller.Protected_Failure_Class = Memory_Failure
                        then 4
                        elsif Caller.Protected_Failure_Class = Handling_Failure
                        then 5 else 2);
                     Handler_Called := Caller.Protected_Handler_Called;
                  end if;
                  Packet.Delete_First;
               end if;
            else
               VM.Take_Foreign_Result
                 (Driver, Packet, Error_Status, Handler_Called);
            end if;
         end if;
         if Pending.Is_Root then
            VM.Finish (Driver);
            if Pending.Is_Resume then
               Caller.C_Resuming := False;
               if Error_Status not in 0 | 1 then
                  Caller.Status := Dead_Context;
               end if;
            else
               VM.Clear_Frames (Owner.Universe.all, Pending.Entry_Depth);
               Caller.Non_Yieldable := Caller.Non_Yieldable - 1;
               --  An ordinary protected C call does not consume a thread's
               --  coroutine lifecycle. In particular an independent main
               --  state may subsequently be used by lua_resume.
               Caller.Status := Pending.Saved_Status;
               Caller.Foreign_Base := Pending.Original_Base;
               Caller.Foreign_Top := Pending.Original_Top;
               Caller.Host_Stack_Top := Pending.Original_Top;
            end if;
         end if;
         if Pending.Is_Resume then
            --  Results cannot replace the bottom of a suspended Lua/C
            --  activation: those registers and C-prefix arguments are still
            --  live. Detach the host-facing stack above every retained real
            --  window. The next resume restores this exact execution view
            --  only after copying its newly supplied arguments into roots.
            Caller.Resume_Foreign_Activation := Caller.Foreign_Activation;
            Caller.Resume_Foreign_Base := Caller.Foreign_Base;
            Caller.Resume_Foreign_Top := Caller.Foreign_Top;
            Caller.Resume_Stack_Used := Caller.Stack_Used;
            Caller.Resume_Host_Stack_Top := Caller.Host_Stack_Top;
            Caller.Detached_Resume_Window := Error_Status = 1;
            Caller.Foreign_Activation := null;
            Caller.Foreign_Base :=
              (if Error_Status = 1 then Caller.Stack_Used
               else Caller.Resume_Return_Base);
            Caller.Foreign_Top :=
              (if Error_Status = 1 then Caller.Foreign_Base
               else Caller.Resume_Return_Top);
            Caller.Host_Stack_Top := Caller.Foreign_Top;
         else
            Set_C_Top (Owner.Universe.all, Caller, Pending.Base);
         end if;
         Count := (if Error_Status not in 0 | 1 then 1
                   elsif Pending.Wanted = -1 then Natural (Packet.Length)
                   else Natural (Pending.Wanted));
         --  The Call_Record contains only scalar ownership metadata; pop it
         --  before publishing results so allocation refusal cannot leave a
         --  finished operation registered as an active nested drive.
         Address := Main_Owner.Calls;
         Main_Owner.Calls := Pending.Previous;
         declare
            Protected_Call : constant Boolean := Pending.Protected_Call;
            Is_Resume : constant Boolean := Pending.Is_Resume;
            Direct_Builtin : constant Boolean := Pending.Direct_Builtin;
            Saved_Driver : constant Driver_View := Pending.Saved_Driver;
            Saved_Owned : constant VM.Driver_Access :=
              Pending.Saved_Owned_Driver;
            Saved_Calls : constant System.Address := Pending.Saved_Calls;
            Saved_Borrowed : constant Boolean := Pending.Saved_Borrowed;
            Saved_Context : constant Context_Access := Pending.Saved_Context;
            Saved_Depth : constant Natural := Pending.Saved_Native_Depth;
         begin
            Memory.Release (Owner.Universe.Memory, Address);
            if Is_Resume then
               --  Release/restore scalar driver ownership before result
               --  publication can allocate. A refused host-window growth
               --  must not strand the caller under a completed child drive.
               VM.Free_Driver (Main_Owner.Owned_Driver);
               Main_Owner.Driver := Saved_Driver;
               Main_Owner.Owned_Driver := Saved_Owned;
               Main_Owner.Calls := Saved_Calls;
               Main_Owner.Driver_Borrowed := Saved_Borrowed;
               Owner.Universe.Current := Saved_Context;
               Owner.Universe.Native_Depth := Saved_Depth;
               Output.Length := C.size_t (Count);
            end if;
            for Index in 1 .. Count loop
               Push (Owner.Universe.all, Caller,
                 (if Index <= Natural (Packet.Length) then Packet (Index)
                  else Nil_Value));
            end loop;
            if Direct_Builtin then
               Output.Length := C.size_t (Count);
            end if;
            Packet.Clear;
            Output.Integer_Data := C.long_long (Error_Status);
            Output.Error_Handled := Boolean'Pos (Handler_Called);
            if Error_Status /= 0 and then Protected_Call and then
              not Is_Resume and then Caller.Foreign_Activation /= null and then
              Caller.Foreign_Activation.Foreign_Continuation /=
                System.Null_Address
            then
               --  Yieldable pcallk recovers errors through K even when the
               --  protected child failed before its first yield. Abandon the
               --  original C body through its live guard, then request K as
               --  the next explicit callback; the coroutine itself has not
               --  yielded a result to its external resumer.
               Caller.Foreign_Activation.Foreign_KStatus :=
                 C.int (Error_Status);
               Caller.Foreign_Activation.Native_Stage := 1;
               return Action_Suspend;
            end if;
            if Error_Status /= 0 and then not Protected_Call and then
              not Is_Resume
            then
               if Stacks.Read (Caller, Caller.Foreign_Top).Kind = String_Kind
               then
                  Output.Pointer :=
                    Stacks.Read (Caller, Caller.Foreign_Top).Reference.C_Bytes;
               end if;
               return (if Error_Status = 4 then Action_Memory
                       elsif Error_Status = 5 then Action_Handling
                       else Action_Raise);
            end if;
         end;
         return Action_Done;
      exception
         when others =>
            Packet.Clear;
            if Main_Owner.Calls = Record_Address then
               Discard_Pending (Owner.Universe.all, Main_Owner);
            end if;
            if Is_Resume_Entry then
               --  Publication may fail after the record was already popped.
               --  Its ownership is restored, but the API error still belongs
               --  to the resumed root, not whichever nested C callback most
               --  recently returned control to this pump.
               Caller.C_Resuming := False;
               Caller.Status := Dead_Context;
               Context := Caller;
            end if;
            raise;
      end Pump;

   begin
      Output.all := (others => <>);
      if Input.Operation in Create_State | Create_Default_State then
         Output.Pointer := New_State (Input.all);
         return Action_Done;
      end if;
      if State = System.Null_Address then
         raise Foreign_Error with "null C state";
      end if;
      Owner := Controls.To_Pointer (Surfaces.To_Pointer (State).Owner);
      Main_Owner := Controls.To_Pointer
        (Surfaces.To_Pointer (Surfaces.To_Pointer (State).Main).Owner);
      Context := Context_Of (Owner);
      Active_World := Owner.Universe;
      Previous := Active_World.Current;
      Active_World.Current := Context;
      Begin_Operation (Active_World.all);
      Operation_Active := True;
      --  Errors and safe-point roots belong to the addressed thread, even
      --  when it is an inactive coroutine. Borrowing it never resets budgets
      --  or resumes Lua execution, and the caller's context is restored below.
      case Input.Operation is
         when Create_Formatter | Append_Format_Value | Append_Format_UTF8 |
           Finish_Formatter | Release_Formatter | Charge_Aux_Work =>
            Format_API (Owner.Universe.all, Context, Input.all, Output.all);
         when Prepare_External_Release =>
            if External_Releases.Pending (Owner.Universe.all) then
               External_Request (Owner.Universe.all, Output.all);
               Output.Pointer := State;
               Leave_Context;
               return Action_External_Release;
            end if;
         when Complete_External_Release =>
            External_Releases.Complete
              (Owner.Universe.all, Input.Callback_Token);
            if Input.Index /= 0 then
               Leave_Context;
               return Action_Status'Enum_Val (Input.Index);
            elsif Input.Count /= 0 then
               declare
                  Result : constant Action_Status := Pump;
               begin
                  Leave_Context;
                  return Result;
               end;
            end if;
         when Set_Hook | Get_Hook | Get_Hook_Mask | Get_Hook_Count |
           Get_Debug_Frame | Get_Debug_Line =>
            Foreign_Hooks.Handle
              (Owner.Universe.all, Context, Input.all, Output.all);
         when Get_Debug_Info | Get_Local | Set_Local | Get_Upvalue |
           Set_Upvalue | Upvalue_Id | Join_Upvalues =>
            Inspect_API
              (Owner.Universe.all, Context, Input.all, Output.all);
         when Get_Status =>
            --  Resume retains the failure category after its public result
            --  window is inspected or cleared. Report the same public status
            --  as the driver, rather than treating every retained error as a
            --  language failure. Suspended execution still takes precedence.
            Output.Integer_Data :=
              (if Context.Status = Suspended_Context then 1
               elsif Context.Has_Failure_Value then
                 (if Context.Failure_Class = Memory_Failure then 4
                  elsif Context.Failure_Class = Handling_Failure then 5
                  else 2)
               else 0);
         when Prepare_Index =>
            declare
               Target : constant Value := Get_Value (Input.Index);
               Is_Set : constant Boolean := Input.Count /= 0;
               Needed : constant Positive := (if Is_Set then 2 else 1);
               Key, Item : Value;
            begin
               if Context.Foreign_Top - Context.Foreign_Base < Needed then
                  raise Foreign_Error with "missing table operation operands";
               end if;
               Key := Get_Value (-C.int (Needed));
               if Is_Set then Item := Get_Value (-1); end if;
               Pin (Owner.Universe.all, Target);
               Pin (Owner.Universe.all, Key);
               Pin (Owner.Universe.all, Item);
               if Target.Kind = Table_Kind and then
                 (Get (Target, Key).Kind /= Nil_Kind or else
                  Metafield (Owner.Universe.all, Target,
                    (if Is_Set then "__newindex" else "__index")).Kind =
                      Nil_Kind)
               then
                  --  A public API lookup on a suspended thread commonly
                  --  needs no callback. Preserve that thread's execution
                  --  stack and avoid inventing an allocating call frame for
                  --  a raw fast path whose handlers are absent.
                  if Is_Set then
                     Set (Owner.Universe.all, Target, Key, Item);
                  else
                     Item := Get (Target, Key);
                     Pin (Owner.Universe.all, Item);
                  end if;
                  Pop (Context, Needed);
                  if not Is_Set then
                     Push (Owner.Universe.all, Context, Item);
                  end if;
                  Leave_Context;
                  return Action_Done;
               end if;
               Pop (Context, Needed);
               --  Public C operations may call handlers, but cannot yield.
               --  Publish a real Ada continuation and its rooted operands;
               --  the ordinary C-owned lua_call pump drives @get/@set after
               --  this dispatcher has returned. Raw APIs use other cases.
               Push (Owner.Universe.all, Context,
                     New_Native (Owner.Universe.all,
                       (if Is_Set then "@set" else "@get")));
               Push (Owner.Universe.all, Context, Target);
               Push (Owner.Universe.all, Context, Key);
               if Is_Set then Push (Owner.Universe.all, Context, Item); end if;
               Output.Length := 1;
            end;
         when Prepare_Length =>
            declare
               Item : constant Value := Get_Value (Input.Index);
            begin
               if Item.Kind = String_Kind then
                  Push (Owner.Universe.all, Context,
                    (Integer_Kind,
                     Integer_Value (Length (Item.Reference.Bytes))));
               elsif Item.Kind = Table_Kind and then
                 Metafield (Owner.Universe.all, Item, "__len").Kind = Nil_Kind
               then
                  Push (Owner.Universe.all, Context,
                        (Integer_Kind, Integer_Value (Table_Length (Item))));
               else
                  --  Use the existing iterative unary operation. The C
                  --  wrapper enters its ordinary nonyieldable call portal
                  --  only after this Ada dispatcher has returned.
                  Pin (Owner.Universe.all, Item);
                  Push (Owner.Universe.all, Context,
                        New_Native (Owner.Universe.all, "@length"));
                  Push (Owner.Universe.all, Context, Item);
                  Output.Length := 1;
               end if;
            end;
         when Prepare_Arithmetic | Prepare_Comparison =>
            declare
               Is_Comparison : constant Boolean :=
                 Input.Operation = Prepare_Comparison;
               Kind : C_Operators.Operation;
               Left, Right, Result : Value;
               Needed : Natural := 0;
            begin
               if Is_Comparison then
                  if Input.Error_Index not in 0 .. 2 then
                     raise Foreign_Error with "invalid comparison operation";
                  elsif not Valid_Index (Context, Input.Index) or else
                    not Valid_Index (Context, Input.Count)
                  then
                     --  Absent acceptable indices compare false, even when
                     --  both otherwise map to the facade's nil sentinel.
                     Leave_Context;
                     return Action_Done;
                  end if;
                  Kind := C_Operators.Operation'Val
                    (C_Operators.Operation'Pos (C_Operators.Equal) +
                     Input.Error_Index);
                  Left := Get_Value (Input.Index);
                  Right := Get_Value (Input.Count);
               else
                  if Input.Index not in 0 .. 13 then
                     raise Foreign_Error with "invalid arithmetic operation";
                  end if;
                  Kind := C_Operators.Operation'Val (Input.Index);
                  Needed := (if C_Operators.Unary (Kind) then 1 else 2);
                  if Context.Foreign_Top - Context.Foreign_Base < Needed then
                     raise Foreign_Error with "not enough arithmetic operands";
                  end if;
                  Left := Get_Value (-C.int (Needed));
                  Right := Get_Value (-1);
               end if;
               if C_Operators.Primitive (Kind, Left, Right) then
                  Result :=
                    (if C_Operators.Unary (Kind) then VM.Unary_Value
                       (Owner.Universe.all, C_Operators.Token (Kind), Left)
                     else VM.Binary_Value
                       (Owner.Universe.all, C_Operators.Token (Kind),
                        Left, Right));
                  if Is_Comparison then
                     Output.Integer_Data := Boolean'Pos (Truth (Result));
                  else
                     Stacks.Write
                       (Owner.Universe.all, Context,
                        Context.Foreign_Top - Needed + 1, Result);
                     Pop (Context, Needed - 1);
                  end if;
               else
                  if not Is_Comparison and then C_Operators.Unary (Kind)
                  then
                     --  lua_arith exposes its fake second unary operand
                     --  as the same caller's next actual C temporary slot.
                     Push (Owner.Universe.all, Context, Left);
                  end if;
                  --  Keep originals in their actual C slots. The helper and
                  --  copied operands start above that top, preserving the
                  --  caller window and real debug.setlocal writes through MM.
                  Push (Owner.Universe.all, Context, New_Native
                    (Owner.Universe.all, C_Operators.Helper_Name (Kind)));
                  Push (Owner.Universe.all, Context, Left);
                  Push (Owner.Universe.all, Context, Right);
                  Output.Length := 1;
               end if;
            end;
         when Prepare_Concatenation =>
            if Input.Count < 0 or else
              Input.Count > C.int
                (Context.Foreign_Top - Context.Foreign_Base)
            then
               raise Foreign_Error with "invalid concatenation operand count";
            elsif Input.Count = 0 then
               Push (Owner.Universe.all, Context,
                     New_String (Owner.Universe.all, ""));
            elsif Input.Count > 1 then
               declare
                  Arguments : Values.Vector := Owned_Values
                    (Owner.Universe.all);
               begin
                  --  Root every operand before retiring its public stack
                  --  edge. The hidden continuation folds from the right via
                  --  the same binary operation used by canonical code;
                  --  arbitrary Lua/C handlers never run in this activation.
                  for Index in reverse 1 .. Natural (Input.Count) loop
                     Append_Root (Owner.Universe.all, Arguments,
                                  Get_Value (-C.int (Index)));
                  end loop;
                  Pin (Owner.Universe.all, Arguments);
                  Pop (Context, Natural (Input.Count));
                  Push (Owner.Universe.all, Context,
                        New_Native (Owner.Universe.all, "@api.concat"));
                  for Item of Arguments loop
                     Push (Owner.Universe.all, Context, Item);
                  end loop;
                  Output.Length := 1;
               end;
            end if;
         when Number_To_C_String =>
            declare
               Item : constant Value := Get_Value (Input.Index);
            begin
               if Item.Kind in Integer_Kind | Real_Kind then
                  if Input.Pointer = System.Null_Address then
                     raise Foreign_Error with "null number output buffer";
                  end if;
                  declare
                     Text : constant String :=
                       Image (Context.Memory, Item) & Character'Val (0);
                     Bytes : String (1 .. Text'Length)
                       with Import, Address => Input.Pointer;
                  begin
                     --  The public caller supplies LUA_N2SBUFFSZ. Numeric
                     --  rendering has constant scalar workspace, changes
                     --  no value/stack slot and makes no provider request.
                     Bytes := Text;
                     Output.Length := C.size_t (Text'Length);
                  end;
               end if;
            end;
         when Mark_Close =>
            declare
               Frame : Frame_Access := Context.Foreign_Activation;
               Slot : constant Natural := Position (Context, Input.Index);
               Item : constant Value := Get_Value (Input.Index);
            begin
               if not Valid_Index
                 (Context, Input.Index) or else Slot <= Context.Foreign_Base
               then
                  raise Foreign_Error with "invalid to-be-closed C slot";
               elsif Frame /= null and then Slot <= Frame.C_Closing_Level
               then
                  raise Foreign_Error with "C close slots are out of order";
               end if;
               if Truth (Item) then
                  if Metafield
                    (Owner.Universe.all, Item, "__close").Kind = Nil_Kind
                  then
                     raise Foreign_Error with
                       "variable '(C temporary)' got a non-closable value";
                  end if;
                  Ensure_Base_C_Frame (Owner.Universe.all, Context);
                  Frame := Context.Foreign_Activation;
                  Context.C_Close_Links.Replace_Element
                    (Slot, (Previous => Frame.C_Closing_Level));
                  Frame.C_Closing_Level := Slot;
               end if;
            end;
         when Close_Slot =>
            declare
               Frame : constant Frame_Access := Context.Foreign_Activation;
               Slot : constant Natural := Position (Context, Input.Index);
            begin
               if Frame = null or else not Valid_Index
                 (Context, Input.Index) or else Slot <= Context.Foreign_Base
               then
                  raise Foreign_Error with "invalid C close slot";
               elsif Input.Count = 0 then
                  if Frame.C_Closing_Level /= Slot
                  then
                     raise Foreign_Error with "C slot is not marked to close";
                  end if;
                  Prepare_C_Slots (Frame, Slot - 1);
               else
                  --  The handler has returned through its C-owned pump.
                  --  Detach the stable closing cell before reusing the slot,
                  --  preserving any independently retained closed capture.
                  Stacks.Detach (Context, Slot, Slot);
                  Stacks.Write (Owner.Universe.all, Context, Slot, Nil_Value);
               end if;
            end;
         when Begin_Resume =>
            declare
               Fresh : constant Boolean := Context.Status = New_Context or
                 (Context.Status = Dead_Context and then
                  not Context.Has_Failure_Value and then
                  Context.Stack.Is_Empty);
               Arguments : Values.Vector :=
                 Owned_Values (Owner.Universe.all);
               Callee : Value;
               Slot : Natural := 0;
               Address : System.Address := System.Null_Address;
               New_Driver : VM.Driver_Access;
               Next : Calls.Object_Pointer;
               Result : Action_Status;
               Start_Error : Boolean := False;
               From_Depth : Natural := 0;
            begin
               --  Resume failures are results of lua_resume, not errors in
               --  the C caller. Keep the original suspended/dead state and
               --  publish one genuine error object on its public stack.
               if Input.Index < 0 or else Natural (Input.Index) >
                 Context.Foreign_Top - Context.Foreign_Base
               then
                  Error_Result ("not enough elements in the stack");
                  Output.Integer_Data := 2;
                  Output.Length := 1;
                  Leave_Context;
                  return Action_Done;
               elsif (not Fresh and then
                      Context.Status /= Suspended_Context) or else
                 (Fresh and then not Context.Stack.Is_Empty)
               then
                  Pop (Context, Natural (Input.Index));
                  Error_Result
                    ((if Context.Status = Dead_Context then
                        "cannot resume dead coroutine" else
                        "cannot resume non-suspended coroutine"));
                  Output.Integer_Data := 2;
                  Output.Length := 1;
                  Leave_Context;
                  return Action_Done;
               end if;
               if Input.Pointer /= System.Null_Address then
                  --  'from' supplies the actual C-call depth only. Native
                  --  Lua also accepts an independently owned source state;
                  --  no value, registry or resumer relationship is shared.
                  From_Depth := Controls.To_Pointer
                    (Surfaces.To_Pointer (Input.Pointer).Owner).
                      Universe.Native_Depth;
               end if;
               if Context.Native_Depth >=
                 Lua.Runtime_Configuration.Maximum_C_Calls or else
                 From_Depth >=
                   Lua.Runtime_Configuration.Maximum_C_Calls -
                     Context.Native_Depth
               then
                  Pop (Context, Natural (Input.Index));
                  Error_Result ("C stack overflow");
                  Output.Integer_Data := 2;
                  Output.Length := 1;
                  Leave_Context;
                  return Action_Done;
               end if;
               for Index in Context.Foreign_Top - Natural (Input.Index) + 1
                 .. Context.Foreign_Top
               loop
                  Append_Root (Owner.Universe.all, Arguments,
                               Stacks.Read (Context, Index));
               end loop;
               if Fresh then
                  if Context.Entry_Function.Kind /= Nil_Kind then
                     Callee := Context.Entry_Function;
                     Slot := 1;
                  elsif Natural (Input.Index) <
                    Context.Foreign_Top - Context.Foreign_Base
                  then
                     Slot := Context.Foreign_Top - Natural (Input.Index);
                     Callee := Stacks.Read (Context, Slot);
                  else
                     Pop (Context, Natural (Input.Index));
                     Error_Result ("cannot resume dead coroutine");
                     Output.Integer_Data := 2;
                     Output.Length := 1;
                     Leave_Context;
                     return Action_Done;
                  end if;
                  Pin (Owner.Universe.all, Callee);
                  Context.Resume_Return_Base := Context.Foreign_Base;
                  Context.Resume_Return_Top := Slot - 1;
               end if;
               Pin (Owner.Universe.all, Arguments);
               --  Allocate both scalar owners before changing the active
               --  driver. Refusal leaves the caller's real execution intact.
               Context.Boundary_Results.Reserve_Capacity (2);
               New_Driver := VM.New_Driver (Owner.Universe.all);
               begin
                  Address := Memory.Allocate
                    (Owner.Universe.Memory,
                     Call_Record'Object_Size / System.Storage_Unit,
                     Call_Record'Alignment);
               exception
                  when others =>
                     VM.Free_Driver (New_Driver);
                     raise;
               end;
               Next := Calls.To_Pointer (Address);
               Next.all :=
                 (Is_Root => True, Is_Resume => True, Wanted => -1,
                  Context => Owner.Context,
                  Saved_Driver => Main_Owner.Driver,
                  Saved_Owned_Driver => Main_Owner.Owned_Driver,
                  Saved_Calls => Main_Owner.Calls,
                  Saved_Borrowed => Main_Owner.Driver_Borrowed,
                  Saved_Context => Previous,
                  Saved_Native_Depth => Owner.Universe.Native_Depth,
                  others => <>);
               Main_Owner.Driver := Driver_View (New_Driver);
               Main_Owner.Owned_Driver := New_Driver;
               Main_Owner.Driver_Borrowed := False;
               Main_Owner.Calls := Address;
               if not Fresh and then Context.Detached_Resume_Window then
                  Context.Foreign_Activation :=
                    Context.Resume_Foreign_Activation;
                  Context.Foreign_Base := Context.Resume_Foreign_Base;
                  Context.Foreign_Top := Context.Resume_Foreign_Top;
                  Context.Stack_Used := Context.Resume_Stack_Used;
                  Context.Host_Stack_Top := Context.Resume_Host_Stack_Top;
                  Context.Resume_Foreign_Activation := null;
                  Context.Detached_Resume_Window := False;
               else
                  Context.Host_Stack_Top := Context.Resume_Return_Top;
               end if;
               Owner.Universe.Native_Depth :=
                 From_Depth + Context.Native_Depth;
               begin
                  VM.Start_Resume
                    (Main_Owner.Driver.all, Owner.Universe.all,
                     Callee, Arguments, Fresh, Slot);
               exception
                  when Language_Error => Start_Error := True;
                  when Memory.Allocation_Error =>
                     Record_Memory_Error (Owner.Universe.all);
                     Start_Error := True;
                  when Program_Error =>
                     if Memory.Refusal_Pending (Owner.Universe.Memory) then
                        Record_Memory_Error (Owner.Universe.all);
                        Start_Error := True;
                     else
                        raise;
                     end if;
               end;
               Result := Pump (Start_Error);
               Leave_Context;
               return Result;
            end;
         when Yield_Call =>
            declare
               Frame : constant Frame_Access := Context.Foreign_Activation;
            begin
               if Frame = null or else Input.Count < 0 or else
                 Natural (Input.Count) >
                   Context.Foreign_Top - Context.Foreign_Base or else
                 Context.Non_Yieldable /= 0 or else
                 (Context.Resumer = null and then not Context.C_Resuming)
               then
                  raise Foreign_Error with
                    (if Context = Owner.Universe.Main_Context and then
                        not Context.C_Resuming then
                       "attempt to yield from outside a coroutine" else
                       "attempt to yield across a C-call boundary");
               end if;
               if Context.Hook_Active and then
                 (Context.Hook_Transfer or else Input.Count /= 0 or else
                  Input.Continuation /= null)
               then
                  raise Foreign_Error with "invalid yield from a hook";
               end if;
               Frame.Foreign_Continuation :=
                 Continuation_Address (Input.Continuation);
               Frame.Foreign_KContext := Input.KContext;
               Frame.Foreign_Yield_Count := Natural (Input.Count);
               Context.Transfer.Kind := Yielded;
               Context.Transfer.Results.Clear;
               for Index in Context.Foreign_Top - Natural (Input.Count) + 1
                 .. Context.Foreign_Top
               loop
                  Append_Root
                    (Owner.Universe.all, Context.Transfer.Results,
                     Stacks.Read (Context, Index));
               end loop;
               if Context.Hook_Active then
                  Frame.Foreign_Suspended := True;
               else
                  Frame.Native_Stage := 5;
                  Leave_Context;
                  return Action_Suspend;
               end if;
            end;
         when Create_State | Create_Default_State => null;
         when Close_State =>
            declare
               Universe : World_Access := Main_Owner.Owned_Universe;
            begin
               if not Main_Owner.Owns_Universe then
                  raise Foreign_Error with "cannot close an Ada-owned state";
               elsif Main_Owner.Calls /= System.Null_Address or else
                 Main_Owner.Driver_Borrowed
               then
                  raise Foreign_Error with "cannot close a running C drive";
               end if;
               VM.Free_Driver (Main_Owner.Owned_Driver);
               Main_Owner.Driver := null;
               End_Operation (Active_World.all);
               Operation_Active := False;
               Active_World := null;
               --  Closing an idle C state borrows the same iterative close
               --  driver as an Ada session. Invoke_Borrowed installs its C
               --  guard above the waiting host boundary; no internal step
               --  survives a callback and no C jump crosses these frames.
               --  Failure to allocate optional close/finalizer storage must
               --  still release the actual universe and allocator blocks.
               begin
                  VM.Close_Lua_State (Universe.all);
               exception
                  when Language_Error | Memory.Allocation_Error |
                    Storage_Error => null;
                  when Program_Error =>
                     if not Memory.Refusal_Pending (Universe.Memory) then
                        raise;
                     end if;
               end;
               Finalize (Universe.all);
               Free_World (Universe);
            end;
         when Create_Thread =>
            declare
               Item : constant Value := New_Thread
                 (Owner.Universe.all, Nil_Value, Parent => Context);
            begin
               --  The parent stack roots the new thread before a caller can
               --  collect. Its C surface is borrowed, not a permanent root.
               Push (Owner.Universe.all, Context, Item);
               Output.Pointer := Create_Surface
                 (Owner.Universe, Context_Id (Item.Reference.Context_Index),
                  Owner.Extra, Owner.Seed,
                  Surfaces.To_Pointer (State).Main);
            end;
         when Set_Warning_Function =>
            Owner.Universe.Warning_Mode :=
              (if Input.Warning_Function = null then No_Warning_Handler
               else Custom_Warning_Handler);
            Owner.Universe.Warning_Handler :=
              Warning_Address (Input.Warning_Function);
            Owner.Universe.Warning_Data := Input.Pointer;
         when Issue_Warning =>
            if Owner.Universe.Warning_Mode = Custom_Warning_Handler then
               --  The caller's C string already outlives this synchronous
               --  wrapper invocation. Snapshot scalar callback data; no Lua
               --  string, event allocation or Ada activation spans the call.
               Output.Warning_Function :=
                 Address_Warning (Owner.Universe.Warning_Handler);
               Output.Warning_Data := Owner.Universe.Warning_Data;
               Output.Warning_Message := Input.Pointer;
               Output.Warning_Continuation := Input.Count;
               Leave_Context;
               return Action_Warning;
            else
               Warnings.Emit
                 (Owner.Universe.all,
                  Byte_String'(Input.Pointer, Natural (Input.Length)),
                  To_Continue => Input.Count /= 0);
            end if;
         when Complete_Warning =>
            declare
               Event : constant Frame_Access := Owner.Universe.Warning_Head;
               Result : Action_Status;
            begin
               if Input.Index not in 0 | 2 | 4 | 5 or else
                 Event = null or else
                 Event.Warning_Phase /= Warning_Callback_Active or else
                 Event.all'Address /= Input.Callback_Token.Activation or else
                 Event.Warning_Ticket /= Input.Callback_Token.Serial
               then
                  raise Foreign_Error with "invalid warning completion";
               end if;
               if Input.Index /= 0 then
                  Context.Failure :=
                    Stacks.Read (Context, Context.Foreign_Top);
                  Root_Barrier (Owner.Universe.all, Context.Failure);
                  Context.Has_Failure_Value := True;
                  Context.Failure_Text := To_Unbounded_String
                    (Image (Context.Memory, Context.Failure));
                  Context.Failure_Class :=
                    (if Input.Index = 4 then Memory_Failure
                     elsif Input.Index = 5 then Handling_Failure
                     else Language_Failure);
                  Context.Failure_Handled := Input.Error_Handled /= 0;
                  Event.Warning_Failed := True;
               end if;
               Warnings.Acknowledge
                 (Owner.Universe.all, Input.Callback_Token);
               Result := Pump;
               Leave_Context;
               return Result;
            end;
         when Collector_Control =>
            declare
               Drain : Boolean;
            begin
               Output.Integer_Data := C.long_long (Garbage_Collection.Control
                 (Owner.Universe.all, Input.Index,
                  Step_Bytes => (if Input.Length <=
                    C.size_t (Memory.Byte_Count'Last)
                    then Memory.Byte_Count (Input.Length) else 0),
                  Parameter => Input.Count, Setting => Input.Error_Index,
                  Drain => Drain));
               Output.Length := Boolean'Pos (Drain);
            end;
         when Push_Collector_Drain =>
            --  The C-owned protected pump performs this optional allocation
            --  only after the control operation has returned. A refusal
            --  leaves queued finalizers intact for a later opportunity.
            Push (Owner.Universe.all, Context,
                  New_Native (Owner.Universe.all, "@gc.finalize"));
         when Open_IO_Module =>
            Push (Owner.Universe.all, Context,
                  IO_Libraries.Open_Module (Owner.Universe.all));
            Output.Integer_Data := 1;
         when Open_OS_Module =>
            Push (Owner.Universe.all, Context,
                  Operating_System.Open_Module (Owner.Universe.all));
            Output.Integer_Data := 1;
         when Open_Standard_Module =>
            if Input.Index not in 0 ..
              Library_Openers.Module_Kind'Pos
                (Library_Openers.Module_Kind'Last)
            then
               raise Foreign_Error with "invalid standard library selector";
            end if;
            Push (Owner.Universe.all, Context,
                  Library_Openers.Open_Module
                    (Owner.Universe.all,
                     Library_Openers.Module_Kind'Val (Input.Index)));
            Output.Integer_Data := 1;
         when Get_Yieldability =>
            --  A new secondary thread is yieldable even outside execution.
            --  Abandoned barriers on a dead thread cannot describe a current
            --  C call; main-thread/closing restrictions remain explicit.
            Output.Integer_Data := Boolean'Pos
              ((Context /= Owner.Universe.Main_Context or else
                Context.C_Resuming) and then
               Context.Phase /= Closing and then
               (Context.Status = Dead_Context or else
                Context.Non_Yieldable = 0));
         when Get_Top =>
            Output.Integer_Data := C.long_long
              (Context.Foreign_Top - Context.Foreign_Base);
         when Absolute_Index =>
            Output.Integer_Data :=
              (if Input.Index > 0 or Input.Index <= Registry_Index then
                  C.long_long (Input.Index)
               else C.long_long
                 (Context.Foreign_Top -
                  Context.Foreign_Base) +
                 C.long_long (Input.Index) + 1);
         when Set_Top =>
            declare
               Count : constant Integer_Value :=
                 (if Input.Index >= 0 then Integer_Value
                    (Context.Foreign_Base) + Integer_Value (Input.Index)
                  else Integer_Value (Context.Foreign_Top) +
                    Integer_Value (Input.Index) + 1);
            begin
               if Count < Integer_Value (Context.Foreign_Base) or else
                 Count >= Integer_Value (Context.Stack_Allocated_Bound)
               then
                  raise Foreign_Error with "invalid stack top";
               end if;
               if Context.Foreign_Activation /= null and then
                 Context.Foreign_Activation.C_Closing_Level > Natural (Count)
               then
                  Prepare_C_Slots
                    (Context.Foreign_Activation, Natural (Count));
               else
                  Set_C_Top (Owner.Universe.all, Context, Natural (Count));
               end if;
            end;
         when Check_Stack =>
            if Input.Count >= 0 then
               begin
                  declare
                     Last : constant Natural :=
                       (if Natural (Input.Count) >
                          Natural'Last - Context.Foreign_Top
                        then Natural'Last else
                          Context.Foreign_Top + Natural (Input.Count));
                     Available : constant Boolean := VM.Ensure_Stack
                       (Owner.Universe.all, Context, Last,
                        Raise_Error => False);
                  begin
                     if not Available then
                        null;
                     elsif Context.Foreign_Activation /= null then
                        VM.Resize_Stack_Window
                          (Owner.Universe.all, Context.Foreign_Activation,
                           Natural'Max
                             (Context.Foreign_Activation.Stack_Window_Length,
                              Last - Context.Foreign_Base));
                     else
                        Stacks.Reserve (Owner.Universe.all, Context, Last);
                        Context.Stack_Used :=
                          Natural'Max (Context.Stack_Used, Last);
                     end if;
                     Output.Integer_Data := Boolean'Pos (Available);
                  end;
               exception
                  when Memory.Allocation_Error =>
                     Memory.Acknowledge_Refusal (Owner.Universe.Memory);
                  when Program_Error | Storage_Error =>
                     if Memory.Refusal_Pending (Owner.Universe.Memory) then
                        Memory.Acknowledge_Refusal (Owner.Universe.Memory);
                     else
                        raise;
                     end if;
               end;
            end if;
         when Push_Value =>
            Push (Owner.Universe.all, Context, Get_Value (Input.Index));
         when Copy_Value =>
            declare
               Slot : constant Natural := Position (Context, Input.Count);
            begin
               if Input.Count < Registry_Index and then
                 Valid_Index (Context, Input.Count)
               then
                  Store_Cell
                    (Owner.Universe.all,
                     Context.Foreign_Activation.Native_Self.Captures
                       (Positive (C.long_long (Registry_Index) -
                         C.long_long (Input.Count))),
                     Get_Value (Input.Index));
               elsif Slot = 0 then
                  raise Foreign_Error with "invalid C stack destination";
               else
                  Stacks.Write (Owner.Universe.all, Context,
                                Slot, Get_Value (Input.Index));
               end if;
            end;
         when Rotate_Values =>
            declare
               First : constant Natural := Position (Context, Input.Index);
               Last : constant Natural :=
                 Context.Foreign_Top;
               procedure Reverse_Range (Left, Right : Natural);
               procedure Reverse_Range (Left, Right : Natural) is
                  Low : Natural := Left;
                  High : Natural := Right;
               begin
                  while Low < High loop
                     declare
                        Saved : constant Value := Stacks.Read (Context, Low);
                     begin
                        Stacks.Write (Owner.Universe.all, Context, Low,
                                      Stacks.Read (Context, High));
                        Stacks.Write
                          (Owner.Universe.all, Context, High, Saved);
                     end;
                     Low := Low + 1;
                     High := High - 1;
                  end loop;
               end Reverse_Range;
            begin
               if First = 0 then
                  raise Foreign_Error with "invalid C stack rotation";
               end if;
               declare
                  Width : constant Natural := Last - First + 1;
                  Shift : constant Natural := Natural
                    (Integer_Value (Input.Count) mod Integer_Value (Width));
               begin
                  --  Three reversals rotate in place without a temporary
                  --  stack vector or per-call input-sized host allocation.
                  if Shift /= 0 then
                     Reverse_Range (First, Last - Shift);
                     Reverse_Range (Last - Shift + 1, Last);
                     Reverse_Range (First, Last);
                  end if;
               end;
            end;
         when Move_Values =>
            declare
               Target_Owner : constant Controls.Object_Pointer :=
                 Controls.To_Pointer
                   (Surfaces.To_Pointer (Input.Pointer).Owner);
               Target : constant Context_Access := Context_Of (Target_Owner);
               Count : constant C.int := Input.Count;
            begin
               if Target_Owner.Universe /= Owner.Universe or else Count < 0
                 or else Integer_Value (Count) >
                   Integer_Value (Context.Foreign_Top) -
                     Integer_Value (Context.Foreign_Base)
               then
                  raise Foreign_Error with "invalid cross-state move";
               end if;
               if Target /= Context and Count > 0 then
                  for Index in Context.Foreign_Top -
                    Natural (Count) + 1 .. Context.Foreign_Top
                  loop
                     Push (Owner.Universe.all, Target,
                           Stacks.Read (Context, Index));
                  end loop;
                  Pop (Context, Natural (Count));
               end if;
            end;
         when Get_Type =>
            Output.Integer_Data :=
              (if not Valid_Index (Context, Input.Index) then -1
               else C.long_long (Type_Code (Get_Value (Input.Index))));
            Output.Length := Boolean'Pos
              (Get_Value (Input.Index).Kind = Integer_Kind);
         when To_Boolean =>
            Output.Integer_Data := Boolean'Pos
              (Truth (Get_Value (Input.Index)));
         when To_Integer | To_Number =>
            declare
               Number : constant Lua.Numbers.Number :=
                 Numeric (Owner.Universe.all, Get_Value (Input.Index));
            begin
               case Number.Kind is
                  when Lua.Numbers.Invalid => null;
                  when Lua.Numbers.Integer_Number =>
                     Output.Integer_Data := C.long_long
                       (Number.Integer_Item);
                     Output.Number_Data := C.double (Number.Integer_Item);
                     Output.Length := 1;
                  when Lua.Numbers.Real_Number =>
                     Output.Number_Data := C.double (Number.Real_Item);
                     if Input.Operation = To_Number then
                        Output.Length := 1;
                     elsif Number.Real_Item >= -2.0 ** 63 and then
                       Number.Real_Item < 2.0 ** 63 and then
                       Real_Value'Truncation (Number.Real_Item) =
                         Number.Real_Item
                     then
                        Output.Integer_Data := C.long_long
                          (Number.Real_Item);
                        Output.Length := 1;
                     end if;
               end case;
            end;
         when String_To_Number =>
            if Input.Pointer = System.Null_Address or else
              Input.Length >= C.size_t (Natural'Last)
            then
               raise Foreign_Error with "invalid numeric string extent";
            end if;
            declare
               --  The C boundary already supplies strlen. Borrow that exact
               --  terminated extent instead of returning an input-sized Ada
               --  String copy from Read_Bytes. Fixed exact scratch preserves
               --  native conversion when the Lua allocator refuses growth.
               Text : constant String (1 .. Natural (Input.Length))
                 with Import, Address => Input.Pointer;
               Number : constant Lua.Numbers.Number :=
                 Read_Number (Owner.Universe.all, Text);
            begin
               case Number.Kind is
                  when Lua.Numbers.Invalid => null;
                  when Lua.Numbers.Integer_Number =>
                     Push (Owner.Universe.all, Context,
                           (Integer_Kind, Number.Integer_Item));
                     Output.Length := Input.Length + 1;
                  when Lua.Numbers.Real_Number =>
                     Push (Owner.Universe.all, Context,
                           (Real_Kind, Number.Real_Item));
                     Output.Length := Input.Length + 1;
               end case;
            end;
         when To_String =>
            declare
               Item : Value := Get_Value (Input.Index);
               Slot : constant Natural := Position (Context, Input.Index);
            begin
               if Item.Kind in Integer_Kind | Real_Kind and then
                 Valid_Index (Context, Input.Index)
               then
                  Item := New_String
                    (Owner.Universe.all, Image (Context.Memory, Item));
                  if Slot > 0 then
                     Stacks.Write (Owner.Universe.all, Context, Slot, Item);
                  else
                     Store_Cell
                       (Owner.Universe.all,
                        Context.Foreign_Activation.Native_Self.Captures
                          (Positive (C.long_long (Registry_Index) -
                            C.long_long (Input.Index))), Item);
                  end if;
               end if;
               if Item.Kind = String_Kind then
                  Output.Pointer := Item.Reference.C_Bytes;
                  Output.Length := C.size_t (Length (Item.Reference.Bytes));
               end if;
            end;
         when Raw_Length =>
            declare
               Item : constant Value := Get_Value (Input.Index);
            begin
               if Item.Kind = String_Kind then
                  Output.Integer_Data := C.long_long
                    (Length (Item.Reference.Bytes));
               elsif Item.Kind = Table_Kind then
                  Output.Integer_Data := C.long_long (Table_Length (Item));
               elsif Item.Kind = Userdata_Kind then
                  Output.Integer_Data := C.long_long
                    (Item.Reference.Userdata_Size);
               end if;
            end;
         when To_Pointer | To_Thread =>
            declare
               Item : constant Value := Get_Value (Input.Index);
            begin
               if Item.Kind = Thread_Kind then
                  Output.Pointer := Owner.Universe.Contexts
                    (Item.Reference.Context_Index).Foreign_State;
                  if Output.Pointer = System.Null_Address then
                     raise Program_Error with "unprepared C thread query";
                  end if;
               elsif Input.Operation = To_Pointer then
                  case Item.Kind is
                     when Light_Identity_Kind | Foreign_Function_Kind =>
                        Output.Pointer := Item.Identity;
                     when Native_Kind_Value =>
                        Output.Pointer := Lua.Builtin_Registry.Handler_Address
                          (Item.Native_Data);
                     when Userdata_Kind =>
                        Output.Pointer := Userdata_Address (Item);
                     when String_Kind | Table_Kind | Closure_Kind |
                       Native_Closure_Kind =>
                        Output.Pointer := Item.Reference.all'Address;
                     when others => null;
                  end case;
               end if;
            end;
         when Push_Nil => Push (Owner.Universe.all, Context, Nil_Value);
         when Push_Boolean =>
            Push (Owner.Universe.all, Context, (Kind => Boolean_Kind,
                            Boolean_Data => Input.Count /= 0));
         when Push_Integer =>
            Push (Owner.Universe.all, Context, (Kind => Integer_Kind,
                            Integer_Data => Integer_Value
                              (Input.Integer_Data)));
         when Push_Number =>
            Push (Owner.Universe.all, Context, (Kind => Real_Kind,
                            Real_Data => Real_Value (Input.Number_Data)));
         when Push_String =>
            declare
               Item : constant Value := New_String
                 (Owner.Universe.all,
                  Read_Bytes (Input.Pointer, Input.Length));
            begin
               Push (Owner.Universe.all, Context, Item);
               Output.Pointer := Item.Reference.C_Bytes;
            end;
         when Push_External_String =>
            if Input.Pointer = System.Null_Address or else
              Input.Length >= C.size_t (Natural'Last)
            then
               raise Foreign_Error with "invalid external string extent";
            end if;
            declare
               Item : constant Value := New_External_String
                 (Owner.Universe.all, Input.Pointer, Natural (Input.Length),
                  Input.Allocator, Input.Warning_Data);
            begin
               Output.Integer_Data := 1;
               Push (Owner.Universe.all, Context, Item);
               Output.Pointer := Item.Reference.C_Bytes;
            end;
         when Push_Pointer =>
            Push (Owner.Universe.all, Context, (Kind => Light_Identity_Kind,
                            Identity => Input.Pointer));
         when Push_Thread =>
            Push (Owner.Universe.all, Context,
                  (Kind => Thread_Kind, Reference => Context.Thread));
            Output.Integer_Data := Boolean'Pos
              (Context = Owner.Universe.Main_Context);
         when Create_Table =>
            Push (Owner.Universe.all, Context, New_Table (Owner.Universe.all));
         when Create_Userdata =>
            if Input.Count < 0 or else
              Input.Count >= C.int (C.short'Last)
            then
               raise Foreign_Error with "invalid userdata uservalue count";
            elsif Input.Length > C.size_t (Memory.Byte_Count'Last) then
               raise Memory.Allocation_Error with "userdata block too large";
            end if;
            declare
               Item : constant Value := New_Userdata
                 (Owner.Universe.all, Memory.Byte_Count (Input.Length),
                  Natural (Input.Count));
            begin
               Push (Owner.Universe.all, Context, Item);
               Output.Pointer := Userdata_Address (Item);
            end;
         when Get_Uservalue | Set_Uservalue =>
            declare
               Item : constant Value := Get_Value (Input.Index);
               Valid : Boolean;
            begin
               if Item.Kind /= Userdata_Kind then
                  raise Foreign_Error with "full userdata expected";
               end if;
               Valid := Input.Count > 0 and then
                 C.long_long (Input.Count) <=
                   C.long_long (Item.Reference.Uservalues.Length);
               if Input.Operation = Get_Uservalue then
                  declare
                     Uservalue : constant Value :=
                       (if Valid then Item.Reference.Uservalues
                          (Positive (Input.Count)) else Nil_Value);
                  begin
                     Pin (Owner.Universe.all, Uservalue);
                     Push (Owner.Universe.all, Context, Uservalue);
                     Output.Integer_Data :=
                       (if Valid then C.long_long (Type_Code (Uservalue))
                        else -1);
                  end;
               else
                  if Context.Foreign_Top <=
                    Context.Foreign_Base
                  then
                     raise Foreign_Error with "missing uservalue";
                  end if;
                  --  Publish the traced edge before popping its source. Even
                  --  an invalid uservalue index consumes the supplied value.
                  if Valid then
                     Item.Reference.Uservalues.Replace_Element
                       (Positive (Input.Count),
                        Stacks.Read (Context, Context.Foreign_Top));
                     --  Uservalues are revisited like table entries. Their
                     --  generational mutation uses the owner's backward
                     --  barrier, rather than promoting the child as a cell.
                     Back_Barrier (Owner.Universe.all, Item.Reference);
                  end if;
                  Pop (Context);
                  Output.Integer_Data := Boolean'Pos (Valid);
               end if;
            end;
         when Get_Metatable =>
            declare
               Meta : constant Object_Access := Raw_Metatable
                 (Owner.Universe.all, Get_Value (Input.Index));
            begin
               if Meta /= null then
                  Push (Owner.Universe.all, Context, (Table_Kind, Meta));
                  Output.Integer_Data := 1;
               end if;
            end;
         when Set_Metatable =>
            declare
               Item : constant Value := Get_Value (Input.Index);
               Meta : Value;
            begin
               if Context.Foreign_Top <=
                 Context.Foreign_Base
               then
                  raise Foreign_Error with "missing metatable";
               end if;
               Meta := Stacks.Read (Context, Context.Foreign_Top);
               if Meta.Kind not in Nil_Kind | Table_Kind then
                  raise Foreign_Error with "table expected";
               end if;
               Set_Metatable (Owner.Universe.all, Item,
                 (if Meta.Kind = Nil_Kind then null else Meta.Reference));
               Pop (Context);
               Output.Integer_Data := 1;
            end;
         when Raw_Get =>
            declare
               Table : constant Value := Require_Table;
               Key : constant Value :=
                 Stacks.Read (Context, Context.Foreign_Top);
               Item : constant Value := Get (Table, Key);
            begin
               Pin (Owner.Universe.all, Item);
               Pop (Context);
               Push (Owner.Universe.all, Context, Item);
               Output.Integer_Data := C.long_long (Type_Code (Item));
            end;
         when Raw_Set =>
            declare
               Table : constant Value := Require_Table;
               Last : constant Positive :=
                 Context.Foreign_Top;
               Item : constant Value := Stacks.Read (Context, Last);
               Key : constant Value := Stacks.Read (Context, Last - 1);
            begin
               --  Keep original operands on the traced C stack until all
               --  allocation/rehash work completes. Ada locals alone cannot
               --  protect an existing key/value across emergency collection.
               Set (Owner.Universe.all, Table, Key, Item);
               Pop (Context, 2);
            end;
         when Raw_Get_Integer =>
            Get_Raw ((Kind => Integer_Kind,
                      Integer_Data => Integer_Value (Input.Integer_Data)));
         when Raw_Set_Integer | Raw_Set_Pointer =>
            declare
               Table : constant Value := Require_Table;
               Item : constant Value :=
                 Stacks.Read (Context, Context.Foreign_Top);
               Key : constant Value :=
                 (if Input.Operation = Raw_Set_Integer then
                    (Kind => Integer_Kind, Integer_Data => Integer_Value
                       (Input.Integer_Data))
                  else (Kind => Light_Identity_Kind,
                        Identity => Input.Pointer));
            begin
               Set (Owner.Universe.all, Table, Key, Item);
               Pop (Context);
            end;
         when Raw_Get_Pointer =>
            Get_Raw ((Kind => Light_Identity_Kind,
                      Identity => Input.Pointer));
         when Raw_Equal =>
            Output.Integer_Data := Boolean'Pos
              (Valid_Index (Context, Input.Index) and then
               Valid_Index (Context, Input.Count) and then
               Equal (Get_Value (Input.Index), Get_Value (Input.Count)));
         when Next_Item =>
            declare
               Table : constant Value := Require_Table;
               Key : constant Value :=
                 Stacks.Read (Context, Context.Foreign_Top);
               Results : constant Values.Vector :=
                 Next (Owner.Universe.all, Table, Key);
            begin
               Pin (Owner.Universe.all, Results);
               Pop (Context);
               --  The Lua-facing primitive returns one nil at termination.
               --  C lua_next instead pops the exhausted key, pushes nothing,
               --  and returns zero; exposing that nil as a row corrupts the
               --  caller's next iteration. See pinned lapi.c:1273-1285.
               if not Results.Is_Empty and then
                 Results.First_Element.Kind /= Nil_Kind
               then
                  for Item of Results loop
                     Push (Owner.Universe.all, Context, Item);
                  end loop;
                  Output.Integer_Data := 1;
               end if;
            end;
         when Get_Allocator =>
            Output.Allocator := Memory.Allocator (Owner.Universe.Memory);
            Output.Pointer := Memory.Userdata (Owner.Universe.Memory);
         when Set_Allocator =>
            if Input.Allocator = null then
               raise Foreign_Error with "null allocator callback";
            end if;
            Memory.Set_Allocator
              (Owner.Universe.Memory, Input.Allocator, Input.Pointer);
         when Push_C_Closure =>
            if Input.Function_Data = null or else Input.Count not in 0 .. 255
              or else Input.Count > C.int
                (Context.Foreign_Top -
                 Context.Foreign_Base)
            then
               raise Foreign_Error with "invalid C closure arguments";
            end if;
            declare
               Builtin : constant Lua.Builtin_Registry.Lookup :=
                 Lua.Builtin_Registry.Find
                   (Function_Address (Input.Function_Data));
            begin
               if Input.Count = 0 and then Builtin.Exists then
                  Push (Owner.Universe.all, Context,
                        (Native_Kind_Value, Builtin.Id));
               elsif Input.Count = 0 then
                  Push (Owner.Universe.all, Context, (Foreign_Function_Kind,
                                  Function_Address (Input.Function_Data)));
               else
                  declare
                     Captures : Values.Vector :=
                       Owned_Values (Owner.Universe.all);
                     Item : Value;
                  begin
                     for Index in Context.Foreign_Top -
                       Natural (Input.Count) + 1 ..
                       Context.Foreign_Top
                     loop
                        Append_Root
                          (Owner.Universe.all, Captures,
                           Stacks.Read (Context, Index));
                     end loop;
                     Item := New_Native
                       (Owner.Universe.all,
                        (if Builtin.Exists then
                            Lua.Builtin_Registry.Name (Builtin.Id)
                         else "foreign.callback"), Captures);
                     if not Builtin.Exists then
                        Item.Reference.Foreign_Handler :=
                          Function_Address (Input.Function_Data);
                     end if;
                     Pop (Context, Natural (Input.Count));
                     Push (Owner.Universe.all, Context, Item);
                  end;
               end if;
            end;
         when To_C_Function =>
            declare
               Item : constant Value := Get_Value (Input.Index);
            begin
               if Item.Kind = Foreign_Function_Kind then
                  Output.Function_Data := Address_Function (Item.Identity);
               elsif Item.Kind = Native_Kind_Value then
                  Output.Function_Data := Address_Function
                    (Lua.Builtin_Registry.Handler_Address (Item.Native_Data));
               elsif Item.Kind = Native_Closure_Kind and then
                 Item.Reference.Foreign_Handler /= System.Null_Address
               then
                  Output.Function_Data :=
                    Address_Function (Item.Reference.Foreign_Handler);
               elsif Item.Kind = Native_Closure_Kind then
                  declare
                     Builtin : constant Lua.Builtin_Registry.Lookup :=
                       Lua.Builtin_Registry.Find
                         (To_String (Item.Reference.Native_Name));
                  begin
                     if Builtin.Exists then
                        Output.Function_Data := Address_Function
                          (Lua.Builtin_Registry.Handler_Address (Builtin.Id));
                     end if;
                  end;
               end if;
            end;
         when Close_IO_Primitive =>
            if Input.Count not in 0 .. 2 then
               raise Foreign_Error with "invalid native file close operation";
            end if;
            declare
               Kind : constant IO_Close_Kind :=
                 IO_Close_Kind'Val (Input.Count);
               Packet : constant Values.Vector :=
                 IO_Libraries.Close_Primitive
                   (Owner.Universe.all, Get_Value (1), Kind);
            begin
               --  Calling closef directly is not lua_call: it adds neither
               --  a visible debug activation nor another native-depth entry.
               --  The current file/C frame owns the receiver throughout; the
               --  The Ada library supplies the actual boolean, error, or
               --  execution-result values.
               Root_Barrier (Owner.Universe.all, Packet);
               for Item of Packet loop
                  Push (Owner.Universe.all, Context, Item);
               end loop;
               Output.Integer_Data := C.long_long (Packet.Length);
            end;
         when Begin_Call | Begin_Builtin =>
            if not Main_Owner.Owns_Universe and then
              not Main_Owner.Driver_Borrowed and then
              Main_Owner.Calls = System.Null_Address
            then
               raise Foreign_Error with
                 "host-owned state requires its active Ada execution";
            end if;
            if Input.Count < -1 or else Input.Count > C.int (Stack_Limit) or
              else Input.Index < 0 or else
              (if Input.Operation = Begin_Builtin then
                  Input.Index > Lua.Builtin_Registry.Kind'Pos
                    (Lua.Builtin_Registry.Kind'Last)
               else Natural (Input.Index) >=
                  Context.Foreign_Top - Context.Foreign_Base)
            then
               raise Foreign_Error with "invalid C call arguments";
            end if;
            declare
               Slot : constant Positive :=
                 (if Input.Operation = Begin_Builtin then
                     Context.Foreign_Top + 1 else
                     Context.Foreign_Top - Natural (Input.Index));
               Callee : constant Value :=
                 (if Input.Operation = Begin_Builtin then
                     (Native_Kind_Value,
                      Lua.Builtin_Registry.Kind'Val (Input.Index))
                  else Stacks.Read (Context, Slot));
               Message_Handler : Value;
               Arguments : Values.Vector :=
                 Owned_Values (Owner.Universe.all);
               Address : System.Address;
               Root_Call : constant Boolean :=
                 Main_Owner.Calls = System.Null_Address and then
                 not Main_Owner.Driver_Borrowed;
               Next : Calls.Object_Pointer;
               Result : Action_Status;
               Start_Error : Boolean := False;
            begin
               for Index in
                 (if Input.Operation = Begin_Builtin then
                     Context.Foreign_Base + 1 else Slot + 1) ..
                 Context.Foreign_Top
               loop
                  Append_Root
                    (Owner.Universe.all, Arguments,
                     Stacks.Read (Context, Index));
               end loop;
               if Input.Error_Index /= 0 then
                  if Input.Error_Index < 1 or else
                    not Valid_Index (Context, Input.Error_Index)
                  then
                     raise Foreign_Error with "invalid error handler index";
                  end if;
                  Message_Handler := Get_Value (Input.Error_Index);
                  if Message_Handler.Kind not in Closure_Kind |
                    Native_Closure_Kind | Native_Kind_Value |
                    Foreign_Function_Kind
                  then
                     raise Foreign_Error with
                       "error handler is not a function";
                  end if;
               elsif Input.Integer_Data = 0 and then not Root_Call then
                  Message_Handler :=
                    VM.Current_Message_Handler (Main_Owner.Driver.all);
               end if;
               Pin (Owner.Universe.all, Callee);
               Pin (Owner.Universe.all, Arguments);
               Pin (Owner.Universe.all, Message_Handler);
               Context.Boundary_Results.Reserve_Capacity (2);
               if Main_Owner.Driver = null then
                  Main_Owner.Owned_Driver :=
                    VM.New_Driver (Owner.Universe.all);
                  Main_Owner.Driver := Driver_View (Main_Owner.Owned_Driver);
               end if;
               Address := Memory.Allocate
                 (Owner.Universe.Memory,
                  Call_Record'Object_Size / System.Storage_Unit,
                  Call_Record'Alignment);
               Next := Calls.To_Pointer (Address);
               Next.all := (Previous => Main_Owner.Calls, Base => Slot - 1,
                 Wanted => Input.Count,
                 Protected_Call => Input.Integer_Data /= 0,
                 Is_Root => Root_Call, Context => Owner.Context,
                 Direct_Builtin => Input.Operation = Begin_Builtin,
                 Activation => Context.Foreign_Activation,
                 Entry_Depth => Natural (Context.Stack.Length),
                 Original_Top => Context.Foreign_Top,
                 Original_Base => Context.Foreign_Base,
                 Saved_Status => Context.Status, others => <>);
               Main_Owner.Calls := Address;
               begin
                  if Root_Call then
                     Context.Failure := Nil_Value;
                     Context.Has_Failure_Value := False;
                     Context.Failure_Class := No_Failure;
                     Context.Failure_Handled := False;
                     Context.Protected_Failure_Class := No_Failure;
                     Context.Protected_Handler_Called := False;
                     Context.Non_Yieldable := Context.Non_Yieldable + 1;
                     VM.Start_Foreign
                       (Main_Owner.Driver.all, Main_Owner.Owned_Universe,
                        Callee, Arguments, Message_Handler,
                        Call_Base => Slot,
                        Has_Call_Window => Input.Operation /= Begin_Builtin,
                        Retained_Depth => Next.Entry_Depth,
                        Direct_Builtin => Input.Operation = Begin_Builtin);
                  else
                     if Context.Foreign_Activation /= null then
                        Context.Foreign_Activation.Foreign_Continuation :=
                          Continuation_Address (Input.Continuation);
                        Context.Foreign_Activation.Foreign_KContext :=
                          Input.KContext;
                     end if;
                     VM.Start_Foreign_Boundary
                       (Main_Owner.Driver.all, Callee, Arguments,
                        Message_Handler,
                        Call_Base => Slot, Has_Call_Window => True,
                        Yieldable => Input.Continuation /= null,
                        Wanted => Integer (Input.Count),
                        Protected_Call => Input.Integer_Data /= 0,
                        Direct_Builtin => Input.Operation = Begin_Builtin);
                  end if;
               exception
                  when Language_Error => Start_Error := True;
                  when Memory.Allocation_Error =>
                     Record_Memory_Error (Owner.Universe.all);
                     Start_Error := True;
                  when Program_Error =>
                     if Memory.Refusal_Pending (Owner.Universe.Memory) then
                        Record_Memory_Error (Owner.Universe.all);
                        Start_Error := True;
                     else
                        raise;
                     end if;
               end;
               --  The callee/argument packet and boundary already own every
               --  input. The suspended C caller keeps only its prefix live;
               --  the published child owns the overlapping call window.
               Publish_Top (Context, Slot - 1);
               Result := Pump (Start_Error);
               Leave_Context;
               return Result;
            end;
         when Complete_Callback =>
            if Main_Owner.Driver = null or else Input.Count < 0 or else
              Input.Index not in 0 | 2 | 4 | 5 | 8
            then
               raise Foreign_Error with "invalid callback completion";
            end if;
            if Input.Index /= 8 then
               begin
                  VM.Complete_Foreign_Call
                    (Main_Owner.Driver.all, Natural (Input.Count),
                     Natural (Input.Index), Input.Error_Handled /= 0,
                     Input.Callback_Token);
               exception
                  when Memory.Allocation_Error =>
                     Memory_Result;
                     VM.Complete_Foreign_Call
                       (Main_Owner.Driver.all, 0, 4,
                        Token => Input.Callback_Token);
                  when Program_Error =>
                     if Memory.Refusal_Pending (Owner.Universe.Memory) then
                        Memory_Result;
                        VM.Complete_Foreign_Call
                          (Main_Owner.Driver.all, 0, 4,
                           Token => Input.Callback_Token);
                     else
                        raise;
                     end if;
               end;
            end if;
            declare
               Result : constant Action_Status := Pump;
            begin
               Leave_Context;
               return Result;
            end;
         when Raise_Error =>
            if Context.Foreign_Top <= Context.Foreign_Base
            then
               raise Foreign_Error with "missing C error object";
            end if;
            if Stacks.Read (Context, Context.Foreign_Top).Kind = String_Kind
            then
               Output.Pointer :=
                 Stacks.Read (Context, Context.Foreign_Top).Reference.C_Bytes;
               if Stacks.Read (Context, Context.Foreign_Top).Reference =
                 Owner.Universe.Memory_Error_Value.Reference
               then
                  --  lua_error recognizes the actual preallocated memory
                  --  error string, including after a protected variadic
                  --  formatter handed that error back to its C caller.
                  Leave_Context;
                  return Action_Memory;
               end if;
            end if;
            Leave_Context;
            return Action_Raise;
         when Prepare_Reader_Error =>
            if Main_Owner.Driver /= null and then
              (Main_Owner.Calls /= System.Null_Address or else
               Main_Owner.Driver_Borrowed)
            then
               declare
                  Handler : constant Value :=
                    VM.Current_Message_Handler (Main_Owner.Driver.all);
                  Item : constant Value := Get_Value (-1);
               begin
                  if Handler.Kind /= Nil_Kind then
                     --  A reader's lua_error inherits the surrounding
                     --  errfunc even though protectedparser catches the
                     --  resulting failure. Reuse the ordinary protected
                     --  driver and its recursive handler rules; the hidden
                     --  raiser contributes no invented public debug frame.
                     Pin (Owner.Universe.all, Handler);
                     Pin (Owner.Universe.all, Item);
                     Push (Owner.Universe.all, Context, Handler);
                     Push (Owner.Universe.all, Context,
                           New_Native (Owner.Universe.all, "@reader.error"));
                     Push (Owner.Universe.all, Context, Item);
                     Output.Integer_Data := 1;
                  end if;
               end;
            end if;
         when Restore_Load_Stack =>
            declare
               Top : Natural;
               Item : Value;
            begin
               if Input.Index < 0 or else Input.Count not in 0 .. 1 then
                  raise Program_Error with "invalid loader stack restore";
               end if;
               Top := Context.Foreign_Base + Natural (Input.Index) +
                 Natural (Input.Count);
               if Top > Natural (Context.Foreign_Stack.Length) then
                  raise Program_Error with "unreserved loader result slot";
               end if;
               --  Pinned protectedparser and lua_dump reset their top
               --  directly, rather than executing lua_settop's C closing
               --  protocol. Copy the single real load result before retiring
               --  callback scratch roots; no allocation or callback can
               --  interrupt publication of this reserved scalar interval.
               if Input.Count = 1 then
                  Item := Get_Value (-1);
                  Stacks.Write (Owner.Universe.all, Context, Top, Item);
               end if;
               if Top < Context.Foreign_Top then
                  Stacks.Clear_Range
                    (Context, Top + 1, Context.Foreign_Top);
               end if;
               Publish_Top (Context, Top);
            end;
         when Reader_Barrier =>
            --  lua_load's protected parser is non-yieldable even when its
            --  caller is a resumable C activation. This scalar guard spans
            --  foreign reads, never an Ada activation; C removes it on every
            --  normal, reader-error and host-abort return path.
            if Input.Index /= 0 then
               Context.Non_Yieldable := Context.Non_Yieldable + 1;
            elsif Context.Non_Yieldable = 0 then
               raise Program_Error with "missing foreign reader barrier";
            else
               Context.Non_Yieldable := Context.Non_Yieldable - 1;
            end if;
         when Release_Buffer =>
            declare
               Block : System.Address := Input.Pointer;
            begin
               --  Release never allocates. Both reader and writer guards
               --  use it before returning a callback failure or forwarding
               --  an error to their caller's live C checkpoint.
               if Block /= System.Null_Address and then not
                 Memory.Owns (Owner.Universe.Memory, Block)
               then
                  raise Foreign_Error with "invalid foreign byte buffer";
               end if;
               Memory.Release (Owner.Universe.Memory, Block);
            end;
         when Dump_Function =>
            declare
               Item : constant Value := Get_Value (-1);
               Block : System.Address := System.Null_Address;
            begin
               if Item.Kind /= Closure_Kind or else
                 Item.Reference.Code.Canonical_Node = null
               then
                  raise Foreign_Error with "Lua function expected";
               end if;
               declare
                  Code : constant Prototype_Access := Item.Reference.Code;
                  Bytes : Owned_Buffer := Lua.Chunks.Encode
                    (Code.Canonical_Owner.Model, Strip => Input.Index /= 0,
                     Maximum_Depth => Owner.Universe.Bounds.Syntax_Depth,
                     Root_Node => Code.Canonical_Node);
                  procedure Copy (Text : String);
                  procedure Copy (Text : String) is
                     Target : String (Text'Range)
                       with Import, Address => Block;
                  begin
                     Target := Text;
                  end Copy;
               begin
                  --  Encode the selected real subtree before invoking C.
                  --  A separate managed byte snapshot survives writer API
                  --  reentry and collection without borrowing a controlled
                  --  Ada buffer across a possible C nonlocal transfer.
                  Block := Memory.Allocate
                    (Owner.Universe.Memory,
                     Memory.Byte_Count (Bytes.Length));
                  Bytes.Query (Copy'Access);
                  Output.Pointer := Block;
                  Output.Length := C.size_t (Bytes.Length);
               end;
            exception
               when others =>
                  Memory.Release (Owner.Universe.Memory, Block);
                  raise;
            end;
         when Load_Buffer | Load_Reader =>
            declare
               Source : Lua.Inputs.Source;
               Capture : aliased Reader_Capture :=
                 (State => State, Universe => Owner.Universe,
                  Reader => Input.Reader, Data => Input.Pointer,
                  others => <>);
               Name : constant String := Read_Name (Input.Name, "?");
               Mode : constant String := Read_Name (Input.Mode, "bt");
               Binary : Boolean;
               Callee : Value;
            begin
               if Input.Operation = Load_Reader then
                  if Input.Reader = null then
                     raise Foreign_Error with "reader function expected";
                  end if;
                  Source.Open
                    (Memory.Reference (Owner.Universe.Memory),
                     Read_Piece'Access, Capture'Address,
                     Owner.Universe.Bounds.Source_Bytes, Retry_Input'Access);
               else
                  if Input.Length > C.size_t (Natural'Last) or else
                    (Input.Length > 0 and then
                     Input.Pointer = System.Null_Address)
                  then
                     raise Foreign_Error with "invalid C string extent";
                  end if;
                  Source.Borrow (Input.Pointer, Natural (Input.Length));
               end if;
               Binary := Source.Ensure (1) and then
                 Source.Element (1) = Character'Val (27);
               --  Loading validates and owns code but never executes it.
               --  The binary decoder and text frontend both produce the real
               --  canonical graph, adopted into this session's actual heap.
               if (if Binary then
                     Ada.Strings.Fixed.Index (Mode, "b") = 0 and then
                     Ada.Strings.Fixed.Index (Mode, "B") = 0
                   else Ada.Strings.Fixed.Index (Mode, "t") = 0)
               then
                  Error_Result ("attempt to load a " &
                    (if Binary then "binary" else "text") &
                    " chunk (mode is '" & Mode & "')");
                  Output.Integer_Data := 3;
               elsif Binary then
                  declare
                     Decoded : Lua.Chunks.Decode_Result := Lua.Chunks.Decode
                       (Source, Memory.Reference (Owner.Universe.Memory),
                        (Input_Bytes => Owner.Universe.Bounds.Source_Bytes,
                         Depth => Owner.Universe.Bounds.Syntax_Depth,
                         others => <>),
                        Fixed_Buffer =>
                          Ada.Strings.Fixed.Index (Mode, "B") /= 0);
                  begin
                     case Decoded.Outcome is
                        when Lua.Chunks.Succeeded =>
                           Callee := Canonical.Adopt
                             (Owner.Universe.all, Decoded.Code,
                              Global_Environment (Owner.Universe.all));
                           Push (Owner.Universe.all, Context, Callee);
                        when Lua.Chunks.Bad_Format =>
                           Error_Result (Name & ": bad binary format (" &
                             Lua.Chunks.Message (Decoded.Error) & ")");
                           Output.Integer_Data := 3;
                        when Lua.Chunks.Resource_Limit =>
                           Fail (Owner.Universe.all,
                             "binary loading resource limit", True);
                        when Lua.Chunks.Memory_Failure =>
                           Memory_Result;
                           Output.Integer_Data := 4;
                     end case;
                  end;
               else
                  declare
                     Unit : Lua.Syntax_Trees.Compilation_Unit;
                  begin
                     Lua.Syntax_Trees.Parse
                       (Unit, Source, Name,
                        (Owner.Universe.Bounds.Source_Bytes,
                         Owner.Universe.Bounds.Tokens,
                         Owner.Universe.Bounds.Syntax_Nodes,
                         Owner.Universe.Bounds.Syntax_Depth),
                        Memory.Reference (Owner.Universe.Memory));
                     if Unit.Result.Status = Lua.Syntax.Resource_Error then
                        Fail (Owner.Universe.all,
                              "source loading resource limit", True);
                     elsif Unit.Result.Status /= Lua.Syntax.Success then
                        Error_Result (Name & ":" & Ada.Strings.Fixed.Trim
                          (Unit.Result.Error.Line'Image, Ada.Strings.Both) &
                          ": " & Lua.Syntax_Trees.Text
                            (Unit, Unit.Result.Error.Message));
                        Output.Integer_Data := 3;
                     else
                        declare
                           Lowered : Lua.Canonical_Compiler.Compilation_Result
                             := Lua.Canonical_Compiler.Compile
                               (Unit, Memory.Reference
                                  (Owner.Universe.Memory), Name);
                        begin
                           case Lowered.Outcome is
                              when Lua.Canonical_Compiler.Succeeded =>
                                 Callee := Canonical.Adopt
                                   (Owner.Universe.all, Lowered.Code,
                                    Global_Environment (Owner.Universe.all));
                                 Push (Owner.Universe.all, Context, Callee);
                              when Lua.Canonical_Compiler.Compiler_Limit =>
                                 Error_Result (Name & ": " &
                                   Lua.Canonical_Compiler.Message
                                     (Lowered.Error));
                                 Output.Integer_Data := 3;
                              when Lua.Canonical_Compiler.Resource_Limit =>
                                 Fail (Owner.Universe.all,
                                   "compiler resource limit", True);
                              when Lua.Canonical_Compiler.Memory_Failure =>
                                 Memory_Result;
                                 Output.Integer_Data := 4;
                           end case;
                        end;
                     end if;
                  end;
               end if;
            exception
               when Lua.Inputs.Reader_Error =>
                  --  The source/partial frontend graph is finalized before
                  --  this actual foreign status reaches C. Its error object
                  --  already belongs to the reader's traced public stack.
                  Output.Integer_Data := C.long_long (Capture.Status);
                  Output.Error_Handled := Capture.Error_Handled;
               when Lua.Inputs.Input_Limit =>
                  Fail (Owner.Universe.all, "source byte limit exceeded",
                        Resource => True);
               when Memory.Allocation_Error =>
                  Memory_Result;
                  Output.Integer_Data := 4;
               when Program_Error =>
                  if Memory.Refusal_Pending (Owner.Universe.Memory) then
                     Memory_Result;
                     Output.Integer_Data := 4;
                  else
                     raise;
                  end if;
            end;
      end case;
      Leave_Context;
      return Action_Done;
   exception
      when Memory.Allocation_Error =>
         Memory_Result;
         Leave_Context;
         return Action_Memory;
      when Language_Error =>
         begin
            if Context.Failure_Class = Host_Abort then
               Leave_Context;
               return Action_Abort;
            end if;
            if Context.Failure_Class = Memory_Failure then
               Memory_Result;
               Leave_Context;
               return Action_Memory;
            end if;
            Error_Result (To_String (Context.Failure_Text));
            if Memory.Refusal_Pending (Owner.Universe.Memory) then
               Memory_Result;
               Leave_Context;
               return Action_Memory;
            end if;
            Leave_Context;
            return Action_Raise;
         exception
            when others =>
               Leave_Context;
               return Action_Abort;
         end;
      when Fault : Foreign_Error =>
         begin
            Error_Result (Ada.Exceptions.Exception_Message (Fault));
            if Owner /= null and then
              Memory.Refusal_Pending (Owner.Universe.Memory)
            then
               Memory_Result;
               Leave_Context;
               return Action_Memory;
            end if;
            Leave_Context;
            return Action_Raise;
         exception
            when others =>
               Leave_Context;
               return Action_Abort;
         end;
      when others =>
         --  Physical Ada exhaustion or internal faults are host aborts, not
         --  catchable Lua allocator refusal. The C boundary handles them only
         --  after this activation has returned; it never jumps across Ada.
         if Owner /= null and then
           Memory.Refusal_Pending (Owner.Universe.Memory)
         then
            Memory_Result;
            Leave_Context;
            return Action_Memory;
         end if;
         Leave_Context;
         return Action_Abort;
   end Dispatch;
end Lua.Engine.Foreign;
