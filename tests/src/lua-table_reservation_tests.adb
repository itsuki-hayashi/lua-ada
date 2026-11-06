with Ada.Containers;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Storage; use Lua.Storage;
with Test_Support;

package body Lua.Table_Reservation_Tests is
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
         when others => Finalize (State); raise;
      end;
      Finalize (State);
      Assert (Statistics (State.Memory).Live_Blocks = 0,
              "table reservation retained storage after finalization");
   end Fixture;

   procedure Real_Empty_Storage (State : in out World);
   procedure Real_Empty_Storage (State : in out World) is
      Table : constant Value := New_Table (State);
      Before : constant Byte_Count := Statistics (State.Memory).Payload_Bytes;
   begin
      --  A size hint must allocate actual provider-owned memory without
      --  inventing members, keys or a nonzero sequence border.
      Reserve_Table (State, Table, 128, 64);
      Assert (Statistics (State.Memory).Payload_Bytes > Before,
              "reservation was only fabricated capacity metadata");
      Assert (Table.Reference.Members.Is_Empty and then
                Table_Length (Table) = 0, "reservation created entries");
      Assert (Table.Reference.Array_Index.Length >= 128 and then
                Table.Reference.Hash_Index.Length >= 64,
              "reservation did not allocate both index families");
      Assert (Get (Table, (Integer_Kind, 1)).Kind = Nil_Kind,
              "empty reserved dense slot is not initialized");
   end Real_Empty_Storage;

   procedure Dense_Fill_Without_Growth (State : in out World);
   procedure Dense_Fill_Without_Growth (State : in out World) is
      Table : constant Value := New_Table (State);
      Before : Byte_Count;
   begin
      --  Reserve once, then refuse every further growth. Filling the promised
      --  sequence must not build an unnecessary hash or grow member rows.
      Reserve_Table (State, Table, 128, 0);
      Before := Statistics (State.Memory).Growth_Attempts;
      Set_Failure_Countdown (State.Memory, 0);
      for Index in 1 .. 128 loop
         Set (State, Table, (Integer_Kind, Integer_Value (Index)),
              (Integer_Kind, Integer_Value (Index * 2)));
      end loop;
      Clear_Failures (State.Memory);
      Assert (Statistics (State.Memory).Growth_Attempts = Before,
              "preallocated sequence attempted managed growth");
      Assert (Table_Length (Table) = 128 and then
                Get (Table, (Integer_Kind, 128)).Integer_Data = 256,
              "preallocated sequence lost values");
   end Dense_Fill_Without_Growth;

   procedure Hash_Fill_Without_Growth (State : in out World);
   procedure Hash_Fill_Without_Growth (State : in out World) is
      Table : constant Value := New_Table (State);
      Before : Byte_Count;
   begin
      --  Negative immediate keys require no Lua allocation and cannot enter
      --  the dense index. All requested hash rows must fit under refusal.
      Reserve_Table (State, Table, 0, 64);
      Before := Statistics (State.Memory).Growth_Attempts;
      Set_Failure_Countdown (State.Memory, 0);
      for Index in 1 .. 64 loop
         Set (State, Table, (Integer_Kind, -Integer_Value (Index)),
              (Integer_Kind, Integer_Value (Index)));
      end loop;
      Clear_Failures (State.Memory);
      Assert (Statistics (State.Memory).Growth_Attempts = Before,
              "preallocated hash attempted managed growth");
      Assert (Table_Length (Table) = 0 and then
                Get (Table, (Integer_Kind, -64)).Integer_Data = 64,
              "preallocated hash lost values");
   end Hash_Fill_Without_Growth;

   procedure Failed_Reserve_Retry (State : in out World);
   procedure Failed_Reserve_Retry (State : in out World) is
      Table : constant Value := New_Table (State);
      Before : constant Natural := State.Entry_Count;
      Refused : Boolean := False;
   begin
      --  Permit member capacity, then fail the next index reserve. Logical
      --  lengths must remain unpublished so reads and a later retry are safe.
      Set_Failure_Countdown (State.Memory, 1);
      begin
         Reserve_Table (State, Table, 128, 64);
      exception
         when Allocation_Error => Refused := True;
      end;
      Clear_Failures (State.Memory);
      Assert (Refused, "injected second reservation was not refused");
      Assert (Table.Reference.Array_Index.Is_Empty and then
                Table.Reference.Hash_Index.Is_Empty and then
                State.Entry_Count = Before, "failed reserve published state");
      Reserve_Table (State, Table, 128, 64);
      Set (State, Table, (Integer_Kind, 1), (Integer_Kind, 42));
      Assert (Get (Table, (Integer_Kind, 1)).Integer_Data = 42,
              "retry after partial capacity reservation failed");
   end Failed_Reserve_Retry;

   procedure Empty_Case is new Fixture (Real_Empty_Storage);
   procedure Dense_Case is new Fixture (Dense_Fill_Without_Growth);
   procedure Hash_Case is new Fixture (Hash_Fill_Without_Growth);
   procedure Failure_Case is new Fixture (Failed_Reserve_Retry);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "table reservation: real empty storage", Empty_Case'Access);
      Test_Support.Add
        (Suite, "table reservation: dense growth refusal", Dense_Case'Access);
      Test_Support.Add
        (Suite, "table reservation: hash growth refusal", Hash_Case'Access);
      Test_Support.Add
        (Suite, "table reservation: partial failure retry",
         Failure_Case'Access);
   end Register;
end Lua.Table_Reservation_Tests;
