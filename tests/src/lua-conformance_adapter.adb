with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Interfaces.C;
with Interfaces;
with Lua.Engine.Foreign;
with Lua.Engine.Stacks;
with Lua.Engine.Table_Storage_Probe;
with Lua.Storage;
with Lua.Runtime_Configuration;
with Lua.Conformance_Memory;
with Lua.Conformance_Allocator;
with System.Address_To_Access_Conversions;

package body Lua.Conformance_Adapter is
   use Lua.Engine;
   package C renames Interfaces.C;
   package Worlds is new System.Address_To_Access_Conversions (World);
   use type C.int;
   use type C.long_long;
   use type Integer_Value;
   use type Interfaces.Unsigned_8;
   use type C.size_t;
   use type Lua.Storage.Byte_Count;
   use type Foreign.C_Function;
   use type System.Address;
   procedure Free_Frame is new Ada.Unchecked_Deallocation
     (Frame, Frame_Access);

   procedure Verify_Collector_Lists (State : World) is
      Live, Generations, Gray_Count, Remembered_Count : Natural := 0;
      Queued, Remembered : Natural := 0;
      Cursor, Previous : Object_Access;
      Count : Natural;
      procedure Check (Condition : Boolean);
      procedure Registered (Item : not null Object_Access);
      procedure Gray_List
        (Head : Object_Access; Membership : Gray_Membership);

      procedure Check (Condition : Boolean) is
      begin
         if not Condition then
            raise Program_Error with "collector ownership invariant failed";
         end if;
      end Check;

      procedure Registered (Item : not null Object_Access) is
      begin
         Check (Item.Registry_Slot in 1 .. Natural (State.Heap.Length));
         Check (State.Heap.Element (Item.Registry_Slot) = Item);
      end Registered;

      procedure Gray_List
        (Head : Object_Access; Membership : Gray_Membership)
      is
         Item : Object_Access := Head;
         Visited : Natural := 0;
      begin
         while Item /= null loop
            Check (Visited < Live);
            Registered (Item);
            Check (Item.Gray_List = Membership);
            Visited := Visited + 1;
            Item := Item.Mark_Next;
         end loop;
         Gray_Count := Gray_Count + Visited;
      end Gray_List;
   begin
      --  Compare independent ownership representations. Every registry row
      --  is counted exactly once; each intrusive list is bounded by that
      --  count so a cycle fails instead of hanging the conformance process.
      for Index in 1 .. Natural (State.Heap.Length) loop
         Cursor := State.Heap.Element (Index);
         if Cursor /= null then
            Check (Cursor.Registry_Slot = Index);
            Live := Live + 1;
            if Cursor.Gray_List /= Not_Queued then
               Queued := Queued + 1;
            end if;
            if Cursor.Remembered then Remembered := Remembered + 1; end if;
         end if;
      end loop;
      Check (Live = State.Live_Objects);
      for Age in Object_Age loop
         Cursor := State.GC.Generations (Age);
         Previous := null;
         Count := 0;
         while Cursor /= null loop
            Check (Count < Live);
            Registered (Cursor);
            Check (Cursor.Age = Age);
            Check (Cursor.Generation_Previous = Previous);
            Previous := Cursor;
            Cursor := Cursor.Generation_Next;
            Count := Count + 1;
         end loop;
         Generations := Generations + Count;
      end loop;
      Check (Generations = Live);
      Gray_List (State.GC.Gray_Head, Primary_Gray);
      Gray_List (State.GC.Gray_Again, Revisit_Gray);
      Check (Gray_Count = Queued);
      Cursor := State.GC.Remembered_Head;
      Previous := null;
      while Cursor /= null loop
         Check (Remembered_Count < Live);
         Registered (Cursor);
         Check (Cursor.Remembered);
         Check (Cursor.Remembered_Previous = Previous);
         Previous := Cursor;
         Cursor := Cursor.Remembered_Next;
         Remembered_Count := Remembered_Count + 1;
      end loop;
      Check (Remembered_Count = Remembered);
   end Verify_Collector_Lists;

   procedure Verify_Table_Storage
     (State : World; Item : Value;
      Member_Rows, Live_Entries : out Natural)
   is
      Table : Object_Access;
      Rows, Hash_Rows, Free_Rows, Free_Flags : Natural := 0;
      Cursor, Visited, Membership : Natural;
      procedure Check (Condition : Boolean);
      procedure Reference (Pointer : Object_Access; Kind : Heap_Kind);
      procedure Value_Reference (Data : Value);

      procedure Check (Condition : Boolean) is
      begin
         if not Condition then
            raise Program_Error with "table storage invariant failed";
         end if;
      end Check;

      procedure Reference (Pointer : Object_Access; Kind : Heap_Kind) is
      begin
         --  A stale or foreign pointer cannot supply its own registry slot.
         --  Compare pointer values against actual owned rows first; only a
         --  matching live allocation may be dereferenced or passed to Hash.
         Check (Pointer /= null);
         for Index in 1 .. State.Heap.Last_Index loop
            if State.Heap (Index) = Pointer then
               Check (Pointer.Kind = Kind);
               Check (Pointer.Registry_Slot = Index);
               return;
            end if;
         end loop;
         Check (False);
      end Reference;

      procedure Value_Reference (Data : Value) is
      begin
         case Data.Kind is
            when String_Kind => Reference (Data.Reference, String_Object);
            when Table_Kind => Reference (Data.Reference, Table_Object);
            when Closure_Kind => Reference (Data.Reference, Closure);
            when Native_Closure_Kind =>
               Reference (Data.Reference, Native_Closure);
            when Thread_Kind => Reference (Data.Reference, Thread_Object);
            when Userdata_Kind => Reference (Data.Reference, Userdata_Object);
            when others => null;
         end case;
      end Value_Reference;
   begin
      Member_Rows := 0;
      Live_Entries := 0;
      Check (Item.Kind = Table_Kind);
      Reference (Item.Reference, Table_Object);
      Table := Item.Reference;
      Rows := Natural (Table.Members.Length);

      --  Establish safe keys/values and scalar link extents independently of
      --  every index. A nil-valued tombstone may still retain a live key and
      --  stay indexed; a collected nil key must have no collision successor.
      for Row of Table.Members loop
         Value_Reference (Row.Key);
         Value_Reference (Row.Item);
         Check (Row.Next <= Rows and then Row.Free_Next <= Rows);
         if Row.Key.Kind = Nil_Kind then
            Check (Row.Item.Kind = Nil_Kind and then Row.Next = 0);
         end if;
         if Row.Item.Kind = Nil_Kind then
            Check (Row.Free_Listed);
         else
            Live_Entries := Live_Entries + 1;
         end if;
         if Row.Free_Listed then
            Free_Flags := Free_Flags + 1;
         else
            Check (Row.Free_Next = 0);
         end if;
      end loop;

      for Index in 1 .. Table.Array_Index.Last_Index loop
         Cursor := Table.Array_Index (Index);
         Check (Cursor <= Rows);
         if Cursor /= 0 then
            Check (Equal (Table.Members (Cursor).Key,
                          (Integer_Kind, Integer_Value (Index))));
            Check (Table.Members (Cursor).Next = 0);
         end if;
      end loop;
      --  Prove every hash walk finite before invoking ordinary lookup. A
      --  repeated row in one chain necessarily exceeds Rows; cross-bucket
      --  aliasing is detected by the independent per-row membership pass.
      for Head of Table.Hash_Index loop
         Cursor := Head;
         Visited := 0;
         while Cursor /= 0 loop
            Check (Cursor <= Rows and then Visited < Rows);
            Check (Table.Members (Cursor).Key.Kind /= Nil_Kind);
            Check (Hash_Rows < Rows);
            Hash_Rows := Hash_Rows + 1;
            Visited := Visited + 1;
            Cursor := Table.Members (Cursor).Next;
         end loop;
      end loop;
      Check (Table.Hash_Rows = Hash_Rows);

      Cursor := Table.Free_Row;
      while Cursor /= 0 loop
         Check (Cursor <= Rows and then Free_Rows < Rows);
         Check (Table.Members (Cursor).Free_Listed);
         Free_Rows := Free_Rows + 1;
         Cursor := Table.Members (Cursor).Free_Next;
      end loop;
      Check (Free_Rows = Free_Flags);

      --  No input-sized visited bitmap or copied row vector is necessary.
      --  Bounded repeated walks prove each retained key has exactly one
      --  index, nil keys have none, and Find agrees with the actual row.
      --  The prior phase proved these unchanged chains finite and in bounds.
      --  Live revived rows may remain on the free list until insertion pops
      --  them; free/index overlap therefore does not imply corruption.
      for Index in 1 .. Rows loop
         Membership := 0;
         for Row of Table.Array_Index loop
            if Row = Index then
               Check (Membership = 0);
               Membership := 1;
            end if;
         end loop;
         for Head of Table.Hash_Index loop
            Cursor := Head;
            while Cursor /= 0 loop
               if Cursor = Index then
                  Check (Membership = 0);
                  Membership := 1;
               end if;
               Cursor := Table.Members (Cursor).Next;
            end loop;
         end loop;
         if Table.Members (Index).Key.Kind = Nil_Kind then
            Check (Membership = 0);
         else
            Check (Membership = 1);
            Check (Table_Storage_Probe.Find
                     (Table, Table.Members (Index).Key) = Index);
         end if;
      end loop;
      Member_Rows := Rows;
   end Verify_Table_Storage;

   type Integer_Results is array (1 .. 5) of C.long_long
     with Convention => C;
   type Adapter_Result is record
      Count : C.int := 0;
      Text_Length : C.int := -1;
      Integers : Integer_Results := [others => 0];
      Text : C.char_array (0 .. 255) := [others => C.nul];
   end record with Convention => C;

   function Callback (Operation : C.int) return Foreign.C_Function
     with Import, Convention => C,
          External_Name => "lua_ada_test_adapter_callback";
   function Address is new Ada.Unchecked_Conversion
     (Foreign.C_Function, System.Address);
   procedure Inspect
     (Pointer : System.Address; Operation : C.int;
      Result : not null access Adapter_Result)
     with Export, Convention => C, External_Name => "lua_ada_test_inspect";
   procedure Control_Count
     (State : in out World; Limit : C.long_long; Remove : Boolean := False);
   function Set_Count
     (Pointer : System.Address; Limit : C.long_long) return C.int
     with Export, Convention => C,
          External_Name => "lua_ada_test_set_allocation_count";

   procedure Control_Count
     (State : in out World; Limit : C.long_long; Remove : Boolean := False)
   is
   begin
      --  The configured launcher's actual shared callback also allocates for
      --  independently constructed states. Plain AUnit worlds keep their
      --  original owner-local controls. Neither setter executes Lua or grows.
      if Lua.Conformance_Allocator.Attached_To
        (Lua.Storage.Reference (State.Memory))
      then
         if Remove or else Limit < 0 then
            Lua.Conformance_Allocator.Clear_Count_Limit;
         else
            Lua.Conformance_Allocator.Set_Count_Limit
              (Lua.Storage.Byte_Count (Limit));
         end if;
      elsif Remove or else Limit < 0 then
         Lua.Storage.Clear_Failures (State.Memory);
      else
         Lua.Storage.Set_Failure_Countdown
           (State.Memory, Lua.Storage.Byte_Count (Limit));
      end if;
   end Control_Count;

   function Set_Count
     (Pointer : System.Address; Limit : C.long_long) return C.int
   is
   begin
      if Pointer = System.Null_Address then return -1; end if;
      Control_Count (Worlds.To_Pointer (Pointer).all, Limit);
      return 0;
   exception
      when others =>
         --  This C-convention leaf returns before C diagnoses a broken test
         --  control. No exception or nonlocal Lua transfer crosses Ada here.
         return -1;
   end Set_Count;

   procedure Inspect
     (Pointer : System.Address; Operation : C.int;
      Result : not null access Adapter_Result)
   is
      State : World renames Worlds.To_Pointer (Pointer).all;
      Context : constant Context_Access := State.Current;
      Invalid_Argument : exception;
      function Argument (Index : Positive) return Value;
      function Number (Index : Positive) return Integer_Value;
      procedure Text (Message : String);
      procedure Integer_Result (Item : Integer_Value);

      function Argument (Index : Positive) return Value is
        (if Index > Context.Foreign_Top - Context.Foreign_Base
         then Nil_Value else Stacks.Read
           (Context, Context.Foreign_Base + Index));

      function Number (Index : Positive) return Integer_Value is
         Item : constant Value := Argument (Index);
      begin
         if Item.Kind /= Integer_Kind then
            raise Invalid_Argument;
         end if;
         return Item.Integer_Data;
      end Number;

      procedure Text (Message : String) is
      begin
         if Message'Length > Result.Text'Length then
            raise Program_Error with "adapter diagnostic overflow";
         end if;
         Result.Count := 1;
         Result.Text_Length := C.int (Message'Length);
         for Index in Message'Range loop
            Result.Text (C.size_t (Index - Message'First)) :=
              C.To_C (Message (Index));
         end loop;
      end Text;

      procedure Integer_Result (Item : Integer_Value) is
      begin
         Result.Count := 1;
         Result.Integers (1) := C.long_long (Item);
      end Integer_Result;
   begin
      Result.all := (others => <>);
      case Operation is
         when 1 =>
            Lua.Storage.Fail_Next_Growth (State.Memory);
         when 2 =>
            if Context.Foreign_Top = Context.Foreign_Base then
               Control_Count (State, 0, Remove => True);
            else
               Control_Count (State, C.long_long (Number (1)));
            end if;
         when 3 | 4 =>
            declare
               Item : constant Value := Argument (1);
            begin
               if Item.Kind not in String_Kind | Table_Kind | Closure_Kind |
                 Native_Closure_Kind | Thread_Kind | Userdata_Kind
               then
                  Text ("no collectable");
               elsif Operation = 3 then
                  Text (case Item.Reference.Color is
                     when White_0 | White_1 => "white",
                     when Gray => "gray", when Black => "black");
               else
                  Text (case Item.Reference.Age is
                     when New_Age => "new", when Survival_Age => "survival",
                     when Old_0_Age => "old0", when Old_1_Age => "old1",
                     when Old_Age => "old", when Touched_1_Age => "touched1",
                     when Touched_2_Age => "touched2");
               end if;
            end;
         when 5 =>
            declare
               Stats : constant Lua.Storage.Allocation_Statistics :=
                 Lua.Storage.Statistics (State.Memory);
               Item : constant Value := Argument (1);
               Count : Integer_Value := 0;
               Shared : constant Boolean :=
                 Lua.Conformance_Allocator.Attached_To
                   (Lua.Storage.Reference (State.Memory));
            begin
               if Context.Foreign_Top = Context.Foreign_Base then
                  Result.Count := 3;
                  Result.Integers :=
                    [C.long_long (Stats.Raw_Bytes),
                     C.long_long (Stats.Live_Blocks),
                     C.long_long (Stats.Peak_Raw_Bytes), others => 0];
                  if Shared then
                     declare
                        Measured : constant
                          Lua.Conformance_Allocator.Provider_Statistics :=
                            Lua.Conformance_Allocator.Measurements;
                     begin
                        Result.Integers :=
                          [C.long_long (Measured.Bytes),
                           C.long_long (Measured.Blocks),
                           C.long_long (Measured.Peak), others => 0];
                     end;
                  end if;
               elsif Item.Kind = String_Kind then
                  --  Count real Lua identities, excluding internal cells,
                  --  prototypes and auxiliary managed allocations.
                  if To_String (Item.Reference.Bytes) not in
                    "table" | "function" | "thread" | "string" | "userdata"
                  then
                     raise Invalid_Argument;
                  end if;
                  for Object of State.Heap loop
                     if Object /= null and then
                       ((To_String (Item.Reference.Bytes) = "table" and then
                         Object.Kind = Table_Object) or else
                        (To_String (Item.Reference.Bytes) = "function" and
                         then Object.Kind in Closure | Native_Closure) or
                        else (To_String (Item.Reference.Bytes) = "thread"
                         and then Object.Kind = Thread_Object) or else
                        (To_String (Item.Reference.Bytes) = "string" and
                         then Object.Kind = String_Object) or else
                        (To_String (Item.Reference.Bytes) = "userdata" and
                         then Object.Kind = Userdata_Object))
                     then
                        Count := Count + 1;
                     end if;
                  end loop;
                  Integer_Result (Count);
               else
                  if Number (1) < 0 then raise Invalid_Argument; end if;
                  if Shared then
                     Lua.Conformance_Allocator.Set_Byte_Limit
                       (Lua.Storage.Byte_Count (Number (1)));
                  else
                     Lua.Storage.Set_Test_Ceiling
                       (State.Memory, Lua.Storage.Byte_Count (Number (1)));
                  end if;
               end if;
            end;
         when 6 =>
            declare
               function Name (Phase : Collector_Phase) return String;
               function Name (Phase : Collector_Phase) return String is
                 (case Phase is
                    when Paused => "pause",
                    when Propagating => "propagate",
                    when Enter_Atomic => "enteratomic",
                    when Sweeping_Objects => "sweepallgc",
                    when Sweeping_Programs => "sweepprograms",
                    when Finishing_Sweep => "sweepend",
                    when Finalizers_Ready => "callfin");
               Item : constant Value := Argument (1);
               Target : Collector_Phase := State.GC.Phase;
               Found, Done : Boolean := False;
            begin
               if Context.Foreign_Top = Context.Foreign_Base then
                  Text (Name (State.GC.Phase));
               else
                  if Item.Kind /= String_Kind or else
                    State.GC.Mode /= Incremental_Mode
                  then
                     raise Invalid_Argument;
                  end if;
                  for Phase in Collector_Phase loop
                     if Name (Phase) = To_String (Item.Reference.Bytes) then
                        Target := Phase;
                        Found := True;
                        exit;
                     end if;
                  end loop;
                  if not Found then raise Invalid_Argument; end if;
                  --  Drive actual incremental work. Finalizer callbacks stay
                  --  queued for the scheduler after this C callback returns.
                  while State.GC.Phase /= Target loop
                     Advance_Collection (State, 1, Done);
                  end loop;
               end if;
            end;
         when 7 =>
            if Number (1) < 0 then raise Invalid_Argument; end if;
            Integer_Result (Integer_Value (Encode_Collector_Parameter
              (Lua.Storage.Byte_Count (Number (1)))));
         when 8 =>
            if Number (2) < 0 then raise Invalid_Argument; end if;
            Integer_Result (Integer_Value (Apply_Collector_Parameter
              (Interfaces.Unsigned_8'Mod (Number (1)),
               Lua.Storage.Byte_Count (Number (2)))));
         when 9 =>
            --  Unlike normal collection's alternating cache shrink, resetCI
            --  discards every unused activation. Active frames are held by
            --  Context.Stack and never belong to this owning cache list.
            declare
               Cursor : Frame_Access := Context.Cache_Head;
               Count : Natural := 0;
               Discarded : Frame_Access;
            begin
               while Cursor /= null loop
                  if Count = Context.Cache_Count or else
                    Cursor.Lifecycle /= Available or else
                    Cursor.Context /= Context
                  then
                     raise Program_Error with "invalid adapter frame cache";
                  end if;
                  Count := Count + 1;
                  Cursor := Cursor.Cache_Next;
               end loop;
               if Count /= Context.Cache_Count then
                  raise Program_Error with "adapter cache count mismatch";
               end if;
               while Context.Cache_Head /= null loop
                  Discarded := Context.Cache_Head;
                  Context.Cache_Head := Discarded.Cache_Next;
                  Context.Cache_Count := Context.Cache_Count - 1;
                  Discarded.Cache_Next := null;
                  Free_Frame (Discarded);
               end loop;
            end;
         when 10 =>
            declare
               Extra : constant Integer_Value := Number (1);
               Last : Natural := Natural'Max
                 (Context.Stack_Used, Natural'Max
                    (Context.Foreign_Top, Context.Host_Stack_Top));
               Maximum : constant Positive :=
                 Lua.Runtime_Configuration.Maximum_Stack;
            begin
               if Extra < 0 or else Extra > Integer_Value (Maximum) then
                  raise Invalid_Argument;
               end if;
               --  Ada activations retain reserved register windows while
               --  a child executes. Preserve their union, including open
               --  cells; merely using the current C top would truncate it.
               for Activation of Context.Stack loop
                  if Activation.Has_Stack_Window then
                     Last := Natural'Max
                       (Last, Activation.Stack_Base +
                          Activation.Stack_Window_Length);
                  end if;
               end loop;
               if Last > Maximum - Natural (Extra) then
                  raise Invalid_Argument;
               end if;
               Last := Natural'Max (Minimum_C_Stack, Last + Natural (Extra));
               if Last + Extra_Stack >
                 Natural (Context.Foreign_Stack.Length)
               then
                  Stacks.Reserve (State, Context, Last + Extra_Stack);
               end if;
               if not Stacks.Try_Shrink (Context, Last + Extra_Stack) then
                  Text ("not enough memory");
                  Result.Count := -1;
               else
                  Context.Stack_Allocated_Bound := Last;
                  Context.Stack_Error_Phase := Normal_Stack;
               end if;
            end;
         when 12 =>
            Verify_Collector_Lists (State);
            Lua.Conformance_Memory.Verify (State);
         when 13 =>
            declare
               Iterations : constant Integer_Value := Number (1);
               Saved_Start : constant Positive := State.Operation_Start;
               Item : Value;
               Before, Cost, Limit, Refusals : Lua.Storage.Byte_Count;
               Collections : Natural;
               procedure Allocate_Table;
               procedure Allocate_Table is
               begin
                  --  Model successive VM allocation operations without
                  --  dropping the enclosing C callback's explicit roots.
                  --  Earlier temporary tables are garbage, while the table
                  --  being constructed is protected by the production
                  --  operation serial boundary during an allocation retry.
                  State.Operation_Start := State.Next_Object;
                  Item := New_Table (State);
                  if Item.Kind /= Table_Kind then raise Program_Error; end if;
               end Allocate_Table;
               procedure Reclaim;
               procedure Reclaim is
               begin
                  State.Operation_Start := State.Next_Object;
                  Collect (State, Emergency => True);
               end Reclaim;
            begin
               if Iterations not in 2 .. 10_000 then
                  raise Invalid_Argument;
               end if;
               --  Counterpart of gc.lua's C-layout-specific +200 allowance.
               --  Prime one registry slot, then measure a real empty table
               --  allocation on this build. Only that measured headroom is
               --  permitted; every subsequent table requires actual recovery.
               Allocate_Table;
               Reclaim;
               Before := Lua.Storage.Statistics (State.Memory).Raw_Bytes;
               Allocate_Table;
               Cost := Lua.Storage.Statistics (State.Memory).Raw_Bytes -
                 Before;
               if Cost = 0 then raise Program_Error; end if;
               Reclaim;
               Before := Lua.Storage.Statistics (State.Memory).Raw_Bytes;
               if Before > Lua.Storage.Byte_Count'Last - Cost then
                  raise Invalid_Argument;
               end if;
               Limit := Before + Cost;
               Refusals := Lua.Storage.Statistics (State.Memory).Refusals;
               Collections := State.Collections;
               Lua.Storage.Set_Test_Ceiling (State.Memory, Limit);
               for Index in 1 .. Iterations loop
                  Allocate_Table;
                  if Lua.Storage.Statistics (State.Memory).Raw_Bytes > Limit
                  then
                     raise Program_Error with "allocation ceiling bypassed";
                  end if;
               end loop;
               Lua.Storage.Set_Test_Ceiling (State.Memory, 0);
               Refusals :=
                 Lua.Storage.Statistics (State.Memory).Refusals - Refusals;
               Collections := State.Collections - Collections;
               if Refusals = 0 or Collections = 0 then
                  raise Program_Error with "emergency recovery not exercised";
               end if;
               Reclaim;
               State.Operation_Start := Saved_Start;
               Result.Count := 3;
               Result.Integers :=
                 [C.long_long (Refusals), C.long_long (Collections),
                  C.long_long (Cost), others => 0];
            exception
               when others =>
                  Lua.Storage.Set_Test_Ceiling (State.Memory, 0);
                  State.Operation_Start := Saved_Start;
                  raise;
            end;
         when 37 =>
            --  Report the real Ada activation/arena counters. calls.lua
            --  compares successive reader tops, and all.lua compares native
            --  nesting before/after the entire campaign. Neither may be
            --  satisfied with an invented constant. Private reserve sizes
            --  remain Ada's actual policy, rather than C backing geometry.
            Result.Count := 4;
            Result.Integers :=
              [C.long_long (Context.Foreign_Top),
               C.long_long (Context.Stack_Allocated_Bound),
               C.long_long (State.Native_Depth),
               C.long_long (Context.Stack.Length), others => 0];
         when 38 =>
            declare
               Rows, Live : Natural;
            begin
               Verify_Table_Storage (State, Argument (1), Rows, Live);
               Result.Count := 2;
               Result.Integers :=
                 [C.long_long (Rows), C.long_long (Live), others => 0];
            end;
         when others => raise Invalid_Argument;
      end case;
   exception
      when Invalid_Argument =>
         Text ("unsupported adapter operation or invalid argument");
         Result.Count := -1;
      when others =>
         --  An invariant failure is not a catchable Lua test success.
         Result.Count := -2;
   end Inspect;

   function Has_Failing_Stream return Boolean is (Callback (15) /= null);
   function Has_Nonblocking_Pair return Boolean is (Callback (16) /= null);

   procedure Install_Platform (State : in out World) is
      Item : Value;
   begin
      if not Has_Failing_Stream then return; end if;
      Begin_Operation (State);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Callback (15));
      Set (State, Global_Environment (State),
           New_String (State, "_test_failing_stream"), Item);
      if Callback (16) /= null then
         Item := New_Native (State, "foreign.callback");
         Item.Reference.Foreign_Handler := Address (Callback (16));
         Set (State, Global_Environment (State),
              New_String (State, "_test_nonblocking_pair"), Item);
      end if;
      End_Operation (State);
   exception
      when others => End_Operation (State); raise;
   end Install_Platform;

   procedure Install (State : in out World) is
      Module : Value;
      procedure Keep_Status (Name : String);
      procedure Add (Name : String; Operation : C.int);
      procedure Keep_Status (Name : String) is
      begin
         Set (State, (Table_Kind, State.Foreign_Registry),
              New_String (State, Name), (Boolean_Kind, True));
      end Keep_Status;
      procedure Add (Name : String; Operation : C.int) is
         Captures : Values.Vector := Owned_Values (State);
         Item : Value;
      begin
         --  Only Ada inspection callbacks consume the operation/world pair.
         --  Public C test drivers are actual light C functions: hidden
         --  captures would make testC's absent-upvalue queries observe two
         --  values and change its C identity and allocation behavior.
         if Operation in 1 .. 10 | 12 | 13 | 37 | 38 then
            Append_Root (State, Captures,
                         (Integer_Kind, Integer_Value (Operation)));
            Append_Root (State, Captures,
                         (Light_Identity_Kind, State'Address));
            Item := New_Native (State, "foreign.callback", Captures);
            Item.Reference.Foreign_Handler := Address (Callback (Operation));
         else
            Item := (Foreign_Function_Kind, Address (Callback (Operation)));
         end if;
         Set (State, Module, New_String (State, Name), Item);
      end Add;
   begin
      Begin_Operation (State);
      Module := New_Table (State);
      Set (State, Global_Environment (State), New_String (State, "T"), Module);
      Add ("newuserdata", 0);
      Add ("allocfailnext", 1);
      Add ("alloccount", 2);
      Add ("gccolor", 3);
      Add ("gcage", 4);
      Add ("totalmem", 5);
      Add ("gcstate", 6);
      Add ("codeparam", 7);
      Add ("applyparam", 8);
      Add ("resetCI", 9);
      Add ("reallocstack", 10);
      Add ("_installwarning", 11);
      Add ("checkmemory", 12);
      Add ("ada_emergency_tables", 13);
      if Callback (14) /= null then Add ("nonblock", 14); end if;
      Add ("testC", 17);
      Add ("makeCfunc", 18);
      Add ("sethook", 19);
      Add ("resume", 20);
      Add ("newstate", 21);
      Add ("loadlib", 22);
      Add ("doremote", 23);
      Add ("closestate", 24);
      Add ("d2s", 25);
      Add ("s2d", 26);
      Add ("pushuserdata", 27);
      Add ("udataval", 28);
      Add ("ref", 29);
      Add ("getref", 30);
      Add ("unref", 31);
      Add ("upvalue", 32);
      Add ("doonnewstack", 33);
      Add ("externstr", 34);
      Add ("checkpanic", 35);
      Add ("stacklevel", 37);
      Add ("ada_check_table_storage", 38);
      --  The source's regcodes roots these actual status strings before
      --  refusal tests. The driver can then push them without resurrecting
      --  an unrooted weak short string while allocator growth is disabled.
      Keep_Status ("OK");
      Keep_Status ("YIELD");
      Keep_Status ("ERRRUN");
      Keep_Status ("ERRSYNTAX");
      Keep_Status ("not enough memory");
      Keep_Status ("ERRERR");
      --  Only test hosts install this binding. The public command driver
      --  invokes a genuine zero-upvalue C leaf, with an explicit scalar
      --  limit, so restoring refusal cannot allocate a Lua call boundary.
      Set (State, (Table_Kind, State.Foreign_Registry),
           New_String (State, "LUA_ADA_T_OWNER"),
           (Light_Identity_Kind, State'Address));
      Set (State, (Table_Kind, State.Foreign_Registry),
           New_String (State, "LUA_ADA_T_COUNT"),
           (Foreign_Function_Kind, Address (Callback (36))));
      End_Operation (State);
   exception
      when others => End_Operation (State); raise;
   end Install;
end Lua.Conformance_Adapter;
