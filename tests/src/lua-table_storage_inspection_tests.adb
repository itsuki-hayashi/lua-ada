with AUnit.Assertions; use AUnit.Assertions;
with Lua.Conformance_Adapter;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Table_Storage_Probe;
with Lua.Storage;
with Test_Support;

package body Lua.Table_Storage_Inspection_Tests is
   use type Lua.Storage.Byte_Count;
   type Trial is
     (Trial_Empty_Table,
      Trial_Mixed_Storage,
      Trial_Indexed_Tombstone,
      Trial_Revived_Free_Row,
      Trial_Collected_Key,
      Trial_Reused_Row,
      Trial_Refused_Insert,
      Trial_No_Allocation,
      Trial_Null_Target,
      Trial_Unregistered_Key,
      Trial_Wrong_Key_Tag,
      Trial_Wrong_Value_Tag,
      Trial_Array_Bounds,
      Trial_Hash_Bounds,
      Trial_Hash_Cycle,
      Trial_Free_Bounds,
      Trial_Free_Cycle,
      Trial_Free_Flags,
      Trial_Nil_Linked,
      Trial_Wrong_Bucket,
      Trial_Hash_Count);

   procedure Run (Kind : Trial);
   procedure Run (Kind : Trial) is
      State : World;
      Table, Key : Value;
      Rows, Live : Natural;
      Original, Changed : Table_Entry;
      Head, Other_Head, Missing_Slot : Natural := 0;
      Saved_Hash, Saved_Other, Saved_Array : Natural := 0;
      Saved_Free, Saved_Count : Natural := 0;
      Missing : Object_Access;
      Rejected : Boolean := False;
      Refusals, Raw : Lua.Storage.Byte_Count;
      Corrupted : Boolean := False;
      procedure Check (Expected_Rows, Expected_Live : Natural);
      procedure Restore;

      procedure Check (Expected_Rows, Expected_Live : Natural) is
      begin
         Conformance_Adapter.Verify_Table_Storage
           (State, Table, Rows, Live);
         Assert (Rows = Expected_Rows and then Live = Expected_Live,
                 "actual retained rows and nonnil entries");
      end Check;

      procedure Restore is
      begin
         if not Corrupted then return; end if;
         --  Restore exact saved evidence, never rebuild or collect a corrupt
         --  graph. Even an unexpected checker exception must leave physical
         --  teardown with the genuine owned pointers and scalar indices.
         if Missing_Slot /= 0 then
            State.Heap.Replace_Element (Missing_Slot, Missing);
         end if;
         Table.Reference.Members.Replace_Element (2, Original);
         Table.Reference.Array_Index.Replace_Element (1, Saved_Array);
         Table.Reference.Hash_Index.Replace_Element (Head, Saved_Hash);
         Table.Reference.Hash_Index.Replace_Element
           (Other_Head, Saved_Other);
         Table.Reference.Free_Row := Saved_Free;
         Table.Reference.Hash_Rows := Saved_Count;
         Corrupted := False;
      end Restore;
   begin
      State.Open_Standard_Libraries := False;
      Initialize (State, (others => <>));
      Table := New_Table (State);
      Pin (State, Table);
      if Kind = Trial_Empty_Table then
         Check (0, 0);
      elsif Kind = Trial_Null_Target then
         begin
            Conformance_Adapter.Verify_Table_Storage
              (State, (Table_Kind, null), Rows, Live);
         exception
            when Program_Error => Rejected := True;
         end;
         Assert (Rejected, "null table pointer rejected before dereference");
      else
         --  One dense row and one hash row expose both real index paths.
         --  Keep only the table rooted: deleting the string binding makes
         --  its header genuinely unreachable despite this Ada local copy.
         Key := New_String (State, "storage-check-hash-key");
         Set (State, Table, (Integer_Kind, 1), (Integer_Kind, 17));
         Set (State, Table, Key, (Integer_Kind, 23));
         case Kind is
            when Trial_Mixed_Storage => Check (2, 2);
            when Trial_Indexed_Tombstone =>
               Set (State, Table, Key, Nil_Value);
               Assert (Table_Storage_Probe.Find (Table.Reference, Key) = 2,
                       "deleted live key still has its actual index");
               Check (2, 1);
            when Trial_Revived_Free_Row =>
               Set (State, Table, Key, Nil_Value);
               Set (State, Table, Key, (Integer_Kind, 29));
               Assert (Table.Reference.Members (2).Free_Listed,
                       "real revival retains its queued free row");
               Check (2, 2);
            when Trial_Collected_Key | Trial_Reused_Row =>
               Set (State, Table, Key, Nil_Value);
               Collect (State);
               Assert (Table.Reference.Members (2).Key.Kind = Nil_Kind,
                       "collector clears the actual dead key before sweep");
               Check (2, 1);
               if Kind = Trial_Reused_Row then
                  Key := New_Table (State);
                  Set (State, Table, Key, (Integer_Kind, 31));
                  Check (2, 2);
                  Assert (Get (Table, Key) = (Integer_Kind, 31) and then
                          Get (Table, (Integer_Kind, 1)) =
                            (Integer_Kind, 17),
                          "same table reuses the dead row and keeps live key");
               end if;
            when Trial_Refused_Insert =>
               --  Fill the retained member reservation, then force actual
               --  growth to fail. Existing rows remain readable and can be
               --  checked before restoring the provider and retrying.
               for Index in 2 .. 7 loop
                  Set (State, Table, (Integer_Kind, Integer_Value (Index)),
                       (Integer_Kind, Integer_Value (Index + 10)));
               end loop;
               Refusals := Lua.Storage.Statistics (State.Memory).Refusals;
               Lua.Storage.Set_Failure_Countdown (State.Memory, 0);
               begin
                  Set (State, Table, (Integer_Kind, 8), (Integer_Kind, 42));
               exception
                  when Language_Error | Lua.Storage.Allocation_Error =>
                     Rejected := True;
               end;
               Lua.Storage.Clear_Failures (State.Memory);
               Assert (Rejected and then
                       Lua.Storage.Statistics (State.Memory).Refusals >
                         Refusals,
                       "insertion actually refused managed growth");
               Check (8, 8);
               Assert (Get (Table, Key) = (Integer_Kind, 23),
                       "refused insertion retains the original hash value");
               Set (State, Table, (Integer_Kind, 8), (Integer_Kind, 42));
               Check (9, 9);
               Assert (Get (Table, (Integer_Kind, 8)) = (Integer_Kind, 42),
                       "restored provider permits the exact insertion retry");
            when Trial_No_Allocation =>
               Raw := Lua.Storage.Statistics (State.Memory).Raw_Bytes;
               Refusals := Lua.Storage.Statistics (State.Memory).Refusals;
               Lua.Storage.Set_Failure_Countdown (State.Memory, 0);
               Check (2, 2);
               Assert (Lua.Storage.Statistics (State.Memory).Raw_Bytes = Raw
                       and then Lua.Storage.Statistics
                         (State.Memory).Refusals = Refusals,
                       "inspection neither allocates nor consumes refusal");
               Lua.Storage.Clear_Failures (State.Memory);
            when others =>
               Original := Table.Reference.Members (2);
               Changed := Original;
               for Index in 1 .. Table.Reference.Hash_Index.Last_Index loop
                  if Table.Reference.Hash_Index (Index) = 2 then
                     Head := Index;
                  end if;
               end loop;
               Assert (Head /= 0, "fixture has an actual indexed hash row");
               Other_Head := Head mod Table.Reference.Hash_Index.Last_Index
                 + 1;
               Saved_Hash := Table.Reference.Hash_Index (Head);
               Saved_Other := Table.Reference.Hash_Index (Other_Head);
               Saved_Array := Table.Reference.Array_Index (1);
               Saved_Free := Table.Reference.Free_Row;
               Saved_Count := Table.Reference.Hash_Rows;
               Corrupted := True;
               case Kind is
                  when Trial_Unregistered_Key =>
                     Missing := Key.Reference;
                     Missing_Slot := Missing.Registry_Slot;
                     State.Heap.Replace_Element (Missing_Slot, null);
                  when Trial_Wrong_Key_Tag =>
                     Changed.Key := (Table_Kind, Key.Reference);
                  when Trial_Wrong_Value_Tag =>
                     Changed.Item := (Closure_Kind, Key.Reference);
                  when Trial_Array_Bounds =>
                     Table.Reference.Array_Index.Replace_Element (1, 3);
                  when Trial_Hash_Bounds =>
                     Table.Reference.Hash_Index.Replace_Element (Head, 3);
                  when Trial_Hash_Cycle => Changed.Next := 2;
                  when Trial_Free_Bounds => Table.Reference.Free_Row := 3;
                  when Trial_Free_Cycle =>
                     Changed.Free_Listed := True;
                     Changed.Free_Next := 2;
                     Table.Reference.Free_Row := 2;
                  when Trial_Free_Flags => Changed.Free_Listed := True;
                  when Trial_Nil_Linked =>
                     Changed.Key := Nil_Value;
                     Changed.Item := Nil_Value;
                     Changed.Free_Listed := True;
                     Table.Reference.Free_Row := 2;
                  when Trial_Wrong_Bucket =>
                     Table.Reference.Hash_Index.Replace_Element (Head, 0);
                     Table.Reference.Hash_Index.Replace_Element
                       (Other_Head, 2);
                  when Trial_Hash_Count => Table.Reference.Hash_Rows := 2;
                  when others => raise Program_Error;
               end case;
               Table.Reference.Members.Replace_Element (2, Changed);
               begin
                  Conformance_Adapter.Verify_Table_Storage
                    (State, Table, Rows, Live);
               exception
                  when Program_Error => Rejected := True;
               end;
               Restore;
               Assert (Rejected, "corrupt storage rejected without repair");
               Check (2, 2);
         end case;
      end if;
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0 and then
              Lua.Storage.Statistics (State.Memory).Raw_Bytes = 0,
              "table checker fixture releases all selected bytes and blocks");
   exception
      when others =>
         Lua.Storage.Clear_Failures (State.Memory);
         Restore;
         Finalize (State);
         raise;
   end Run;

   procedure Empty_Table;
   procedure Empty_Table is
   begin
      --  Protect empty table using actual owned storage.
      Run (Trial_Empty_Table);
   end Empty_Table;

   procedure Mixed_Storage;
   procedure Mixed_Storage is
   begin
      --  Protect actual row and live counts using actual owned storage.
      Run (Trial_Mixed_Storage);
   end Mixed_Storage;

   procedure Indexed_Tombstone;
   procedure Indexed_Tombstone is
   begin
      --  Protect indexed nil-valued tombstone using actual owned storage.
      Run (Trial_Indexed_Tombstone);
   end Indexed_Tombstone;

   procedure Revived_Free_Row;
   procedure Revived_Free_Row is
   begin
      --  Protect revived free-listed row using actual owned storage.
      Run (Trial_Revived_Free_Row);
   end Revived_Free_Row;

   procedure Collected_Key;
   procedure Collected_Key is
   begin
      --  Protect collected key unlinks actual row using actual owned storage.
      Run (Trial_Collected_Key);
   end Collected_Key;

   procedure Reused_Row;
   procedure Reused_Row is
   begin
      --  Protect same-table collected row reuse using actual owned storage.
      Run (Trial_Reused_Row);
   end Reused_Row;

   procedure Refused_Insert;
   procedure Refused_Insert is
   begin
      --  Protect insertion refusal and retry using actual owned storage.
      Run (Trial_Refused_Insert);
   end Refused_Insert;

   procedure No_Allocation;
   procedure No_Allocation is
   begin
      --  Protect read-only checker under refusal using actual owned storage.
      Run (Trial_No_Allocation);
   end No_Allocation;

   procedure Null_Target;
   procedure Null_Target is
   begin
      --  Reject null target using actual owned storage.
      Run (Trial_Null_Target);
   end Null_Target;

   procedure Unregistered_Key;
   procedure Unregistered_Key is
   begin
      --  Reject unregistered key using actual owned storage.
      Run (Trial_Unregistered_Key);
   end Unregistered_Key;

   procedure Wrong_Key_Tag;
   procedure Wrong_Key_Tag is
   begin
      --  Reject key object tag mismatch using actual owned storage.
      Run (Trial_Wrong_Key_Tag);
   end Wrong_Key_Tag;

   procedure Wrong_Value_Tag;
   procedure Wrong_Value_Tag is
   begin
      --  Reject value object tag mismatch using actual owned storage.
      Run (Trial_Wrong_Value_Tag);
   end Wrong_Value_Tag;

   procedure Array_Bounds;
   procedure Array_Bounds is
   begin
      --  Reject array row outside members using actual owned storage.
      Run (Trial_Array_Bounds);
   end Array_Bounds;

   procedure Hash_Bounds;
   procedure Hash_Bounds is
   begin
      --  Reject hash row outside members using actual owned storage.
      Run (Trial_Hash_Bounds);
   end Hash_Bounds;

   procedure Hash_Cycle;
   procedure Hash_Cycle is
   begin
      --  Reject cyclic hash chain using actual owned storage.
      Run (Trial_Hash_Cycle);
   end Hash_Cycle;

   procedure Free_Bounds;
   procedure Free_Bounds is
   begin
      --  Reject free row outside members using actual owned storage.
      Run (Trial_Free_Bounds);
   end Free_Bounds;

   procedure Free_Cycle;
   procedure Free_Cycle is
   begin
      --  Reject cyclic free chain using actual owned storage.
      Run (Trial_Free_Cycle);
   end Free_Cycle;

   procedure Free_Flags;
   procedure Free_Flags is
   begin
      --  Reject unreachable free flag using actual owned storage.
      Run (Trial_Free_Flags);
   end Free_Flags;

   procedure Nil_Linked;
   procedure Nil_Linked is
   begin
      --  Reject linked nil-key row using actual owned storage.
      Run (Trial_Nil_Linked);
   end Nil_Linked;

   procedure Wrong_Bucket;
   procedure Wrong_Bucket is
   begin
      --  Reject wrong hash bucket using actual owned storage.
      Run (Trial_Wrong_Bucket);
   end Wrong_Bucket;

   procedure Hash_Count;
   procedure Hash_Count is
   begin
      --  Reject incorrect hash row count using actual owned storage.
      Run (Trial_Hash_Count);
   end Hash_Count;

   procedure Lua_Actual_Counts;
   procedure Lua_Actual_Counts is
      State : World;
      Source : constant String :=
        "-- Ada-only actual storage counterp" &
        "art, never a native querytab emulat" &
        "ion." & ASCII.LF &
        "assert(T and type(T.ada_check_table" &
        "_storage)=='function')" & ASCII.LF &
        "collectgarbage('stop')" & ASCII.LF &
        "local a={[{}]=4,[3]=0,alo=1," & ASCII.LF &
        "         a1234567890123456789012345" &
        "678901234567890=10}" & ASCII.LF &
        "local weak=setmetatable({},{__mode=" &
        "'v'})" & ASCII.LF &
        "for k in pairs(a)do if type(k)=='ta" &
        "ble'then weak[1]=k end end" & ASCII.LF &
        "local rows,live=T.ada_check_table_s" &
        "torage(a)" & ASCII.LF &
        "assert(rows==4 and live==4)" & ASCII.LF &
        "for k in pairs(a)do a[k]=nil end" & ASCII.LF &
        "collectgarbage()" & ASCII.LF &
        "local retained,after=T.ada_check_ta" &
        "ble_storage(a)" & ASCII.LF &
        "assert(retained==rows and after==0 " &
        "and weak[1]==nil and next(a)==nil)" & ASCII.LF &
        "local fresh={};a[fresh]=42" & ASCII.LF &
        "local reused,inserted=T.ada_check_t" &
        "able_storage(a)" & ASCII.LF &
        "assert(reused==rows and inserted==1" &
        " and a[fresh]==42)" & ASCII.LF &
        "collectgarbage('restart')" & ASCII.LF &
        "print('Table storage private OK')" & ASCII.LF &
        "";
   begin
      --  The real generic C inspection callback publishes two actual counts.
      --  Public weak collection observes the original anonymous key, and the
      --  same owned table is reused after those dead rows have been cleared.
      Initialize (State, (others => <>));
      Conformance_Adapter.Install (State);
      Assert (Execute (State, Source, "=table-storage"),
              Failure_Image (State.Current));
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0 and then
              Lua.Storage.Statistics (State.Memory).Raw_Bytes = 0,
              "Lua storage counterpart closes every selected allocation");
   exception
      when others =>
         Lua.Storage.Clear_Failures (State.Memory);
         Finalize (State);
         raise;
   end Lua_Actual_Counts;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "table storage: actual Lua counts and weak witness",
         Lua_Actual_Counts'Access);
      Test_Support.Add
        (Suite, "table storage: empty table",
                        Empty_Table'Access);
      Test_Support.Add
        (Suite, "table storage: actual row and live counts",
                        Mixed_Storage'Access);
      Test_Support.Add
        (Suite, "table storage: indexed nil-valued tombstone",
                        Indexed_Tombstone'Access);
      Test_Support.Add
        (Suite, "table storage: revived free-listed row",
                        Revived_Free_Row'Access);
      Test_Support.Add
        (Suite, "table storage: collected key unlinks actual row",
                        Collected_Key'Access);
      Test_Support.Add
        (Suite, "table storage: same-table collected row reuse",
                        Reused_Row'Access);
      Test_Support.Add
        (Suite, "table storage: insertion refusal and retry",
                        Refused_Insert'Access);
      Test_Support.Add
        (Suite, "table storage: read-only checker under refusal",
                        No_Allocation'Access);
      Test_Support.Add
        (Suite, "table storage: rejects null target",
                        Null_Target'Access);
      Test_Support.Add
        (Suite, "table storage: rejects unregistered key",
                        Unregistered_Key'Access);
      Test_Support.Add
        (Suite, "table storage: rejects key object tag mismatch",
                        Wrong_Key_Tag'Access);
      Test_Support.Add
        (Suite, "table storage: rejects value object tag mismatch",
                        Wrong_Value_Tag'Access);
      Test_Support.Add
        (Suite, "table storage: rejects array row outside members",
                        Array_Bounds'Access);
      Test_Support.Add
        (Suite, "table storage: rejects hash row outside members",
                        Hash_Bounds'Access);
      Test_Support.Add
        (Suite, "table storage: rejects cyclic hash chain",
                        Hash_Cycle'Access);
      Test_Support.Add
        (Suite, "table storage: rejects free row outside members",
                        Free_Bounds'Access);
      Test_Support.Add
        (Suite, "table storage: rejects cyclic free chain",
                        Free_Cycle'Access);
      Test_Support.Add
        (Suite, "table storage: rejects unreachable free flag",
                        Free_Flags'Access);
      Test_Support.Add
        (Suite, "table storage: rejects linked nil-key row",
                        Nil_Linked'Access);
      Test_Support.Add
        (Suite, "table storage: rejects wrong hash bucket",
                        Wrong_Bucket'Access);
      Test_Support.Add
        (Suite, "table storage: rejects incorrect hash row count",
                        Hash_Count'Access);
   end Register;
end Lua.Table_Storage_Inspection_Tests;
