with Ada.Containers;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Stacks;
with Lua.Lexers;
with Lua.Storage; use Lua.Storage;
with Test_Support;

package body Lua.Frame_Cache_Tests is
   use type Ada.Containers.Count_Type;
   use type Byte_Count;
   use type Lua.Lexers.Token_Kind;

   generic
      with procedure Behavior (State : in out World);
   procedure Fixture;
   procedure Fixture is
      State : World;
   begin
      Initialize (State, (others => <>));
      begin
         Behavior (State);
      exception
         when others => Finalize (State); raise;
      end;
      Finalize (State);
      Assert (Statistics (State.Memory).Live_Blocks = 0,
              "context teardown released active and cached records");
   end Fixture;

   procedure Identity_Reuse (State : in out World);
   procedure Cache_Is_Per_Context (State : in out World);
   procedure Retained_Packet_Capacity (State : in out World);
   procedure Private_Arena_Capacity (State : in out World);
   procedure Continuation_State_Reset (State : in out World);
   procedure Captures_Keep_Actual_Cells (State : in out World);
   procedure Cached_Values_Are_Not_Roots (State : in out World);
   procedure Refusing_Provider_Reuses_Frame (State : in out World);
   procedure Double_Return_Rejected (State : in out World);
   procedure Teardown_Active_And_Cached (State : in out World);
   procedure Abandoned_Native_Depth (State : in out World);

   procedure Identity_Reuse (State : in out World) is
      Item : Frame_Access := New_Frame (State);
      Identity : constant Frame_Access := Item;
      Attempts : Byte_Count;
   begin
      --  Return one detached clean frame, then borrow again. The allocator
      --  must see no new request, and the intrusive cache relinquishes its
      --  ownership before the caller receives the same stable identity.
      Return_Frame (Item);
      Attempts := Statistics (State.Memory).Growth_Attempts;
      Assert (Item = null and State.Current.Cache_Count = 1,
              "retirement transferred frame ownership to context cache");
      Item := New_Frame (State);
      Assert (Item = Identity and Item.Context = State.Current and
              Item.Lifecycle = Active and State.Current.Cache_Count = 0,
              "borrow returned clean stable identity from correct context");
      Assert (Statistics (State.Memory).Growth_Attempts = Attempts,
              "warm activation borrow allocated no new storage");
      Return_Frame (Item);
   end Identity_Reuse;

   procedure Cache_Is_Per_Context (State : in out World) is
      Other : constant Context_Id := Create_Context (State);
      Context : constant Context_Access := State.Contexts (Positive (Other));
      Main_Item : Frame_Access := New_Frame (State);
      Other_Item : Frame_Access := New_Frame (State, Context);
      Main_Identity : constant Frame_Access := Main_Item;
      Other_Identity : constant Frame_Access := Other_Item;
   begin
      --  Two inactive caches share one allocator but no frame identities.
      --  Explicit-context creation must not silently use State.Current.
      Return_Frame (Main_Item);
      Return_Frame (Other_Item);
      Main_Item := New_Frame (State);
      Other_Item := New_Frame (State, Context);
      Assert (Main_Item = Main_Identity and Other_Item = Other_Identity and
              Main_Item /= Other_Item and Other_Item.Context = Context,
              "independent execution contexts own independent caches");
      Return_Frame (Main_Item);
      Return_Frame (Other_Item);
   end Cache_Is_Per_Context;

   procedure Retained_Packet_Capacity (State : in out World) is
      Item : Frame_Access := New_Frame (State);
      Capacity : Ada.Containers.Count_Type;
      Error_Capacity : Ada.Containers.Count_Type;
      Attempts : Byte_Count;
      Outgoing : Values.Vector := Owned_Values (State);
   begin
      --  A future memory-error holder needs its already reserved packet.
      --  Retiring removes values but preserves both ordinary/emergency space.
      Item.Native_Arguments.Reserve_Capacity (64);
      Item.Native_Arguments.Append ((Integer_Kind, 42));
      Item.Error_Packet.Reserve_Capacity (2);
      Item.Error_Packet.Append ((Boolean_Kind, False));
      Capacity := Item.Native_Arguments.Capacity;
      Error_Capacity := Item.Error_Packet.Capacity;
      Return_Frame (Item);
      Attempts := Statistics (State.Memory).Growth_Attempts;
      Item := New_Frame (State);
      Assert (Item.Native_Arguments.Is_Empty and Item.Error_Packet.Is_Empty,
              "cached packets retained no logical Lua values");
      Assert (Item.Native_Arguments.Capacity = Capacity and
              Item.Error_Packet.Capacity = Error_Capacity,
              "retirement preserved managed packet capacity");
      Item.Native_Arguments.Append ((Integer_Kind, 1));
      Item.Error_Packet.Append ((Boolean_Kind, False));
      Item.Error_Packet.Append (Nil_Value);
      Assert (Statistics (State.Memory).Growth_Attempts = Attempts,
              "reserved packet publication required no new growth");
      Values.Move (Outgoing, Item.Error_Packet);
      Return_Frame (Item);
      Item := New_Frame (State);
      Assert (Item.Error_Packet.Owner_Of = Reference (State.Memory) and
              Item.Error_Packet.Is_Empty,
              "moved-from error packet regained explicit allocator owner");
      Return_Frame (Item);
   end Retained_Packet_Capacity;

   procedure Private_Arena_Capacity (State : in out World) is
      Item : Frame_Access := New_Frame (State);
      Capacity : Ada.Containers.Count_Type;
      Attempts : Byte_Count;
      procedure Populate (Packet : in out Values.Vector);
      procedure Populate (Packet : in out Values.Vector) is
      begin
         Packet.Reserve_Capacity (16);
         Packet.Append ((Integer_Kind, 42));
      end Populate;
   begin
      --  Keeping only the outer vector's capacity is insufficient: shrinking
      --  its rows destroys nested packet storage. Reuse a smaller active
      --  register set while retaining and clearing the complete row arena.
      Prepare_Private_Registers (Item, 8);
      Item.Slots.Update_Element (8, Populate'Access);
      Capacity := Item.Slots (8).Capacity;
      Return_Frame (Item);
      Attempts := Statistics (State.Memory).Growth_Attempts;
      Item := New_Frame (State);
      Prepare_Private_Registers (Item, 2);
      Assert (Item.Active_Registers = 2 and Item.Slots.Length = 8 and
              Item.Slots (8).Is_Empty and Item.Slots (8).Capacity = Capacity,
              "private arena retained cleared inactive packet rows");
      Prepare_Private_Registers (Item, 8);
      Item.Slots.Update_Element (8, Populate'Access);
      Assert (Statistics (State.Memory).Growth_Attempts = Attempts,
              "reactivated private rows reused nested capacity");
      Return_Frame (Item);
   end Private_Arena_Capacity;

   procedure Continuation_State_Reset (State : in out World) is
      Item : Frame_Access := New_Frame (State);
   begin
      --  Deliberately populate independent continuation/error/hook phases.
      --  A later unrelated call must not inherit any control-flow decisions.
      Item.Is_Native := True;
      Item.Native_Name := To_Unbounded_String ("test");
      Item.Native_Stage := 7;
      Item.Native_Index := 13;
      Item.Native_Aux := 19;
      Item.Native_Operator := Lua.Lexers.Plus;
      Item.Protection := 11;
      Item.Unwind := Error_Exit;
      Item.Unwind_Has_Error := True;
      Item.Unwind_Error := (Integer_Kind, 42);
      Item.Callee := (Native_Kind_Value, Print_Function);
      Item.Entry_Hook_Done := True;
      Item.Return_Hook_Done := True;
      Item.Canonical_Pending := Store_Canonical_Results;
      Item.Canonical_Top := 8;
      Item.Canonical_GC_Top := 8;
      Item.Message_Handler := (Native_Kind_Value, Error_Function);
      Item.Retain_On_Failure := True;
      Return_Frame (Item);
      Item := New_Frame (State);
      Assert (not Item.Is_Native and Length (Item.Native_Name) = 0 and
              Item.Native_Stage = 0 and Item.Native_Index = 0 and
              Item.Native_Aux = 0 and Item.Native_Operator =
                Lua.Lexers.End_Of_Input and Item.Protection = 0,
              "native continuation and protection phases reset");
      Assert (Item.Unwind = No_Unwind and not Item.Unwind_Has_Error and
              Item.Unwind_Error.Kind = Nil_Kind and
              Item.Callee.Kind = Nil_Kind and
              Item.Message_Handler.Kind = Nil_Kind and
              not Item.Retain_On_Failure and not Item.Entry_Hook_Done and
              not Item.Return_Hook_Done and Item.Canonical_Top = 0 and
              Item.Canonical_GC_Top = 0 and
              Item.Canonical_Pending = No_Canonical_Result,
              "Lua roots and hook/canonical phases reset");
      Return_Frame (Item);
   end Continuation_State_Reset;

   procedure Captures_Keep_Actual_Cells (State : in out World) is
      Item : Frame_Access := New_Frame (State);
      Context : constant Context_Access := State.Current;
      Cell : Object_Access;
   begin
      --  Simulate one open canonical register cell in the shared arena.
      --  Retirement detaches its association without changing the actual
      --  captured identity that an escaping closure can retain independently.
      Lua.Engine.Stacks.Reserve (State, Context, 1);
      Lua.Engine.Stacks.Write (State, Context, 1, (Integer_Kind, 42));
      Cell := Lua.Engine.Stacks.Capture (State, Context, 1);
      Item.Stack_Base := 0;
      Item.Stack_Window_Length := 1;
      Item.Has_Stack_Window := True;
      Item.Canonical_Top := 1;
      Item.Canonical_GC_Top := 1;
      Return_Frame (Item);
      Item := New_Frame (State);
      Assert (not Item.Has_Stack_Window and Item.Stack_Window_Length = 0 and
              Context.Stack_Cells (1) = null and
              Cell.Cell_Value = Value'(Integer_Kind, 42),
              "cached frame detached actual cell without changing value");
      Return_Frame (Item);
   end Captures_Keep_Actual_Cells;

   procedure Cached_Values_Are_Not_Roots (State : in out World) is
      Item : Frame_Access := New_Frame (State);
      Held : constant Value := New_Table (State);
   begin
      --  No global/table edge retains Held. It appears only in a retired
      --  native packet; cached capacity must not make that dead edge a root.
      Item.Native_Captures.Append (Held);
      Item.Native_Results.Append (Held);
      Item.Callee := Held;
      Item.Unwind_Error := Held;
      Return_Frame (Item);
      Collect (State);
      Assert (not State.Heap.Contains (Held.Reference) and
              State.Current.Cache_Count = 1,
              "cached activations retained capacity without Lua objects");
   end Cached_Values_Are_Not_Roots;

   procedure Refusing_Provider_Reuses_Frame (State : in out World) is
      Item : Frame_Access := New_Frame (State);
      Identity : constant Frame_Access := Item;
      Attempts : Byte_Count;
   begin
      --  A continuously refusing provider must still permit a warmed frame
      --  to be borrowed and retired; do not retry through a hidden allocator.
      Return_Frame (Item);
      Attempts := Statistics (State.Memory).Growth_Attempts;
      Set_Failure_Countdown (State.Memory, 0);
      Item := New_Frame (State);
      Assert (Item = Identity and
              Statistics (State.Memory).Growth_Attempts = Attempts and
              not Refusal_Pending (State.Memory),
              "warm frame remained usable under permanent growth refusal");
      Return_Frame (Item);
      Clear_Failures (State.Memory);
   end Refusing_Provider_Reuses_Frame;

   procedure Double_Return_Rejected (State : in out World) is
      Item : Frame_Access := New_Frame (State);
      Alias : Frame_Access := Item;
      Failed : Boolean := False;
   begin
      --  A stale alias cannot insert one record twice into an intrusive
      --  cache. Reject the misuse before touching its existing owning edge.
      Return_Frame (Item);
      begin
         Return_Frame (Alias);
      exception
         when Program_Error => Failed := True;
      end;
      Assert (Failed and State.Current.Cache_Count = 1,
              "double retirement left cache structure intact");
   end Double_Return_Rejected;

   procedure Teardown_Active_And_Cached (State : in out World) is
      Item : Frame_Access := New_Frame (State);
   begin
      --  Teardown owns both lists, including partially constructed active
      --  frames. A second world Finalize must be harmless and retain nothing.
      Item.Error_Packet.Reserve_Capacity (2);
      Return_Frame (Item);
      Item := New_Frame (State);
      State.Current.Stack.Append (Item);
      Item := New_Frame (State);
      Item.Native_Arguments.Reserve_Capacity (32);
      Return_Frame (Item);
      Finalize (State);
      Assert (Statistics (State.Memory).Live_Blocks = 0 and
              State.Current = null and State.Contexts.Is_Empty,
              "explicit teardown freed active/cache frames exactly once");
   end Teardown_Active_And_Cached;

   procedure Abandoned_Native_Depth (State : in out World) is
      Thread : constant Value := New_Thread (State, Nil_Value);
      Slot : constant Positive := Thread.Reference.Context_Index;
      Context : constant Context_Access := State.Contexts (Slot);
      Item : Frame_Access := New_Frame (State, Context);
      Main_Item : Frame_Access := New_Frame (State);
      Before : Natural;
   begin
      --  A suspended context retains its own native depth, but scheduler
      --  yield has already excluded it from the active resumer chain. Its
      --  collection must not subtract that excluded charge a second time.
      Main_Item.Is_Native := True;
      Main_Item.Native_Charge := True;
      State.Current.Stack.Append (Main_Item);
      State.Current.Native_Depth := State.Current.Native_Depth + 1;
      State.Native_Depth := State.Native_Depth + 1;
      Before := State.Native_Depth;
      Context.Status := Suspended_Context;
      Item.Is_Native := True;
      Item.Native_Charge := True;
      Context.Stack.Append (Item);
      Context.Native_Depth := 1;
      Item := New_Frame (State, Context);
      Return_Frame (Item);
      Collect (State);
      Assert (State.Contexts (Slot) = null and
              State.Native_Depth = Before,
              "abandoned graph preserved active resumer-chain depth");
      State.Current.Stack.Delete_Last;
      State.Current.Native_Depth := State.Current.Native_Depth - 1;
      State.Native_Depth := State.Native_Depth - 1;
      Return_Frame (Main_Item);
   end Abandoned_Native_Depth;

   procedure Identity_Case is new Fixture (Identity_Reuse);
   procedure Context_Case is new Fixture (Cache_Is_Per_Context);
   procedure Packet_Case is new Fixture (Retained_Packet_Capacity);
   procedure Private_Case is new Fixture (Private_Arena_Capacity);
   procedure Reset_Case is new Fixture (Continuation_State_Reset);
   procedure Capture_Case is new Fixture (Captures_Keep_Actual_Cells);
   procedure Root_Case is new Fixture (Cached_Values_Are_Not_Roots);
   procedure Refusal_Case is new Fixture (Refusing_Provider_Reuses_Frame);
   procedure Double_Case is new Fixture (Double_Return_Rejected);
   procedure Teardown_Case is new Fixture (Teardown_Active_And_Cached);
   procedure Depth_Case is new Fixture (Abandoned_Native_Depth);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "frame cache: stable identity reuse",
                        Identity_Case'Access);
      Test_Support.Add (Suite, "frame cache: per-context ownership",
                        Context_Case'Access);
      Test_Support.Add (Suite, "frame cache: retained packet capacity",
                        Packet_Case'Access);
      Test_Support.Add (Suite, "frame cache: nested private arena capacity",
                        Private_Case'Access);
      Test_Support.Add (Suite, "frame cache: continuation reset",
                        Reset_Case'Access);
      Test_Support.Add (Suite, "frame cache: captured cell detachment",
                        Capture_Case'Access);
      Test_Support.Add (Suite, "frame cache: no retained Lua roots",
                        Root_Case'Access);
      Test_Support.Add (Suite, "frame cache: reuse under allocator refusal",
                        Refusal_Case'Access);
      Test_Support.Add (Suite, "frame cache: duplicate return guard",
                        Double_Case'Access);
      Test_Support.Add (Suite, "frame cache: active/cache teardown",
                        Teardown_Case'Access);
      Test_Support.Add (Suite, "frame cache: abandoned native depth",
                        Depth_Case'Access);
   end Register;
end Lua.Frame_Cache_Tests;
