with AUnit.Assertions; use AUnit.Assertions;
with Interfaces.C;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.Loader_Storage_Tests is
   use type Interfaces.C.size_t;
   use type Lua.Storage.Byte_Count;

   function Refuse_Large_Growth
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
     with Convention => C;
   function Refuse_Large_Growth
     (Data, Block : System.Address;
      Old_Size, New_Size : Interfaces.C.size_t) return System.Address
   is
   begin
      --  Keep small VM/parser setup possible, then refuse the source-sized
      --  buffer or token/string allocation. This is an actual allocator
      --  failure, not a host instruction/resource quota.
      if New_Size > Old_Size and then New_Size >= 16_384 then
         return System.Null_Address;
      end if;
      return Lua.Storage.Default_Allocator (Data, Block, Old_Size, New_Size);
   end Refuse_Large_Growth;

   generic
      with procedure Action (State : in out World);
   procedure Fixture;
   procedure Fixture is
      State : World;
   begin
      Initialize (State, (others => <>));
      begin
         Set (State, Global_Environment (State), New_String (State, "source"),
              New_String (State, "return '" & String'(1 .. 64_000 => 'x') &
                                  "'"));
         Action (State);
      exception
         when others => Finalize (State); raise;
      end;
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "loader memory fixture leaked managed storage");
   end Fixture;

   procedure Raw_Load_Memory_Result (State : in out World);
   procedure Reader_Load_Memory_Result (State : in out World);

   procedure Raw_Load_Memory_Result (State : in out World) is
   begin
      --  The source already exists as a rooted Lua string. Refuse loading's
      --  managed growth: load returns nil/message, and successful Lua code
      --  following it proves that the parser boundary consumed the failure.
      Lua.Storage.Set_Allocator (State.Memory, Refuse_Large_Growth'Access);
      Assert (Execute (State,
        "local f,m=load(source,'=refused'); " &
        "assert(f==nil and m=='not enough memory')", "load-memory"),
        "raw load did not return a protected memory result");
      Assert (State.Current.Failure_Class = No_Failure and then
                not Lua.Storage.Refusal_Pending (State.Memory),
              "raw load retained a pending memory failure");
      Lua.Storage.Set_Allocator
        (State.Memory, Lua.Storage.Default_Allocator'Access);
      Assert (Execute (State, "assert(type(source)=='string')", "recovery"),
              "raw load refusal damaged the session");
   end Raw_Load_Memory_Result;

   procedure Reader_Load_Memory_Result (State : in out World) is
   begin
      --  A reader supplies one large fragment. Refusal while retaining that
      --  fragment must return load's nil/message, with no extra reader call
      --  and no restart of the abandoned continuation or its work budget.
      Lua.Storage.Set_Allocator (State.Memory, Refuse_Large_Growth'Access);
      Assert (Execute (State,
        "local n=0; local f,m=load(function() n=n+1; " &
        "if n==1 then return source end end,'=reader'); " &
        "assert(f==nil and m=='not enough memory' and n==1)",
        "reader-memory"), "reader load did not return memory result");
      Assert (State.Current.Failure_Class = No_Failure and then
                not Lua.Storage.Refusal_Pending (State.Memory),
              "reader load retained a pending memory failure");
      Lua.Storage.Set_Allocator
        (State.Memory, Lua.Storage.Default_Allocator'Access);
      Assert (Execute (State, "assert(1+1==2)", "recovery"),
              "reader load refusal damaged the session");
   end Reader_Load_Memory_Result;

   procedure Raw_Case is new Fixture (Raw_Load_Memory_Result);
   procedure Reader_Case is new Fixture (Reader_Load_Memory_Result);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "loader storage: raw load memory result",
                        Raw_Case'Access);
      Test_Support.Add (Suite, "loader storage: reader load memory result",
                        Reader_Case'Access);
   end Register;
end Lua.Loader_Storage_Tests;
