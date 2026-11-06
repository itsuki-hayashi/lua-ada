with Ada.Containers;
with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Storage; use Lua.Storage;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;
with Test_Support;

package body Lua.Userdata_Tests is
   use type Ada.Containers.Count_Type;
   use type Byte_Count;
   use type Integer_Value;
   use type System.Address;
   use type System.Storage_Elements.Integer_Address;
   use type System.Storage_Elements.Storage_Element;

   type Cleanup_Record is record
      Calls : Natural := 0;
      Reason : Resource_Release_Reason := Host_Disposal;
   end record;
   package Cleanup_Addresses is new
     System.Address_To_Access_Conversions (Cleanup_Record);
   package Payload_Addresses is new System.Address_To_Access_Conversions
     (System.Storage_Elements.Storage_Element);
   Cleanup_Counter : aliased Cleanup_Record;
   --  AUnit executes these cases serially. This test-only witness outlives
   --  exception unwinding too; a failed assertion cannot leave a callback
   --  pointing into an already returned Behavior activation.

   procedure Record_Cleanup
     (Memory : not null Owner_Access; Payload, Data : System.Address;
      Reason : Resource_Release_Reason);
   procedure Record_Cleanup
     (Memory : not null Owner_Access; Payload, Data : System.Address;
      Reason : Resource_Release_Reason) is
      pragma Unreferenced (Memory, Payload);
      Counter : constant Cleanup_Addresses.Object_Pointer :=
        Cleanup_Addresses.To_Pointer (Data);
   begin
      --  This stand-in owns no operating-system handle. It witnesses the
      --  actual release point without allocating or entering Lua from GC.
      Counter.Calls := Counter.Calls + 1;
      Counter.Reason := Reason;
   end Record_Cleanup;

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
              "userdata fixture retained managed storage");
   end Fixture;

   procedure Keep (State : in out World; Name : String; Item : Value);
   function Weak_Values (State : in out World) return Value;
   procedure Payload_Alignment (State : in out World);
   procedure Empty_Identity (State : in out World);
   procedure Payload_Stability (State : in out World);
   procedure Initial_Uservalues (State : in out World);
   procedure Uservalue_Tracing (State : in out World);
   procedure Metatable_Tracing (State : in out World);
   procedure Cyclic_Uservalues (State : in out World);
   procedure Table_Key_Identity (State : in out World);
   procedure Equality_Handler (State : in out World);
   procedure Resource_Release (State : in out World);
   procedure Invalid_Count (State : in out World);
   procedure Oversized_Payload (State : in out World);
   procedure Duplicate_Resource (State : in out World);

   procedure Keep (State : in out World; Name : String; Item : Value) is
   begin
      Set (State, (Table_Kind, State.Globals), New_String (State, Name), Item);
   end Keep;

   function Weak_Values (State : in out World) return Value is
      Weak : constant Value := New_Table (State);
      Meta : constant Value := New_Table (State);
   begin
      Set (State, Meta, New_String (State, "__mode"), New_String (State, "v"));
      Set_Metatable (State, Weak, Meta.Reference);
      Keep (State, "weak", Weak);
      return Weak;
   end Weak_Values;

   procedure Payload_Alignment (State : in out World) is
      Sizes : constant array (Positive range <>) of Byte_Count :=
        [0, 1, 3, 17, 97];
   begin
      --  Odd sizes exercise the array's component alignment independently
      --  from its enclosing Ada discriminant/header layout. The C consumer
      --  checks this same address against an actual C maximum-align union.
      for Size of Sizes loop
         declare
            Item : constant Value := New_Userdata (State, Size);
         begin
            Assert (System.Storage_Elements.To_Integer
                      (Userdata_Address (Item)) mod
                        System.Storage_Elements.Integer_Address
                          (Native_Payload_Alignment) = 0,
                    "userdata payload lost native C alignment");
            Assert (Item.Reference.Userdata_Size = Size,
                    "physical alignment changed logical byte length");
         end;
      end loop;
   end Payload_Alignment;

   procedure Empty_Identity (State : in out World) is
      Left : constant Value := New_Userdata (State, 0);
      Right : constant Value := New_Userdata (State, 0);
   begin
      --  Size zero still needs an independently owned nonnull pointer. It
      --  must not collapse into null light userdata or another empty object.
      Assert (Userdata_Address (Left) /= System.Null_Address and then
              Userdata_Address (Left) /= Userdata_Address (Right),
              "zero-byte userdata did not preserve unique payload identity");
      Assert (not Equal (Left, Right), "empty userdata compared by size");
      Assert (Userdata_Address (Nil_Value) = System.Null_Address,
              "non-userdata acquired a fabricated payload address");
   end Empty_Identity;

   procedure Payload_Stability (State : in out World) is
      Item : constant Value := New_Userdata (State, 97, 1);
      Address : constant System.Address := Userdata_Address (Item);
   begin
      --  A real byte buffer survives heap/list growth and collection while
      --  its Lua value is rooted. No string copy or facade cache backs it.
      for Index in Byte_Count range 0 .. 96 loop
         Payload_Addresses.To_Pointer (Address + Index).all :=
             System.Storage_Elements.Storage_Element (Index mod 256);
      end loop;
      Keep (State, "payload", Item);
      for Index in 1 .. 128 loop
         declare
            Unused : constant Value :=
              New_Userdata (State, Byte_Count (Index));
            pragma Unreferenced (Unused);
         begin
            null;
         end;
      end loop;
      Collect (State);
      Assert (Userdata_Address (Item) = Address, "collector moved payload");
      for Index in Byte_Count range 0 .. 96 loop
         Assert (Payload_Addresses.To_Pointer (Address + Index).all =
                        System.Storage_Elements.Storage_Element
                          (Index mod 256),
                 "userdata byte contents changed during collection");
      end loop;
   end Payload_Stability;

   procedure Initial_Uservalues (State : in out World) is
      Item : constant Value := New_Userdata (State, 1, 7);
   begin
      --  Only Lua references have specified initial values. Their future
      --  growth policy belongs to this universe before constructor return.
      Assert (Item.Reference.Uservalues.Owner_Of = Reference (State.Memory),
              "uservalue storage bypassed the universe allocator");
      Assert (Item.Reference.Uservalues.Length = 7,
              "uservalue count differs from requested count");
      for Uservalue of Item.Reference.Uservalues loop
         Assert (Uservalue.Kind = Nil_Kind, "new uservalue was not nil");
      end loop;
   end Initial_Uservalues;

   procedure Uservalue_Tracing (State : in out World) is
      Weak : constant Value := Weak_Values (State);
      Item : constant Value := New_Userdata (State, 1, 1);
      Child : constant Value := New_Table (State);
   begin
      --  Weak observation avoids accidentally rooting the child through the
      --  test's Ada local. Its only strong runtime edge is a real uservalue.
      Keep (State, "owner", Item);
      Set (State, Weak, (Integer_Kind, 1), Child);
      Item.Reference.Uservalues.Replace_Element (1, Child);
      Collect (State);
      Assert (Equal (Get (Weak, (Integer_Kind, 1)), Child),
              "collector omitted a reachable userdata uservalue");
      Item.Reference.Uservalues.Replace_Element (1, Nil_Value);
      Collect (State);
      Assert (Get (Weak, (Integer_Kind, 1)).Kind = Nil_Kind,
              "cleared uservalue retained its old child");
   end Uservalue_Tracing;

   procedure Metatable_Tracing (State : in out World) is
      Weak : constant Value := Weak_Values (State);
      Item : constant Value := New_Userdata (State, 1);
      Meta : constant Value := New_Table (State);
   begin
      --  The per-object metatable is a traced edge, distinct from primitive
      --  type metatables. Removing it permits ordinary weak reclamation.
      Keep (State, "owner", Item);
      Set (State, Weak, (Integer_Kind, 1), Meta);
      Set_Metatable (State, Item, Meta.Reference);
      Collect (State);
      Assert (Raw_Metatable (State, Item) = Meta.Reference and then
              Get (Weak, (Integer_Kind, 1)).Kind = Table_Kind,
              "userdata metatable was not retained");
      Set_Metatable (State, Item, null);
      Collect (State);
      Assert (Get (Weak, (Integer_Kind, 1)).Kind = Nil_Kind,
              "removed userdata metatable stayed reachable");
   end Metatable_Tracing;

   procedure Cyclic_Uservalues (State : in out World) is
      Weak : constant Value := Weak_Values (State);
      Item : constant Value := New_Userdata (State, 1, 1);
      Child : constant Value := New_Table (State);
   begin
      --  Both nodes reference each other, but neither has a strong root.
      --  Counting references would leak them; actual tracing must clear both
      --  weak observations before either stable object address is released.
      Item.Reference.Uservalues.Replace_Element (1, Child);
      Set (State, Child, (Integer_Kind, 1), Item);
      Set (State, Weak, (Integer_Kind, 1), Item);
      Set (State, Weak, (Integer_Kind, 2), Child);
      Collect (State);
      Assert (Get (Weak, (Integer_Kind, 1)).Kind = Nil_Kind and then
              Get (Weak, (Integer_Kind, 2)).Kind = Nil_Kind,
              "unreachable userdata/table cycle survived tracing");
   end Cyclic_Uservalues;

   procedure Table_Key_Identity (State : in out World) is
      Left : constant Value := New_Userdata (State, 1);
      Right : constant Value := New_Userdata (State, 1);
      Table : constant Value := New_Table (State);
   begin
      --  Identical size/content does not merge keys. Hashing, equality and
      --  post-collection lookup must all use the same stable object identity.
      Keep (State, "keys", Table);
      Set (State, Table, Left, (Integer_Kind, 11));
      Set (State, Table, Right, (Integer_Kind, 22));
      Collect (State);
      Assert (Get (Table, Left).Integer_Data = 11 and then
              Get (Table, Right).Integer_Data = 22,
              "userdata table keys lost independent identity");
   end Table_Key_Identity;

   procedure Equality_Handler (State : in out World) is
      Left : constant Value := New_Userdata (State, 0);
      Right : constant Value := New_Userdata (State, 0);
      Passed : Boolean;
   begin
      --  Distinct full userdata can use __eq, while rawequal stays false.
      --  The two objects deliberately have different handlers: pinned Lua
      --  selects the left handler without a shared-handler requirement.
      Keep (State, "left", Left);
      Keep (State, "right", Right);
      Passed := Execute
        (State, "debug.setmetatable(left,{__eq=function(a,b)" &
         "assert(rawequal(a,left) and rawequal(b,right));return true end});" &
         "debug.setmetatable(right,{__eq=function()return false end});" &
         "assert(left==right and not rawequal(left,right));" &
         "assert(not (right==left) and type(left)=='userdata')", "=userdata");
      Assert (Passed, "userdata equality bypassed its real metamethod");
   end Equality_Handler;

   procedure Resource_Release (State : in out World) is
      Counter : Cleanup_Record renames Cleanup_Counter;
      Item : constant Value := New_Userdata (State, 1);
   begin
      --  Marking and a live root must never call host cleanup. The sole call
      --  occurs when the object really dies, with the reason needed to avoid
      --  overriding removed/replaced Lua __gc behavior in file libraries.
      Counter := (others => <>);
      Attach_Resource (Item, Counter'Address, Record_Cleanup'Access);
      Keep (State, "resource", Item);
      Collect (State);
      Assert (Counter.Calls = 0, "marking released a live host resource");
      Keep (State, "resource", Nil_Value);
      Collect (State);
      Assert (Counter.Calls = 1 and then Counter.Reason = Collected,
              "real reclamation omitted/repeated resource cleanup");
      Collect (State);
      Assert (Counter.Calls = 1, "cleanup was repeated by later collection");
   end Resource_Release;

   procedure Invalid_Count (State : in out World) is
      Before : constant Byte_Count :=
        Statistics (State.Memory).Growth_Attempts;
   begin
      --  The pinned public count bound is SHRT_MAX, not USHRT_MAX. Reject it
      --  before constructing an object or consuming allocator growth.
      declare
         Unexpected : Value;
         pragma Unreferenced (Unexpected);
      begin
         Unexpected := New_Userdata
           (State, 1, Natural (Interfaces.C.short'Last));
         Assert (False, "invalid uservalue count was accepted");
      exception
         when Language_Error => null;
      end;
      Assert (Statistics (State.Memory).Growth_Attempts = Before,
              "invalid count allocated a partial userdata");
   end Invalid_Count;

   procedure Oversized_Payload (State : in out World) is
      Before : constant Byte_Count :=
        Statistics (State.Memory).Growth_Attempts;
   begin
      --  Mathematical object-size overflow is a managed memory failure; it
      --  must not request enormous storage or become an Ada range exception.
      declare
         Unexpected : Value;
         pragma Unreferenced (Unexpected);
      begin
         Unexpected := New_Userdata (State, Byte_Count'Last);
         Assert (False, "overflowing userdata size was accepted");
      exception
         when Allocation_Error => null;
      end;
      Assert (Statistics (State.Memory).Growth_Attempts = Before,
              "overflowing payload reached the allocator");
   end Oversized_Payload;

   procedure Duplicate_Resource (State : in out World) is
      Counter : Cleanup_Record renames Cleanup_Counter;
      Item : constant Value := New_Userdata (State, 1);
   begin
      --  Overwriting owned metadata would leak the first attachment. Reject
      --  the internal misuse and prove that its original cleanup still runs.
      Counter := (others => <>);
      Attach_Resource (Item, Counter'Address, Record_Cleanup'Access);
      begin
         Attach_Resource (Item, Counter'Address, Record_Cleanup'Access);
         Assert (False, "resource attachment silently replaced its owner");
      exception
         when Program_Error => null;
      end;
      Collect (State);
      Assert (Counter.Calls = 1, "original resource attachment was lost");
   end Duplicate_Resource;

   procedure Case_Alignment is new Fixture (Payload_Alignment);
   procedure Case_Empty is new Fixture (Empty_Identity);
   procedure Case_Stability is new Fixture (Payload_Stability);
   procedure Case_Initial is new Fixture (Initial_Uservalues);
   procedure Case_Values is new Fixture (Uservalue_Tracing);
   procedure Case_Metatable is new Fixture (Metatable_Tracing);
   procedure Case_Cycle is new Fixture (Cyclic_Uservalues);
   procedure Case_Keys is new Fixture (Table_Key_Identity);
   procedure Case_Equality is new Fixture (Equality_Handler);
   procedure Case_Resource is new Fixture (Resource_Release);
   procedure Case_Count is new Fixture (Invalid_Count);
   procedure Case_Oversized is new Fixture (Oversized_Payload);
   procedure Case_Duplicate is new Fixture (Duplicate_Resource);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "userdata: aligned inline payload",
                        Case_Alignment'Access);
      Test_Support.Add (Suite, "userdata: unique empty identity",
                        Case_Empty'Access);
      Test_Support.Add (Suite, "userdata: stable mutable payload",
                        Case_Stability'Access);
      Test_Support.Add (Suite, "userdata: owned nil uservalues",
                        Case_Initial'Access);
      Test_Support.Add (Suite, "userdata: traces and releases uservalues",
                        Case_Values'Access);
      Test_Support.Add (Suite, "userdata: traces per-object metatable",
                        Case_Metatable'Access);
      Test_Support.Add (Suite, "userdata: reclaims cyclic uservalues",
                        Case_Cycle'Access);
      Test_Support.Add (Suite, "userdata: stable table-key identity",
                        Case_Keys'Access);
      Test_Support.Add (Suite, "userdata: real equality metamethod",
                        Case_Equality'Access);
      Test_Support.Add (Suite, "userdata: cleanup only at actual release",
                        Case_Resource'Access);
      Test_Support.Add (Suite, "userdata: rejects SHRT_MAX uservalues",
                        Case_Count'Access);
      Test_Support.Add (Suite, "userdata: rejects mathematical size overflow",
                        Case_Oversized'Access);
      Test_Support.Add (Suite, "userdata: rejects duplicate resource owner",
                        Case_Duplicate'Access);
   end Register;
end Lua.Userdata_Tests;
