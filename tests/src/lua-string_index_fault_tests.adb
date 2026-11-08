with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.String_Index_Fault_Tests is
   use type Interfaces.C.size_t;
   use type Interfaces.Unsigned_64;
   use type Lua.Storage.Byte_Count;
   use type System.Address;

   --  AUnit runs these fixtures serially. The actual selected provider owns
   --  every raw block from initialization through finalization; refusal is
   --  recorded here, below managed allocation and emergency-collection logic.
   Refuse : Boolean := False;
   Refusals : Natural := 0;
   Raw_Live : Lua.Storage.Byte_Count := 0;
   function Provider
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
     with Convention => C;
   function Provider
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
   is
      Result : System.Address;
   begin
      if Refuse and then New_Size > Old_Size then
         Refusals := Refusals + 1;
         return System.Null_Address;
      end if;
      Result := Lua.Storage.Default_Allocator
        (Data, Block, Old_Size, New_Size);
      if New_Size = 0 or else Result /= System.Null_Address then
         Raw_Live := Raw_Live - Lua.Storage.Byte_Count (Old_Size) +
           Lua.Storage.Byte_Count (New_Size);
      end if;
      return Result;
   end Provider;

   generic
      with procedure Action (State : in out World);
   procedure Fixture;
   procedure Fixture is
      State : World;
   begin
      Refuse := False;
      Refusals := 0;
      Raw_Live := 0;
      Lua.Storage.Set_Allocator (State.Memory, Provider'Access);
      State.Open_Standard_Libraries := False;
      Initialize (State, (others => <>));
      Action (State);
      Refuse := False;
      Finalize (State);
      Assert (Raw_Live = 0 and then
              Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "intern fault fixture releases actual selected storage");
   exception
      when others =>
         Refuse := False;
         Finalize (State);
         raise;
   end Fixture;

   procedure Verify_Index (State : World);
   procedure Verify_Index (State : World) is
      Item : Object_Access;
      Found : Boolean;
      Count, Steps : Natural := 0;
   begin
      --  Establish heap membership before dereferencing any bucket pointer.
      --  A bounded walk rejects cycles; bucket ownership and the total then
      --  protect against dangling links, duplicate chains and stale counts.
      for Bucket in 1 .. State.Short_Strings.Last_Index loop
         Item := State.Short_Strings (Bucket);
         Steps := 0;
         while Item /= null loop
            Found := False;
            for Live of State.Heap loop
               if Live = Item then Found := True; exit; end if;
            end loop;
            Assert (Found, "intern chain pointer belongs to actual heap");
            Assert (Item.Kind = String_Object and then Item.Interned,
                    "intern chain owns a live string header");
            Assert (Natural (Item.String_Hash mod
                      Interfaces.Unsigned_64 (State.Short_Strings.Length))
                    + 1 = Bucket, "intern header belongs to its bucket");
            Steps := Steps + 1;
            Assert (Steps <= Natural (State.Heap.Length),
                    "intern chain is finite");
            Count := Count + 1;
            Item := Item.Intern_Next;
         end loop;
      end loop;
      Assert (Count = State.Short_String_Count,
              "actual chain population matches authoritative count");
   end Verify_Index;

   procedure Disabled_Collection (State : in out World);
   procedure Dead_Headers (State : in out World);
   procedure Refused_Replacement (State : in out World);

   procedure Disabled_Collection (State : in out World) is
      Root, Key, Text : Value;
      Before : Natural;
   begin
      --  Retain an embedded-zero key and value independently of a thousand
      --  discarded dynamic strings. Only the retained table crosses epochs.
      Begin_Operation (State);
      Root := New_Table (State);
      Key := New_String (State, "live" & ASCII.NUL & "key");
      Text := New_String (State, "live" & ASCII.NUL & "value");
      Set (State, Root, Key, Text);
      for Index in 1 .. 1_000 loop
         Text := New_String (State, "discarded-string" & Index'Image);
      end loop;
      End_Operation (State);
      Begin_Operation (State);
      Pin (State, Root);
      Before := Refusals;
      Refuse := True;
      Collect (State);
      Verify_Index (State);
      Assert (New_String (State, "live" & ASCII.NUL & "key").Reference =
                Key.Reference, "live binary key retains actual identity");
      Text := Get (Root, Key);
      Assert (Text.Kind = String_Kind and then
              Text.Reference.Bytes = "live" & ASCII.NUL & "value",
              "zero-growth collection preserves exact live payload");
      Assert (Refusals = Before,
              "actual collection did not request provider growth");
      Refuse := False;
      End_Operation (State);
   end Disabled_Collection;

   procedure Dead_Headers (State : in out World) is
      Slots : array (1 .. 1_000) of Positive;
      Item : Value;
   begin
      --  Record real ownership slots, rather than using weak string values
      --  (which Lua deliberately does not clear). No new objects are created
      --  between collection and the slot/index inspection.
      Begin_Operation (State);
      for Index in Slots'Range loop
         Item := New_String (State, "retired-string" & Index'Image);
         Slots (Index) := Item.Reference.Registry_Slot;
      end loop;
      End_Operation (State);
      Refuse := True;
      Collect (State);
      for Slot of Slots loop
         Assert (State.Heap (Slot) = null,
                 "unreachable intern header is actually disposed");
      end loop;
      Verify_Index (State);
      Refuse := False;
      Item := New_String (State, "retired-string 1");
      Assert (Item.Reference.Bytes = "retired-string 1",
              "lookup/recreation recovers after actual header disposal");
   end Dead_Headers;

   procedure Refused_Replacement (State : in out World) is
      Originals : array (1 .. 2_048) of Value;
      Used : Natural := 0;
      Capacity, Population : Natural;
      Item : Value;
      Failed : Boolean := False;
   begin
      Collect (State);
      Begin_Operation (State);
      Capacity := State.Short_Strings.Last_Index;
      Assert (Capacity <= Originals'Length, "bounded fixture capacity");
      while State.Short_String_Count < Capacity loop
         Used := Used + 1;
         Originals (Used) := New_String (State, "replacement" & Used'Image);
      end loop;
      Population := State.Short_String_Count;
      --  New_String must attempt bucket replacement before allocating the
      --  new header. All old strings remain operation roots during the real
      --  provider refusal and the engine's emergency retry/collection.
      Refuse := True;
      begin
         Item := New_String (State, "replacement-trigger");
      exception
         when Lua.Storage.Allocation_Error => Failed := True;
      end;
      Assert (Failed and then Refusals > 0,
              "actual selected provider refused replacement allocation");
      Assert (State.Short_Strings.Last_Index = Capacity and then
              State.Short_String_Count = Population,
              "failed replacement publishes neither capacity nor header");
      Verify_Index (State);
      for Index in 1 .. Used loop
         Item := New_String (State, "replacement" & Index'Image);
         Assert (Item.Reference = Originals (Index).Reference,
                 "refused replacement preserves each actual old identity");
      end loop;
      Refuse := False;
      Lua.Storage.Acknowledge_Refusal (State.Memory);
      Item := New_String (State, "replacement-trigger");
      Assert (State.Short_Strings.Last_Index > Capacity and then
              Item.Reference.Bytes = "replacement-trigger",
              "restored provider permits actual replacement retry");
      Verify_Index (State);
      End_Operation (State);
   end Refused_Replacement;

   procedure Check_Disabled is new Fixture (Disabled_Collection);
   procedure Check_Dead is new Fixture (Dead_Headers);
   procedure Check_Refused is new Fixture (Refused_Replacement);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "strings: disabled-provider live intern roots",
                        Check_Disabled'Access);
      Test_Support.Add (Suite, "strings: dead intern headers detach",
                        Check_Dead'Access);
      Test_Support.Add (Suite, "strings: provider-refused index replacement",
                        Check_Refused'Access);
   end Register;
end Lua.String_Index_Fault_Tests;
