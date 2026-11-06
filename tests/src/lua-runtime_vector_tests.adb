with Ada.Containers;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Storage; use Lua.Storage;
with Test_Support;

package body Lua.Runtime_Vector_Tests is
   use type Ada.Containers.Count_Type;
   use type Byte_Count;
   use type Integer_Value;

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
              "runtime retained managed storage after explicit finalization");
   end Fixture;

   procedure Constructor_Owners (State : in out World);
   procedure Empty_Packet_Owner (State : in out World);
   procedure Collection_Without_Allocation (State : in out World);
   procedure Suspended_Frame_Packets (State : in out World);
   procedure Failed_Mark_Resets_Queues (State : in out World);
   procedure Packet_Copy_Independence (State : in out World);

   procedure Constructor_Owners (State : in out World) is
      Memory : constant Owner_Access := Reference (State.Memory);
      Scope : constant Object_Access := New_Environment (State, null);
      Native : constant Value := New_Native (State, "owned-test");
      Program : constant Prototype_Access := New_Program (State);
      Closure : Value;
      Activation : constant Frame_Access := New_Frame (State);
   begin
      --  Every constructor must seed future list growth, even when the list
      --  is empty. These objects have no executable code or host callbacks.
      State.Programs.Append (Program);
      Closure := New_Closure (State, Program, null);
      State.Current.Stack.Append (Activation);
      Assert (State.Heap.Owner_Of = Memory and
              State.Contexts.Owner_Of = Memory and
              State.Programs.Owner_Of = Memory,
              "universe ownership indexes selected allocator");
      Assert (Scope.Locals.Owner_Of = Memory and
              Native.Reference.Captures.Owner_Of = Memory and
              Closure.Reference.Upvalues.Owner_Of = Memory,
              "heap variants selected allocator before publication");
      Assert (Activation.Memory = Memory and
              Activation.Native_Arguments.Owner_Of = Memory and
              Activation.Slots.Owner_Of = Memory and
              Activation.Closers.Owner_Of = Memory,
              "activation future packet growth selected allocator");
      Assert (Program.Code.Owner_Of = Memory and
              Program.Parameters.Owner_Of = Memory and
              Program.Names.Owner_Of = Memory,
              "prototype metadata selected allocator");
   end Constructor_Owners;

   procedure Empty_Packet_Owner (State : in out World) is
      Packet : Values.Vector := Owned_Values (State, Values.Empty_Vector);
      Action : Native_Action := New_Action (State);
      Before : constant Byte_Count :=
        Statistics (State.Memory).Growth_Attempts;
   begin
      --  An empty source carries no owner. The explicit universe helper must
      --  bind its result without allocating, so later appends cannot escape.
      Assert (Packet.Owner_Of = Reference (State.Memory) and Packet.Is_Empty,
              "empty packet retained explicit owner");
      Assert (Statistics (State.Memory).Growth_Attempts = Before,
              "empty packet binding required no growth");
      Packet.Append (Nil_Value);
      Action.Results.Append ((Integer_Kind, 42));
      Action.Arguments.Append ((Boolean_Kind, True));
      Assert (Packet.Length = 1 and Action.Results.Length = 1 and
              Action.Arguments.Length = 1,
              "bound empty packets support ordinary owned growth");
   end Empty_Packet_Owner;

   procedure Collection_Without_Allocation (State : in out World) is
      Kept : constant Value := New_Table (State);
      Before_Count : Natural;
      Before_Attempts : Byte_Count;
   begin
      --  Keep one cyclic table alive and abandon many other cycles. Once all
      --  growth is refused, tracing/ephemeron work and compaction must still
      --  finish using only intrusive mark links and existing registry space.
      Set (State, Global_Environment (State), New_String (State, "kept"),
           Kept);
      Set (State, Kept, (Integer_Kind, 1), Kept);
      for Index in 1 .. 128 loop
         declare
            Left : constant Value := New_Table (State);
            Right : constant Value := New_Table (State);
         begin
            Set (State, Left, (Integer_Kind, 1), Right);
            Set (State, Right, (Integer_Kind, 1), Left);
         end;
      end loop;
      Before_Count := Natural (State.Heap.Length);
      --  Emergency collection conservatively retains objects born during
      --  the current atomic operation. Begin after constructing the garbage,
      --  so these older cycles are eligible while any new temporaries root.
      Begin_Operation (State);
      Before_Attempts := Statistics (State.Memory).Growth_Attempts;
      Set_Failure_Countdown (State.Memory, 0);
      Collect (State, Emergency => True);
      Assert (Statistics (State.Memory).Growth_Attempts = Before_Attempts,
              "emergency collection attempted managed growth");
      Assert (not Refusal_Pending (State.Memory),
              "allocation-free collection reached allocator refusal");
      Assert (Natural (State.Heap.Length) <= Before_Count - 256,
              "unreachable cycles reclaimed without scratch allocation");
      Assert (Get (Kept, (Integer_Kind, 1)) = Kept,
              "reachable cycle survived allocation-free marking");
      End_Operation (State);
      Clear_Failures (State.Memory);
   end Collection_Without_Allocation;

   procedure Suspended_Frame_Packets (State : in out World) is
      Thread : constant Value := New_Thread (State, Nil_Value);
      Slot : constant Positive := Thread.Reference.Context_Index;
      Context : constant Context_Access := State.Contexts (Slot);
      Activation : constant Frame_Access := New_Frame (State, Context);
      Held : constant Value := New_Table (State);
      Key : constant Value := New_String (State, "owned-thread");
   begin
      --  A suspended Lua-owned context is reached through its thread, and
      --  its managed native packet is the sole strong edge to Held. Dropping
      --  the thread must release that packet/context rather than root forever.
      Context.Status := Suspended_Context;
      Activation.Is_Native := True;
      Activation.Native_Arguments.Append (Held);
      Context.Stack.Append (Activation);
      Set (State, Global_Environment (State), Key, Thread);
      Collect (State);
      Assert (State.Heap.Contains (Held.Reference),
              "reachable suspended packet retained table");
      Set (State, Global_Environment (State), Key, Nil_Value);
      Collect (State);
      Assert (State.Contexts (Slot) = null,
              "unreachable Lua context released its managed frame packets");
   end Suspended_Frame_Packets;

   procedure Failed_Mark_Resets_Queues (State : in out World) is
      Thread : constant Value := New_Thread (State, Nil_Value);
      Valid_Slot : constant Positive := Thread.Reference.Context_Index;
      Failed : Boolean := False;
   begin
      --  Deliberately violate one private registry link to interrupt marking
      --  before sweep. Restoring it must permit another collection;
      --  no stale mark color or intrusive link can hide a reachable object.
      Set (State, Global_Environment (State), New_String (State, "mark-test"),
           Thread);
      Thread.Reference.Context_Index := State.Contexts.Last_Index + 1;
      begin
         Collect (State);
      exception
         when Constraint_Error => Failed := True;
      end;
      Thread.Reference.Context_Index := Valid_Slot;
      Assert (Failed and not State.Collector_Active,
              "failed marking restored collector lifecycle");
      for Item of State.Heap loop
         Assert (not Item.Marked and Item.Mark_Next = null,
                 "failed marking cleared object colors and queue links");
      end loop;
      for Program of State.Programs loop
         Assert (not Program.Marked and Program.Mark_Next = null,
                 "failed marking cleared prototype colors and links");
      end loop;
      Collect (State);
      Assert (State.Heap.Contains (Thread.Reference),
              "collection recovered after repaired registry invariant");
   end Failed_Mark_Resets_Queues;

   procedure Packet_Copy_Independence (State : in out World) is
      Source : Values.Vector := One_Value (State, (Integer_Kind, 17));
      Copy : Values.Vector := Owned_Values (State, Source);
   begin
      --  Runtime packet copies retain an explicit allocator and independent
      --  storage. Mutating one continuation's results must not affect another.
      Copy.Replace_Element (1, (Integer_Kind, 23));
      Source.Append ((Boolean_Kind, True));
      Assert (Source.First_Element.Integer_Data = 17 and
              Copy.First_Element.Integer_Data = 23 and Copy.Length = 1,
              "owned packet copy preserved continuation independence");
      Assert (Source.Owner_Of = Reference (State.Memory) and
              Copy.Owner_Of = Reference (State.Memory),
              "both packet allocations belong to their universe");
   end Packet_Copy_Independence;

   procedure Constructor_Case is new Fixture (Constructor_Owners);
   procedure Empty_Case is new Fixture (Empty_Packet_Owner);
   procedure Collection_Case is new Fixture (Collection_Without_Allocation);
   procedure Suspended_Case is new Fixture (Suspended_Frame_Packets);
   procedure Mark_Failure_Case is new Fixture (Failed_Mark_Resets_Queues);
   procedure Copy_Case is new Fixture (Packet_Copy_Independence);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "runtime vectors: constructor owners",
                        Constructor_Case'Access);
      Test_Support.Add (Suite, "runtime vectors: bound empty packets",
                        Empty_Case'Access);
      Test_Support.Add (Suite, "runtime vectors: allocation-free collection",
                        Collection_Case'Access);
      Test_Support.Add (Suite, "runtime vectors: suspended packet lifetime",
                        Suspended_Case'Access);
      Test_Support.Add (Suite, "runtime vectors: failed mark recovery",
                        Mark_Failure_Case'Access);
      Test_Support.Add (Suite, "runtime vectors: independent packet copies",
                        Copy_Case'Access);
   end Register;
end Lua.Runtime_Vector_Tests;
