with Ada.Containers;
with Ada.Finalization;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Storage; use Lua.Storage;
with Lua.Storage.Vectors;
with System;
with Test_Support;

package body Lua.Storage_Vector_Tests is
   use type Ada.Containers.Count_Type;
   use type Byte_Count;
   use type System.Address;

   package Integers is new Lua.Storage.Vectors (Integer);
   package Nested is new Lua.Storage.Vectors
     (Integers.Vector, Integers."=");
   type Default_Item is record
      Number : Integer := 42;
   end record;
   package Defaults is new Lua.Storage.Vectors (Default_Item);
   use type Integers.Vector;

   --  Give each controlled copy a distinct identity. Unlike the managed
   --  vector's deliberately idempotent Finalize, this probe records repeated
   --  finalization of the same object so subpool ordering bugs stay visible.
   Next_Id : Natural := 0;
   Finalizations : array (Positive range 1 .. 512) of Natural := [others => 0];
   type Counted_Item is new Ada.Finalization.Controlled with record
      Id : Natural := 0;
   end record;
   overriding procedure Adjust (Self : in out Counted_Item);
   overriding procedure Finalize (Self : in out Counted_Item);
   overriding procedure Adjust (Self : in out Counted_Item) is
   begin
      Next_Id := Next_Id + 1;
      Self.Id := Next_Id;
   end Adjust;
   overriding procedure Finalize (Self : in out Counted_Item) is
   begin
      if Self.Id /= 0 then
         Finalizations (Self.Id) := Finalizations (Self.Id) + 1;
      end if;
   end Finalize;
   package Counted is new Lua.Storage.Vectors (Counted_Item);
   type Counted_Vector_Access is access Counted.Vector;
   for Counted_Vector_Access'Storage_Pool use Pool;

   procedure Binding_Required;
   procedure Geometric_Growth;
   procedure Indexed_Mutation;
   procedure Independent_Copy;
   procedure Failed_Copy_Preserves_Source;
   procedure Nested_Delete_Releases;
   procedure Update_Stored_Nested_Vector;
   procedure Reference_Blocks_Tampering;
   procedure Iteration_Blocks_Tampering;
   procedure Update_Exception_Releases_Borrow;
   procedure Length_Defaults;
   procedure Insert_Delete_Order;
   procedure Growth_Failure_Is_Atomic;
   procedure Clear_Retains_Owner;
   procedure Rebinding_Allocated_Rejected;
   procedure Self_Append;
   procedure Subpool_Nested_Finalization;
   procedure Move_Transfers_Allocation;
   procedure Move_Empty_Capacity;
   procedure Move_Borrowed_Source_Rejected;
   procedure Move_Borrowed_Target_Rejected;
   procedure Move_Self_Preserves_Storage;
   procedure Move_Controlled_Elements;
   procedure Release_Preserves_Binding;
   procedure Concatenation_Carries_Owner;
   procedure Concatenation_Refusal_Preserves_Inputs;
   procedure Prepend_And_Swap;

   procedure Binding_Required is
      Data : Integers.Vector;
      Rejected : Boolean := False;
   begin
      --  A local vector has no implicit universe. Allocating without explicit
      --  binding must fail instead of escaping the state's allocator policy.
      begin
         Data.Append (1);
      exception
         when Program_Error => Rejected := True;
      end;
      Assert (Rejected and Data.Is_Empty, "unowned append rejected");
   end Binding_Required;

   procedure Geometric_Growth is
      Memory : Owner;
      Data : Integers.Vector;
   begin
      --  A long flat vector should require logarithmically many allocations,
      --  protecting compiler/VM stacks against growth-by-one regressions.
      Data.Set_Owner (Reference (Memory));
      for Index in 1 .. 4_096 loop
         Data.Append (Index);
      end loop;
      Assert (Data.Length = 4_096 and Data.Last_Element = 4_096,
              "geometric append content");
      Assert (Statistics (Memory).Growth_Attempts < 20,
              "amortized growth allocation count");
      Assert (Data.Capacity >= Data.Length and Data.Capacity <= 8_192,
              "bounded geometric spare capacity");
   end Geometric_Growth;

   procedure Indexed_Mutation is
      Memory : Owner;
      Data : Integers.Vector;
   begin
      --  Exercise both Ada indexing aspects. Assignment must mutate the live
      --  element; reading it must release its temporary borrow afterwards.
      Data.Set_Owner (Reference (Memory));
      Data.Append (10, 2);
      Data (2) := 42;
      Assert (Data (1) = 10 and Data (2) = 42, "indexed mutation");
      Data.Append (99);
      Assert (Data.Last_Element = 99, "index borrow released");
   end Indexed_Mutation;

   procedure Independent_Copy is
      Memory : Owner;
      Source : Integers.Vector;
   begin
      --  Controlled copying retains allocator ownership but not data aliasing.
      --  Destruction of the copy must leave the original allocation intact.
      Source.Set_Owner (Reference (Memory));
      Source.Append (17);
      declare
         Duplicate : Integers.Vector := Integers.Copy (Source);
      begin
         Assert (Duplicate.Owner_Of = Source.Owner_Of, "copy inherited owner");
         Assert (Duplicate = Source, "copy initially equal");
         Duplicate (1) := 23;
         Assert (Source (1) = 17 and Duplicate (1) = 23,
                 "copy buffers independent");
      end;
      Assert (Statistics (Memory).Live_Blocks = 1, "copy finalized alone");
   end Independent_Copy;

   procedure Failed_Copy_Preserves_Source is
      Memory : Owner;
      Source : Integers.Vector;
      Failed : Boolean := False;
   begin
      --  Allocation inside Adjust may be wrapped as Program_Error by Ada.
      --  The owner's witness retains memory-error classification, and failed
      --  copy cleanup must never release the source's shallow-copied pointer.
      Source.Set_Owner (Reference (Memory));
      Source.Append (73);
      Set_Failure_Countdown (Memory, 0);
      begin
         declare
            Duplicate : constant Integers.Vector := Integers.Copy (Source);
         begin
            Assert (Duplicate.Length = 1, "copy unexpectedly succeeded");
         end;
      exception
         when Allocation_Error | Program_Error => Failed := True;
      end;
      Assert (Failed and Refusal_Pending (Memory), "copy failure witness");
      Assert (Source (1) = 73 and Statistics (Memory).Live_Blocks = 1,
              "failed copy retained source");
      Acknowledge_Refusal (Memory);
      Clear_Failures (Memory);
      Source.Append (74);
      Assert (not Refusal_Pending (Memory), "copy failure acknowledged");
   end Failed_Copy_Preserves_Source;

   procedure Nested_Delete_Releases is
      Memory : Owner;
      Inner : Integers.Vector;
      Outer : Nested.Vector;
   begin
      --  Deleting an outer slot must finalize the nested vector immediately,
      --  even while outer capacity remains allocated for reuse.
      Inner.Set_Owner (Reference (Memory));
      Outer.Set_Owner (Reference (Memory));
      Inner.Append (1);
      Outer.Append (Inner);
      Assert (Statistics (Memory).Live_Blocks = 3, "three owned buffers");
      Outer.Delete_Last;
      Assert (Statistics (Memory).Live_Blocks = 2,
              "removed nested element finalized");
      Assert (Inner (1) = 1, "original inner remains independent");
   end Nested_Delete_Releases;

   procedure Update_Stored_Nested_Vector is
      Memory : Owner;
      Inner : Integers.Vector;
      Outer : Nested.Vector;
      procedure Add_Item (Item : in out Integers.Vector);
      procedure Add_Item (Item : in out Integers.Vector) is
      begin
         Item.Append (2);
      end Add_Item;
   begin
      --  Update_Element must borrow the stored child rather than copy it out
      --  and back. This is the compiler's linear-time child-append operation.
      Inner.Set_Owner (Reference (Memory));
      Outer.Set_Owner (Reference (Memory));
      Inner.Append (1);
      Outer.Append (Inner);
      Outer.Update_Element (1, Add_Item'Access);
      Assert (Outer (1).Length = 2 and Inner.Length = 1,
              "updated actual stored child");
   end Update_Stored_Nested_Vector;

   procedure Reference_Blocks_Tampering is
      Memory : Owner;
      Data : aliased Integers.Vector;
      Rejected : Boolean := False;
   begin
      --  A retained variable reference keeps its address valid by prohibiting
      --  structural mutation until the reference object's finalizer runs.
      Data.Set_Owner (Reference (Memory));
      Data.Append (1);
      declare
         Item : constant Integers.Reference_Type := Data.Reference (1);
      begin
         Item.Element.all := 42;
         begin
            Data.Append (2);
         exception
            when Program_Error => Rejected := True;
         end;
      end;
      Assert (Rejected and Data (1) = 42, "borrow prevented relocation");
      Data.Append (2);
      Assert (Data.Length = 2, "reference finalizer released borrow");
   end Reference_Blocks_Tampering;

   procedure Iteration_Blocks_Tampering is
      Memory : Owner;
      Data : Integers.Vector;
      Total : Integer := 0;
      Rejected : Boolean := False;
   begin
      --  For-of must visit live elements without copied containers. Its
      --  iterator also protects the buffer against append/delete during use.
      Data.Set_Owner (Reference (Memory));
      Data.Append (3, 3);
      for Item of Data loop
         Total := Total + Item;
         begin
            Data.Append (4);
         exception
            when Program_Error => Rejected := True;
         end;
      end loop;
      Assert (Total = 9 and Rejected, "iteration contents and tampering");
      Data.Append (4);
      Assert (Data.Length = 4, "iterator finalizer released borrow");
   end Iteration_Blocks_Tampering;

   procedure Update_Exception_Releases_Borrow is
      Memory : Owner;
      Data : Integers.Vector;
      Raised : Boolean := False;
      procedure Reject (Item : in out Integer);
      procedure Reject (Item : in out Integer) is
         pragma Unreferenced (Item);
      begin
         raise Constraint_Error with "update callback";
      end Reject;
   begin
      --  A raising update callback must release its borrow so subsequent
      --  vector operations recover with their existing elements intact.
      Data.Set_Owner (Reference (Memory));
      Data.Append (1);
      begin
         Data.Update_Element (1, Reject'Access);
      exception
         when Constraint_Error => Raised := True;
      end;
      Data.Append (2);
      Assert (Raised and Data (1) = 1 and Data.Length = 2,
              "update error released borrow");
   end Update_Exception_Releases_Borrow;

   procedure Length_Defaults is
      Memory : Owner;
      Data : Defaults.Vector;
   begin
      --  Growing length invokes Ada default initialization of each newly live
      --  slot. Shrinking removes values while preserving buffer capacity.
      Data.Set_Owner (Reference (Memory));
      Data.Set_Length (3);
      Assert (Data (3).Number = 42, "new element default initialized");
      Data.Set_Length (1);
      Assert (Data.Length = 1 and Data.Capacity >= 3, "length shrink");
   end Length_Defaults;

   procedure Insert_Delete_Order is
      Memory : Owner;
      Data : Integers.Vector;
   begin
      --  Shift a middle suffix in both directions, then replace/search. This
      --  protects ordered scope/register storage against off-by-one shifts.
      Data.Set_Owner (Reference (Memory));
      Data.Append (1);
      Data.Append (3);
      Data.Insert (2, 2, 2);
      Assert (Data.Length = 4 and Data (2) = 2 and Data (4) = 3,
              "insertion shifted suffix");
      Data.Delete (2, 2);
      Data.Replace_Element (2, 4);
      Assert (Data.First_Element = 1 and Data.Last_Element = 4,
              "deletion shifted suffix");
      Assert (Data.Contains (4) and Data.Find_Index (1) = 1,
              "search live elements");
   end Insert_Delete_Order;

   procedure Growth_Failure_Is_Atomic is
      Memory : Owner;
      Data : Integers.Vector;
      Old_Capacity : Ada.Containers.Count_Type;
      Failed : Boolean := False;
   begin
      --  Refuse a replacement buffer before publication. Existing values and
      --  capacity must survive unchanged so engine allocation retry is safe.
      Data.Set_Owner (Reference (Memory));
      Data.Append (7, 3);
      Old_Capacity := Data.Capacity;
      Set_Failure_Countdown (Memory, 0);
      begin
         Data.Reserve_Capacity (Old_Capacity + 1);
      exception
         when Allocation_Error => Failed := True;
      end;
      Assert (Failed and Data.Length = 3 and Data.Capacity = Old_Capacity,
              "failed reserve retained shape");
      Assert (Data (3) = 7, "failed reserve retained payload");
   end Growth_Failure_Is_Atomic;

   procedure Clear_Retains_Owner is
      Memory : Owner;
      Data : Integers.Vector;
      Old_Capacity : Ada.Containers.Count_Type;
   begin
      --  Reuse is explicit: Clear keeps the bound owner and spare capacity,
      --  avoiding accidental unowned appends after resetting temporary lists.
      Data.Set_Owner (Reference (Memory));
      Data.Append (1);
      Old_Capacity := Data.Capacity;
      Data.Clear;
      Assert (Data.Is_Empty and Data.Capacity = Old_Capacity,
              "clear retained capacity");
      Assert (Data.Owner_Of = Reference (Memory), "clear retained owner");
      Data.Append (2);
      Assert (Data (1) = 2, "clear then append");
   end Clear_Retains_Owner;

   procedure Rebinding_Allocated_Rejected is
      First, Second : Owner;
      Data : Integers.Vector;
      Rejected : Boolean := False;
   begin
      --  Spare capacity is still owned storage after Clear. Rebinding it to
      --  another allocator would free through the wrong provider: reject it.
      Data.Set_Owner (Reference (First));
      Data.Append (1);
      Data.Clear;
      begin
         Data.Set_Owner (Reference (Second));
      exception
         when Program_Error => Rejected := True;
      end;
      Assert (Rejected and Data.Owner_Of = Reference (First),
              "allocated vector retained original owner");
   end Rebinding_Allocated_Rejected;

   procedure Self_Append is
      Memory : Owner;
      Data : Integers.Vector;
   begin
      --  Self append reads its original prefix while growing geometrically.
      --  Increasing length must not extend the source loop indefinitely.
      Data.Set_Owner (Reference (Memory));
      Data.Append (1);
      Data.Append (2);
      Data.Append (Data);
      Assert (Data.Length = 4 and Data (3) = 1 and Data (4) = 2,
              "self append copied original prefix");
   end Self_Append;

   procedure Subpool_Nested_Finalization is
   begin
      --  Both a vector object and its later-created buffer belong to one
      --  subpool. The buffer is visited first during Close, then the vector
      --  frees it. Every real controlled copy must still be finalized once.
      Next_Id := 0;
      Finalizations := [others => 0];
      declare
         Memory : Owner;
         Source : Counted_Item;
         Data : Counted_Vector_Access;
      begin
         Next_Id := 1;
         Source.Id := 1;
         Data := new (Handle (Memory)) Counted.Vector;
         Data.Set_Owner (Reference (Memory));
         Data.Append (Source);
         Close (Memory);
      end;
      for Index in 1 .. Next_Id loop
         Assert (Finalizations (Index) = 1,
                 "controlled vector element finalized exactly once");
      end loop;
   end Subpool_Nested_Finalization;

   procedure Move_Transfers_Allocation is
      From_Memory, To_Memory : Owner;
      Source, Target : aliased Integers.Vector;
      Original : System.Address;
   begin
      --  Prepare distinct providers and an occupied destination. Even when
      --  both providers refuse growth, moving must free the old destination,
      --  preserve the source element's address and transfer its actual owner.
      Source.Set_Owner (Reference (From_Memory));
      Target.Set_Owner (Reference (To_Memory));
      Source.Append (73);
      Target.Append (19);
      declare
         Item : constant Integers.Constant_Reference_Type :=
           Source.Constant_Reference (1);
      begin
         Original := Item.Element.all'Address;
      end;
      Set_Failure_Countdown (From_Memory, 0);
      Set_Failure_Countdown (To_Memory, 0);
      Integers.Move (Target, Source);
      Assert (Source.Is_Empty and Source.Owner_Of = null,
              "move consumed source binding");
      Assert (Target.Owner_Of = Reference (From_Memory) and Target (1) = 73,
              "move transferred source owner and payload");
      Assert (Statistics (To_Memory).Live_Blocks = 0 and
              Statistics (From_Memory).Live_Blocks = 1,
              "move released previous destination only");
      Assert (not Refusal_Pending (From_Memory) and
              not Refusal_Pending (To_Memory), "move did not allocate");
      declare
         Item : constant Integers.Constant_Reference_Type :=
           Target.Constant_Reference (1);
      begin
         Assert (Item.Element.all'Address = Original,
                 "move preserved actual element address");
      end;
   end Move_Transfers_Allocation;

   procedure Move_Empty_Capacity is
      Memory : Owner;
      Source, Target : Integers.Vector;
      Reserved : Ada.Containers.Count_Type;
   begin
      --  An empty vector can still own reserved capacity. Transfer that spare
      --  storage as well as the binding, so the destination can reuse it while
      --  the consumed source cannot silently allocate through a stale owner.
      Source.Set_Owner (Reference (Memory));
      Source.Reserve_Capacity (8);
      Reserved := Source.Capacity;
      Set_Failure_Countdown (Memory, 0);
      Integers.Move (Target, Source);
      Target.Append (11);
      Assert (Target.Capacity = Reserved and Target (1) = 11,
              "move retained empty reserved storage");
      Assert (Source.Capacity = 0 and Source.Owner_Of = null,
              "empty source surrendered all storage");
      Assert (not Refusal_Pending (Memory), "reserved move reused capacity");
   end Move_Empty_Capacity;

   procedure Move_Borrowed_Source_Rejected is
      Memory : Owner;
      Source : aliased Integers.Vector;
      Target : Integers.Vector;
      Rejected : Boolean := False;
   begin
      --  A live source view must keep its address and vector identity. Refuse
      --  before freeing the destination; retry successfully after it expires.
      Source.Set_Owner (Reference (Memory));
      Target.Set_Owner (Reference (Memory));
      Source.Append (1);
      Target.Append (2);
      declare
         Item : constant Integers.Constant_Reference_Type :=
           Source.Constant_Reference (1);
      begin
         begin
            Integers.Move (Target, Source);
         exception
            when Program_Error => Rejected := True;
         end;
         Assert (Item.Element.all = 1, "rejected move retained source view");
      end;
      Assert (Rejected and Source (1) = 1 and Target (1) = 2,
              "source borrow rejected move atomically");
      Integers.Move (Target, Source);
      Assert (Source.Is_Empty and Target (1) = 1,
              "move recovered after source borrow");
   end Move_Borrowed_Source_Rejected;

   procedure Move_Borrowed_Target_Rejected is
      Memory : Owner;
      Source : Integers.Vector;
      Target : aliased Integers.Vector;
      Rejected : Boolean := False;
   begin
      --  Destination references are equally protected: cleanup cannot destroy
      --  an element still borrowed by a caller. Neither vector may be changed.
      Source.Set_Owner (Reference (Memory));
      Target.Set_Owner (Reference (Memory));
      Source.Append (1);
      Target.Append (2);
      declare
         Item : constant Integers.Reference_Type := Target.Reference (1);
      begin
         begin
            Integers.Move (Target, Source);
         exception
            when Program_Error => Rejected := True;
         end;
         Item.Element.all := 3;
      end;
      Assert (Rejected and Source (1) = 1 and Target (1) = 3,
              "target borrow rejected move atomically");
      Integers.Move (Target, Source);
      Assert (Source.Is_Empty and Target (1) = 1,
              "move recovered after destination borrow");
   end Move_Borrowed_Target_Rejected;

   procedure Move_Self_Preserves_Storage is
      Memory : Owner;
      Data : Integers.Vector;
      Reserved : Ada.Containers.Count_Type;
   begin
      --  Generic ownership code can discover that both operands are the same
      --  object. Self-move must retain its storage and original owner.
      Data.Set_Owner (Reference (Memory));
      Data.Append (42);
      Reserved := Data.Capacity;
      Set_Failure_Countdown (Memory, 0);
      Integers.Move (Data, Data);
      Assert (Data.Length = 1 and Data.Capacity = Reserved and Data (1) = 42,
              "self move retained contents and capacity");
      Assert (Data.Owner_Of = Reference (Memory) and
              not Refusal_Pending (Memory), "self move retained owner");
   end Move_Self_Preserves_Storage;

   procedure Move_Controlled_Elements is
      Memory : Owner;
      Source, Target : aliased Counted.Vector;
      First, Second : Counted_Item;
      Incoming, Outgoing, Copies : Natural;
   begin
      --  Controlled elements make an accidental assignment visible. Moving
      --  must finalize the old target once, never adjust the incoming value,
      --  and finalize that element only when its new owner removes it.
      Next_Id := 2;
      Finalizations := [others => 0];
      First.Id := 1;
      Second.Id := 2;
      Source.Set_Owner (Reference (Memory));
      Target.Set_Owner (Reference (Memory));
      Source.Append (First);
      Target.Append (Second);
      declare
         From_Item : constant Counted.Constant_Reference_Type :=
           Source.Constant_Reference (1);
         To_Item : constant Counted.Constant_Reference_Type :=
           Target.Constant_Reference (1);
      begin
         Incoming := From_Item.Element.Id;
         Outgoing := To_Item.Element.Id;
      end;
      Copies := Next_Id;
      Counted.Move (Target, Source);
      Assert (Next_Id = Copies, "move did not adjust controlled elements");
      Assert (Finalizations (Outgoing) = 1 and
              Finalizations (Incoming) = 0,
              "move finalized old target and retained incoming element");
      Target.Clear;
      Assert (Finalizations (Incoming) = 1,
              "transferred controlled element finalized exactly once");
   end Move_Controlled_Elements;

   procedure Release_Preserves_Binding is
      Memory : Owner;
      Data : Integers.Vector;
   begin
      --  Session shutdown needs to release registry capacity before closing
      --  its owner. The reusable container must retain its explicit binding.
      Data.Set_Owner (Reference (Memory));
      Data.Append (7);
      Data.Release;
      Assert (Data.Is_Empty and Data.Capacity = 0 and
              Data.Owner_Of = Reference (Memory),
              "release retained only the allocation policy");
      Assert (Statistics (Memory).Live_Blocks = 0,
              "release freed reserved vector capacity");
      Data.Append (8);
      Assert (Data (1) = 8, "released vector reused explicit owner");
   end Release_Preserves_Binding;

   procedure Concatenation_Carries_Owner is
      Memory : Owner;
      Left, Right, Joined : Integers.Vector;
   begin
      --  An unbound empty left operand contributes no policy. The right
      --  operand's real owner must fund the result, with independent contents.
      Joined := Left & Right;
      Assert (Joined.Is_Empty and Joined.Owner_Of = null,
              "two unbound empty inputs need no allocation policy");
      Right.Set_Owner (Reference (Memory));
      Right.Append (2);
      Joined := Left & Right;
      Assert (Joined.Owner_Of = Reference (Memory) and Joined (1) = 2,
              "concatenation inherited the nonempty source owner");
      Left.Set_Owner (Reference (Memory));
      Left.Append (1);
      Joined := Left & Right;
      Joined (1) := 9;
      Assert (Joined.Length = 2 and Joined (2) = 2 and Left (1) = 1,
              "concatenation copied ordered independent values");
   end Concatenation_Carries_Owner;

   procedure Concatenation_Refusal_Preserves_Inputs is
      Memory : Owner;
      Left, Right : Integers.Vector;
      Failed : Boolean := False;
   begin
      --  A failed result allocation cannot consume either source. Cleanup
      --  must release the partial result and preserve the owner's refusal.
      Left.Set_Owner (Reference (Memory));
      Right.Set_Owner (Reference (Memory));
      Left.Append (1);
      Right.Append (2);
      Set_Failure_Countdown (Memory, 0);
      begin
         declare
            Joined : constant Integers.Vector := Left & Right;
         begin
            Assert (Joined.Length = 2, "unexpected concatenation shape");
         end;
      exception
         when Allocation_Error | Program_Error => Failed := True;
      end;
      Assert (Failed and Refusal_Pending (Memory),
              "concatenation retained allocator refusal");
      Assert (Left (1) = 1 and Right (1) = 2 and
              Statistics (Memory).Live_Blocks = 2,
              "refused concatenation left both sources alive");
   end Concatenation_Refusal_Preserves_Inputs;

   procedure Prepend_And_Swap is
      Memory : Owner;
      Data : aliased Integers.Vector;
   begin
      --  Callable dispatch prepends its receiver and the C stack rotates by
      --  swaps. Both must preserve order and actual slot addresses;
      --  a nonstructural swap remains valid while a slot reference is live.
      Data.Set_Owner (Reference (Memory));
      Data.Append (1);
      Data.Append (3);
      Data.Prepend (0);
      Data.Swap (1, 3);
      Assert (Data (1) = 3 and Data (2) = 1 and Data (3) = 0,
              "prepend and swap ordered live elements");
      Set_Failure_Countdown (Memory, 0);
      declare
         Held : constant Integers.Reference_Type := Data.Reference (1);
      begin
         Data.Swap (1, 2);
         Assert (Held.Element.all = 1, "swap retained referenced slot");
      end;
      Assert (not Refusal_Pending (Memory), "scalar swap did not allocate");
   end Prepend_And_Swap;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "managed vector: owner required",
                        Binding_Required'Access);
      Test_Support.Add (Suite, "managed vector: geometric growth",
                        Geometric_Growth'Access);
      Test_Support.Add (Suite, "managed vector: indexed mutation",
                        Indexed_Mutation'Access);
      Test_Support.Add (Suite, "managed vector: independent copy",
                        Independent_Copy'Access);
      Test_Support.Add (Suite, "managed vector: failed copy source",
                        Failed_Copy_Preserves_Source'Access);
      Test_Support.Add (Suite, "managed vector: nested deletion cleanup",
                        Nested_Delete_Releases'Access);
      Test_Support.Add (Suite, "managed vector: update stored nested value",
                        Update_Stored_Nested_Vector'Access);
      Test_Support.Add (Suite, "managed vector: reference tampering",
                        Reference_Blocks_Tampering'Access);
      Test_Support.Add (Suite, "managed vector: iterator tampering",
                        Iteration_Blocks_Tampering'Access);
      Test_Support.Add (Suite, "managed vector: update error recovery",
                        Update_Exception_Releases_Borrow'Access);
      Test_Support.Add (Suite, "managed vector: length defaults",
                        Length_Defaults'Access);
      Test_Support.Add (Suite, "managed vector: insert delete order",
                        Insert_Delete_Order'Access);
      Test_Support.Add (Suite, "managed vector: atomic reserve refusal",
                        Growth_Failure_Is_Atomic'Access);
      Test_Support.Add (Suite, "managed vector: clear preserves owner",
                        Clear_Retains_Owner'Access);
      Test_Support.Add (Suite, "managed vector: rebind rejected",
                        Rebinding_Allocated_Rejected'Access);
      Test_Support.Add (Suite, "managed vector: self append",
                        Self_Append'Access);
      Test_Support.Add (Suite, "managed vector: nested subpool finalization",
                        Subpool_Nested_Finalization'Access);
      Test_Support.Add (Suite, "managed vector: allocation-free move",
                        Move_Transfers_Allocation'Access);
      Test_Support.Add (Suite, "managed vector: move empty capacity",
                        Move_Empty_Capacity'Access);
      Test_Support.Add (Suite, "managed vector: move source borrow",
                        Move_Borrowed_Source_Rejected'Access);
      Test_Support.Add (Suite, "managed vector: move target borrow",
                        Move_Borrowed_Target_Rejected'Access);
      Test_Support.Add (Suite, "managed vector: self move",
                        Move_Self_Preserves_Storage'Access);
      Test_Support.Add (Suite, "managed vector: controlled move lifecycle",
                        Move_Controlled_Elements'Access);
      Test_Support.Add (Suite, "managed vector: release capacity",
                        Release_Preserves_Binding'Access);
      Test_Support.Add (Suite, "managed vector: owner-carrying concatenate",
                        Concatenation_Carries_Owner'Access);
      Test_Support.Add (Suite, "managed vector: refused concatenate",
                        Concatenation_Refusal_Preserves_Inputs'Access);
      Test_Support.Add (Suite, "managed vector: prepend and slot swap",
                        Prepend_And_Swap'Access);
   end Register;
end Lua.Storage_Vector_Tests;
