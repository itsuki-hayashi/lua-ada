with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with Interfaces.C;
with Interfaces;
with Lua.Engine.Foreign;
with Lua.Engine.Stacks;
with Lua.Storage;
with Lua.Runtime_Configuration;
with Lua.Conformance_Memory;
with System.Address_To_Access_Conversions;

package body Lua.Conformance_Adapter is
   use Lua.Engine;
   package C renames Interfaces.C;
   package Worlds is new System.Address_To_Access_Conversions (World);
   use type C.int;
   use type Integer_Value;
   use type Interfaces.Unsigned_8;
   use type C.size_t;
   use type Lua.Storage.Byte_Count;
   use type Foreign.C_Function;
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

   type Integer_Results is array (1 .. 3) of C.long_long
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
               Lua.Storage.Clear_Failures (State.Memory);
            elsif Number (1) < 0 then
               raise Invalid_Argument;
            else
               Lua.Storage.Set_Failure_Countdown
                 (State.Memory, Lua.Storage.Byte_Count (Number (1)));
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
            begin
               if Context.Foreign_Top = Context.Foreign_Base then
                  Result.Count := 3;
                  Result.Integers :=
                    [C.long_long (Stats.Raw_Bytes),
                     C.long_long (Stats.Live_Blocks),
                     C.long_long (Stats.Peak_Raw_Bytes)];
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
                  Lua.Storage.Set_Test_Ceiling
                    (State.Memory, Lua.Storage.Byte_Count (Number (1)));
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
                  C.long_long (Cost)];
            exception
               when others =>
                  Lua.Storage.Set_Test_Ceiling (State.Memory, 0);
                  State.Operation_Start := Saved_Start;
                  raise;
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

   procedure Install_Platform (State : in out World) is
      Item : Value;
   begin
      if not Has_Failing_Stream then return; end if;
      Begin_Operation (State);
      Item := New_Native (State, "foreign.callback");
      Item.Reference.Foreign_Handler := Address (Callback (15));
      Set (State, Global_Environment (State),
           New_String (State, "_test_failing_stream"), Item);
      End_Operation (State);
   exception
      when others => End_Operation (State); raise;
   end Install_Platform;

   procedure Install (State : in out World) is
      Module : Value;
      procedure Add (Name : String; Operation : C.int);
      procedure Add (Name : String; Operation : C.int) is
         Captures : Values.Vector := Owned_Values (State);
         Item : Value;
      begin
         Append_Root (State, Captures,
                      (Integer_Kind, Integer_Value (Operation)));
         Append_Root (State, Captures,
                      (Light_Identity_Kind, State'Address));
         Item := New_Native (State, "foreign.callback", Captures);
         Item.Reference.Foreign_Handler := Address (Callback (Operation));
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
      End_Operation (State);
   exception
      when others => End_Operation (State); raise;
   end Install;
end Lua.Conformance_Adapter;
