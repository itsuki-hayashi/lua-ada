with Lua.Engine.Library_Openers;
with Lua.Engine.Canonical;
with Lua.Engine.Finalizers;
with Lua.Engine.Warnings;
with Lua.Engine.External_Releases;
with Lua.Engine.Formats;
with Lua.Engine.Native_Modules;
with Lua.Storage.Fixed_Arenas;
with Lua.Platform_Streams;
with Lua.Engine.Stacks;
with Lua.Number_Parsing;
with Lua.Platform_Locales;
with Lua.Platform_Numerics;
with Ada.Exceptions;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;
with Ada.Strings.Fixed;
with Ada.Unchecked_Deallocation;
with Ada.Unchecked_Conversion;
with Lua_Ada_Config;
with Lua.Engine.Compiler;
with Lua.Engine.Tables;
with Lua.Engine.Machine;
with Lua.Engine.Foreign;

package body Lua.Engine is
   use type Ada.Containers.Count_Type;
   use type Interfaces.C.int;
   use type Interfaces.C.size_t;
   use type Ada.Exceptions.Exception_Id;
   use type Integer_Value;
   use type System.Address;
   use System.Storage_Elements;
   use type Real_Value;
   use type Interfaces.Unsigned_64;
   use type Lua.Prototypes.Prototype_Access;
   use type Lua.Storage.Owner_Access;
   use type Lua.Storage.Allocation_Function;
   package Locales renames Lua.Platform_Locales;

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

   procedure Free_Object
     (State : in out World; Item : in out Object_Access;
      Reason : Resource_Release_Reason := Collected);

   procedure Free_Object
     (State : in out World; Item : in out Object_Access;
      Reason : Resource_Release_Reason := Collected) is
   begin
      if Item /= null and then Item.Kind = Userdata_Object and then
        Item.Cleanup_Resource /= null
      then
         declare
            Cleanup : constant Resource_Cleanup := Item.Cleanup_Resource;
            Data : constant System.Address := Item.Resource_Data;
         begin
            --  Clear the attachment first: a first-party cleanup owns only
            --  host resources and its metadata, never a Lua callback. This
            --  path also handles abandoned sessions/coroutines and cannot
            --  run __gc or close a borrowed standard stream by accident.
            Item.Cleanup_Resource := null;
            Item.Resource_Data := System.Null_Address;
            Cleanup (Lua.Storage.Reference (State.Memory),
                     Item.Payload'Address, Data,
                     (if Item.Finalization_Aborted then Host_Disposal
                      else Reason));
         end;
      end if;
      --  C observes this immutable view only while the Lua string is live.
      --  Release it with the string, never through a permanent facade cache.
      if Item /= null and then Item.Kind = String_Object then
         if Item.Interned then
            declare
               Bucket : constant Positive := Natural
                 (Item.String_Hash mod Interfaces.Unsigned_64
                    (State.Short_Strings.Length)) + 1;
               Cursor : Object_Access := State.Short_Strings (Bucket);
               Previous : Object_Access;
            begin
               --  Unlink while the header and chain are still valid. The
               --  weak index never marks a string or delays its collection.
               while Cursor /= Item loop
                  Previous := Cursor;
                  Cursor := Cursor.Intern_Next;
               end loop;
               if Previous = null then
                  State.Short_Strings.Replace_Element
                    (Bucket, Item.Intern_Next);
               else
                  Previous.Intern_Next := Item.Intern_Next;
               end if;
               State.Short_String_Count := State.Short_String_Count - 1;
               Item.Interned := False;
               Item.Intern_Next := null;
            end;
         end if;
         if Item.External_String then
            if Item.Release_Queued or else Item.String_Allocator /= null then
               --  The collector detaches ownership before this call. Keep
               --  the existing header as an allocation-free release packet;
               --  no foreign code executes inside this Ada sweep/teardown.
               External_Releases.Enqueue (State, Item);
               Item := null;
               return;
            end if;
         elsif Item.C_Bytes /= System.Null_Address then
            Lua.Storage.Release (State.Memory, Item.C_Bytes);
         end if;
      end if;
      Release_Object (Item);
   end Free_Object;

   procedure Release_Detached_String
     (State : in out World; Item : in out Object_Access) is
   begin
      if Item = null or else Item.Registry_Slot /= 0 or else
        Item.String_Allocator /= null or else Item.Release_Queued
      then
         raise Program_Error with "invalid external header retirement";
      end if;
      Free_Object (State, Item);
   end Release_Detached_String;

   function Current_Decimal_Point return Character is
     (Character'Val (Integer (Locales.Decimal_Point)));
   --  Read the native localeconv()->decimal_point[0] byte at each runtime
   --  conversion, so an os.setlocale change is seen by the next tonumber or
   --  arithmetic coercion. Nothing is cached, allocated or charged here: the
   --  call only supplies one byte to the existing shared parser. Callers that
   --  change locale elsewhere must serialize it with this read, as documented
   --  in Lua.Platform_Locales.

   function Read_Number
     (Memory : not null Lua.Storage.Owner_Access; Text : String;
      Base : Natural := 0) return Lua.Numbers.Number is
   begin
      --  The parser retains its exact-decimal default for every other caller;
      --  only this runtime boundary passes the current native separator.
      return Lua.Number_Parsing.Read
        (Text, Memory, Base, Current_Decimal_Point);
   end Read_Number;

   function Read_Number
     (Memory : not null Lua.Storage.Owner_Access; Text : Byte_String;
      Base : Natural := 0) return Lua.Numbers.Number
   is
      View : constant String (1 .. Text.Size)
        with Import, Address => Text.Address;
   begin
      --  The caller's frame, stack window or operation root retains this
      --  immutable string object throughout conversion. The parser owns only
      --  its limb scratch; it neither copies nor caches the borrowed payload.
      return Lua.Number_Parsing.Read
        (View, Memory, Base, Current_Decimal_Point);
   end Read_Number;

   function Read_Number
     (State : in out World; Text : String; Base : Natural := 0)
      return Lua.Numbers.Number is
   begin
      if State.Policy = Bounded then
         if Text'Length > State.Bounds.Instructions - Natural'Min
           (State.Steps, State.Bounds.Instructions)
         then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         State.Steps := State.Steps + Text'Length;
      end if;
      return Read_Number (Text, Base);
   end Read_Number;

   function Read_Number
     (State : in out World; Text : Byte_String; Base : Natural := 0)
      return Lua.Numbers.Number is
   begin
      --  Numeric strings can be much longer than their retained significant
      --  prefix. Charge the linear scan once to the existing execution epoch;
      --  callbacks/protection never acquire a fresh conversion allowance.
      if State.Policy = Bounded then
         if Text.Size > State.Bounds.Instructions - Natural'Min
           (State.Steps, State.Bounds.Instructions)
         then
            Fail (State, "instruction limit exceeded", Resource => True);
         end if;
         State.Steps := State.Steps + Text.Size;
      end if;
      return Read_Number (Text, Base);
   end Read_Number;

   function Read_Number
     (Text : String; Base : Natural := 0) return Lua.Numbers.Number is
   begin
      return Lua.Number_Parsing.Read_Without_Allocation
        (Text, Base, Current_Decimal_Point);
   end Read_Number;

   function Read_Number
     (Text : Byte_String; Base : Natural := 0) return Lua.Numbers.Number
   is
      View : constant String (1 .. Text.Size)
        with Import, Address => Text.Address;
   begin
      return Read_Number (View, Base);
   end Read_Number;

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
         Lua.Engine.Foreign.Release_Context_Control (State, Context);
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
      Item.Boundary_Results.Set_Owner (Item.Memory);
      Item.Foreign_Stack.Set_Owner (Item.Memory);
      Item.Stack_Cells.Set_Owner (Item.Memory);
      Item.C_Close_Links.Set_Owner (Item.Memory);
      Item.Transfer.Results.Set_Owner (Item.Memory);
      --  Registration transfers ownership. Failed vector growth leaves the
      --  allocation local, so release it before propagating Storage_Error.
      begin
         --  Error publication must work after provider refusal. Reserve its
         --  bounded packet while context construction can still fail cleanly.
         Item.Boundary_Results.Reserve_Capacity (2);
         Item.Stack.Reserve_Capacity (1);
         --  A valid lua_toclose cannot request allocator storage. Reserve
         --  the actual base CallInfo and stack-resident closing links
         --  during context construction; it acquires a window only on use.
         Item.Base_C_Frame := New_Frame (State, Item);
         Item.Base_C_Frame.Native_Name :=
           To_Unbounded_String ("@host.base");
         Stacks.Reserve
           (State, Item, Initial_Stack_Size + Extra_Stack);
         Item.Stack_Used := Minimum_C_Stack;
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
            if Item.Base_C_Frame /= null then
               Free_Frame (Item.Base_C_Frame);
            end if;
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

   function Allocate
     (State : in out World; Kind : Heap_Kind;
      Payload_Length : Lua.Storage.Byte_Count := 0) return Object_Access;
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
      State.Current.Failure_Handled := False;
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
      End_Operation (State);
      State.Operation_Start := State.Next_Object;
      State.Operation_Active := True;
   end Begin_Operation;

   procedure End_Operation (State : in out World) is
      Item : Object_Access;
   begin
      while State.String_Root_Head /= null loop
         Item := State.String_Root_Head;
         State.String_Root_Head := Item.String_Root_Next;
         Item.String_Root_Next := null;
         Item.String_Rooted := False;
      end loop;
      State.Operation_Roots.Clear;
      State.Operation_Programs.Clear;
      State.Operation_Active := False;
      State.Operation_Start := State.Next_Object;
   end End_Operation;

   procedure Pin (State : in out World; Item : Value) is
   begin
      Root_Barrier (State, Item);
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
      Code_Barrier (State, Code);
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
      State.Current.Failure_Handled := False;
   end Record_Memory_Error;

   package Collector is
      function Encode (Percent : Lua.Storage.Byte_Count)
                       return Interfaces.Unsigned_8;
      function Apply
        (Encoded : Interfaces.Unsigned_8; Amount : Lua.Storage.Byte_Count)
         return Lua.Storage.Byte_Count;
      procedure Full (State : in out World; Emergency : Boolean := False);
      procedure Advance
        (State : in out World; Work : Positive; Finished : out Boolean);
      procedure Step
        (State : in out World; Extra_Bytes : Lua.Storage.Byte_Count;
         Finished : out Boolean);
      procedure Poll (State : in out World);
      procedure Restart (State : in out World);
      --  Advance performs actual gray traversal/sweeping. Atomic is the
      --  pinned indivisible phase, never a stand-in for an entire cycle.
      procedure Register_Object
        (State : in out World; Item : not null Object_Access);
      procedure Unregister_Object
        (State : in out World; Item : not null Object_Access);
      procedure Register_Program
        (State : in out World; Item : not null Prototype_Access);
      --  Initialize color/age membership after ownership-slot publication.
      procedure Root_Barrier (State : in out World; Item : Value);
      procedure Root_Barrier
        (State : in out World; Item : Object_Access);
      procedure Revive_String
        (State : in out World; Item : not null Object_Access);
      procedure Code_Barrier
        (State : in out World; Item : Prototype_Access);
      procedure Write_Barrier
        (State : in out World; Owner : not null Object_Access; Item : Value);
      procedure Write_Barrier
        (State : in out World; Owner : not null Object_Access;
         Item : Object_Access);
      procedure Back_Barrier
        (State : in out World; Owner : not null Object_Access);
      function Unreachable (State : World; Item : Object_Access)
                            return Boolean;
      procedure Change_Mode
        (State : in out World; Mode : Collector_Mode);
      function Parameter
        (State : in out World; Name : Collector_Parameter;
         Value : Integer_Value := Integer_Value'First) return Integer_Value;
   end Collector;


   function Reserve_Heap_Slot (State : in out World) return Positive;
   function Reserve_Heap_Slot (State : in out World) return Positive is
      Slot : Positive;
      Needed : Ada.Containers.Count_Type;
   begin
      if State.Heap_Free_Head /= 0 then
         Slot := State.Heap_Free_Head;
         State.Heap_Free_Head := State.Heap_Free_Next.Element (Slot);
         State.Heap_Free_Next.Replace_Element (Slot, 0);
         return Slot;
      end if;
      if State.Heap.Last_Index = Positive'Last then
         raise Lua.Storage.Allocation_Error;
      end if;
      Needed := State.Heap.Length + 1;
      --  Neither logical index is published until both ownership arrays
      --  have space. The reserved nil slot is safe if a later typed object
      --  allocation invokes emergency collection before construction ends.
      State.Heap.Reserve_Capacity (Needed);
      State.Heap_Free_Next.Reserve_Capacity (Needed);
      State.Heap.Append (null);
      State.Heap_Free_Next.Append (0);
      return State.Heap.Last_Index;
   end Reserve_Heap_Slot;

   procedure Return_Heap_Slot (State : in out World; Slot : Positive);
   procedure Return_Heap_Slot (State : in out World; Slot : Positive) is
   begin
      State.Heap.Replace_Element (Slot, null);
      State.Heap_Free_Next.Replace_Element (Slot, State.Heap_Free_Head);
      State.Heap_Free_Head := Slot;
   end Return_Heap_Slot;

   procedure Publish_Heap_Object
     (State : in out World; Slot : Positive; Item : not null Object_Access);
   procedure Publish_Heap_Object
     (State : in out World; Slot : Positive; Item : not null Object_Access) is
   begin
      if State.Heap.Element (Slot) /= null then
         raise Program_Error with "publishing occupied heap registry slot";
      end if;
      Item.Registry_Slot := Slot;
      State.Heap.Replace_Element (Slot, Item);
      State.Live_Objects := State.Live_Objects + 1;
      Collector.Register_Object (State, Item);
   end Publish_Heap_Object;

   procedure Release_Heap_Object (State : in out World; Slot : Positive);
   procedure Release_Heap_Object (State : in out World; Slot : Positive) is
      Item : Object_Access := State.Heap.Element (Slot);
   begin
      if Item = null then
         raise Program_Error with "releasing empty heap registry slot";
      end if;
      --  Detach the owning registry edge before object finalization. GC and
      --  provider callbacks can never observe a deallocated stale identity.
      Collector.Unregister_Object (State, Item);
      Return_Heap_Slot (State, Slot);
      Item.Registry_Slot := 0;
      State.Live_Objects := State.Live_Objects - 1;
      if Item.Kind = Table_Object then
         State.Entry_Count :=
           State.Entry_Count - Natural (Item.Members.Length);
      end if;
      Free_Object (State, Item);
   end Release_Heap_Object;

   function Reserve_Program_Slot (State : in out World) return Positive;
   function Reserve_Program_Slot (State : in out World) return Positive is
      Slot : Positive;
      Needed : Ada.Containers.Count_Type;
   begin
      if State.Program_Free_Head /= 0 then
         Slot := State.Program_Free_Head;
         State.Program_Free_Head := State.Program_Free_Next.Element (Slot);
         State.Program_Free_Next.Replace_Element (Slot, 0);
         return Slot;
      end if;
      if State.Programs.Last_Index = Positive'Last then
         raise Lua.Storage.Allocation_Error;
      end if;
      Needed := State.Programs.Length + 1;
      State.Programs.Reserve_Capacity (Needed);
      State.Program_Free_Next.Reserve_Capacity (Needed);
      State.Programs.Append (null);
      State.Program_Free_Next.Append (0);
      return State.Programs.Last_Index;
   end Reserve_Program_Slot;

   procedure Return_Program_Slot (State : in out World; Slot : Positive);
   procedure Return_Program_Slot (State : in out World; Slot : Positive) is
   begin
      State.Programs.Replace_Element (Slot, null);
      State.Program_Free_Next.Replace_Element
        (Slot, State.Program_Free_Head);
      State.Program_Free_Head := Slot;
   end Return_Program_Slot;

   procedure Publish_Program
     (State : in out World; Slot : Positive;
      Item : not null Prototype_Access);
   procedure Publish_Program
     (State : in out World; Slot : Positive;
      Item : not null Prototype_Access) is
   begin
      if State.Programs.Element (Slot) /= null then
         raise Program_Error with "publishing occupied code registry slot";
      end if;
      Item.Registry_Slot := Slot;
      State.Programs.Replace_Element (Slot, Item);
      State.Live_Programs := State.Live_Programs + 1;
      Collector.Register_Program (State, Item);
   end Publish_Program;

   procedure Release_Registered_Program
     (State : in out World; Item : in out Prototype_Access) is
   begin
      if Item = null then
         return;
      elsif Item.Registry_Slot = 0 or else
        State.Programs.Element (Item.Registry_Slot) /= Item
      then
         raise Program_Error with "invalid owned code registry slot";
      end if;
      Return_Program_Slot (State, Item.Registry_Slot);
      State.Live_Programs := State.Live_Programs - 1;
      Item.Registry_Slot := 0;
      Release_Program (Item);
   end Release_Registered_Program;

   package body Collector is separate;

   function Encode_Collector_Parameter
     (Value : Lua.Storage.Byte_Count) return Interfaces.Unsigned_8 is
     (Collector.Encode (Value));

   function Apply_Collector_Parameter
     (Encoded : Interfaces.Unsigned_8; Value : Lua.Storage.Byte_Count)
      return Lua.Storage.Byte_Count is
     (Collector.Apply (Encoded, Value));

   procedure Advance_Collection
     (State : in out World; Work : Positive; Finished : out Boolean) is
   begin
      Collector.Advance (State, Work, Finished);
   end Advance_Collection;

   procedure Step_Collection
     (State : in out World; Extra_Bytes : Lua.Storage.Byte_Count;
      Finished : out Boolean) is
   begin
      Collector.Step (State, Extra_Bytes, Finished);
   end Step_Collection;

   procedure Poll_Collection (State : in out World) is
   begin
      Collector.Poll (State);
   end Poll_Collection;

   procedure Restart_Collection (State : in out World) is
   begin
      Collector.Restart (State);
   end Restart_Collection;

   procedure Set_Collector_Mode
     (State : in out World; Mode : Collector_Mode) is
   begin
      Collector.Change_Mode (State, Mode);
   end Set_Collector_Mode;

   function Collector_Parameter_Value
     (State : in out World; Name : Collector_Parameter;
      Value : Integer_Value := Integer_Value'First) return Integer_Value is
   begin
      return Collector.Parameter (State, Name, Value);
   end Collector_Parameter_Value;

   procedure Root_Barrier (State : in out World; Item : Value) is
   begin
      Collector.Root_Barrier (State, Item);
   end Root_Barrier;

   procedure Root_Barrier (State : in out World; Item : Object_Access) is
   begin
      Collector.Root_Barrier (State, Item);
   end Root_Barrier;

   procedure Write_Barrier
     (State : in out World; Owner : not null Object_Access; Item : Value) is
   begin
      Collector.Write_Barrier (State, Owner, Item);
   end Write_Barrier;

   procedure Write_Barrier
     (State : in out World; Owner : not null Object_Access;
      Item : Object_Access) is
   begin
      Collector.Write_Barrier (State, Owner, Item);
   end Write_Barrier;

   procedure Back_Barrier
     (State : in out World; Owner : not null Object_Access) is
   begin
      Collector.Back_Barrier (State, Owner);
   end Back_Barrier;

   procedure Code_Barrier
     (State : in out World; Item : Prototype_Access) is
   begin
      Collector.Code_Barrier (State, Item);
   end Code_Barrier;

   procedure Root_Barrier (State : in out World; Items : Values.Vector) is
   begin
      for Item of Items loop
         Collector.Root_Barrier (State, Item);
      end loop;
   end Root_Barrier;

   procedure Root_Barrier
     (State : in out World; Items : Scalar_Values.Vector) is
   begin
      for Item of Items loop
         Collector.Root_Barrier (State, Item);
      end loop;
   end Root_Barrier;

   procedure Root_Barrier (State : in out World; Items : Objects.Vector) is
   begin
      for Item of Items loop
         Collector.Root_Barrier (State, Item);
      end loop;
   end Root_Barrier;

   procedure Store_Cell
     (State : in out World; Cell : not null Object_Access; Item : Value) is
   begin
      if Cell.Kind /= Cell_Object then
         raise Program_Error with "cell store requires an actual binding";
      end if;
      Write_Barrier (State, Cell, Item);
      Cell.Cell_Value := Item;
   end Store_Cell;

   procedure Shrink_Frame_Cache (Context : not null Context_Access);
   procedure Shrink_Frame_Cache (Context : not null Context_Access) is
      Kept : Frame_Access := Context.Cache_Head;
      Discarded : Frame_Access;
      Cursor : Frame_Access := Context.Cache_Head;
      Count : Natural := 0;
   begin
      --  Validate before releasing the first record. A corrupt borrowed
      --  frame or cycle must not produce a partially detached owning list.
      while Cursor /= null loop
         if Count = Context.Cache_Count or else
           Cursor.Lifecycle /= Available or else Cursor.Context /= Context
         then
            raise Program_Error with
              "invalid cache ownership while shrinking";
         end if;
         Count := Count + 1;
         Cursor := Cursor.Cache_Next;
      end loop;
      if Count /= Context.Cache_Count then
         raise Program_Error with "cache count mismatch while shrinking";
      end if;
      --  Pinned lstate.c keeps the first unused CallInfo and frees alternate
      --  subsequent entries. Each released Ada record finalizes its actual
      --  retained packet/builder capacity through the selected provider.
      while Kept /= null and then Kept.Cache_Next /= null loop
         if Kept.Lifecycle /= Available or else Kept.Context /= Context then
            raise Program_Error with "invalid cached frame during shrinking";
         end if;
         Discarded := Kept.Cache_Next;
         if Discarded.Lifecycle /= Available or else
           Discarded.Context /= Context
         then
            raise Program_Error with "invalid released cache frame owner";
         end if;
         Kept.Cache_Next := Discarded.Cache_Next;
         Context.Cache_Count := Context.Cache_Count - 1;
         Discarded.Cache_Next := null;
         Free_Frame (Discarded);
         Kept := Kept.Cache_Next;
      end loop;
   end Shrink_Frame_Cache;


   procedure Shrink_Context_Storage
     (State : in out World; Context : not null Context_Access)
   is
      Maximum : constant Positive := Lua.Runtime_Configuration.Maximum_Stack;
      In_Use : Natural := Natural'Max
        (Context.Stack_Used, Natural'Max
           (Context.Foreign_Top, Context.Host_Stack_Top));
      Threshold, Target : Natural;
   begin
      if State.GC.Emergency then
         return;
      end if;
      --  A small current child can overlap a wide parent's dead tail during
      --  execution. Shrinking is different: every ancestor still needs its
      --  actual reserved window on return, so all real ends participate.
      for Activation of Context.Stack loop
         if Activation.Has_Stack_Window then
            In_Use := Natural'Max
              (In_Use, Activation.Stack_Base +
                 Activation.Stack_Window_Length);
            if Activation.Warning_Borrow_Depth /= 0 then
               In_Use := Natural'Max (In_Use, Activation.Stack_Live_Top);
            end if;
         end if;
      end loop;
      Shrink_Frame_Cache (Context);
      if In_Use > Maximum - 2 then
         return;
      end if;
      --  Lua stackinuse counts an exclusive top plus an additional row.
      --  Our offsets are inclusive, so the corresponding adjustment is +2.
      In_Use := Natural'Max (Minimum_C_Stack, In_Use + 2);
      Threshold :=
        (if In_Use > Maximum / 3 then Maximum else In_Use * 3);
      if Context.Stack_Allocated_Bound <= Threshold then
         return;
      end if;
      Target := (if In_Use > Maximum / 2 then Maximum else In_Use * 2);
      if Lua.Engine.Stacks.Try_Shrink (Context, Target + Extra_Stack) then
         --  Only a successful physical resize repairs the semantic bound.
         --  Relabeling a retained MAX+200 reserve would falsify both memory
         --  accounting and the next stack-overflow transition.
         Context.Stack_Allocated_Bound := Target;
         Context.Stack_Error_Phase := Normal_Stack;
      end if;
   end Shrink_Context_Storage;


   procedure Request_Process_Exit
     (State : in out World; Code : Interfaces.C.int;
      Close_State : Boolean) is
   begin
      State.Exit_Code := Code;
      State.Exit_Close_State := Close_State;
      State.Exit_Phase := Exit_Requested;
   end Request_Process_Exit;


   procedure Check_Root_Owner
     (State : in out World; Items : Values.Vector);
   procedure Check_Root_Owner
     (State : in out World; Items : Values.Vector) is
   begin
      if Items.Owner_Of /= null and then Items.Owner_Of /=
        Lua.Storage.Reference (State.Memory)
      then
         raise Program_Error with "root packet belongs to another universe";
      end if;
   end Check_Root_Owner;

   procedure Append_Root
     (State : in out World; Target : in out Values.Vector; Item : Value) is
   begin
      Check_Root_Owner (State, Target);
      Target.Set_Owner (Lua.Storage.Reference (State.Memory));
      Root_Barrier (State, Item);
      Target.Append (Item);
   end Append_Root;

   procedure Append_Root
     (State : in out World; Target : in out Values.Vector;
      Items : Values.Vector) is
   begin
      Check_Root_Owner (State, Target);
      Check_Root_Owner (State, Items);
      Target.Set_Owner (Lua.Storage.Reference (State.Memory));
      Root_Barrier (State, Items);
      Target.Append (Items);
   end Append_Root;

   procedure Replace_Root
     (State : in out World; Target : in out Values.Vector;
      Index : Positive; Item : Value) is
   begin
      Check_Root_Owner (State, Target);
      if Index > Natural (Target.Length) then
         raise Constraint_Error with "root replacement outside packet";
      end if;
      Root_Barrier (State, Item);
      Target.Replace_Element (Index, Item);
   end Replace_Root;

   procedure Copy_Roots
     (State : in out World; Target : in out Values.Vector;
      Source : Values.Vector) is
   begin
      Check_Root_Owner (State, Target);
      Check_Root_Owner (State, Source);
      if Target'Address = Source'Address then
         return;
      end if;
      Target.Set_Owner (Lua.Storage.Reference (State.Memory));
      Root_Barrier (State, Source);
      --  Capacity is reserved before clearing the old publication. Values
      --  are scalar discriminated records, so the following append cannot
      --  allocate/finalize user code once its complete space is available.
      Target.Reserve_Capacity (Source.Length);
      Target.Clear;
      Target.Append (Source);
   end Copy_Roots;

   procedure Move_Roots
     (State : in out World; Target, Source : in out Values.Vector) is
   begin
      Check_Root_Owner (State, Target);
      Check_Root_Owner (State, Source);
      if Target'Address = Source'Address then
         return;
      end if;
      Target.Set_Owner (Lua.Storage.Reference (State.Memory));
      Source.Set_Owner (Lua.Storage.Reference (State.Memory));
      Root_Barrier (State, Source);
      Values.Move (Target, Source);
      --  The owned transfer itself cannot allocate. Rebinding its now empty
      --  source is explicit and allocation-free; no later caller must guess
      --  whether a prior move silently stripped its allocation policy.
      Source.Set_Owner (Lua.Storage.Reference (State.Memory));
   end Move_Roots;

   procedure Append_Object_Edge
     (State : in out World; Owner : not null Object_Access;
      Target : in out Objects.Vector; Item : Object_Access) is
   begin
      if Target.Owner_Of /= null and then Target.Owner_Of /=
        Lua.Storage.Reference (State.Memory)
      then
         raise Program_Error with "capture vector belongs to another owner";
      end if;
      Target.Set_Owner (Lua.Storage.Reference (State.Memory));
      Write_Barrier (State, Owner, Item);
      Target.Append (Item);
   end Append_Object_Edge;

   procedure Replace_Object_Edge
     (State : in out World; Owner : not null Object_Access;
      Target : in out Objects.Vector; Index : Positive;
      Item : Object_Access) is
   begin
      if Target.Owner_Of /= Lua.Storage.Reference (State.Memory) then
         raise Program_Error with "capture vector belongs to another owner";
      elsif Index > Natural (Target.Length) then
         raise Constraint_Error with "capture replacement outside vector";
      end if;
      Write_Barrier (State, Owner, Item);
      Target.Replace_Element (Index, Item);
   end Replace_Object_Edge;


   function Allocate
     (State : in out World; Kind : Heap_Kind;
      Payload_Length : Lua.Storage.Byte_Count := 0) return Object_Access
   is
      Item : Object_Access;
      Slot : Natural := 0;
      Retried : Boolean := False;
      Before : Lua.Storage.Byte_Count;
   begin
      if State.Live_Objects >= State.Bounds.Heap_Objects or else
        State.Next_Object = Positive'Last
      then
         Fail (State, "heap object limit exceeded", Resource => True);
      end if;
      loop
         begin
            Slot := Reserve_Heap_Slot (State);
            exit;
         exception
            when Lua.Storage.Allocation_Error =>
               if not Retry_Allocation (State, Retried) then
                  raise;
               end if;
         end;
      end loop;
      --  The ownership row exists before a typed allocation can invoke the
      --  provider or emergency collection. Its null payload is not an edge;
      --  success publishes one completed, owner-bound record exactly once.
      Retried := False;
      loop
         begin
            Before := Lua.Storage.Statistics (State.Memory).Raw_Bytes;
            Item := new (Lua.Storage.Handle (State.Memory))
              Heap_Object (Kind, Payload_Length);
            Item.Allocation_Bytes :=
              Lua.Storage.Statistics (State.Memory).Raw_Bytes - Before;
            exit;
         exception
            when Lua.Storage.Allocation_Error =>
               if not Retry_Allocation (State, Retried) then
                  raise;
               end if;
         end;
      end loop;
      --  A controlled typed object can have a compiler finalization prefix.
      --  Its visible record address is not necessarily the pool payload's
      --  start, so never feed Item.all'Address to a raw-header accessor. The
      --  successful request's actual provider delta includes that prefix
      --  and allocator overhead; no other growth occurs between these reads.
      case Kind is
         when Userdata_Object =>
            Item.Uservalues.Set_Owner (Lua.Storage.Reference (State.Memory));
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
      Publish_Heap_Object (State, Slot, Item);
      return Item;
   exception
      when others =>
         if Slot /= 0 then
            if State.Heap.Element (Slot) = Item and Item /= null then
               Release_Heap_Object (State, Slot);
            else
               Return_Heap_Slot (State, Slot);
               Free_Object (State, Item);
            end if;
         end if;
         raise;
   end Allocate;


   function New_Cell (State : in out World; Item : Value) return Object_Access
   is
      Cell : constant Object_Access := Allocate (State, Cell_Object);
   begin
      Store_Cell (State, Cell, Item);
      return Cell;
   end New_Cell;

   function New_Thread
     (State : in out World; Entry_Function : Value;
      Parent : Context_Access := null) return Value
   is
      Id : constant Context_Id := Create_Context (State);
      Thread : Object_Access;
      Context : constant Context_Access := State.Contexts (Positive (Id));
      Origin : constant Context_Access :=
        (if Parent = null then State.Current else Parent);
   begin
      Lua.Engine.Foreign.Prepare_Thread_Surface (State, Id);
      Thread := Allocate (State, Thread_Object);
      Thread.Context_Index := Positive (Id);
      Context.Thread := Thread;
      Root_Barrier (State, Entry_Function);
      Context.Entry_Function := Entry_Function;
      Context.Host_Owned := False;
      --  lstate.c:lua_newthread copies the actual hook dispatcher pointer,
      --  mask and base count, then resets the countdown. A Lua dispatcher is
      --  inherited without its thread-keyed callback entry: gethook can
      --  therefore return nil plus the inherited mask/count, and registering
      --  a mapping later activates those same controls. Foreign dispatchers
      --  retain their non-owning scalar trampoline/callback identities.
      Context.Hook := Origin.Hook;
      Context.Lua_Hook_Installed := Origin.Lua_Hook_Installed;
      Context.Hook_Mask := Origin.Hook_Mask;
      Context.Foreign_Hook := Origin.Foreign_Hook;
      Context.Foreign_Hook_Mask := Origin.Foreign_Hook_Mask;
      Context.Hook_Count := Origin.Hook_Count;
      Context.Hook_Reported_Count := Origin.Hook_Reported_Count;
      Context.Hook_Remaining := Origin.Hook_Count;
      return (Thread_Kind, Thread);
   exception
      when others =>
         --  Until publication there is no Lua owner for this registry slot.
         --  Failed allocation must not leave an immortal host-owned context.
         declare
            Abandoned : Context_Access := Context;
         begin
            Destroy_Frames (State, Abandoned);
            Release_Foreign_Context (State, Abandoned);
            Free_Context (Abandoned);
            State.Contexts.Replace_Element (Positive (Id), null);
         end;
         raise;
   end New_Thread;

   procedure Clear_Frame (Item : not null Frame_Access);
   procedure Clear_Frame (Item : not null Frame_Access) is
      procedure Clear_Packet (Packet : in out Values.Vector);
      procedure Clear_Packet (Packet : in out Values.Vector) is
      begin
         Packet.Clear;
         Packet.Set_Owner (Item.Memory);
      end Clear_Packet;
   begin
      --  All exits, including abandoned coroutine teardown, detach actual
      --  captured cells before reusing a register window. Cells retain their
      --  authoritative value independently of this activation's storage.
      Lua.Engine.Canonical.Close_Cells (Item, 0);

      --  Clear logical values, retaining managed capacity. In particular,
      --  shrinking the outer packet arena would finalize nested vectors and
      --  discard the buffers needed to report a later allocation refusal.
      Item.Native_Arguments.Clear;
      Item.Native_Results.Clear;
      Item.Error_Packet.Clear;
      Item.Native_Captures.Clear;
      Item.Native_Buffer.Clear;
      Item.Call_Name_Bytes.Clear;
      for Index in Item.Slots.First_Index .. Item.Slots.Last_Index loop
         Item.Slots.Update_Element (Index, Clear_Packet'Access);
      end loop;
      Item.Active_Registers := 0;
      Item.Canonical_Registers.Clear;
      Item.Canonical_Cells.Clear;
      Item.Varargs.Clear;
      Item.Closers.Clear;
      Item.Unwind_Live.Clear;
      Item.Unwind_Results.Clear;

      --  Allocation-free delivery moves ownership out of a source packet,
      --  leaving it deliberately unbound. Rebind every emptied component
      --  before reuse; Set_Owner is a no-op for an existing matching owner.
      Item.Native_Arguments.Set_Owner (Item.Memory);
      Item.Native_Results.Set_Owner (Item.Memory);
      Item.Error_Packet.Set_Owner (Item.Memory);
      Item.Native_Captures.Set_Owner (Item.Memory);
      Item.Varargs.Set_Owner (Item.Memory);
      Item.Unwind_Results.Set_Owner (Item.Memory);

      --  Never assign a default Frame aggregate: controlled component
      --  assignment would replace owned buffers rather than reusing them.
      --  Each pointer, value and scheduler phase is reset explicitly so an
      --  available frame is not a hidden strong edge into the Lua heap.
      Item.Is_Native := False;
      Item.Native_Name := Null_Unbounded_String;
      Item.Native_Id := Print_Function;
      Item.Native_Builtin_Direct := False;
      Item.Native_Results_Published := False;
      Item.Native_Return_First := 0;
      Item.Result_Failure_Class := No_Failure;
      Item.Result_Handler_Called := False;
      Item.Native_Self := null;
      Item.Native_Stage := 0;
      Item.Native_Index := 0;
      Item.Native_Aux := 0;
      Item.Native_Operator := Lua.Lexers.End_Of_Input;
      Item.C_Closing_Level := 0;
      Item.Foreign_Handler := System.Null_Address;
      Item.Foreign_Ticket := 0;
      Item.Foreign_Continuation := System.Null_Address;
      Item.Foreign_KContext := 0;
      Item.Foreign_KStatus := 0;
      Item.Foreign_Yield_Count := 0;
      Item.Foreign_Suspended := False;
      Item.Foreign_Wanted := 0;
      Item.Foreign_Protected := False;
      Item.Error_Guard_Owner := null;
      Item.Deferred_Error_Head := null;
      Item.Deferred_Error_Next := null;
      Item.Deferred_Error_Count := 0;
      Item.Deferred_Error_Traceback := False;
      Item.Pending_Error_Transfer := False;
      Item.Error_Previous_Prefix := 0;
      Item.Warning_Phase := No_Pending_Warning;
      Item.Warning_Previous := null;
      Item.Warning_Window := null;
      Item.Warning_Borrow_Depth := 0;
      Item.Warning_Ticket := 0;
      Item.Warning_Message := (others => <>);
      Item.Warning_Root := Nil_Value;
      Item.Warning_To_Continue := False;
      Item.Warning_Handler := System.Null_Address;
      Item.Warning_Data := System.Null_Address;
      Item.Warning_Previous_Base := 0;
      Item.Warning_Previous_Top := 0;
      Item.Warning_Previous_Frame := null;
      Item.Warning_Failed := False;
      Item.Foreign_Base := 0;
      Item.Foreign_Previous_Base := 0;
      Item.Foreign_Previous_Frame := null;
      Item.Foreign_Entered := False;
      Item.Call_Site := (others => 1);
      Item.Code := null;
      Item.PC := 1;
      Item.Scope := null;
      Item.Scope_Depth := 0;
      Item.Canonical_Top := 0;
      Item.Canonical_GC_Top := 0;
      Item.Canonical_Pending := No_Canonical_Result;
      Item.Canonical_Base := 0;
      Item.Canonical_Wanted := 0;
      Item.Canonical_Test := False;
      Item.Canonical_Concat_Last := 0;
      Item.Stack_Base := 0;
      Item.Stack_Window_Length := 0;
      Item.Saved_Stack_Used := 0;
      Item.Call_Base := 0;
      Item.Has_Stack_Window := False;
      Item.Hidden_Varargs := False;
      Item.Vararg_Base := 0;
      Item.Vararg_Count := 0;
      Item.Stack_Live_Top := 0;
      Item.Saved_Foreign_Top := 0;
      Item.Previous_Stack_Window := null;
      Item.Vararg_Table := null;
      Item.Completion := Deliver_Results;
      Item.Finalizer_Phase := Choosing_Finalizer;
      Item.Finalizer_Charge := False;
      Item.Return_To := 0;
      Item.Protection := 0;
      Item.Message_Handler := Nil_Value;
      Item.Retain_On_Failure := False;
      Item.Slot_Cost := 0;
      Item.Native_Charge := False;
      Item.Message_Charge := False;
      Item.Unwind_Charge := False;
      Item.Blocks_Yield := False;
      Item.Callee := Nil_Value;
      Item.Is_C_Hook_Transport := False;
      Item.Is_C_Collector_Transport := False;
      Item.Is_Finalizer_Call := False;
      Item.Logically_Unwound := False;
      Item.Is_Tail_Call := False;
      Item.Call_Metamethod_Count := 0;
      Item.Native_Tail_State := No_Native_Tail;
      Item.Call_Name := Null_Unbounded_String;
      Item.Name_Kind := Null_Unbounded_String;
      Item.Transfer_Count := 0;
      Item.Transfer_First := 1;
      Item.Entry_Hook_Done := False;
      Item.Return_Hook_Done := False;
      Item.External_Return_Pending := False;
      Item.External_Return_Independent := False;
      Item.Hook_Line := -1;
      Item.Hook_PC := 0;
      Item.Last_Executed_PC := 0;
      Item.Line_Hook_Checked := False;
      Item.Unwind := No_Unwind;
      Item.Unwind_Owner := null;
      Item.Unwind_Depth := 0;
      Item.Unwind_PC := 0;
      Item.Unwind_Error := Nil_Value;
      Item.Unwind_Failure_Class := Language_Failure;
      Item.Unwind_Handler_Called := False;
      Item.Unwind_Has_Error := False;
      Item.Unwind_Previous_Prefix := 0;
   end Clear_Frame;

   function New_Frame
     (State : in out World; Context : not null Context_Access)
      return Frame_Access
   is
      Item : Frame_Access;
      Retried : Boolean := False;
   begin
      if Context.Memory /= Lua.Storage.Reference (State.Memory) then
         raise Program_Error with "activation belongs to another universe";
      end if;
      if Context.C_Reset_Active and then Context.Reset_Frame_Head /= null then
         Item := Context.Reset_Frame_Head;
         if Item.Lifecycle /= Available or else Item.Context /= Context or
           else not Item.Reset_Reserve
         then
            raise Program_Error with "invalid reserved reset activation";
         end if;
         Context.Reset_Frame_Head := Item.Cache_Next;
         Context.Reset_Frame_Count := Context.Reset_Frame_Count - 1;
         Item.Cache_Next := null;
         Item.Lifecycle := Active;
         return Item;
      elsif Context.Cache_Head /= null then
         Item := Context.Cache_Head;
         if Item.Lifecycle /= Available or else Item.Context /= Context then
            raise Program_Error with "invalid cached activation owner";
         end if;
         Context.Cache_Head := Item.Cache_Next;
         Context.Cache_Count := Context.Cache_Count - 1;
         Item.Cache_Next := null;
         Item.Lifecycle := Active;
         return Item;
      end if;
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
      --  Owner binding is allocation-free. The caller publishes this new
      --  frame before filling parameters/captures or growing any component.
      Item.Context := Context;
      Item.Memory := Context.Memory;
      Item.Native_Buffer.Set_Owner (Item.Memory);
      Item.Call_Name_Bytes.Set_Owner (Item.Memory);
      Item.Native_Arguments.Set_Owner (Item.Memory);
      Item.Native_Results.Set_Owner (Item.Memory);
      Item.Error_Packet.Set_Owner (Item.Memory);
      Item.Native_Captures.Set_Owner (Item.Memory);
      Item.Slots.Set_Owner (Item.Memory);
      Item.Varargs.Set_Owner (Item.Memory);
      Item.Closers.Set_Owner (Item.Memory);
      Item.Unwind_Live.Set_Owner (Item.Memory);
      Item.Unwind_Results.Set_Owner (Item.Memory);
      Item.Canonical_Registers.Set_Owner (Item.Memory);
      Item.Canonical_Cells.Set_Owner (Item.Memory);
      return Item;
   end New_Frame;

   procedure Prepare_Reset_Frames
     (State : in out World; Context : not null Context_Access)
   is
      Item : Frame_Access;
   begin
      Context.Stack.Reserve_Capacity
        (Context.Stack.Length +
           Ada.Containers.Count_Type (Context.Deferred_Error_Depth +
             Reset_Continuation_Frames + 1));
      while Context.Reset_Frame_Count < Reset_Continuation_Frames loop
         Item := New_Frame (State, Context);
         begin
            --  These are actual continuation-owned argument/result owners,
            --  not copies of live stack values. Three close arguments plus
            --  protected success/error pairs fit without refusal-time growth.
            Item.Native_Arguments.Reserve_Capacity (4);
            Item.Native_Results.Reserve_Capacity (4);
            Item.Error_Packet.Reserve_Capacity (2);
            Item.Unwind_Results.Reserve_Capacity (2);
            Item.Native_Captures.Reserve_Capacity (4);
            Item.Call_Name_Bytes.Set_Value ("__close");
            Item.Call_Name_Bytes.Clear;
            Item.Reset_Reserve := True;
            Return_Frame (Item);
         exception
            when others =>
               Return_Frame (Item);
               raise;
         end;
      end loop;
   end Prepare_Reset_Frames;

   function New_Frame (State : in out World) return Frame_Access is
   begin
      if State.Current = null then
         raise Program_Error with "activation requires an explicit context";
      end if;
      return New_Frame (State, State.Current);
   end New_Frame;

   procedure Prepare_Private_Registers
     (Item : not null Frame_Access; Count : Natural)
   is
      Previous : constant Natural := Natural (Item.Slots.Length);
      procedure Bind (Packet : in out Values.Vector);
      procedure Bind (Packet : in out Values.Vector) is
      begin
         Packet.Set_Owner (Item.Memory);
      end Bind;
   begin
      if Item.Lifecycle /= Active then
         raise Program_Error with "private registers require borrowed frame";
      end if;
      if Count > Previous then
         Item.Slots.Set_Length (Ada.Containers.Count_Type (Count));
         for Index in Previous + 1 .. Count loop
            Item.Slots.Update_Element (Index, Bind'Access);
         end loop;
      end if;
      Item.Active_Registers := Count;
   end Prepare_Private_Registers;

   procedure Return_Frame (Item : in out Frame_Access) is
      Context : Context_Access;
   begin
      if Item = null then
         return;
      elsif Item.Lifecycle /= Active or else Item.Context = null then
         raise Program_Error with "activation is not borrowed";
      end if;
      Context := Item.Context;
      if Item.Deferred_Error_Head /= null then
         raise Program_Error with "returning owned deferred error scopes";
      end if;
      Item.Lifecycle := Retiring;
      Clear_Frame (Item);
      if Context.Base_C_Frame = Item then
         --  The base CallInfo has its own lifetime, equal to the context's.
         --  Keep its empty reserved metadata outside the ordinary cache so
         --  collection cannot shrink away allocation-free C registration.
         Item.Lifecycle := Active;
         Item := null;
         return;
      end if;
      if Item.Reset_Reserve then
         Item.Cache_Next := Context.Reset_Frame_Head;
         Item.Lifecycle := Available;
         Context.Reset_Frame_Head := Item;
         Context.Reset_Frame_Count := Context.Reset_Frame_Count + 1;
         Item := null;
         return;
      end if;
      --  This link publishes only an empty record. Cached frames are never
      --  traced as roots, and no user callback runs during this transition.
      Item.Cache_Next := Context.Cache_Head;
      Item.Lifecycle := Available;
      Context.Cache_Head := Item;
      Context.Cache_Count := Context.Cache_Count + 1;
      Item := null;
   end Return_Frame;

   procedure Destroy_Frames
     (State : in out World; Context : not null Context_Access)
   is
      Item : Frame_Access;
      Deferred : Frame_Access;
   begin
      if Context.Memory /= Lua.Storage.Reference (State.Memory) then
         raise Program_Error with "teardown belongs to another universe";
      end if;
      --  Physical context destruction can follow reclamation of its dead
      --  cells: reusable heap slots impose no object dependency order.
      --  Surviving cells already own their authoritative values. Discard
      --  associations without reading them before Clear_Frame would detach
      --  them into scalar slots that are themselves about to be destroyed.
      Lua.Engine.Stacks.Clear_Range
        (Context, 1, Natural (Context.Stack_Cells.Length));
      --  Teardown bypasses recycling. Remove each owning edge before freeing
      --  its record, so no context list can retain a deallocated identity.
      while not Context.Stack.Is_Empty loop
         Item := Context.Stack.Last_Element;
         Context.Stack.Delete_Last;
         if Context.Base_C_Frame = Item then
            Context.Base_C_Frame := null;
         end if;
         --  A host abort may destroy a context while C error transfer owns
         --  detached, already retired scopes. No callback can execute here;
         --  remove every intrusive owner before freeing its record.
         while Item.Deferred_Error_Head /= null loop
            Deferred := Item.Deferred_Error_Head;
            Item.Deferred_Error_Head := Deferred.Deferred_Error_Next;
            if Deferred.Deferred_Error_Head /= null then
               raise Program_Error with "nested deferred scope ownership";
            end if;
            Deferred.Deferred_Error_Next := null;
            Clear_Frame (Deferred);
            Free_Frame (Deferred);
         end loop;
         Clear_Frame (Item);
         Free_Frame (Item);
      end loop;
      if Context.Base_C_Frame /= null then
         Free_Frame (Context.Base_C_Frame);
      end if;
      while Context.Cache_Head /= null loop
         Item := Context.Cache_Head;
         Context.Cache_Head := Item.Cache_Next;
         Context.Cache_Count := Context.Cache_Count - 1;
         Item.Cache_Next := null;
         Free_Frame (Item);
      end loop;
      while Context.Reset_Frame_Head /= null loop
         Item := Context.Reset_Frame_Head;
         Context.Reset_Frame_Head := Item.Cache_Next;
         Context.Reset_Frame_Count := Context.Reset_Frame_Count - 1;
         Item.Cache_Next := null;
         Free_Frame (Item);
      end loop;
      --  Scheduler yield has already excluded an inactive context's native
      --  depth from the active resumer chain. Reclaim only its own counters;
      --  subtracting again would corrupt an unrelated running context.
      Context.Stack_Slots := 0;
      Context.Deferred_Error_Depth := 0;
      Context.Error_Recovery_Pending := False;
      Context.Error_Recovery_Floor := 0;
      Context.Native_Depth := 0;
      Context.Non_Yieldable := 0;
      Context.Message_Depth := 0;
      Context.Cleanup_Depth := 0;
      Context.Hook_Frame := null;
      Context.Hook_Suspended := False;
      Context.Hook_Yield_Pending := False;
      Context.Foreign_Activation := null;
      Context.Base_C_Frame := null;
      Context.Closing_Stack_Prefix := 0;
      Context.Stack_Window := null;
   end Destroy_Frames;

   function New_Program (State : in out World) return Prototype_Access is
      Retried : Boolean := False;
      Item : Prototype_Access;
      Slot : Natural := 0;
   begin
      loop
         begin
            Slot := Reserve_Program_Slot (State);
            exit;
         exception
            when Lua.Storage.Allocation_Error =>
               if not Retry_Allocation (State, Retried) then
                  raise;
               end if;
         end;
      end loop;
      Retried := False;
      loop
         begin
            Item := new (Lua.Storage.Handle (State.Memory)) Prototype;
            exit;
         exception
            when Lua.Storage.Allocation_Error =>
               if not Retry_Allocation (State, Retried) then
                  raise;
               end if;
         end;
      end loop;
      Item.Code.Set_Owner (Lua.Storage.Reference (State.Memory));
      Item.Parameters.Set_Owner (Lua.Storage.Reference (State.Memory));
      Item.Capture_Symbols.Set_Owner (Lua.Storage.Reference (State.Memory));
      Item.Names.Set_Owner (Lua.Storage.Reference (State.Memory));
      Item.Canonical_Constants.Set_Owner
        (Lua.Storage.Reference (State.Memory));
      Publish_Program (State, Slot, Item);
      return Item;
   exception
      when others =>
         if Slot /= 0 then
            if State.Programs.Element (Slot) = Item and Item /= null then
               Release_Registered_Program (State, Item);
            else
               Return_Program_Slot (State, Slot);
               Release_Program (Item);
            end if;
         end if;
         raise;
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

   procedure String_Work (State : in out World; Count : Natural);
   procedure Grow_String_Index (State : in out World);

   procedure String_Work (State : in out World; Count : Natural) is
   begin
      if State.Policy /= Bounded or else not State.Memory_Ready then
         return;
      elsif Count > State.Bounds.Instructions -
        Natural'Min (State.Steps, State.Bounds.Instructions)
      then
         Fail (State, "instruction limit exceeded", Resource => True);
      end if;
      State.Steps := State.Steps + Count;
   end String_Work;

   procedure Grow_String_Index (State : in out World) is
      Buckets : Objects.Vector;
      Retried : Boolean := False;
      Size : constant Positive :=
        (if State.Short_Strings.Is_Empty then 128
         else State.Short_Strings.Last_Index * 2);
      Item, Next : Object_Access;
      Target : Positive;
   begin
      Buckets.Set_Owner (Lua.Storage.Reference (State.Memory));
      String_Work (State, Size);
      String_Work (State, State.Short_String_Count);
      --  Allocate the replacement first. Refusal/emergency collection may
      --  unlink dead strings from the old chains; no chain is rewritten
      --  until allocation has succeeded and the complete new index exists.
      loop
         begin
            Buckets.Reserve_Capacity (Ada.Containers.Count_Type (Size));
            exit;
         exception
            when Lua.Storage.Allocation_Error =>
               if not Retry_Allocation (State, Retried) then raise; end if;
         end;
      end loop;
      for Index in 1 .. Size loop
         Buckets.Append (null);
      end loop;
      for Head of State.Short_Strings loop
         Item := Head;
         while Item /= null loop
            Next := Item.Intern_Next;
            Target := Natural
              (Item.String_Hash mod Interfaces.Unsigned_64 (Size)) + 1;
            Item.Intern_Next := Buckets (Target);
            Buckets.Replace_Element (Target, Item);
            Item := Next;
         end loop;
      end loop;
      Objects.Move (State.Short_Strings, Buckets);
   end Grow_String_Index;

   function New_String (State : in out World; Text : String) return Value is
      Item : Object_Access;
      Retried : Boolean := False;
      Hash : Interfaces.Unsigned_64;
      Bucket : Positive;
   begin
      if Text'Length = Natural'Last then
         Fail (State, "string length overflow");
      elsif Text'Length > State.Bounds.String_Bytes then
         Fail (State, "string byte limit exceeded", Resource => True);
      end if;
      Hash := Tables.Hash_Bytes (Text);
      if Text'Length <= 40 then
         if not State.Short_Strings.Is_Empty then
            Bucket := Natural
              (Hash mod Interfaces.Unsigned_64
                 (State.Short_Strings.Length)) + 1;
            Item := State.Short_Strings (Bucket);
            while Item /= null loop
               String_Work (State, 1);
               if Item.String_Hash = Hash and then Item.Bytes = Text then
                  Collector.Revive_String (State, Item);
                  if State.Operation_Active and then not Item.String_Rooted
                  then
                     Item.String_Root_Next := State.String_Root_Head;
                     State.String_Root_Head := Item;
                     Item.String_Rooted := True;
                  end if;
                  return (String_Kind, Item);
               end if;
               Item := Item.Intern_Next;
            end loop;
         end if;
         if State.Short_String_Count >= State.Short_Strings.Last_Index then
            Grow_String_Index (State);
         end if;
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
      Item.String_Hash := Hash;
      if Text'Length <= 40 then
         Bucket := Natural
           (Hash mod Interfaces.Unsigned_64 (State.Short_Strings.Length)) + 1;
         Item.Intern_Next := State.Short_Strings (Bucket);
         State.Short_Strings.Replace_Element (Bucket, Item);
         Item.Interned := True;
         State.Short_String_Count := State.Short_String_Count + 1;
      end if;
      return (String_Kind, Item);
   end New_String;

   function New_External_String
     (State : in out World; Address : System.Address; Size : Natural;
      Allocator : Lua.Storage.Allocation_Function;
      Data : System.Address) return Value
   is
      Item : Object_Access;
   begin
      if Size = Natural'Last then
         Fail (State, "string length overflow");
      elsif Size > State.Bounds.String_Bytes then
         Fail (State, "string byte limit exceeded", Resource => True);
      end if;
      --  Hashing an external payload is actual shared runtime work. Charge
      --  before adopting the caller's ownership so quota failure remains a
      --  C-guard cleanup path, without a partially adopted header.
      String_Work (State, Size);
      Item := Allocate (State, String_Object);
      --  External strings are deliberately never interned here, including
      --  zero-length/short buffers. The exact caller payload remains the
      --  returned C view until release. Table insertion normalizes a short
      --  external key separately, matching Lua 5.5's luaS_normstr boundary.
      Item.External_String := True;
      Item.Bytes := (Address, Size);
      Item.C_Bytes := Address;
      Item.String_Allocator := Allocator;
      Item.String_Allocator_Data := Data;
      declare
         Text : constant String (1 .. Size) with Import, Address => Address;
      begin
         Item.String_Hash := Tables.Hash_Bytes (Text);
      end;
      return (String_Kind, Item);
   end New_External_String;

   function Userdata_Address (Item : Value) return System.Address is
     (if Item.Kind = Userdata_Kind then Item.Reference.Payload'Address
      else System.Null_Address);

   procedure Attach_Resource
     (Item : Value; Data : System.Address;
      Cleanup : not null Resource_Cleanup) is
   begin
      if Item.Kind /= Userdata_Kind or else
        Item.Reference.Cleanup_Resource /= null
      then
         raise Program_Error with "invalid userdata resource attachment";
      end if;
      Item.Reference.Resource_Data := Data;
      Item.Reference.Cleanup_Resource := Cleanup;
   end Attach_Resource;

   function New_Userdata
     (State : in out World; Size : Lua.Storage.Byte_Count;
      Uservalue_Count : Natural := 0) return Value
   is
      subtype One_Byte_Object is Heap_Object (Userdata_Object, 1);
      Header_Bytes : constant Lua.Storage.Byte_Count :=
        One_Byte_Object'Object_Size / System.Storage_Unit;
      Block_Bytes : constant Lua.Storage.Byte_Count :=
        Payload_Block'Object_Size / System.Storage_Unit;
      Physical : constant Lua.Storage.Byte_Count :=
        Lua.Storage.Byte_Count'Max
          (1, Size / Block_Bytes +
             (if Size mod Block_Bytes = 0 then 0 else 1));
      Item : Object_Access;
   begin
      if Uservalue_Count >= Natural (Interfaces.C.short'Last) then
         Fail (State, "invalid userdata uservalue count");
      end if;
      --  Reject the mathematical object-size overflow before either Ada's
      --  discriminant-size arithmetic or a host allocator sees it. The
      --  one-byte subtype includes every fixed component and tail padding,
      --  so this conservative exact-type bound never undercounts storage.
      if Size > Lua.Storage.Byte_Count'Last - Header_Bytes - Block_Bytes then
         raise Lua.Storage.Allocation_Error with "userdata block too large";
      end if;
      Item := Allocate (State, Userdata_Object, Physical);
      Item.Userdata_Size := Size;
      --  The construction serial roots Item if initializing uservalues needs
      --  emergency collection. A failed constructor leaves no C pointer or
      --  host resource published; a later collection reclaims its storage.
      Item.Uservalues.Set_Length (Ada.Containers.Count_Type (Uservalue_Count));
      return (Userdata_Kind, Item);
   end New_Userdata;

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

   procedure Reserve_Table
     (State : in out World; Table : Value;
      Sequence_Size, Hash_Size : Natural) is
   begin
      if Table.Kind /= Table_Kind or else
        Table.Reference = null or else not Table.Reference.Members.Is_Empty
      then
         raise Program_Error with "capacity receiver must be an empty table";
      end if;
      Tables.Reserve (State, Table.Reference, Sequence_Size, Hash_Size);
   end Reserve_Table;


   function Global_Environment (State : World) return Value is
   begin
      --  The registry owns this edge. A cached bootstrap address must neither
      --  retarget an existing closure nor keep a replaced table alive.
      return Get
        ((Table_Kind, State.Foreign_Registry), (Integer_Kind, 2));
   end Global_Environment;

   function New_Environment
     (State : in out World; Parent : Object_Access) return Object_Access
   is
      Item : constant Object_Access := Allocate (State, Environment);
   begin
      Write_Barrier (State, Item, Parent);
      Item.Parent := Parent;
      return Item;
   end New_Environment;

   function New_Closure
     (State : in out World; Code : Prototype_Access;
      Capture : Object_Access) return Value
   is
      Item : constant Object_Access := Allocate (State, Closure);
   begin
      Code_Barrier (State, Code);
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
                     (if Index = 1 then Global_Environment (State)
                      else Nil_Value))));
            end loop;
         end if;
         Back_Barrier (State, Item);
         return (Closure_Kind, Item);
      elsif Capture = null and then Code.Is_Main then
         --  A chunk's _ENV is an actual ordered upvalue, including host
         --  chunks. Debug updates and nested closures share this same cell.
         Item.Capture := New_Environment (State, null);
         Declare_Local (State, Item.Capture, Code.Environment_Symbol,
                        Global_Environment (State));
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
      Back_Barrier (State, Item);
      return (Closure_Kind, Item);
   end New_Closure;

   function New_Native
     (State : in out World; Name : String;
      Captures : Values.Vector := Values.Empty_Vector) return Value
   is
      Found : constant Lua.Builtin_Registry.Lookup :=
        Lua.Builtin_Registry.Find (Name);
      Item : Object_Access;
   begin
      --  A stateless builtin is an actual light C function identity: no
      --  closure object/cache survives in the universe merely to remember a
      --  name. Stateful functions still own distinct real upvalue cells.
      if Captures.Is_Empty and then Found.Exists then
         return (Native_Kind_Value, Found.Id);
      end if;
      Item := Allocate (State, Native_Closure);
      Item.Native_Name := To_Unbounded_String (Name);
      for Capture of Captures loop
         declare
            Cell : constant Object_Access := Allocate (State, Cell_Object);
         begin
            --  Native upvalues also have stable cells. Stateful iterator
            --  writes and debug identities refer to this same owned storage.
            Store_Cell (State, Cell, Capture);
            Write_Barrier (State, Item, Cell);
            Item.Captures.Append (Cell);
         end;
      end loop;
      return (Native_Closure_Kind, Item);
   end New_Native;

   function Native_Operation_Name
     (Activation : not null Frame_Access) return String is
     (if Activation.Native_Builtin_Direct and then
         Activation.Native_Name = "@builtin.direct"
      then Lua.Builtin_Registry.Implementation (Activation.Native_Id)
      else To_String (Activation.Native_Name));

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
      elsif Item.Kind = Userdata_Kind then
         return Item.Reference.Userdata_Metatable;
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
         Write_Barrier (State, Item.Reference, Meta);
         Item.Reference.Metatable := Meta;
      elsif Item.Kind = Userdata_Kind then
         Write_Barrier (State, Item.Reference, Meta);
         Item.Reference.Userdata_Metatable := Meta;
      elsif Item.Kind = String_Kind then
         Root_Barrier (State, Meta);
         State.String_Metatable := Meta;
      else
         Root_Barrier (State, Meta);
         State.Type_Metatables (Metatable_Kind (Item.Kind)) := Meta;
      end if;
      Lua.Engine.Finalizers.Register (State, Item);
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
         when Table_Kind | Closure_Kind | Native_Closure_Kind | Thread_Kind |
           Userdata_Kind =>
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
         when Light_Identity_Kind | Userdata_Kind => "userdata",
         when Nil_Kind => "nil",
         when Boolean_Kind => "boolean",
         when Integer_Kind | Real_Kind => "number",
         when String_Kind => "string",
         when Table_Kind => "table",
         when Closure_Kind | Native_Closure_Kind | Native_Kind_Value |
           Foreign_Function_Kind =>
            "function");

   function Error_Type
     (State : World; Item : Value; Auxiliary : Boolean) return String;
   function Error_Type
     (State : World; Item : Value; Auxiliary : Boolean) return String
   is
      Meta : constant Object_Access := Raw_Metatable (State, Item);
      Name : constant Value :=
        (if Meta /= null and then
           (Auxiliary or else Item.Kind in Table_Kind | Userdata_Kind)
         then Tables.Raw_Field (Meta, "__name") else Nil_Value);
   begin
      --  luaT_objtypename and luaL_typeerror have deliberately different
      --  primitive-metatable policies. Both read a raw field and use its C
      --  string prefix. Borrow actual immutable bytes for the scan so a NUL
      --  near the start does not first copy a potentially huge counted name.
      if Name.Kind = String_Kind then
         declare
            Bytes : constant Byte_String := Name.Reference.Bytes;
            Text : String (1 .. Bytes.Size)
              with Import, Address => Bytes.Address;
         begin
            for Index in Text'Range loop
               if Text (Index) = Character'Val (0) then
                  return Text (Text'First .. Index - 1);
               end if;
            end loop;
            return Text;
         end;
      elsif Auxiliary and then Item.Kind = Light_Identity_Kind then
         return "light userdata";
      end if;
      return Type_Name (Item);
   end Error_Type;

   function Diagnostic_Type (State : World; Item : Value) return String is
     (Error_Type (State, Item, Auxiliary => False));

   function Argument_Type
     (State : World; Item : Value; Present : Boolean := True) return String is
     (if not Present then "no value" else
        Error_Type (State, Item, Auxiliary => True));

   function Real_Image (Item : Real_Value) return String is
   begin
      if Item /= Item then
         return NaN_Image (Item, Lua_Ada_Config.Alire_Host_OS);
      elsif Item > Real_Value'Last then
         return "inf";
      elsif Item < -Real_Value'Last then
         return "-inf";
      end if;
      declare
         Arena : Lua.Storage.Fixed_Arenas.Arena;
         Memory : Lua.Storage.Owner;
         Output : Owned_Buffer;
         Precision : Positive := 15;
         Text : String (1 .. 64);
         Size : Natural;
         Integer_Looking : Boolean := True;
         Point : constant Character := Character'Val (Locales.Decimal_Point);
      begin
         --  Finite binary64 conversion has a fixed rational/digit bound.
         --  Run the existing exact renderer and parser in a scoped fixed
         --  arena: public numbertocstring must make no Lua allocator request
         --  even when every provider growth is refused. The arena precedes
         --  its owner and all buffers, preserving reverse-order teardown.
         Lua.Storage.Fixed_Arenas.Bind (Arena, Memory);
         Output.Set_Owner (Lua.Storage.Reference (Memory));
         loop
            Formats.Finite_Number_Image
              (Lua.Storage.Reference (Memory), Item, Precision, Output);
            exit when Precision = 17 or else Lua.Numbers.To_Real
              (Read_Number (Lua.Storage.Reference (Memory),
                            Output.To_String)) = Item;
            Precision := 17;
         end loop;
         Size := Output.Length;
         for Index in 1 .. Size loop
            Text (Index) := Output.Element (Index);
            if Text (Index) not in '-' | '0' .. '9' then
               Integer_Looking := False;
            end if;
            if Text (Index) = '.' then
               Text (Index) := Point;
            end if;
         end loop;
         if Integer_Looking then
            --  Preserve a real value's numeric type when it has an integer
            --  looking general spelling, including either sign of zero.
            Text (Size + 1) := Point;
            Text (Size + 2) := '0';
            Size := Size + 2;
         end if;
         return Text (1 .. Size);
      end;
   end Real_Image;

   function Image (Memory : not null Lua.Storage.Owner_Access;
                   Item : Value) return String is
      pragma Unreferenced (Memory);
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
         when Table_Kind | Closure_Kind | Native_Closure_Kind | Thread_Kind |
           Userdata_Kind =>
            return Type_Name (Item) & ": " &
              Ada.Strings.Fixed.Trim
                (Item.Reference.Serial'Image, Ada.Strings.Both);
         when Native_Kind_Value =>
            return "function: " &
              Lua.Builtin_Registry.Handler_Address (Item.Native_Data)'Image;
      end case;
   end Image;

   function Image (Item : Value) return String is
      Memory : Lua.Storage.Owner;
   begin
      --  Host/testing inspection keeps its small interface. Runtime callers
      --  provide the universe instead of allocating hidden numeric scratch.
      return Image (Lua.Storage.Reference (Memory), Item);
   end Image;

   function Pointer_Of
     (State : in out World; Item : Value) return System.Address
   is
   begin
      case Item.Kind is
         when Thread_Kind =>
            return Lua.Engine.Foreign.Thread_Identity
              (State, Context_Id (Item.Reference.Context_Index));
         when Light_Identity_Kind | Foreign_Function_Kind =>
            return Item.Identity;
         when Native_Kind_Value =>
            return Lua.Builtin_Registry.Handler_Address (Item.Native_Data);
         when Userdata_Kind => return Userdata_Address (Item);
         when String_Kind | Table_Kind | Closure_Kind | Native_Closure_Kind =>
            return Item.Reference.all'Address;
         when others => return System.Null_Address;
      end case;
   end Pointer_Of;

   function Pointer_Image
     (Pointer : System.Address; Width : Natural := 0;
      Left_Aligned : Boolean := False) return String
   is
      Text : aliased String (1 .. 128);
      Size : constant Interfaces.C.size_t := Lua.Platform_Numerics.Pointer_Text
        (Pointer, Text'Address, Text'Length, Interfaces.C.int (Width),
         Boolean'Pos (Left_Aligned));
   begin
      if Size = 0 then
         raise Program_Error with "native pointer text exceeded fixed bound";
      end if;
      return Text (1 .. Natural (Size));
   end Pointer_Image;

   procedure Describe_Value
     (State : in out World; Item : Value; Output : in out Owned_Buffer)
   is
      Name : Value;
      procedure Append_Name (Text : String);
      procedure Work (Count : Natural);

      procedure Work (Count : Natural) is
      begin
         if State.Policy = Bounded then
            if Count > State.Bounds.Instructions - State.Steps then
               Fail (State, "instruction limit exceeded", Resource => True);
            end if;
            State.Steps := State.Steps + Count;
         end if;
      end Work;

      procedure Append_Name (Text : String) is
         Size : Natural := 0;
         Pending : Natural := 0;
      begin
         --  Borrow the counted bytes only while scanning/copying their C
         --  prefix. A short name before NUL never copies the huge suffix to
         --  an Ada String temporary. Scan and owned copy charge separately.
         for Byte of Text loop
            Pending := Pending + 1;
            exit when Byte = Character'Val (0);
            Size := Size + 1;
            if Pending = 4_096 then
               Work (Pending);
               Pending := 0;
            end if;
         end loop;
         Work (Pending);
         Work (Size);
         Output.Append (Text (Text'First .. (Text'First - 1) + Size));
      end Append_Name;
   begin
      Output.Set_Owner (Lua.Storage.Reference (State.Memory));
      Output.Clear;
      if Item.Kind in Nil_Kind | Boolean_Kind | Integer_Kind | Real_Kind then
         Output.Set_Value (Image (State.Current.Memory, Item));
      elsif Item.Kind = String_Kind then
         declare
            Text : String (1 .. Item.Reference.Bytes.Size)
              with Import, Address => Item.Reference.Bytes.Address;
         begin
            Work (Text'Length);
            Output.Set_Value (Text);
         end;
      else
         Name := Metafield (State, Item, "__name");
         if Name.Kind = String_Kind then
            declare
               Text : String (1 .. Name.Reference.Bytes.Size)
                 with Import, Address => Name.Reference.Bytes.Address;
            begin
               Append_Name (Text);
            end;
         else
            Output.Append (Type_Name (Item));
         end if;
         Output.Append (": ");
         Output.Append (Pointer_Image (Pointer_Of (State, Item)));
      end if;
   end Describe_Value;

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
     (State : in out World; Scope : Object_Access;
      Symbol : Positive; Item : Value) is
   begin
      Store_Cell (State, Find_Cell (Scope, Symbol), Item);
   end Write_Local;

   procedure Declare_Local
     (State : in out World; Scope : Object_Access;
      Symbol : Positive; Item : Value)
   is
      Cell : constant Object_Access := Allocate (State, Cell_Object);
   begin
      --  Each dynamic declaration gets a new identity. It is published in the
      --  owning environment before the VM reaches another collection point.
      Store_Cell (State, Cell, Item);
      Write_Barrier (State, Scope, Cell);
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

   procedure Emit_Warning
     (State : in out World; Message : Value;
      To_Continue : Boolean := False) is
   begin
      Lua.Engine.Warnings.Emit (State, Message, To_Continue);
   end Emit_Warning;

   procedure Emit_Warning
     (State : in out World; Message : Byte_String;
      Root : Value := Nil_Value; To_Continue : Boolean := False) is
   begin
      Lua.Engine.Warnings.Emit (State, Message, Root, To_Continue);
   end Emit_Warning;

   function Emit_Output
     (State : in out World; Bytes : String) return Output_Result
   is
      package Streams renames Lua.Platform_Streams;
      Error : aliased Interfaces.C.int := 0;
      Written : Interfaces.C.size_t;
   begin
      --  The output counter is independent of retained capture storage:
      --  immediate process writes still obey explicit embedding quotas.
      --  Subtraction avoids overflowing before testing a large write. Under
      --  compatible policy no indefinitely increasing counter is maintained.
      if State.Policy = Bounded then
         if State.Output_Used > State.Bounds.Output_Bytes or else
           Bytes'Length > State.Bounds.Output_Bytes - State.Output_Used
         then
            Fail (State, "output byte limit exceeded", Resource => True);
         end if;
         State.Output_Used := State.Output_Used + Bytes'Length;
      end if;
      if Bytes'Length = 0 then
         return (others => <>);
      elsif State.Output_Mode = Captured then
         Append (State.Output, Bytes);
         return (Bytes_Written => Bytes'Length, others => <>);
      end if;
      --  A String object's address denotes its first byte regardless of its
      --  lower bound. The empty case above never borrows a nonexistent byte.
      --  Native text translation/buffering remains libc's responsibility;
      --  embedded NUL and every high byte pass through unchanged to fwrite.
      Written := Streams.Write
        (Streams.Standard (Streams.Standard_Output), Bytes'Address,
         Interfaces.C.size_t (Bytes'Length), Error'Access);
      return
        (Succeeded => Written = Interfaces.C.size_t (Bytes'Length),
         Bytes_Written => Natural (Written), Error => Error);
   end Emit_Output;

   procedure Emit_Output (State : in out World; Bytes : String) is
      Ignored : constant Output_Result := Emit_Output (State, Bytes);
      pragma Unreferenced (Ignored);
   begin
      null;
   end Emit_Output;

   function Flush_Output (State : in out World) return Output_Result is
      package Streams renames Lua.Platform_Streams;
      Error : aliased Interfaces.C.int := 0;
      Status : Interfaces.C.int;
   begin
      if State.Output_Mode = Captured then
         return (others => <>);
      end if;
      Status := Streams.Flush
        (Streams.Standard (Streams.Standard_Output), Error'Access);
      return (Succeeded => Status = 0, Error => Error, others => <>);
   end Flush_Output;

   procedure Flush_Output (State : in out World) is
      Ignored : constant Output_Result := Flush_Output (State);
      pragma Unreferenced (Ignored);
   begin
      null;
   end Flush_Output;

   procedure Initialize (State : in out World; Bounds : Limits) is
      Table : Value;
   begin
      --  Ownership indexes and temporary roots exist before bootstrap can
      --  allocate a context or heap object. No registry grows implicitly.
      State.Contexts.Set_Owner (Lua.Storage.Reference (State.Memory));
      State.Heap.Set_Owner (Lua.Storage.Reference (State.Memory));
      State.Short_Strings.Set_Owner (Lua.Storage.Reference (State.Memory));
      State.Heap_Free_Next.Set_Owner (Lua.Storage.Reference (State.Memory));
      State.Program_Free_Next.Set_Owner
        (Lua.Storage.Reference (State.Memory));
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
      State.Warning_Mode := Default_Warnings_On;
      State.Warning_Handler := System.Null_Address;
      State.Warning_Data := System.Null_Address;
      State.Warning_Head := null;
      State.Saved_Bounds := Bounds;
      State.Memory_Error_Value := New_String (State, "not enough memory");
      State.Handling_Error_Value :=
        New_String (State, "error in error handling");
      Table := New_Table (State);
      State.Loaded_Modules := New_Table (State).Reference;
      State.Preload_Modules := New_Table (State).Reference;
      --  Ada and C consumers see one real registry, not debug-only mirrors.
      --  Publish it before adding its roots; bootstrap collection is disabled
      --  until initialization completes. Public package fields can later be
      --  replaced without retargeting these internal module tables.
      State.Foreign_Registry := New_Table (State).Reference;
      Set (State, (Table_Kind, State.Foreign_Registry),
           (Integer_Kind, 2), Table);
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
      --  Both eager sessions and explicit C opening use the same Ada
      --  constructors. This bootstrap operation cannot collect until globals
      --  and the loaded registry own all returned module tables.
      Lua.Engine.Library_Openers.Open_All (State);
      --  Bootstrap replaces several M1 bindings and creates temporary lookup
      --  keys. Publish a stable live baseline before returning the session;
      --  later heap quotas and collection statistics must describe its owned
      --  environment, not abandoned initialization temporaries.
      Collect (State);
      State.Memory_Ready := True;
   end Initialize;

   procedure Collect
     (State : in out World; Emergency : Boolean := False) is
   begin
      Collector.Full (State, Emergency);
   end Collect;

   procedure Finalize
     (State : in out World;
      Reason : Resource_Release_Reason := Host_Disposal) is
   begin
      End_Operation (State);
      loop
         External_Releases.Prepare_Close (State);
         exit when not External_Releases.Pending (State);
         State.Current := State.Main_Context;
         begin
            Machine.Drain_External_Releases (State);
         exception
            when Language_Error =>
               --  A host quota/error may stop Lua called by a deallocator.
               --  Its C guard has already acknowledged/released the active
               --  header. Physical disposal still owns every remaining
               --  packet and must finish rather than abandon this universe.
               null;
         end;
      end loop;
      --  A session is the unique allocator owner, so finalization can release
      --  all remaining objects without tracing or invoking user code.
      for Context of State.Contexts loop
         declare
            Owned : Context_Access := Context;
         begin
            if Owned /= null then
               Destroy_Frames (State, Owned);
               Release_Foreign_Context (State, Owned);
               Free_Context (Owned);
            end if;
         end;
      end loop;
      State.Contexts.Release;
      State.Native_Depth := 0;
      State.Current := null;
      State.Main_Context := null;
      State.Main_Thread := null;
      for Object of State.Heap loop
         declare
            Item : Object_Access := Object;
         begin
            Free_Object (State, Item, Reason);
         end;
      end loop;
      State.Heap.Release;
      State.Short_Strings.Release;
      State.Short_String_Count := 0;
      State.Heap_Free_Next.Release;
      State.Live_Objects := 0;
      State.Heap_Free_Head := 0;
      State.Finalizable_Head := null;
      State.Finalizer_Head := null;
      State.Finalizer_Tail := null;
      State.Finalizing_Object := null;
      State.Finalizing_Handler := Nil_Value;
      State.Finalizer_Active := False;
      State.Finalizers_Requested := False;
      for Program of State.Programs loop
         declare
            Item : Prototype_Access := Program;
         begin
            Release_Program (Item);
         end;
      end loop;
      State.Programs.Release;
      State.Program_Free_Next.Release;
      State.Live_Programs := 0;
      State.Program_Free_Head := 0;
      State.Foreign_Registry := null;
      State.String_Metatable := null;
      State.Type_Metatables := [others => null];
      State.Memory_Error_Value := Nil_Value;
      State.Handling_Error_Value := Nil_Value;
      State.Entry_Code := null;
      End_Operation (State);
      State.Operation_Roots.Release;
      State.Operation_Programs.Release;
      State.Memory_Ready := False;
      --  Foreign finalizers, external-string releasers and all heap/context
      --  payload cleanup have finished. Native code remains loaded through
      --  those phases and through its own provider-owned cache metadata.
      Native_Modules.Close_All (State);
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
      State.Current.Failure_Handled := False;
      State.Current.Protected_Failure_Class := No_Failure;
      State.Current.Protected_Handler_Called := False;
      State.Output := Null_Unbounded_String;
      State.Output_Used := 0;
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
      if State.Exit_Phase = Exit_Complete then
         --  Process exit is a typed scheduler result. Keep the final phase
         --  and code latched for the public boundary; ordinary post-execution
         --  collection must not restart callbacks after explicit shutdown.
         State.Entry_Code := null;
         End_Operation (State);
         State.Current.Arguments.Clear;
         return True;
      end if;
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
