with Ada.Containers;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Storage; use Lua.Storage;
with Test_Support;

package body Lua.Root_Packet_Tests is
   use type Ada.Containers.Count_Type;
   use type Integer_Value;
   use type Byte_Count;

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
         when others =>
            Clear_Failures (State.Memory);
            Finalize (State);
            raise;
      end;
      Clear_Failures (State.Memory);
      Finalize (State);
      Assert (Statistics (State.Memory).Live_Blocks = 0,
              "root packet fixture released all managed storage");
   end Fixture;

   procedure Copy_Uses_Retained_Capacity (State : in out World);
   procedure Copy_Failure_Preserves_Target (State : in out World);
   procedure Copy_Self_Is_No_Op (State : in out World);
   procedure Move_Is_Allocation_Free (State : in out World);
   procedure Cross_Owner_Rejected (State : in out World);
   procedure Append_Publishes_Current_Root (State : in out World);
   procedure Append_Capture_Edge (State : in out World);
   procedure Replace_Capture_Edge (State : in out World);

   procedure Copy_Uses_Retained_Capacity (State : in out World) is
      Target : Values.Vector := Owned_Values (State);
      Source : constant Values.Vector :=
        One_Value (State, Value'(Integer_Kind, 17));
      Capacity : Ada.Containers.Count_Type;
      Attempts : Byte_Count;
   begin
      --  Copying into a reused root packet must preserve its capacity/owner.
      --  A refusing allocator proves this is not ordinary controlled-vector
      --  assignment, which would deep-copy and discard the prepared buffer.
      Target.Reserve_Capacity (64);
      Capacity := Target.Capacity;
      Attempts := Statistics (State.Memory).Growth_Attempts;
      Set_Failure_Countdown (State.Memory, 0);
      Copy_Roots (State, Target, Source);
      Assert (Target.Length = 1 and Target.First_Element.Integer_Data = 17 and
              Target.Capacity = Capacity and Target.Owner_Of =
                Reference (State.Memory) and
              Statistics (State.Memory).Growth_Attempts = Attempts,
              "root copy reused prepared capacity without allocation");
      Clear_Failures (State.Memory);
   end Copy_Uses_Retained_Capacity;

   procedure Copy_Failure_Preserves_Target (State : in out World) is
      Target : Values.Vector := One_Value (State, Value'(Integer_Kind, 3));
      Source : Values.Vector := Owned_Values (State);
      Refused : Boolean := False;
   begin
      --  Reserve before clearing makes failed growth non-destructive. Keep
      --  an old target value and a larger source, then refuse the new buffer.
      for Index in 1 .. 128 loop
         Source.Append (Value'(Integer_Kind, Integer_Value (Index)));
      end loop;
      Set_Failure_Countdown (State.Memory, 0);
      begin
         Copy_Roots (State, Target, Source);
      exception
         when Allocation_Error => Refused := True;
      end;
      Assert (Refused and Target.Length = 1 and
              Target.First_Element.Integer_Data = 3 and Source.Length = 128,
              "failed root copy retained old destination and source");
      Clear_Failures (State.Memory);
      Acknowledge_Refusal (State.Memory);
   end Copy_Failure_Preserves_Target;

   procedure Copy_Self_Is_No_Op (State : in out World) is
      Packet : Values.Vector := One_Value (State, Value'(Integer_Kind, 9));
      Capacity : constant Ada.Containers.Count_Type := Packet.Capacity;
      Attempts : constant Byte_Count :=
        Statistics (State.Memory).Growth_Attempts;
   begin
      --  Tagged packets are by-reference. Detect actual self-copy/move before
      --  clearing, releasing or borrowing either buffer, even under refusal.
      Set_Failure_Countdown (State.Memory, 0);
      Copy_Roots (State, Packet, Packet);
      Move_Roots (State, Packet, Packet);
      Assert (Packet.Length = 1 and Packet.First_Element.Integer_Data = 9 and
              Packet.Capacity = Capacity and
              Statistics (State.Memory).Growth_Attempts = Attempts,
              "actual packet self operations preserved ownership and value");
      Clear_Failures (State.Memory);
   end Copy_Self_Is_No_Op;

   procedure Move_Is_Allocation_Free (State : in out World) is
      Source : Values.Vector := One_Value (State, Value'(Integer_Kind, 23));
      Target : Values.Vector := Owned_Values (State);
      Capacity : constant Ada.Containers.Count_Type := Source.Capacity;
      Attempts : Byte_Count;
   begin
      --  Transfer the already owned buffer under permanent refusal, then
      --  verify the source's explicit empty binding can grow again normally.
      Target.Reserve_Capacity (32);
      Attempts := Statistics (State.Memory).Growth_Attempts;
      Set_Failure_Countdown (State.Memory, 0);
      Move_Roots (State, Target, Source);
      Assert (Target.Length = 1 and Target.First_Element.Integer_Data = 23 and
              Target.Capacity = Capacity and Source.Is_Empty and
              Source.Owner_Of = Reference (State.Memory) and
              Statistics (State.Memory).Growth_Attempts = Attempts,
              "root move transferred buffer and rebound empty source");
      Clear_Failures (State.Memory);
      Append_Root (State, Source, Value'(Integer_Kind, 24));
      Assert (Source.First_Element.Integer_Data = 24,
              "moved-from root source retained explicit growth policy");
   end Move_Is_Allocation_Free;

   procedure Cross_Owner_Rejected (State : in out World) is
      Other : World;
      Rejected : Boolean := False;
   begin
      --  Even scalar-looking packets carry their own universe policy. A
      --  rejected foreign packet must not alter the destination or rebind it
      --  silently; local containers finalize before their owner's teardown.
      Initialize (Other, (others => <>));
      begin
         declare
            Source : constant Values.Vector :=
              One_Value (Other, Value'(Integer_Kind, 5));
            Target : Values.Vector :=
              One_Value (State, Value'(Integer_Kind, 7));
         begin
            begin
               Copy_Roots (State, Target, Source);
            exception
               when Program_Error => Rejected := True;
            end;
            Assert (Rejected and Target.First_Element.Integer_Data = 7,
                    "cross-universe root publication was rejected intact");
         end;
      exception
         when others => Finalize (Other); raise;
      end;
      Finalize (Other);
   end Cross_Owner_Rejected;

   procedure Append_Publishes_Current_Root (State : in out World) is
      Activation : Frame_Access := New_Frame (State);
      Child : Value;
      Serial : Positive;
      Done : Boolean := False;
   begin
      --  Publish into an actual active native packet after the root wave
      --  started. The explicit helper shades that new value immediately;
      --  the attached activation owns its lifetime across later safe points.
      State.Current.Stack.Append (Activation);
      Advance_Collection (State, 1, Done);
      Child := New_Table (State);
      Serial := Child.Reference.Serial;
      Append_Root (State, Activation.Native_Captures, Child);
      Assert (Child.Reference.Color = Gray,
              "new packet root was immediately shaded during propagation");
      while not Done loop
         Advance_Collection (State, 32, Done);
      end loop;
      Assert (State.Heap.Contains (Child.Reference) and
              Child.Reference.Serial = Serial,
              "actual activation packet retained published object");
      State.Current.Stack.Delete_Last;
      Return_Frame (Activation);
   end Append_Publishes_Current_Root;

   procedure Append_Capture_Edge (State : in out World) is
      Holder : constant Value := New_Native (State, "root-append");
      Cell : Object_Access;
      Item : Value;
      Done : Boolean;
   begin
      --  A forward cell-edge publication into an old closure must promote
      --  the real new cell to OLD0 while retaining its younger value graph.
      Pin (State, Holder);
      Set_Collector_Mode (State, Generational_Minor_Mode);
      Item := New_Table (State);
      Cell := New_Cell (State, Item);
      Append_Object_Edge (State, Holder.Reference,
                          Holder.Reference.Captures, Cell);
      Assert (Cell.Age = Old_0_Age and Cell.Color = Gray,
              "actual closure edge applied the generational forward barrier");
      Advance_Collection (State, 1, Done);
      Assert (Done and State.Heap.Contains (Item.Reference),
              "new captured cell retained its younger referent");
   end Append_Capture_Edge;

   procedure Replace_Capture_Edge (State : in out World) is
      Holder : constant Value := New_Native
        (State, "root-replace", One_Value (State, Nil_Value));
      Cell : Object_Access;
      Done : Boolean;
   begin
      --  Upvalue joining replaces the actual ordered cell identity, rather
      --  than copying a value or synthesizing a function/index identity.
      Pin (State, Holder);
      Set_Collector_Mode (State, Generational_Minor_Mode);
      Cell := New_Cell (State, Value'(Integer_Kind, 31));
      Replace_Object_Edge (State, Holder.Reference,
                           Holder.Reference.Captures, 1, Cell);
      Advance_Collection (State, 1, Done);
      Assert (Done and Holder.Reference.Captures (1) = Cell and
              Cell.Cell_Value.Integer_Data = 31,
              "capture replacement retained actual shared binding identity");
   end Replace_Capture_Edge;

   procedure Capacity_Case is new Fixture (Copy_Uses_Retained_Capacity);
   procedure Refusal_Case is new Fixture (Copy_Failure_Preserves_Target);
   procedure Self_Case is new Fixture (Copy_Self_Is_No_Op);
   procedure Move_Case is new Fixture (Move_Is_Allocation_Free);
   procedure Owner_Case is new Fixture (Cross_Owner_Rejected);
   procedure Root_Case is new Fixture (Append_Publishes_Current_Root);
   procedure Append_Case is new Fixture (Append_Capture_Edge);
   procedure Replace_Case is new Fixture (Replace_Capture_Edge);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "root packets: retained destination capacity",
                        Capacity_Case'Access);
      Test_Support.Add (Suite, "root packets: failed copy preserves value",
                        Refusal_Case'Access);
      Test_Support.Add (Suite, "root packets: actual self copy and move",
                        Self_Case'Access);
      Test_Support.Add (Suite, "root packets: allocation-free owned transfer",
                        Move_Case'Access);
      Test_Support.Add (Suite, "root packets: independent owner rejection",
                        Owner_Case'Access);
      Test_Support.Add (Suite, "root packets: interleaved actual publication",
                        Root_Case'Access);
      Test_Support.Add (Suite, "root packets: actual capture append barrier",
                        Append_Case'Access);
      Test_Support.Add (Suite, "root packets: actual cell replacement barrier",
                        Replace_Case'Access);
   end Register;
end Lua.Root_Packet_Tests;
