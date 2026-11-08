with Ada.Containers;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Conformance_Adapter;
with Lua.Conformance_Allocator;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Foreign;
with Lua.Engine.Machine;
with Lua.Engine.Stacks;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.Call_Metadata_Tests is
   use type Lua.Storage.Byte_Count;
   use type System.Address;
   procedure Check
     (Name : String; Tail_Fixture : Boolean := False;
      Require_Refusal : Boolean := False);
   procedure Prepare (State : in out World);
   procedure Pure_Ada_Capacity;
   procedure Cached_Capacity;
   procedure Surface_Preserves_Warm_Cache;
   procedure Refused_Reservation;
   procedure Physical_Shrink;
   procedure Host_Abort_Recovery;
   procedure Physical_Headroom_Privacy;
   procedure Headroom_Refusal (Allowed : Lua.Storage.Byte_Count);
   procedure Headroom_Value_Refusal;
   procedure Headroom_Cell_Refusal;
   procedure Headroom_Close_Refusal;
   procedure Primitive_Strings;
   procedure Primitive_Numbers;
   procedure Primitive_False_Nil;
   procedure Same_Object_Equality;
   procedure Table_Equality_Yields;
   procedure Userdata_Equality_Handler;
   procedure Equality_Budget_Recovery;
   procedure Assert_Success_Tuple;
   procedure Assert_Protected_Tuple;
   procedure Independent_Checkstack_Refusal;
   procedure First_Protected;
   procedure Nested_Protected;
   procedure Numeric_Error;
   procedure False_Result;
   procedure Byte_Ceiling;
   procedure Repeated_Entry;
   procedure Outstanding_Shrink;
   procedure Error_After_Shrink;
   procedure Cross_Context_Return;
   procedure Cross_Context_Error;
   procedure ResetCI_Capacity;
   procedure ResetCI_Outstanding;
   procedure ResetCI_Refusal;
   procedure Tail_Budget_Recovery;
   procedure Tail_Refusal_Recovery;
   procedure Tail_Close_Error;
   procedure Tail_Yield;
   procedure Tail_Hook_Error;
   procedure Tail_Hook_Mutation;
   procedure Tail_Weak_Argument;
   procedure Tail_Chain;
   procedure Tail_Tuple;
   procedure Optimized_Vararg_Bytes;
   procedure Optimized_Vararg_Count;

   procedure Check
     (Name : String; Tail_Fixture : Boolean := False;
      Require_Refusal : Boolean := False) is
      State : World;
      Success : Boolean;
   begin
      Initialize (State, (others => <>));
      Conformance_Allocator.Attach (Lua.Storage.Reference (State.Memory));
      Conformance_Adapter.Install (State);
      Success := Execute
        (State, (if Tail_Fixture then "_TAIL_OWNERSHIP_CASE='" else
            "_CALL_METADATA_CASE='") & Name & "';dofile('tests/lua/" &
         (if Tail_Fixture then "canonical_tail_ownership.lua"
          else "call_metadata_windows.lua") & "')", "=call-metadata");
      --  Verification and physical teardown run after the actual application
      --  refusal has ended; a failed operation must still release all owners.
      Conformance_Allocator.Clear_Count_Limit;
      Conformance_Allocator.Set_Byte_Limit (0);
      Assert (Success, Failure_Image (State.Current));
      if Require_Refusal then
         Assert (Lua.Storage.Statistics (State.Memory).Refusals > 0,
                 "tail refusal fixture did not reject an actual growth");
      end if;
      Finalize (State);
      Conformance_Allocator.Finish;
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "C metadata retained physical provider blocks");
   exception
      when others =>
         Conformance_Allocator.Clear_Count_Limit;
         Conformance_Allocator.Set_Byte_Limit (0);
         Lua.Storage.Clear_Failures (State.Memory);
         Finalize (State);
         Conformance_Allocator.Finish;
         raise;
   end Check;

   procedure Prepare (State : in out World) is
      Identity : System.Address;
   begin
      Conformance_Adapter.Install (State);
      --  Registering callbacks alone leaves the C surface lazy. This private
      --  reservation fixture needs its actual surface before forcing the
      --  following raw-frame allocation to exhaust its metadata allowance.
      Identity := Foreign.Thread_Identity
        (State, Context_Id (State.Current.Thread.Context_Index));
      Assert (Identity /= System.Null_Address,
              "metadata fixture did not construct its real C surface");
   end Prepare;

   procedure Pure_Ada_Capacity is
      State : World;
      Item : Frame_Access;
      Before : Natural;
   begin
      Initialize (State, (others => <>));
      Before := State.Current.Frame_Capacity;
      Item := New_Frame (State);
      Assert (State.Current.Frame_Capacity = Before + 1 and then
              State.Current.Foreign_State = System.Null_Address,
              "pure Ada frame capacity forced a foreign surface");
      Return_Frame (Item);
      Assert (State.Current.Frame_Capacity = Before + 1,
              "cache return discarded actual allocated capacity");
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "pure frame count retained allocation ownership");
   exception
      when others => Return_Frame (Item); Finalize (State); raise;
   end Pure_Ada_Capacity;

   procedure Cached_Capacity is
      State : World;
      Item : Frame_Access;
      Capacity : Natural;
      Attempts : Lua.Storage.Byte_Count;
   begin
      Initialize (State, (others => <>));
      Prepare (State);
      Item := New_Frame (State);
      Return_Frame (Item);
      Capacity := State.Current.Frame_Capacity;
      Attempts := Lua.Storage.Statistics (State.Memory).Growth_Attempts;
      Lua.Storage.Set_Failure_Countdown (State.Memory, 0);
      Item := New_Frame (State);
      Assert (State.Current.Frame_Capacity = Capacity and then
              Lua.Storage.Statistics (State.Memory).Growth_Attempts = Attempts,
              "cached frame or metadata reservation attempted new growth");
      Return_Frame (Item);
      Lua.Storage.Clear_Failures (State.Memory);
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "cached C reservation retained provider blocks");
   exception
      when others =>
         Lua.Storage.Clear_Failures (State.Memory);
         Return_Frame (Item); Finalize (State); raise;
   end Cached_Capacity;

   procedure Surface_Preserves_Warm_Cache is
      State : World;
      Items : array (1 .. 4) of Frame_Access;
      Cached : Natural;
      Attempts : Lua.Storage.Byte_Count;
   begin
      Initialize (State, (others => <>));
      for Item of Items loop Item := New_Frame (State); end loop;
      for Item of Items loop Return_Frame (Item); end loop;
      Cached := State.Current.Cache_Count;
      --  Dedicated reset owners belong to first C surface construction.
      --  They must not consume the application's already warmed call depth.
      Prepare (State);
      Assert (State.Current.Cache_Count = Cached,
              "C surface construction stole warmed ordinary activations");
      Attempts := Lua.Storage.Statistics (State.Memory).Growth_Attempts;
      Lua.Storage.Set_Failure_Countdown (State.Memory, 0);
      for Item of Items loop Item := New_Frame (State); end loop;
      Assert (Lua.Storage.Statistics (State.Memory).Growth_Attempts = Attempts,
              "first C exposure destroyed zero-growth call depth");
      for Item of Items loop Return_Frame (Item); end loop;
      Lua.Storage.Clear_Failures (State.Memory);
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "dedicated C reset reservation retained provider blocks");
   exception
      when others =>
         Lua.Storage.Clear_Failures (State.Memory);
         for Item of Items loop Return_Frame (Item); end loop;
         Finalize (State); raise;
   end Surface_Preserves_Warm_Cache;

   procedure Refused_Reservation is
      State : World;
      Item : Frame_Access;
      Capacity : Natural;
      Refused : Boolean := False;
   begin
      Initialize (State, (others => <>));
      Prepare (State);
      Assert (State.Current.Cache_Head = null,
              "reservation fixture unexpectedly borrowed a cached frame");
      Capacity := State.Current.Frame_Capacity;
      --  Prepare the owning reference vector so the second growth below
      --  specifically exercises the new pool node, after the raw frame.
      State.Current.Stack.Reserve_Capacity
        (Ada.Containers.Count_Type (Capacity + 2));
      --  The new raw frame fits, but its following metadata node refuses.
      --  Retry/GC may run; the unpublished frame must roll back each time.
      Lua.Storage.Set_Failure_Countdown (State.Memory, 1);
      begin
         Item := New_Frame (State);
      exception
         when Lua.Storage.Allocation_Error => Refused := True;
      end;
      Lua.Storage.Clear_Failures (State.Memory);
      Assert (Refused and then State.Current.Frame_Capacity = Capacity,
              "metadata refusal published an orphan frame/capacity");
      Item := New_Frame (State);
      Return_Frame (Item);
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "transactional metadata reservation leaked provider blocks");
   exception
      when others =>
         Lua.Storage.Clear_Failures (State.Memory);
         Return_Frame (Item); Finalize (State); raise;
   end Refused_Reservation;

   procedure Physical_Shrink is
      State : World;
      Items : array (1 .. 12) of Frame_Access;
      Capacity : Natural;
   begin
      Initialize (State, (others => <>));
      Prepare (State);
      for Item of Items loop Item := New_Frame (State); end loop;
      for Item of Items loop Return_Frame (Item); end loop;
      Capacity := State.Current.Frame_Capacity;
      Shrink_Context_Storage (State, State.Current);
      Assert (State.Current.Frame_Capacity < Capacity,
              "physical cache shrink retained its old frame capacity");
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "trimmed C pool retained provider blocks");
   exception
      when others =>
         for Item of Items loop Return_Frame (Item); end loop;
         Finalize (State); raise;
   end Physical_Shrink;

   procedure Physical_Headroom_Privacy is
      State : World;
      Context : Context_Access;
      Before_Top, Before_Used : Natural;
      Before_Window : Frame_Access;
      Bound : Natural;
      Attempts : Lua.Storage.Byte_Count;
      Available : Boolean;
      Last : constant Natural := Initial_Stack_Size - Minimum_C_Stack / 2;
   begin
      Initialize (State, (others => <>));
      Context := State.Current;
      Bound := Context.Stack_Allocated_Bound;
      Before_Top := Context.Foreign_Top;
      Before_Used := Context.Stack_Used;
      Before_Window := Context.Stack_Window;
      Machine.Prepare_C_Call_Storage (State, Context, Last);
      Assert (Context.Stack_Allocated_Bound = Bound and then
              Context.Foreign_Top = Before_Top and then
              Context.Stack_Used = Before_Used and then
              Context.Stack_Window = Before_Window and then
              Natural (Context.Foreign_Stack.Length) > Bound + Extra_Stack,
              "physical C headroom published a guest bound/top/window");
      Attempts := Lua.Storage.Statistics (State.Memory).Growth_Attempts;
      Lua.Storage.Set_Failure_Countdown (State.Memory, 0);
      Available := Machine.Ensure_Stack
        (State, Context, Last + Minimum_C_Stack);
      Assert (Available and then Context.Stack_Allocated_Bound > Bound and then
              Lua.Storage.Statistics (State.Memory).Growth_Attempts = Attempts,
              "actual C request did not reuse its prepared backing");
      Lua.Storage.Clear_Failures (State.Memory);
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "prepared C backing retained provider blocks");
   exception
      when others =>
         Lua.Storage.Clear_Failures (State.Memory);
         Finalize (State); raise;
   end Physical_Headroom_Privacy;

   procedure Headroom_Refusal (Allowed : Lua.Storage.Byte_Count) is
      State : World;
      Context : Context_Access;
      Before_Top, Before_Used : Natural;
      Before_Window : Frame_Access;
      Bound, Initialized : Natural;
      Refused : Boolean := False;
      Last : constant Natural := Initial_Stack_Size - Minimum_C_Stack / 2;
   begin
      Initialize (State, (others => <>));
      Context := State.Current;
      Stacks.Reserve (State, Context, Initial_Stack_Size + Extra_Stack);
      Bound := Context.Stack_Allocated_Bound;
      Before_Top := Context.Foreign_Top;
      Before_Used := Context.Stack_Used;
      Before_Window := Context.Stack_Window;
      Initialized := Natural (Context.Foreign_Stack.Length);
      --  Refuse each parallel array growth in turn. Earlier successful
      --  capacity reservations are allowed; initialized lengths and every
      --  semantic/API field must remain at their original values.
      Lua.Storage.Set_Failure_Countdown (State.Memory, Allowed);
      begin
         Machine.Prepare_C_Call_Storage (State, Context, Last);
      exception
         when Lua.Storage.Allocation_Error => Refused := True;
      end;
      Lua.Storage.Clear_Failures (State.Memory);
      Assert (Refused and then Context.Stack_Allocated_Bound = Bound and then
              Context.Foreign_Top = Before_Top and then
              Context.Stack_Used = Before_Used and then
              Context.Stack_Window = Before_Window and then
              Natural (Context.Foreign_Stack.Length) = Initialized and then
              Natural (Context.Stack_Cells.Length) = Initialized and then
              Natural (Context.C_Close_Links.Length) = Initialized,
              "refused C headroom published partial stack state");
      Machine.Prepare_C_Call_Storage (State, Context, Last);
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "refused C headroom retained provider blocks");
   exception
      when others =>
         Lua.Storage.Clear_Failures (State.Memory);
         Finalize (State); raise;
   end Headroom_Refusal;

   procedure Headroom_Value_Refusal is
   begin
      Headroom_Refusal (0);
   end Headroom_Value_Refusal;

   procedure Headroom_Cell_Refusal is
   begin
      Headroom_Refusal (1);
   end Headroom_Cell_Refusal;

   procedure Headroom_Close_Refusal is
   begin
      Headroom_Refusal (2);
   end Headroom_Close_Refusal;

   procedure Host_Abort_Recovery is
      State : World;
   begin
      Initialize (State, (Instructions => 1_000, others => <>));
      Conformance_Adapter.Install (State);
      Assert (not Execute
        (State, "local function f()while true do end end;" &
         "T.testC('call 0 0',function()" &
         "T.testC('call 0 0',f)end)", "=call-metadata-host-stop"),
        "nested API calls escaped the shared instruction budget");
      Assert (State.Current.Failure_Class = Host_Abort,
              "embedding stop became a catchable C/Lua error");
      Assert (Execute (State, "return 37", "=call-metadata-recovery"),
              "abandoned C records prevented same-session recovery");
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "abandoned C guards retained metadata/provider blocks");
   exception
      when others => Finalize (State); raise;
   end Host_Abort_Recovery;

   procedure Primitive_Strings is
   begin
      Check ("Primitive_Strings");
   end Primitive_Strings;

   procedure Primitive_Numbers is
   begin
      Check ("Primitive_Numbers");
   end Primitive_Numbers;

   procedure Primitive_False_Nil is
   begin
      Check ("Primitive_False_Nil");
   end Primitive_False_Nil;

   procedure Same_Object_Equality is
   begin
      Check ("Same_Object_Equality");
   end Same_Object_Equality;

   procedure Table_Equality_Yields is
   begin
      Check ("Table_Equality_Yields");
   end Table_Equality_Yields;

   procedure Userdata_Equality_Handler is
   begin
      Check ("Userdata_Equality_Handler");
   end Userdata_Equality_Handler;

   procedure Equality_Budget_Recovery is
      State : World;
   begin
      Initialize (State, (Instructions => 50_000, others => <>));
      Assert (Execute
        (State, "eqleft=string.rep('x',5000);" &
         "eqright=string.rep('x',5000);" &
         "function eqcheck(a,b)return a==b end", "=equality-setup"),
        "equality quota fixture failed to prepare actual strings");
      State.Bounds.Instructions := 200;
      Assert (not Execute
        (State, "pcall(eqcheck,eqleft,eqright);error('caught')",
         "=equality-quota"), "linear equality work escaped the host quota");
      Assert (State.Current.Failure_Class = Host_Abort,
              "equality quota became a catchable protected failure");
      State.Bounds.Instructions := 1_000;
      Assert (Execute (State, "return 37", "=equality-recovery"),
              "equality host stop left the session unusable");
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "equality quota retained provider blocks");
   exception
      when others => Finalize (State); raise;
   end Equality_Budget_Recovery;

   procedure Assert_Success_Tuple is
   begin
      Check ("Assert_Success_Tuple");
   end Assert_Success_Tuple;

   procedure Assert_Protected_Tuple is
   begin
      Check ("Assert_Protected_Tuple");
   end Assert_Protected_Tuple;

   procedure Independent_Checkstack_Refusal is
   begin
      Check ("Independent_Checkstack_Refusal");
   end Independent_Checkstack_Refusal;

   procedure First_Protected is
   begin
      Check ("First_Protected");
   end First_Protected;

   procedure Nested_Protected is
   begin
      Check ("Nested_Protected");
   end Nested_Protected;

   procedure Numeric_Error is
   begin
      Check ("Numeric_Error");
   end Numeric_Error;

   procedure False_Result is
   begin
      Check ("False_Result");
   end False_Result;

   procedure Byte_Ceiling is
   begin
      Check ("Byte_Ceiling");
   end Byte_Ceiling;

   procedure Repeated_Entry is
   begin
      Check ("Repeated_Entry");
   end Repeated_Entry;

   procedure Outstanding_Shrink is
   begin
      Check ("Outstanding_Shrink");
   end Outstanding_Shrink;

   procedure Error_After_Shrink is
   begin
      Check ("Error_After_Shrink");
   end Error_After_Shrink;

   procedure Cross_Context_Return is
   begin
      --  Two actual context pools remain active while the child grows and
      --  physically shrinks its cache, then returns through both guards.
      Check ("Cross_Context_Return");
   end Cross_Context_Return;

   procedure Cross_Context_Error is
   begin
      --  Independent context generations must not discard another owner
      --  during nested numeric-error transfer and subsequent healthy entry.
      Check ("Cross_Context_Error");
   end Cross_Context_Error;

   procedure ResetCI_Capacity is
      State : World;
      Before_Capacity : Natural;
      Before_Bytes : Lua.Storage.Byte_Count;
      Expected : Natural;
   begin
      Initialize (State, (others => <>));
      Prepare (State);
      --  Warm actual recursive VM depth, then stop automatic collection so
      --  resetCI itself owns the physical cache deletion being measured.
      Assert (Execute
        (State, "collectgarbage('stop');local function deep(n)" &
         "if n>0 then deep(n-1)end end;deep(48)", "=reset-cache-warm"),
        Failure_Image (State.Current));
      Assert (State.Current.Cache_Count > 16,
              "resetCI fixture did not warm real cached frames");
      Before_Capacity := State.Current.Frame_Capacity;
      Before_Bytes := Lua.Storage.Statistics (State.Memory).Raw_Bytes;
      Assert (Execute (State, "T.resetCI()", "=reset-cache"),
              Failure_Image (State.Current));
      Expected := State.Current.Cache_Count + State.Current.Reset_Frame_Count +
        Natural (State.Current.Stack.Length) +
        (if State.Current.Base_C_Frame = null then 0 else 1);
      Assert (State.Current.Frame_Capacity = Expected and then
              State.Current.Frame_Capacity < Before_Capacity,
              "resetCI retained deleted physical frame reservations");
      Assert (Lua.Storage.Statistics (State.Memory).Raw_Bytes < Before_Bytes,
              "resetCI did not release warmed physical owner allocations");
      Assert (Execute (State, "assert(37==37)", "=reset-cache-recovery"),
              Failure_Image (State.Current));
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "resetCI owning release retained selected provider blocks");
   exception
      when others => Finalize (State); raise;
   end ResetCI_Capacity;

   procedure ResetCI_Outstanding is
   begin
      --  resetCI physically frees only cached owners while this real outer
      --  C call still needs its metadata through numeric-error guard ACK.
      Check ("ResetCI_Outstanding");
   end ResetCI_Outstanding;

   procedure ResetCI_Refusal is
   begin
      --  Cache and unused metadata deletion allocate nothing, even after
      --  the actual provider refuses growth; a following call stays healthy.
      Check ("ResetCI_Refusal");
   end ResetCI_Refusal;

   procedure Optimized_Vararg_Count is
   begin
      --  Execute only this source-linked public tail ownership behavior.
      Check ("Optimized_Vararg_Count", Tail_Fixture => True);
   end Optimized_Vararg_Count;

   procedure Optimized_Vararg_Bytes is
   begin
      --  Execute only this source-linked public tail ownership behavior.
      Check ("Optimized_Vararg_Bytes", Tail_Fixture => True);
   end Optimized_Vararg_Bytes;

   procedure Tail_Tuple is
   begin
      --  Execute only this source-linked public tail ownership behavior.
      Check ("Tail_Tuple", Tail_Fixture => True);
   end Tail_Tuple;

   procedure Tail_Chain is
   begin
      --  Execute only this source-linked public tail ownership behavior.
      Check ("Tail_Chain", Tail_Fixture => True);
   end Tail_Chain;

   procedure Tail_Weak_Argument is
   begin
      --  Execute only this source-linked public tail ownership behavior.
      Check ("Tail_Weak_Argument", Tail_Fixture => True);
   end Tail_Weak_Argument;

   procedure Tail_Hook_Mutation is
   begin
      --  Execute only this source-linked public tail ownership behavior.
      Check ("Tail_Hook_Mutation", Tail_Fixture => True);
   end Tail_Hook_Mutation;

   procedure Tail_Hook_Error is
   begin
      --  Execute only this source-linked public tail ownership behavior.
      Check ("Tail_Hook_Error", Tail_Fixture => True);
   end Tail_Hook_Error;

   procedure Tail_Yield is
   begin
      --  Execute only this source-linked public tail ownership behavior.
      Check ("Tail_Yield", Tail_Fixture => True);
   end Tail_Yield;

   procedure Tail_Close_Error is
   begin
      --  Execute only this source-linked public tail ownership behavior.
      Check ("Tail_Close_Error", Tail_Fixture => True);
   end Tail_Close_Error;

   procedure Tail_Refusal_Recovery is
   begin
      --  Execute only this source-linked public tail ownership behavior.
      Check ("Tail_Refusal_Recovery", Tail_Fixture => True,
             Require_Refusal => True);
   end Tail_Refusal_Recovery;

   procedure Tail_Budget_Recovery is
      State : World;
   begin
      Initialize (State, (Instructions => 50_000, others => <>));
      Assert (Execute
        (State, "function tailagain(n,a,b,c)" &
         "if n==0 then return a,b,c end;return tailagain(n-1,a,b,c)end",
         "=tail-budget-setup"), Failure_Image (State.Current));
      State.Bounds.Instructions := 100;
      Assert (not Execute
        (State, "pcall(tailagain,1000,1,2,3);error('caught')",
         "=tail-budget-stop"), "tail ownership work escaped the host budget");
      Assert (State.Current.Failure_Class = Host_Abort,
              "tail ownership quota became a catchable Lua failure");
      State.Bounds.Instructions := 1_000;
      Assert (Execute (State, "assert(37==37)", "=tail-budget-recovery"),
              "tail host abort retained an abandoned argument owner");
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "tail host abort retained selected allocations");
   exception
      when others => Finalize (State); raise;
   end Tail_Budget_Recovery;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "C metadata: pure Ada frame capacity",
                        Pure_Ada_Capacity'Access);
      Test_Support.Add (Suite, "C metadata: cached reservation reuse",
                        Cached_Capacity'Access);
      Test_Support.Add (Suite, "C metadata: first surface preserves depth",
                        Surface_Preserves_Warm_Cache'Access);
      Test_Support.Add (Suite, "C metadata: transactional refusal",
                        Refused_Reservation'Access);
      Test_Support.Add (Suite, "C metadata: physical capacity shrink",
                        Physical_Shrink'Access);
      Test_Support.Add (Suite, "C backing: no visible capacity publication",
                        Physical_Headroom_Privacy'Access);
      Test_Support.Add (Suite, "C backing: value array refusal",
                        Headroom_Value_Refusal'Access);
      Test_Support.Add (Suite, "C backing: cell array refusal",
                        Headroom_Cell_Refusal'Access);
      Test_Support.Add (Suite, "C backing: close-link array refusal",
                        Headroom_Close_Refusal'Access);
      Test_Support.Add (Suite, "C metadata: abandoned nested guard recovery",
                        Host_Abort_Recovery'Access);
      Test_Support.Add (Suite, "Equality: primitive string equality",
                        Primitive_Strings'Access);
      Test_Support.Add (Suite, "Equality: integer real NaN equality",
                        Primitive_Numbers'Access);
      Test_Support.Add (Suite, "Equality: false nil equality",
                        Primitive_False_Nil'Access);
      Test_Support.Add (Suite, "Equality: same object skips handler",
                        Same_Object_Equality'Access);
      Test_Support.Add (Suite, "Equality: distinct table handler yields",
                        Table_Equality_Yields'Access);
      Test_Support.Add (Suite, "Equality: distinct userdata handler",
                        Userdata_Equality_Handler'Access);
      Test_Support.Add (Suite, "Equality: charged scan and host recovery",
                        Equality_Budget_Recovery'Access);
      Test_Support.Add (Suite, "C metadata: refused successful assert tuple",
                        Assert_Success_Tuple'Access);
      Test_Support.Add (Suite, "C metadata: protected assert tuple",
                        Assert_Protected_Tuple'Access);
      Test_Support.Add (Suite, "C metadata: fresh state checkstack refusal",
                        Independent_Checkstack_Refusal'Access);
      Test_Support.Add (Suite, "C metadata: first protected entry",
                        First_Protected'Access);
      Test_Support.Add (Suite, "C metadata: nested protected entries",
                        Nested_Protected'Access);
      Test_Support.Add (Suite, "C metadata: numeric protected error",
                        Numeric_Error'Access);
      Test_Support.Add (Suite, "C metadata: false success result",
                        False_Result'Access);
      Test_Support.Add (Suite, "C metadata: zero spare provider bytes",
                        Byte_Ceiling'Access);
      Test_Support.Add (Suite, "C metadata: repeated refused entries",
                        Repeated_Entry'Access);
      Test_Support.Add (Suite, "C metadata: shrink under outstanding call",
                        Outstanding_Shrink'Access);
      Test_Support.Add (Suite, "C metadata: error after outstanding shrink",
                        Error_After_Shrink'Access);
      Test_Support.Add (Suite, "C metadata: cross-context return after shrink",
                        Cross_Context_Return'Access);
      Test_Support.Add (Suite, "C metadata: cross-context error after shrink",
                        Cross_Context_Error'Access);
      Test_Support.Add (Suite, "C metadata: resetCI physical capacity release",
                        ResetCI_Capacity'Access);
      Test_Support.Add (Suite, "C metadata: resetCI outstanding guard",
                        ResetCI_Outstanding'Access);
      Test_Support.Add (Suite, "C metadata: resetCI actual growth refusal",
                        ResetCI_Refusal'Access);
      Test_Support.Add (Suite, "Tail ownership: optimized vararg M0",
                        Optimized_Vararg_Count'Access);
      Test_Support.Add (Suite, "Tail ownership: optimized vararg byte ceiling",
                        Optimized_Vararg_Bytes'Access);
      Test_Support.Add (Suite, "Tail ownership: owned nil tuple",
                        Tail_Tuple'Access);
      Test_Support.Add (Suite, "Tail ownership: recursive owned arena",
                        Tail_Chain'Access);
      Test_Support.Add (Suite, "Tail ownership: retired weak argument",
                        Tail_Weak_Argument'Access);
      Test_Support.Add (Suite, "Tail ownership: actual callee hook mutation",
                        Tail_Hook_Mutation'Access);
      Test_Support.Add (Suite, "Tail ownership: hook error recovery",
                        Tail_Hook_Error'Access);
      Test_Support.Add (Suite, "Tail ownership: yielded callee tuple",
                        Tail_Yield'Access);
      Test_Support.Add (Suite, "Tail ownership: outer close error roots",
                        Tail_Close_Error'Access);
      Test_Support.Add (Suite, "Tail ownership: callee publication refusal",
                        Tail_Refusal_Recovery'Access);
      Test_Support.Add (Suite, "Tail ownership: charged work and recovery",
                        Tail_Budget_Recovery'Access);
   end Register;
end Lua.Call_Metadata_Tests;
