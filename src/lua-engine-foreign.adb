with Ada.Containers;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Interfaces.C.Strings;
with Lua.Canonical_Compiler;
with Lua.Chunks;
with Lua.Engine.Canonical;
with Lua.Engine.Machine;
with Lua.Runtime_Configuration;
with Lua.Syntax;
with Lua.Syntax_Trees;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;

package body Lua.Engine.Foreign is
   package C renames Interfaces.C;
   package Memory renames Lua.Storage;
   package VM renames Lua.Engine.Machine;
   use System.Storage_Elements;
   use type Ada.Containers.Count_Type;
   use type C.int;
   use type C.long_long;
   use type C.size_t;
   use type VM.Driver_Access;
   use type Lua.Syntax.Check_Status;
   use type Integer_Value;
   use type Real_Value;
   use type Memory.Allocation_Function;
   use type System.Address;

   Registry_Index : constant C.int := -(C.int'Last / 2 + 1_000);
   Stack_Limit : constant Natural :=
     Lua.Runtime_Configuration.Maximum_Stack;
   Foreign_Error : exception;

   type Control is record
      Universe : World_Access;
      Context : Context_Id;
      Extra : Storage_Count;
      Seed : C.unsigned;
      Driver : VM.Driver_Access;
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
   end record;
   package Calls is new System.Address_To_Access_Conversions (Call_Record);
   function Function_Address is new Ada.Unchecked_Conversion
     (C_Function, System.Address);
   function Address_Function is new Ada.Unchecked_Conversion
     (System.Address, C_Function);
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
     (State : World_Access; Context : Context_Id; Extra : Storage_Count;
      Seed : C.unsigned; Main : System.Address) return System.Address;
   function New_State (Input : Request) return System.Address;
   function Position
     (Context : Context_Access; Index : C.int) return Natural;
   function At_Index
     (State : World; Context : Context_Access; Index : C.int) return Value;
   function Valid_Index (Context : Context_Access; Index : C.int)
                         return Boolean;
   function Type_Code (Item : Value) return C.int;
   function Numeric
     (Arena : not null Memory.Owner_Access; Item : Value)
      return Lua.Numbers.Number;
   procedure Push (Context : Context_Access; Item : Value);
   function Read_Bytes
     (Pointer : System.Address; Length : C.size_t) return String;
   function Read_Name (Pointer : System.Address; Default : String)
                       return String;

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
   end Initialize_Bridge;

   function Context_Of (Owner : Controls.Object_Pointer)
                        return Context_Access is
   begin
      return Owner.Universe.Contexts (Positive (Owner.Context));
   end Context_Of;

   function Create_Surface
     (State : World_Access; Context : Context_Id; Extra : Storage_Count;
      Seed : C.unsigned; Main : System.Address) return System.Address
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
      Item.Foreign_Stack.Reserve_Capacity (21);
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
         Seed => Seed, Driver => null, others => <>);
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
      Begin_Operation (State.all);
      Operation_Active := True;
      Result := Create_Surface
        (State, Context_Id (State.Main_Thread.Context_Index),
         Storage_Count (Input.Length), Input.Seed, System.Null_Address);
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

   function Position
     (Context : Context_Access; Index : C.int) return Natural
   is
      Number : constant Integer_Value :=
        (if Index > 0 then Integer_Value (Context.Foreign_Base) +
           Integer_Value (Index)
         else Integer_Value (Context.Foreign_Stack.Length) +
           Integer_Value (Index) + 1);
   begin
      if Index = 0 or else Index <= Registry_Index or else
        Number <= Integer_Value (Context.Foreign_Base)
        or else Number > Integer_Value (Context.Foreign_Stack.Length)
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
      return Context.Foreign_Stack (Slot);
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
         when Thread_Kind => return 8;
      end case;
   end Type_Code;

   function Numeric
     (Arena : not null Memory.Owner_Access; Item : Value)
      return Lua.Numbers.Number is
   begin
      case Item.Kind is
         when Integer_Kind =>
            return (Lua.Numbers.Integer_Number, Item.Integer_Data);
         when Real_Kind =>
            return (Lua.Numbers.Real_Number, Item.Real_Data);
         when String_Kind =>
            return Read_Number (Arena, Item.Reference.Bytes);
         when others => return (Kind => Lua.Numbers.Invalid);
      end case;
   end Numeric;

   procedure Push (Context : Context_Access; Item : Value) is
   begin
      if Natural (Context.Foreign_Stack.Length) >= Stack_Limit -
        Natural'Min (Stack_Limit, Context.Stack_Slots)
      then
         raise Foreign_Error with "stack overflow";
      end if;
      if Context.Foreign_Stack.Length + 1 >=
        Context.Foreign_Stack.Capacity
      then
         Context.Foreign_Stack.Reserve_Capacity
           (Ada.Containers.Count_Type'Max
              (21, Ada.Containers.Count_Type'Min
                 (Ada.Containers.Count_Type (Stack_Limit + 1),
                  Context.Foreign_Stack.Capacity * 2)));
      end if;
      Context.Foreign_Stack.Append (Item);
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

   function Dispatch
     (State : System.Address; Input : not null access constant Request;
      Output : not null access Response) return Action_Status
   is
      Owner : Controls.Object_Pointer;
      Context : Context_Access;
      Active_World : World_Access;
      Previous : Context_Access;
      Operation_Active : Boolean := False;
      Keep_Scheduler : Boolean := False;
      Main_Owner : Controls.Object_Pointer;

      procedure Leave_Context;
      procedure Error_Result (Text : String);
      procedure Memory_Result;
      function Require_Table return Value;
      procedure Get_Raw (Key : Value);
      function Pump (Start_Error : Boolean := False) return Action_Status;

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
            Context.Foreign_Stack.Append (Item);
            Output.Pointer := Item.Reference.C_Bytes;
         end if;
      exception
         when others => null;
      end Error_Result;

      procedure Memory_Result is
      begin
         if Context /= null then
            --  The actual immutable error string was allocated during state
            --  initialization. Its reserved stack slot needs no provider call.
            Record_Memory_Error (Owner.Universe.all);
            Context.Foreign_Stack.Append (Context.Failure);
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
         Push (Context, Item);
         Output.Integer_Data := C.long_long (Type_Code (Item));
      end Get_Raw;

      function Pump (Start_Error : Boolean := False) return Action_Status is
         Driver : VM.Driver renames Main_Owner.Driver.all;
         Pending : constant Calls.Object_Pointer :=
           Calls.To_Pointer (Main_Owner.Calls);
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
            Packet.Append
              ((if Owner.Universe.Current.Has_Failure_Value then
                   Owner.Universe.Current.Failure else
                   New_String (Owner.Universe.all, To_String
                     (Owner.Universe.Current.Failure_Text))));
         end if;
         loop
            exit when Error_Status /= 0 or else VM.Is_Complete (Driver) or else
              VM.Has_Foreign_Result (Driver);
            if VM.Needs_Foreign_Call (Driver) then
               declare
                  Target : constant Context_Access :=
                    VM.Foreign_Context (Driver);
               begin
                  Output.Pointer := Create_Surface
                    (Owner.Universe, Context_Id (Target.Thread.Context_Index),
                     Main_Owner.Extra, Main_Owner.Seed,
                     Surfaces.To_Pointer (State).Main);
                  Output.Function_Data :=
                    Address_Function (VM.Foreign_Handler (Driver));
                  return Action_Call;
               end;
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
                  Packet.Append
                    ((if Owner.Universe.Current.Has_Failure_Value then
                         Owner.Universe.Current.Failure else
                         New_String (Owner.Universe.all, To_String
                           (Owner.Universe.Current.Failure_Text))));
                  exit;
            end;
         end loop;
         if Error_Status = 0 then
            if Pending.Is_Root then
               if VM.Outcome (Driver) /= Completed then
                  raise Foreign_Error with "unexpected C-call suspension";
               end if;
               VM.Take_Results (Driver, Packet);
               if Packet.Is_Empty or else
                 Packet.First_Element.Kind /= Boolean_Kind
               then
                  raise Program_Error with "C entry lost protection packet";
               end if;
               if not Packet.First_Element.Boolean_Data then
                  Error_Status :=
                    (if Caller.Protected_Failure_Class = Memory_Failure then 4
                     elsif Caller.Protected_Failure_Class = Handling_Failure
                     then 5 else 2);
                  Handler_Called := Caller.Protected_Handler_Called;
               end if;
               Packet.Delete_First;
            else
               VM.Take_Foreign_Result
                 (Driver, Packet, Error_Status, Handler_Called);
            end if;
         end if;
         if Pending.Is_Root then
            VM.Finish (Driver);
            VM.Clear_Frames (Owner.Universe.all);
            Caller.Non_Yieldable := Caller.Non_Yieldable - 1;
         end if;
         Caller.Foreign_Stack.Set_Length
           (Ada.Containers.Count_Type (Pending.Base));
         Count := (if Error_Status /= 0 then 1
                   elsif Pending.Wanted = -1 then Natural (Packet.Length)
                   else Natural (Pending.Wanted));
         --  The Call_Record contains only scalar ownership metadata; pop it
         --  before publishing results so allocation refusal cannot leave a
         --  finished operation registered as an active nested drive.
         Address := Main_Owner.Calls;
         Main_Owner.Calls := Pending.Previous;
         declare
            Protected_Call : constant Boolean := Pending.Protected_Call;
         begin
            Memory.Release (Owner.Universe.Memory, Address);
            for Index in 1 .. Count loop
               Push (Caller,
                 (if Index <= Natural (Packet.Length) then Packet (Index)
                  else Nil_Value));
            end loop;
            Packet.Clear;
            Output.Integer_Data := C.long_long (Error_Status);
            Output.Error_Handled := Boolean'Pos (Handler_Called);
            if Error_Status /= 0 and then not Protected_Call then
               if Caller.Foreign_Stack.Last_Element.Kind = String_Kind
               then
                  Output.Pointer :=
                    Caller.Foreign_Stack.Last_Element.Reference.C_Bytes;
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
         when Create_State | Create_Default_State => null;
         when Close_State =>
            declare
               Universe : World_Access := Owner.Universe;
            begin
               if Main_Owner.Calls /= System.Null_Address then
                  raise Foreign_Error with "cannot close a running C drive";
               end if;
               VM.Free_Driver (Main_Owner.Driver);
               End_Operation (Active_World.all);
               Operation_Active := False;
               Active_World := null;
               Finalize (Universe.all);
               Free_World (Universe);
            end;
         when Create_Thread =>
            declare
               Item : constant Value := New_Thread
                 (Owner.Universe.all, Nil_Value);
            begin
               --  The parent stack roots the new thread before a caller can
               --  collect. Its C surface is borrowed, not a permanent root.
               Push (Context, Item);
               Output.Pointer := Create_Surface
                 (Owner.Universe, Context_Id (Item.Reference.Context_Index),
                  Owner.Extra, Owner.Seed,
                  Surfaces.To_Pointer (State).Main);
            end;
         when Get_Top =>
            Output.Integer_Data := C.long_long
              (Natural (Context.Foreign_Stack.Length) - Context.Foreign_Base);
         when Absolute_Index =>
            Output.Integer_Data :=
              (if Input.Index > 0 or Input.Index <= Registry_Index then
                  C.long_long (Input.Index)
               else C.long_long
                 (Natural (Context.Foreign_Stack.Length) -
                  Context.Foreign_Base) +
                 C.long_long (Input.Index) + 1);
         when Set_Top =>
            declare
               Count : constant Integer_Value :=
                 (if Input.Index >= 0 then Integer_Value
                    (Context.Foreign_Base) + Integer_Value (Input.Index)
                  else Integer_Value (Context.Foreign_Stack.Length) +
                    Integer_Value (Input.Index) + 1);
            begin
               if Count < Integer_Value (Context.Foreign_Base) or else
                 Count > Integer_Value (Stack_Limit)
               then
                  raise Foreign_Error with "invalid stack top";
               end if;
               while Integer_Value (Context.Foreign_Stack.Length) < Count
               loop
                  Push (Context, Nil_Value);
               end loop;
               if Integer_Value (Context.Foreign_Stack.Length) > Count then
                  Context.Foreign_Stack.Set_Length
                    (Ada.Containers.Count_Type (Count));
               end if;
            end;
         when Check_Stack =>
            if Input.Count >= 0 and then Integer_Value (Input.Count) <=
              Integer_Value (Stack_Limit) -
                Integer_Value (Context.Foreign_Stack.Length) -
                Integer_Value (Context.Stack_Slots)
            then
               begin
                  Context.Foreign_Stack.Reserve_Capacity
                    (Context.Foreign_Stack.Length +
                     Ada.Containers.Count_Type (Input.Count) + 1);
                  Output.Integer_Data := 1;
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
         when Push_Value => Push (Context, Get_Value (Input.Index));
         when Copy_Value =>
            declare
               Slot : constant Natural := Position (Context, Input.Count);
            begin
               if Input.Count < Registry_Index and then
                 Valid_Index (Context, Input.Count)
               then
                  Context.Foreign_Activation.Native_Self.Captures
                    (Positive (C.long_long (Registry_Index) -
                      C.long_long (Input.Count))).Cell_Value :=
                        Get_Value (Input.Index);
               elsif Slot = 0 then
                  raise Foreign_Error with "invalid C stack destination";
               else
                  Context.Foreign_Stack.Replace_Element
                    (Slot, Get_Value (Input.Index));
               end if;
            end;
         when Rotate_Values =>
            declare
               First : constant Natural := Position (Context, Input.Index);
               Last : constant Natural :=
                 Natural (Context.Foreign_Stack.Length);
               procedure Reverse_Range (Left, Right : Natural);
               procedure Reverse_Range (Left, Right : Natural) is
                  Low : Natural := Left;
                  High : Natural := Right;
               begin
                  while Low < High loop
                     Context.Foreign_Stack.Swap (Low, High);
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
                   Integer_Value (Context.Foreign_Stack.Length) -
                     Integer_Value (Context.Foreign_Base)
               then
                  raise Foreign_Error with "invalid cross-state move";
               end if;
               if Target /= Context and Count > 0 then
                  for Index in Context.Foreign_Stack.Last_Index -
                    Natural (Count) + 1 .. Context.Foreign_Stack.Last_Index
                  loop
                     Push (Target, Context.Foreign_Stack (Index));
                  end loop;
                  Context.Foreign_Stack.Delete_Last
                    (Ada.Containers.Count_Type (Count));
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
                 Numeric (Context.Memory, Get_Value (Input.Index));
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
                     Context.Foreign_Stack.Replace_Element (Slot, Item);
                  else
                     Context.Foreign_Activation.Native_Self.Captures
                       (Positive (C.long_long (Registry_Index) -
                         C.long_long (Input.Index))).Cell_Value := Item;
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
               end if;
            end;
         when To_Pointer | To_Thread =>
            declare
               Item : constant Value := Get_Value (Input.Index);
            begin
               if Item.Kind = Thread_Kind then
                  Output.Pointer := Create_Surface
                    (Owner.Universe, Context_Id
                       (Item.Reference.Context_Index),
                     Owner.Extra, Owner.Seed,
                     Surfaces.To_Pointer (State).Main);
               elsif Input.Operation = To_Pointer then
                  case Item.Kind is
                     when Light_Identity_Kind | Foreign_Function_Kind =>
                        Output.Pointer := Item.Identity;
                     when String_Kind =>
                        Output.Pointer := Item.Reference.C_Bytes;
                     when Table_Kind | Closure_Kind |
                       Native_Closure_Kind =>
                        Output.Pointer := Item.Reference.all'Address;
                     when others => null;
                  end case;
               end if;
            end;
         when Push_Nil => Push (Context, Nil_Value);
         when Push_Boolean =>
            Push (Context, (Kind => Boolean_Kind,
                            Boolean_Data => Input.Count /= 0));
         when Push_Integer =>
            Push (Context, (Kind => Integer_Kind,
                            Integer_Data => Integer_Value
                              (Input.Integer_Data)));
         when Push_Number =>
            Push (Context, (Kind => Real_Kind,
                            Real_Data => Real_Value (Input.Number_Data)));
         when Push_String =>
            declare
               Item : constant Value := New_String
                 (Owner.Universe.all,
                  Read_Bytes (Input.Pointer, Input.Length));
            begin
               Push (Context, Item);
               Output.Pointer := Item.Reference.C_Bytes;
            end;
         when Push_Pointer =>
            Push (Context, (Kind => Light_Identity_Kind,
                            Identity => Input.Pointer));
         when Push_Thread =>
            Push (Context, (Kind => Thread_Kind, Reference => Context.Thread));
            Output.Integer_Data := Boolean'Pos
              (Context = Owner.Universe.Main_Context);
         when Create_Table =>
            Push (Context, New_Table (Owner.Universe.all));
         when Raw_Get =>
            declare
               Table : constant Value := Require_Table;
               Key : constant Value := Context.Foreign_Stack.Last_Element;
               Item : constant Value := Get (Table, Key);
            begin
               Pin (Owner.Universe.all, Item);
               Context.Foreign_Stack.Delete_Last;
               Push (Context, Item);
               Output.Integer_Data := C.long_long (Type_Code (Item));
            end;
         when Raw_Set =>
            declare
               Table : constant Value := Require_Table;
               Last : constant Positive :=
                 Context.Foreign_Stack.Last_Index;
               Item : constant Value := Context.Foreign_Stack (Last);
               Key : constant Value := Context.Foreign_Stack (Last - 1);
            begin
               --  Keep original operands on the traced C stack until all
               --  allocation/rehash work completes. Ada locals alone cannot
               --  protect an existing key/value across emergency collection.
               Set (Owner.Universe.all, Table, Key, Item);
               Context.Foreign_Stack.Delete_Last (2);
            end;
         when Raw_Get_Integer =>
            Get_Raw ((Kind => Integer_Kind,
                      Integer_Data => Integer_Value (Input.Integer_Data)));
         when Raw_Set_Integer | Raw_Set_Pointer =>
            declare
               Table : constant Value := Require_Table;
               Item : constant Value := Context.Foreign_Stack.Last_Element;
               Key : constant Value :=
                 (if Input.Operation = Raw_Set_Integer then
                    (Kind => Integer_Kind, Integer_Data => Integer_Value
                       (Input.Integer_Data))
                  else (Kind => Light_Identity_Kind,
                        Identity => Input.Pointer));
            begin
               Set (Owner.Universe.all, Table, Key, Item);
               Context.Foreign_Stack.Delete_Last;
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
               Key : constant Value := Context.Foreign_Stack.Last_Element;
               Results : constant Values.Vector :=
                 Next (Owner.Universe.all, Table, Key);
            begin
               Pin (Owner.Universe.all, Results);
               Context.Foreign_Stack.Delete_Last;
               --  The Lua-facing primitive returns one nil at termination.
               --  C lua_next instead pops the exhausted key, pushes nothing,
               --  and returns zero; exposing that nil as a row corrupts the
               --  caller's next iteration. See pinned lapi.c:1273-1285.
               if not Results.Is_Empty and then
                 Results.First_Element.Kind /= Nil_Kind
               then
                  for Item of Results loop
                     Push (Context, Item);
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
                (Natural (Context.Foreign_Stack.Length) -
                 Context.Foreign_Base)
            then
               raise Foreign_Error with "invalid C closure arguments";
            end if;
            if Input.Count = 0 then
               Push (Context, (Foreign_Function_Kind,
                               Function_Address (Input.Function_Data)));
            else
               declare
                  Captures : Values.Vector :=
                    Owned_Values (Owner.Universe.all);
                  Item : Value;
               begin
                  for Index in Natural (Context.Foreign_Stack.Length) -
                    Natural (Input.Count) + 1 ..
                    Natural (Context.Foreign_Stack.Length)
                  loop
                     Captures.Append (Context.Foreign_Stack (Index));
                  end loop;
                  Item := New_Native (Owner.Universe.all, "foreign.callback",
                                      Captures);
                  Item.Reference.Foreign_Handler :=
                    Function_Address (Input.Function_Data);
                  Context.Foreign_Stack.Delete_Last
                    (Ada.Containers.Count_Type (Input.Count));
                  Push (Context, Item);
               end;
            end if;
         when To_C_Function =>
            declare
               Item : constant Value := Get_Value (Input.Index);
            begin
               if Item.Kind = Foreign_Function_Kind then
                  Output.Function_Data := Address_Function (Item.Identity);
               elsif Item.Kind = Native_Closure_Kind and then
                 Item.Reference.Foreign_Handler /= System.Null_Address
               then
                  Output.Function_Data :=
                    Address_Function (Item.Reference.Foreign_Handler);
               end if;
            end;
         when Begin_Call =>
            if Input.Index < 0 or else Input.Count < -1 or else
              Input.Count > C.int (Stack_Limit) or else
              Natural (Input.Index) >= Natural (Context.Foreign_Stack.Length)
                - Context.Foreign_Base
            then
               raise Foreign_Error with "invalid C call arguments";
            end if;
            declare
               Slot : constant Positive :=
                 Context.Foreign_Stack.Last_Index - Natural (Input.Index);
               Callee : constant Value := Context.Foreign_Stack (Slot);
               Message_Handler : Value;
               Arguments : Values.Vector :=
                 Owned_Values (Owner.Universe.all);
               Address : System.Address;
               Root_Call : constant Boolean :=
                 Main_Owner.Calls = System.Null_Address;
               Next : Calls.Object_Pointer;
               Result : Action_Status;
               Start_Error : Boolean := False;
            begin
               for Index in Slot + 1 .. Context.Foreign_Stack.Last_Index loop
                  Arguments.Append (Context.Foreign_Stack (Index));
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
               if Main_Owner.Driver = null then
                  Main_Owner.Driver := VM.New_Driver (Owner.Universe.all);
               end if;
               Address := Memory.Allocate
                 (Owner.Universe.Memory,
                  Call_Record'Object_Size / System.Storage_Unit,
                  Call_Record'Alignment);
               Next := Calls.To_Pointer (Address);
               Next.all := (Previous => Main_Owner.Calls, Base => Slot - 1,
                 Wanted => Input.Count,
                 Protected_Call => Input.Integer_Data /= 0,
                 Is_Root => Root_Call, Context => Owner.Context);
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
                       (Main_Owner.Driver.all, Owner.Universe,
                        Callee, Arguments, Message_Handler);
                  else
                     VM.Start_Foreign_Boundary
                       (Main_Owner.Driver.all, Callee, Arguments,
                        Message_Handler);
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
               Context.Foreign_Stack.Set_Length
                 (Ada.Containers.Count_Type (Slot - 1));
               Result := Pump (Start_Error);
               Leave_Context;
               return Result;
            end;
         when Complete_Callback =>
            if Main_Owner.Driver = null or else Input.Count < 0 or else
              Input.Index not in 0 | 2 | 4 | 5
            then
               raise Foreign_Error with "invalid callback completion";
            end if;
            begin
               VM.Complete_Foreign_Call
                 (Main_Owner.Driver.all, Natural (Input.Count),
                  Natural (Input.Index), Input.Error_Handled /= 0);
            exception
               when Memory.Allocation_Error =>
                  Memory_Result;
                  VM.Complete_Foreign_Call (Main_Owner.Driver.all, 0, 4);
               when Program_Error =>
                  if Memory.Refusal_Pending (Owner.Universe.Memory) then
                     Memory_Result;
                     VM.Complete_Foreign_Call (Main_Owner.Driver.all, 0, 4);
                  else
                     raise;
                  end if;
            end;
            declare
               Result : constant Action_Status := Pump;
            begin
               Leave_Context;
               return Result;
            end;
         when Raise_Error =>
            if Natural (Context.Foreign_Stack.Length) <= Context.Foreign_Base
            then
               raise Foreign_Error with "missing C error object";
            end if;
            if Context.Foreign_Stack.Last_Element.Kind = String_Kind then
               Output.Pointer :=
                 Context.Foreign_Stack.Last_Element.Reference.C_Bytes;
            end if;
            Leave_Context;
            return Action_Raise;
         when Load_Buffer =>
            declare
               Source : constant String := Read_Bytes
                 (Input.Pointer, Input.Length);
               Name : constant String := Read_Name (Input.Name, "?");
               Mode : constant String := Read_Name (Input.Mode, "bt");
               Binary : constant Boolean := Source'Length > 0 and then
                 Source (Source'First) = Character'Val (27);
               Callee : Value;
            begin
               --  Loading validates and owns code but never executes it.
               --  The binary decoder and text frontend both produce the real
               --  canonical graph, adopted into this session's actual heap.
               if Ada.Strings.Fixed.Index
                 (Mode, (if Binary then "b" else "t")) = 0
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
                         others => <>));
                  begin
                     case Decoded.Outcome is
                        when Lua.Chunks.Succeeded =>
                           Callee := Canonical.Adopt
                             (Owner.Universe.all, Decoded.Code,
                              (Table_Kind, Owner.Universe.Globals));
                           Push (Context, Callee);
                        when Lua.Chunks.Bad_Format =>
                           Error_Result (Name & ": " &
                             Lua.Chunks.Message (Decoded.Error));
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
                                    (Table_Kind, Owner.Universe.Globals));
                                 Push (Context, Callee);
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
