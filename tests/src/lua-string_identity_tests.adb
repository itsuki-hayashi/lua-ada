with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with Test_Support;

package body Lua.String_Identity_Tests is
   use type Lua.Storage.Byte_Count;

   generic
      with procedure Action (State : in out World);
   procedure Fixture;

   procedure Fixture is
      State : World;
   begin
      State.Open_Standard_Libraries := False;
      Initialize (State, (others => <>));
      Action (State);
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "string buckets and headers release their selected owner");
   exception
      when others => Finalize (State); raise;
   end Fixture;

   procedure Short_Boundary (State : in out World);
   procedure Binary_Content (State : in out World);
   procedure Weak_Index (State : in out World);
   procedure Sweep_Revival (State : in out World);
   procedure Reused_Operation_Root (State : in out World);
   procedure Rehash_Retains_Live (State : in out World);

   procedure Short_Boundary (State : in out World) is
      Forty : constant String (1 .. 40) := [others => 's'];
      Long : constant String (1 .. 41) := [others => 'l'];
      A : constant Value := New_String (State, Forty);
      B : constant Value := New_String (State, Forty);
      C : constant Value := New_String (State, Long);
      D : constant Value := New_String (State, Long);
   begin
      --  Byte equality is independent of identity. Ordinary length 40 is
      --  interned universe-wide; length 41 owns a distinct immutable header.
      Assert (A.Reference = B.Reference, "40-byte ordinary identity");
      Assert (C.Reference /= D.Reference and then Equal (C, D),
              "41-byte ordinary equality with distinct identity");
   end Short_Boundary;

   procedure Binary_Content (State : in out World) is
      A : constant Value := New_String (State, "a" & ASCII.NUL & "b");
      B : constant Value := New_String (State, "a" & ASCII.NUL & "b");
      C : constant Value := New_String (State, "a" & ASCII.NUL & "c");
   begin
      --  The weak index hashes/compares the explicit byte extent. C-string
      --  termination cannot merge two different bytes after an embedded NUL.
      Assert (A.Reference = B.Reference and then A.Reference /= C.Reference,
              "interning includes every embedded-zero payload byte");
   end Binary_Content;

   procedure Weak_Index (State : in out World) is
      Before : Natural;
      Item : Value;
      Slot : Positive;
   begin
      Collect (State);
      Before := State.Short_String_Count;
      Item := New_String (State, "unrooted-intern-index-witness");
      Slot := Item.Reference.Registry_Slot;
      Collect (State);
      Assert (State.Heap (Slot) = null and then
              State.Short_String_Count = Before,
              "intern bucket is not a permanent strong string cache");
   end Weak_Index;

   procedure Sweep_Revival (State : in out World) is
      Item, Found : Value;
      Done : Boolean := False;
      Slot : Positive;
   begin
      Collect (State);
      Item := New_String (State, "unswept-intern-revival-witness");
      Slot := Item.Reference.Registry_Slot;
      while State.GC.Phase /= Sweeping_Objects loop
         Advance_Collection (State, 1, Done);
      end loop;
      --  Atomic declared this unrooted string old-white, but no sweep slot
      --  has run yet. A normal lookup revives that exact physical header.
      Begin_Operation (State);
      Found := New_String (State, "unswept-intern-revival-witness");
      Assert (Found.Reference = Item.Reference, "revived actual header");
      while not Done loop Advance_Collection (State, 1, Done); end loop;
      Assert (State.Heap (Slot) = Found.Reference,
              "revived string survives the already-running sweep");
      End_Operation (State);
      Collect (State);
      Assert (State.Heap (Slot) = null, "revival is not a permanent root");
   end Sweep_Revival;

   procedure Reused_Operation_Root (State : in out World) is
      Item : constant Value := New_String
        (State, "operation-reused-intern-witness");
      Found : Value;
   begin
      --  Unlike a newly allocated serial, this existing header predates the
      --  operation epoch. Its intrusive transient root protects it through
      --  collection before a subsequent table/stack publication allocates.
      Begin_Operation (State);
      Found := New_String (State, "operation-reused-intern-witness");
      Collect (State);
      Assert (Found.Reference = Item.Reference and then
              State.Heap (Found.Reference.Registry_Slot) = Found.Reference,
              "reused short string is rooted without allocating a packet");
      End_Operation (State);
   end Reused_Operation_Root;

   procedure Rehash_Retains_Live (State : in out World) is
      Table : Value;
      Text : Value;
   begin
      Begin_Operation (State);
      Table := New_Table (State);
      Pin (State, Table);
      for Index in 1 .. 1_024 loop
         Text := New_String (State, "intern-rehash" & Index'Image);
         Set (State, Table, (Integer_Kind, Integer_Value (Index)), Text);
      end loop;
      --  Growth rewrites weak chains only after replacement storage exists;
      --  ordinary table values keep all real headers live during collection.
      Collect (State);
      for Index in 1 .. 1_024 loop
         Text := New_String (State, "intern-rehash" & Index'Image);
         Assert (Get (Table, (Integer_Kind, Integer_Value (Index))).Reference =
                   Text.Reference, "rehash retains each actual intern entry");
      end loop;
      Assert (State.Short_Strings.Last_Index >= 1_024,
              "weak intern index grows with actual short-string population");
      End_Operation (State);
   end Rehash_Retains_Live;

   procedure Check_Short is new Fixture (Short_Boundary);
   procedure Check_Binary is new Fixture (Binary_Content);
   procedure Check_Weak is new Fixture (Weak_Index);
   procedure Check_Revival is new Fixture (Sweep_Revival);
   procedure Check_Root is new Fixture (Reused_Operation_Root);
   procedure Check_Rehash is new Fixture (Rehash_Retains_Live);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "strings: short identity boundary",
                        Check_Short'Access);
      Test_Support.Add (Suite, "strings: intern embedded-zero content",
                        Check_Binary'Access);
      Test_Support.Add (Suite, "strings: intern index remains weak",
                        Check_Weak'Access);
      Test_Support.Add (Suite, "strings: unswept short-string revival",
                        Check_Revival'Access);
      Test_Support.Add (Suite, "strings: reused operation transient root",
                        Check_Root'Access);
      Test_Support.Add (Suite, "strings: weak index growth retains live keys",
                        Check_Rehash'Access);
   end Register;
end Lua.String_Identity_Tests;
