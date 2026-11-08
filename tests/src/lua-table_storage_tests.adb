with Ada.Containers;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Test_Support;

package body Lua.Table_Storage_Tests is
   use type Ada.Containers.Count_Type;
   use type Integer_Value;
   use type Real_Value;

   generic
      with procedure Action (State : in out World);
   procedure Fixture;

   procedure Fixture is
      State : World;
   begin
      Initialize (State, (others => <>));
      begin
         Action (State);
      exception
         when others => Finalize (State); raise;
      end;
      Finalize (State);
   end Fixture;

   function Int (Item : Integer_Value) return Value is (Integer_Kind, Item);

   procedure Dense_Append (State : in out World);
   procedure Sparse_Keys (State : in out World);
   procedure Numeric_Keys (State : in out World);
   procedure String_Keys (State : in out World);
   procedure Deleted_Traversal (State : in out World);
   procedure Prefix_Border (State : in out World);
   procedure Promote_Sparse_Key (State : in out World);
   procedure Hash_Growth (State : in out World);
   procedure Quota_Failure (State : in out World);
   procedure Weak_Index_Cleanup (State : in out World);
   procedure Deleted_Key_Churn (State : in out World);
   procedure Revived_Free_Rows (State : in out World);

   procedure Dense_Append (State : in out World) is
      Item : constant Value := New_Table (State);
   begin
      --  Fill a realistic sequence one entry at a time. Every append must
      --  update the cached border and the direct index, without rescanning
      --  the previously appended prefix or allocating an index per element.
      for Index in 1 .. 10_000 loop
         Set (State, Item, Int (Integer_Value (Index)),
              Int (Integer_Value (Index * 2)));
         Assert (Table_Length (Item) = Index, "append border");
      end loop;
      Assert (Item.Reference.Array_Index.Length >= 10_000,
              "dense keys did not enter direct index");
      Assert (Get (Item, Int (9_999)).Integer_Data = 19_998,
              "direct-index lookup");
   end Dense_Append;

   procedure Sparse_Keys (State : in out World) is
      Item : constant Value := New_Table (State);
   begin
      --  Huge and negative integer keys are legal hash keys. Their numeric
      --  magnitude must not cause an enormous direct-array allocation.
      Set (State, Item, Int (Integer_Value'Last), Int (1));
      Set (State, Item, Int (Integer_Value'First), Int (2));
      Set (State, Item, Int (-17), Int (3));
      Assert (Item.Reference.Array_Index.Is_Empty, "sparse array allocation");
      Assert (Get (Item, Int (Integer_Value'Last)).Integer_Data = 1,
              "maximum integer key");
      Assert (Get (Item, Int (Integer_Value'First)).Integer_Data = 2,
              "minimum integer key");
      Assert (Table_Length (Item) = 0, "sparse keys changed sequence border");
   end Sparse_Keys;

   procedure Numeric_Keys (State : in out World) is
      Item : constant Value := New_Table (State);
   begin
      --  Equal integer/float keys must reach one row, including signed zero.
      --  Distinct integers beyond binary64's exact range must stay distinct.
      Set (State, Item, Int (7), Int (11));
      Set (State, Item, (Real_Kind, 7.0), Int (12));
      Assert (Item.Reference.Members.Length = 1, "duplicate numeric row");
      Assert (Get (Item, Int (7)).Integer_Data = 12, "numeric replacement");
      Set (State, Item, (Real_Kind, -0.0), Int (13));
      Assert (Get (Item, Int (0)).Integer_Data = 13, "signed zero key");
      Set (State, Item, Int (9_007_199_254_740_993), Int (14));
      Set (State, Item, (Real_Kind, 9_007_199_254_740_992.0), Int (15));
      Assert (Get (Item, Int (9_007_199_254_740_993)).Integer_Data = 14,
              "rounded integer alias");
      Assert (Get (Item, Int (9_007_199_254_740_992)).Integer_Data = 15,
              "exact float canonicalization");
   end Numeric_Keys;

   procedure String_Keys (State : in out World) is
      Item : constant Value := New_Table (State);
      Text : constant String :=
        "a" & ASCII.NUL & "z" & String'(1 .. 40 => 'p');
      First : constant Value := New_String (State, Text);
      Other : constant Value := New_String (State, Text);
   begin
      --  Separate equal long byte strings share a hash bucket and binding.
      --  A zero byte is part of the key, not an option-string terminator.
      Assert (First.Reference /= Other.Reference, "fixture string identity");
      Set (State, Item, First, Int (42));
      Assert (Get (Item, Other).Integer_Data = 42, "equal byte-string hash");
      Assert (Get (Item, New_String (State, "a")).Kind = Nil_Kind,
              "embedded NUL truncated a table key");
   end String_Keys;

   procedure Deleted_Traversal (State : in out World) is
      Item : constant Value := New_Table (State);
      Packet : Values.Vector;
   begin
      --  Deleting the current next key retains its traversal position. Each
      --  subsequent lookup starts at that indexed row instead of the table's
      --  beginning; the final packet must still contain exactly one nil.
      Set (State, Item, Int (1), Int (10));
      Set (State, Item, Int (2), Int (20));
      Set (State, Item, Int (1), Nil_Value);
      Packet := Next (State, Item, Int (1));
      Assert (Packet.Length = 2 and then Packet (1).Integer_Data = 2,
              "next after deleting current key");
      Packet := Next (State, Item, Int (2));
      Assert (Packet.Length = 1 and then Packet (1).Kind = Nil_Kind,
              "next final result adjustment");
   end Deleted_Traversal;

   procedure Prefix_Border (State : in out World) is
      Item : constant Value := New_Table (State);
   begin
      --  Fill a hole, remove an interior value, then refill it. The cache
      --  must always describe a valid border, including hashed positive keys.
      Set (State, Item, Int (3), Int (30));
      Set (State, Item, Int (1), Int (10));
      Assert (Table_Length (Item) = 1, "first hole border");
      Set (State, Item, Int (2), Int (20));
      Assert (Table_Length (Item) = 3, "filled hole border");
      Set (State, Item, Int (1), Nil_Value);
      Assert (Table_Length (Item) = 0, "removed prefix value");
      Set (State, Item, Int (1), Int (40));
      Assert (Table_Length (Item) = 3, "restored prefix border");
   end Prefix_Border;

   procedure Promote_Sparse_Key (State : in out World) is
      Item : constant Value := New_Table (State);
   begin
      --  A once-sparse key moves into the growing direct index. Rehashing
      --  must publish its old row there before lookups choose that index.
      Set (State, Item, Int (100), Int (123));
      for Index in 1 .. 99 loop
         Set (State, Item, Int (Integer_Value (Index)), Int (1));
      end loop;
      Assert (Get (Item, Int (100)).Integer_Data = 123,
              "promoted sparse key disappeared");
      Assert (Table_Length (Item) = 100, "promoted key prefix");
   end Promote_Sparse_Key;

   procedure Hash_Growth (State : in out World) is
      Item : constant Value := New_Table (State);
      Packet : Values.Vector;
      Cursor : Value := Nil_Value;
      Count : Natural := 0;
   begin
      --  Grow and rehash thousands of independently allocated string keys.
      --  Recreate lookup strings and traverse every row to protect both
      --  collision links and amortized whole-table iteration.
      for Index in 1 .. 4_096 loop
         Set (State, Item, New_String (State, Index'Image),
              Int (Integer_Value (Index)));
      end loop;
      for Index in 1 .. 4_096 loop
         Assert (Get (Item, New_String (State, Index'Image)).Integer_Data =
                   Integer_Value (Index), "rehash lost a binding");
      end loop;
      loop
         Packet := Next (State, Item, Cursor);
         exit when Packet (1).Kind = Nil_Kind;
         Cursor := Packet (1);
         Count := Count + 1;
      end loop;
      Assert (Count = 4_096, "rehash traversal lost or repeated rows");
   end Hash_Growth;

   procedure Quota_Failure (State : in out World) is
      Item : constant Value := New_Table (State);
      Rejected : Boolean := False;
   begin
      --  Permit one new row, then reject another through the existing host
      --  quota. The failed operation must not change the index or count.
      State.Bounds.Table_Entries := State.Entry_Count + 1;
      Set (State, Item, Int (1), Int (10));
      begin
         Set (State, Item, Int (2), Int (20));
      exception
         when Language_Error => Rejected := True;
      end;
      Assert (Rejected, "table quota was bypassed");
      Assert (Get (Item, Int (1)).Integer_Data = 10, "old binding changed");
      Assert (Get (Item, Int (2)).Kind = Nil_Kind, "failed row published");
      Assert (Item.Reference.Members.Length = 1, "failed row retained");
   end Quota_Failure;

   procedure Weak_Index_Cleanup (State : in out World) is
   begin
      --  Weak collection clears hash and dense rows before freeing objects.
      --  Surviving keys remain searchable; the sequence cache must forget a
      --  collected first value and recover when that hole is filled again.
      Assert (Execute (State,
        "local a,b={},{}; keep=b; weak=setmetatable({a,b}," &
        "{__mode='v'}); keys=setmetatable({[a]=1,[b]=2}," &
        "{__mode='k'}); a=nil; collectgarbage(); " &
        "assert(rawlen(weak)==0 and weak[2]==b); " &
        "assert(keys[b]==2); weak[1]=b; assert(#weak==2)", "weak-index"),
        "weak indexes and border: " & Failure_Image (State.Current));
   end Weak_Index_Cleanup;

   procedure Deleted_Key_Churn (State : in out World) is
      Item : constant Value := New_Table (State);
      Before : constant Natural := State.Entry_Count;
   begin
      --  Repeatedly insert and delete a novel key into one live table. Its
      --  empty logical state must not accumulate an unbounded row history.
      for Index in 1 .. 20_000 loop
         Set (State, Item, Int (Integer_Value (Index)), Int (1));
         Set (State, Item, Int (Integer_Value (Index)), Nil_Value);
      end loop;
      Assert (Item.Reference.Members.Length = 1, "unbounded deleted rows");
      Assert (State.Entry_Count = Before + 1, "recycled row counted twice");
      Assert (Item.Reference.Hash_Index.Length = 8, "churn grew hash index");
      Assert (Table_Length (Item) = 0, "empty churn border");
   end Deleted_Key_Churn;

   procedure Revived_Free_Rows (State : in out World) is
      Item : constant Value := New_Table (State);
   begin
      --  Revive and delete a row which is already on the reusable list.
      --  Two new keys must reuse different rows without a free-list cycle.
      Set (State, Item, Int (1), Int (10));
      Set (State, Item, Int (2), Int (20));
      Set (State, Item, Int (1), Nil_Value);
      Set (State, Item, Int (2), Nil_Value);
      Set (State, Item, Int (2), Int (21));
      Set (State, Item, Int (2), Nil_Value);
      Set (State, Item, Int (3), Int (30));
      Set (State, Item, Int (4), Int (40));
      Assert (Get (Item, Int (3)).Integer_Data = 30, "first reused row");
      Assert (Get (Item, Int (4)).Integer_Data = 40, "second reused row");
      Assert (Item.Reference.Members.Length = 2, "revived row duplicated");
   end Revived_Free_Rows;

   procedure Churn_Case is new Fixture (Deleted_Key_Churn);
   procedure Revival_Case is new Fixture (Revived_Free_Rows);
   procedure Dense_Case is new Fixture (Dense_Append);
   procedure Sparse_Case is new Fixture (Sparse_Keys);
   procedure Numeric_Case is new Fixture (Numeric_Keys);
   procedure String_Case is new Fixture (String_Keys);
   procedure Deleted_Case is new Fixture (Deleted_Traversal);
   procedure Prefix_Case is new Fixture (Prefix_Border);
   procedure Promote_Case is new Fixture (Promote_Sparse_Key);
   procedure Growth_Case is new Fixture (Hash_Growth);
   procedure Quota_Case is new Fixture (Quota_Failure);
   procedure Weak_Case is new Fixture (Weak_Index_Cleanup);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "tables: deleted key churn", Churn_Case'Access);
      Test_Support.Add
        (Suite, "tables: revived free rows", Revival_Case'Access);
      Test_Support.Add
        (Suite, "tables: dense append index", Dense_Case'Access);
      Test_Support.Add (Suite, "tables: sparse hash keys", Sparse_Case'Access);
      Test_Support.Add
        (Suite, "tables: numeric key hashing", Numeric_Case'Access);
      Test_Support.Add
        (Suite, "tables: byte string hashing", String_Case'Access);
      Test_Support.Add (Suite, "tables: deleted key traversal",
                        Deleted_Case'Access);
      Test_Support.Add (Suite, "tables: cached sequence border",
                        Prefix_Case'Access);
      Test_Support.Add (Suite, "tables: sparse key promotion",
                        Promote_Case'Access);
      Test_Support.Add (Suite, "tables: hash growth and traversal",
                        Growth_Case'Access);
      Test_Support.Add (Suite, "tables: insertion quota atomicity",
                        Quota_Case'Access);
      Test_Support.Add (Suite, "tables: weak index cleanup", Weak_Case'Access);
   end Register;
end Lua.Table_Storage_Tests;
