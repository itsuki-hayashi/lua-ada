with AUnit.Assertions; use AUnit.Assertions;
with Lua.Storage; use Lua.Storage;
with Lua.Storage.Buffers;
with System;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;
with Test_Support;

package body Lua.Storage_Buffer_Tests is
   use System.Storage_Elements;
   use type System.Address;
   package Characters is new
     System.Address_To_Access_Conversions (Character);

   procedure Binary_And_Shifted_Bytes;
   procedure Independent_Copy;
   procedure Query_Borrows_Actual_Storage;
   procedure Query_Tampering_Rejected;
   procedure Query_Exception_Recovery;
   procedure Aliased_Append_Growth;
   procedure Aliased_Set_Value;
   procedure Refused_Growth_Preserves;
   procedure Refused_Copy_Preserves;
   procedure Clear_And_C_Terminator;
   procedure Release_And_Rebind;
   procedure Geometric_Growth;
   procedure Slice_And_Replacement;
   procedure Empty_Query;
   procedure Append_Buffers_And_Self;
   procedure Insert_Delete_Byte_Order;
   procedure Overlapping_Insert_Refusal;
   procedure Ordered_Mutation_Query_Guard;

   procedure Binary_And_Shifted_Bytes is
      Memory : Owner;
      Data : Buffers.Buffer;
      Input : constant String (19 .. 21) := "a" & Character'Val (0) & "b";
   begin
      --  String lower bounds and embedded NUL must not affect byte length or
      --  appending. Only the extra terminator is outside the Lua byte string.
      Data.Set_Owner (Reference (Memory));
      Data.Append (Input);
      Data.Append ('c');
      Assert (Data.Length = 4 and Data.To_String = Input & "c",
              "shifted binary append");
      Assert (Characters.To_Pointer
        (Data.C_Address + Storage_Offset (Data.Length)).all =
          Character'Val (0),
        "extra C terminator");
   end Binary_And_Shifted_Bytes;

   procedure Independent_Copy is
      Memory : Owner;
      Data : Buffers.Buffer;
   begin
      --  Controlled copying retains the owner but allocates distinct payload.
      --  Mutation/finalization of the copy must leave the source untouched.
      Data.Set_Owner (Reference (Memory));
      Data.Append ("source");
      declare
         Duplicate : Buffers.Buffer := Buffers.Copy (Data);
      begin
         Duplicate.Replace_Element (1, 'S');
         Assert (Data.To_String = "source" and
                 Duplicate.To_String = "Source", "independent byte copy");
      end;
      Assert (Statistics (Memory).Live_Blocks = 1, "only source remains");
   end Independent_Copy;

   procedure Query_Borrows_Actual_Storage is
      Memory : Owner;
      Data : Buffers.Buffer;
      Called : Boolean := False;
      Before : Byte_Count;
      procedure Inspect (Text : String);
      procedure Inspect (Text : String) is
      begin
         Called := True;
         Assert (Text = "actual" and Text (Text'First)'Address = Data.Address,
                 "query uses actual payload address");
      end Inspect;
   begin
      --  The synchronous view must not allocate an input-sized String copy.
      --  Compare addresses and provider accounting around the callback.
      Data.Set_Owner (Reference (Memory));
      Data.Append ("actual");
      Before := Statistics (Memory).Growth_Attempts;
      Data.Query (Inspect'Access);
      Assert (Called and Statistics (Memory).Growth_Attempts = Before,
              "query did not allocate");
   end Query_Borrows_Actual_Storage;

   procedure Query_Tampering_Rejected is
      Memory : Owner;
      Data : Buffers.Buffer;
      Rejected : Boolean := False;
      procedure Inspect (Text : String);
      procedure Inspect (Text : String) is
      begin
         Assert (Text = "held", "borrowed source");
         begin
            Data.Append ('!');
         exception
            when Program_Error => Rejected := True;
         end;
      end Inspect;
   begin
      --  A callback captures its source builder. Reentrant mutation must not
      --  invalidate the borrowed String while the query is still executing.
      Data.Set_Owner (Reference (Memory));
      Data.Append ("held");
      Data.Query (Inspect'Access);
      Assert (Rejected and Data.To_String = "held", "query tampering guard");
      Data.Append ('!');
      Assert (Data.To_String = "held!", "query released borrow");
   end Query_Tampering_Rejected;

   procedure Query_Exception_Recovery is
      Memory : Owner;
      Data : Buffers.Buffer;
      Raised : Boolean := False;
      procedure Reject (Text : String);
      procedure Reject (Text : String) is
         pragma Unreferenced (Text);
      begin
         raise Constraint_Error with "query callback";
      end Reject;
   begin
      --  Callback failure must release its borrow on the exceptional path.
      --  The same buffer must then remain writable and correctly finalized.
      Data.Set_Owner (Reference (Memory));
      Data.Append ('a');
      begin
         Data.Query (Reject'Access);
      exception
         when Constraint_Error => Raised := True;
      end;
      Data.Append ('b');
      Assert (Raised and Data.To_String = "ab", "query failure recovery");
   end Query_Exception_Recovery;

   procedure Aliased_Append_Growth is
      Memory : Owner;
      Data : Buffers.Buffer;
      Input : constant String (1 .. 80) := [others => 'x'];
   begin
      --  Append an imported view of the builder to itself across realloc.
      --  The implementation must rebase its source, not copy freed storage.
      Data.Set_Owner (Reference (Memory));
      Data.Append (Input);
      declare
         View : constant String (1 .. Data.Length)
           with Import, Address => Data.Address;
      begin
         Data.Append (View);
      end;
      Assert (Data.To_String = Input & Input,
              "aliased append survived growth");
   end Aliased_Append_Growth;

   procedure Aliased_Set_Value is
      Memory : Owner;
      Data : Buffers.Buffer;
   begin
      --  Replace the contents with an overlapping suffix. Clearing first
      --  would corrupt the source; forward memmove must preserve the suffix.
      Data.Set_Owner (Reference (Memory));
      Data.Append ("abcde");
      declare
         View : constant String (1 .. 3)
           with Import, Address => Data.Address + 2;
      begin
         Data.Set_Value (View);
      end;
      Assert (Data.To_String = "cde", "overlapping replacement");
   end Aliased_Set_Value;

   procedure Refused_Growth_Preserves is
      Memory : Owner;
      Data : Buffers.Buffer;
      Before : System.Address;
      Failed : Boolean := False;
   begin
      --  Refuse managed growth. Address, bytes and logical length must remain
      --  unchanged so a protected allocation retry can reuse the builder.
      Data.Set_Owner (Reference (Memory));
      Data.Append ("keep");
      Before := Data.Address;
      Set_Failure_Countdown (Memory, 0);
      begin
         Data.Append (String'(1 .. 256 => 'x'));
      exception
         when Allocation_Error => Failed := True;
      end;
      Assert (Failed and Data.Address = Before and Data.To_String = "keep",
              "refused buffer growth preserved source");
   end Refused_Growth_Preserves;

   procedure Refused_Copy_Preserves is
      Memory : Owner;
      Data : Buffers.Buffer;
      Failed : Boolean := False;
   begin
      --  Failed controlled copying must clear the shallow copy before cleanup,
      --  preserving both the source and its semantic memory-failure witness.
      Data.Set_Owner (Reference (Memory));
      Data.Append ("keep");
      Set_Failure_Countdown (Memory, 0);
      begin
         declare
            Duplicate : constant Buffers.Buffer := Buffers.Copy (Data);
         begin
            Assert (Duplicate.Length = 4, "copy unexpectedly succeeded");
         end;
      exception
         when Allocation_Error | Program_Error => Failed := True;
      end;
      Assert (Failed and Refusal_Pending (Memory), "copy refusal witness");
      Assert (Data.To_String = "keep" and
              Statistics (Memory).Live_Blocks = 1, "failed copy kept source");
   end Refused_Copy_Preserves;

   procedure Clear_And_C_Terminator is
      Memory : Owner;
      Data : Buffers.Buffer;
      Before : Natural;
   begin
      --  The empty C view needs an actual NUL even before first append. Clear
      --  preserves allocation and binding while restoring that terminator.
      Data.Set_Owner (Reference (Memory));
      Assert (Characters.To_Pointer (Data.C_Address).all = Character'Val (0),
              "empty C address has terminator");
      Data.Append ("bytes");
      Before := Data.Capacity;
      Data.Clear;
      Assert (Data.Is_Empty and Data.Capacity = Before,
              "clear keeps capacity");
      Assert (Characters.To_Pointer (Data.Address).all = Character'Val (0),
              "clear restores first NUL");
   end Clear_And_C_Terminator;

   procedure Release_And_Rebind is
      First, Second : Owner;
      Data : Buffers.Buffer;
   begin
      --  Releasing capacity must balance the original allocator. With no live
      --  storage the builder can be rebound deliberately to another universe.
      Data.Set_Owner (Reference (First));
      Data.Append ("first");
      Data.Release;
      Assert (Statistics (First).Live_Blocks = 0, "released original owner");
      Data.Set_Owner (Reference (Second));
      Data.Append ("second");
      Assert (Data.To_String = "second", "released builder rebound");
   end Release_And_Rebind;

   procedure Geometric_Growth is
      Memory : Owner;
      Data : Buffers.Buffer;
   begin
      --  Byte-by-byte construction must grow geometrically, not allocate
      --  every append. This is the common loader/native-builder workload.
      Data.Set_Owner (Reference (Memory));
      for Index in 1 .. 4_096 loop
         Data.Append ('x');
      end loop;
      Assert (Data.Length = 4_096 and Data.Element (4_096) = 'x',
              "geometric byte content");
      Assert (Statistics (Memory).Growth_Attempts < 20,
              "geometric byte allocation count");
   end Geometric_Growth;

   procedure Slice_And_Replacement is
      Memory : Owner;
      Data : Buffers.Buffer;
   begin
      --  Slice retains its requested Ada bounds; mutation targets the actual
      --  byte and does not change length or remove the trailing terminator.
      Data.Set_Owner (Reference (Memory));
      Data.Append ("abcde");
      Data.Replace_Element (3, 'X');
      declare
         Part : constant String := Data.Slice (2, 4);
      begin
         Assert (Part'First = 2 and Part = "bXd", "slice bounds and bytes");
      end;
      Assert (Data.Length = 5, "replacement preserved length");
   end Slice_And_Replacement;

   procedure Empty_Query is
      Memory : Owner;
      Data : Buffers.Buffer;
      Called : Boolean := False;
      procedure Inspect (Text : String);
      procedure Inspect (Text : String) is
      begin
         Called := True;
         Assert (Text'Length = 0, "empty view");
      end Inspect;
   begin
      --  Empty queries need no payload allocation and must still invoke their
      --  consumer once, distinguishing an empty source from a missing call.
      Data.Set_Owner (Reference (Memory));
      Data.Query (Inspect'Access);
      Assert (Called and Statistics (Memory).Live_Blocks = 0,
              "empty query did not allocate");
   end Empty_Query;

   procedure Append_Buffers_And_Self is
      First, Second : Owner;
      Source, Target : Buffers.Buffer;
   begin
      --  Appending another owner's bytes must borrow, never transfer storage.
      --  Self append then forces growth, protecting rebasing of aliased input.
      Source.Set_Owner (Reference (First));
      Target.Set_Owner (Reference (Second));
      Source.Set_Value (String'(1 .. 40 => 'x'));
      Target.Append (Source);
      Target.Append (Target);
      Assert (Source.Length = 40 and Target.Length = 80,
              "buffer and self append lengths");
      Assert (Source.Element (1) = 'x' and Target.Element (80) = 'x',
              "buffer and self append retained bytes");
      Assert (Source.Owner_Of = Reference (First) and
              Target.Owner_Of = Reference (Second),
              "buffer append preserved both allocator bindings");
   end Append_Buffers_And_Self;

   procedure Insert_Delete_Byte_Order is
      Memory : Owner;
      Data : Buffers.Buffer;
   begin
      --  Insert at every boundary, remove a middle range and preserve binary
      --  payload length. Both shift directions must leave the extra NUL valid.
      Data.Set_Owner (Reference (Memory));
      Data.Insert (1, "bc");
      Data.Insert (1, "a");
      Data.Insert (4, "d");
      Data.Insert (3, String'(1 => Character'Val (0)));
      Assert (Data.To_String = "ab" & Character'Val (0) & "cd",
              "ordered insertion retained embedded NUL");
      Data.Delete (2, 4);
      Data.Delete (3, 2);
      Assert (Data.To_String = "ad", "ordered deletion and empty interval");
      Assert (Characters.To_Pointer (Data.C_Address + 2).all =
                Character'Val (0), "ordered mutations restored terminator");
      Data.Delete (1, 2);
      Assert (Data.Is_Empty and Characters.To_Pointer
        (Data.C_Address).all = Character'Val (0), "delete whole payload");
   end Insert_Delete_Byte_Order;

   procedure Overlapping_Insert_Refusal is
      Memory : Owner;
      Data : Buffers.Buffer;
      Failed : Boolean := False;
   begin
      --  An imported slice aliases the suffix that insertion will shift.
      --  Snapshot it through the same owner; refusal must precede any shift.
      Data.Set_Owner (Reference (Memory));
      Data.Set_Value ("abcd");
      declare
         View : constant String (1 .. 4)
           with Import, Address => Data.Address;
      begin
         Set_Failure_Countdown (Memory, 0);
         begin
            Data.Insert (2, View (2 .. 3));
         exception
            when Allocation_Error => Failed := True;
         end;
      end;
      Assert (Failed and Data.To_String = "abcd",
              "failed overlapping snapshot preserved source");
      Clear_Failures (Memory);
      Acknowledge_Refusal (Memory);
      declare
         View : constant String (1 .. 4)
           with Import, Address => Data.Address;
      begin
         Data.Insert (2, View (2 .. 3));
      end;
      Assert (Data.To_String = "abcbcd", "overlapping insertion byte order");
      Assert (Statistics (Memory).Live_Blocks = 1,
              "temporary overlapping snapshot released");
   end Overlapping_Insert_Refusal;

   procedure Ordered_Mutation_Query_Guard is
      Memory : Owner;
      Data : Buffers.Buffer;
      Rejections : Natural := 0;
      procedure Inspect (Text : String);
      procedure Inspect (Text : String) is
      begin
         begin
            Data.Insert (1, "x");
         exception
            when Program_Error => Rejections := Rejections + 1;
         end;
         begin
            Data.Delete (1, 1);
         exception
            when Program_Error => Rejections := Rejections + 1;
         end;
         Assert (Text = "held", "borrowed bytes survived rejected shifts");
      end Inspect;
   begin
      --  Ordered edits invalidate borrowed slices even without growth. Both
      --  operations must therefore honor the same guard as append/release.
      Data.Set_Owner (Reference (Memory));
      Data.Set_Value ("held");
      Data.Query (Inspect'Access);
      Assert (Rejections = 2 and Data.To_String = "held",
              "query prevented insertion and deletion");
      Data.Insert (1, "x");
      Assert (Data.To_String = "xheld", "ordered edit recovered after query");
   end Ordered_Mutation_Query_Guard;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "managed bytes: binary shifted source",
                        Binary_And_Shifted_Bytes'Access);
      Test_Support.Add (Suite, "managed bytes: independent copy",
                        Independent_Copy'Access);
      Test_Support.Add (Suite, "managed bytes: actual borrowed view",
                        Query_Borrows_Actual_Storage'Access);
      Test_Support.Add (Suite, "managed bytes: query tampering",
                        Query_Tampering_Rejected'Access);
      Test_Support.Add (Suite, "managed bytes: query exception recovery",
                        Query_Exception_Recovery'Access);
      Test_Support.Add (Suite, "managed bytes: aliased append growth",
                        Aliased_Append_Growth'Access);
      Test_Support.Add (Suite, "managed bytes: aliased set value",
                        Aliased_Set_Value'Access);
      Test_Support.Add (Suite, "managed bytes: refused growth",
                        Refused_Growth_Preserves'Access);
      Test_Support.Add (Suite, "managed bytes: refused copy",
                        Refused_Copy_Preserves'Access);
      Test_Support.Add (Suite, "managed bytes: clear C terminator",
                        Clear_And_C_Terminator'Access);
      Test_Support.Add (Suite, "managed bytes: release rebind",
                        Release_And_Rebind'Access);
      Test_Support.Add (Suite, "managed bytes: geometric growth",
                        Geometric_Growth'Access);
      Test_Support.Add (Suite, "managed bytes: slice replacement",
                        Slice_And_Replacement'Access);
      Test_Support.Add (Suite, "managed bytes: empty query",
                        Empty_Query'Access);
      Test_Support.Add (Suite, "managed bytes: buffer and self append",
                        Append_Buffers_And_Self'Access);
      Test_Support.Add (Suite, "managed bytes: insertion deletion order",
                        Insert_Delete_Byte_Order'Access);
      Test_Support.Add (Suite, "managed bytes: overlapping insert refusal",
                        Overlapping_Insert_Refusal'Access);
      Test_Support.Add (Suite, "managed bytes: ordered mutation borrow",
                        Ordered_Mutation_Query_Guard'Access);
   end Register;
end Lua.Storage_Buffer_Tests;
