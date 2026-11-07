with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Compiler;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.Managed_Runtime_Tests is
   use type Lua.Storage.Byte_Count;

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
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "runtime finalization retained managed blocks");
   end Fixture;

   procedure String_Reclamation (State : in out World);
   procedure Memory_Recovery (State : in out World);
   procedure Table_Buffer_Accounting (State : in out World);
   procedure Mixed_Heap_Survivors (State : in out World);
   procedure Program_Operation_Root (State : in out World);
   procedure Raw_Metafield_Allocation (State : in out World);
   procedure Weak_Mode_Nul (State : in out World);

   procedure String_Reclamation (State : in out World) is
      Item : constant Value := New_String (State, "a" & ASCII.NUL & "b");
      Address : constant System.Address := Item.Reference.C_Bytes;
   begin
      --  A byte string and its C view share one tracked immutable allocation.
      --  Drop its only unrooted value, collect, and query ownership without
      --  dereferencing the now-dead object or payload.
      Assert (Lua.Storage.Owns (State.Memory, Address), "unmanaged bytes");
      Assert (Item.Reference.Bytes = "a" & ASCII.NUL & "b",
              "managed binary payload");
      Assert (Length (Item.Reference.Bytes) = 3, "embedded NUL length");
      Collect (State);
      Assert (not Lua.Storage.Owns (State.Memory, Address),
              "string C view survived unreachable string");
   end String_Reclamation;

   procedure Memory_Recovery (State : in out World) is
   begin
      --  Refuse managed growth during compilation, then restore the provider.
      --  It must produce a semantic memory diagnostic with a preallocated
      --  error object and preserve the universe for another execution.
      Assert (Execute (State, "saved=17", "setup"), "memory setup");
      Lua.Storage.Set_Ceiling (State.Memory, 0);
      Assert (not Execute (State, "local answer=42", "refused"),
              "managed refusal escaped or succeeded");
      Assert (State.Current.Failure_Class = Memory_Failure,
              "managed refusal became a host abort");
      Assert (State.Current.Has_Failure_Value and then
                State.Current.Failure = State.Memory_Error_Value,
              "memory error did not use retained error object");
      Assert (not Lua.Storage.Refusal_Pending (State.Memory),
              "handled refusal remained sticky");
      Lua.Storage.Set_Ceiling (State.Memory, Lua.Storage.Byte_Count'Last);
      Assert (Execute (State, "assert(saved==17)", "recovery"),
              "memory refusal damaged persistent state");
   end Memory_Recovery;

   procedure Table_Buffer_Accounting (State : in out World) is
      Before : constant Lua.Storage.Allocation_Statistics :=
        Lua.Storage.Statistics (State.Memory);
      Item : constant Value := New_Table (State);
   begin
      --  Populate an unrooted dense table. Row, direct-index and hash buffers
      --  must be actual managed allocations, and collection must release them
      --  along with the object rather than waiting for universe destruction.
      for Index in 1 .. 5_000 loop
         Set (State, Item, (Integer_Kind, Integer_Value (Index)),
              (Integer_Kind, Integer_Value (Index)));
      end loop;
      Assert (Lua.Storage.Statistics (State.Memory).Payload_Bytes >
                Before.Payload_Bytes + 5_000 * 8, "unmanaged table buffers");
      Collect (State);
      Assert (Lua.Storage.Statistics (State.Memory).Raw_Bytes =
                Before.Raw_Bytes, "table buffer collection balance");
   end Table_Buffer_Accounting;

   procedure Mixed_Heap_Survivors (State : in out World) is
      Held : constant Value := New_Table (State);
      Before : Natural;
   begin
      --  Interleave live and dead strings, retaining only even entries in a
      --  global table. One real sweep must release exactly the unrooted
      --  half while preserving all object addresses and surviving contents.
      Set (State, Global_Environment (State),
           New_String (State, "keepers"), Held);
      for Index in 1 .. 1_000 loop
         declare
            Text : constant Value := New_String (State, Index'Image);
         begin
            if Index mod 2 = 0 then
               Set (State, Held, (Integer_Kind, Integer_Value (Index)), Text);
            end if;
         end;
      end loop;
      Before := State.Live_Objects;
      Collect (State);
      Assert (State.Live_Objects = Before - 500,
              "mixed heap survivor count");
      for Index in 1 .. 500 loop
         Assert (Get (Held, (Integer_Kind,
                   Integer_Value (Index * 2))).Reference.Bytes =
                     Integer'Image (Index * 2),
                 "stable-slot survivor changed");
      end loop;
   end Mixed_Heap_Survivors;

   procedure Program_Operation_Root (State : in out World) is
      Code : constant Prototype_Access :=
        Compiler.Compile (State, "return 42", "operation-root");
   begin
      --  Remove the compiler bridge so only the explicit operation pin owns
      --  this program. It must survive during the operation and be reclaimed
      --  after End_Operation, including failed activation-setup paths.
      State.Entry_Code := null;
      Begin_Operation (State);
      Pin (State, Code);
      Collect (State);
      Assert (State.Programs.Contains (Code), "operation lost prototype");
      End_Operation (State);
      Collect (State);
      Assert (not State.Programs.Contains (Code), "operation retained code");
   end Program_Operation_Root;

   procedure Raw_Metafield_Allocation (State : in out World) is
      Item : constant Value := New_Table (State);
      Meta : constant Value := New_Table (State);
      Handler : constant Value := New_Table (State);
      Before : Lua.Storage.Allocation_Statistics;
   begin
      --  Build a metatable before refusing growth. Event lookup must read its
      --  actual string bucket without constructing a temporary Lua key. Both
      --  hits and misses remain usable during emergency collection/refusal.
      Item.Reference.Metatable := Meta.Reference;
      Set (State, Meta, New_String (State, "__index"), Handler);
      Before := Lua.Storage.Statistics (State.Memory);
      Lua.Storage.Set_Ceiling (State.Memory, 0);
      Assert (Metafield (State, Item, "__index") = Handler,
              "raw event lookup lost handler");
      Assert (Metafield (State, Item, "__missing").Kind = Nil_Kind,
              "raw event miss was not nil");
      Assert (Lua.Storage.Statistics (State.Memory).Growth_Attempts =
                Before.Growth_Attempts, "metafield lookup allocated");
      Lua.Storage.Set_Ceiling (State.Memory, Lua.Storage.Byte_Count'Last);
   end Raw_Metafield_Allocation;

   procedure Weak_Mode_Nul (State : in out World) is
   begin
      --  Lua's collector tests __mode through C-string strchr semantics.
      --  A v after NUL must not weaken an otherwise strongly held value, even
      --  though ordinary byte-string operations retain that suffix.
      Assert (Execute (State,
        "local value={}; local weak=setmetatable({value}," &
        "{__mode='\0v'}); value=nil; collectgarbage(); " &
        "assert(type(weak[1])=='table')", "weak-mode-nul"),
        "weak mode after NUL: " & To_String (State.Current.Failure_Text));
   end Weak_Mode_Nul;

   procedure Metafield_Case is new Fixture (Raw_Metafield_Allocation);
   procedure Weak_Nul_Case is new Fixture (Weak_Mode_Nul);
   procedure Program_Case is new Fixture (Program_Operation_Root);
   procedure String_Case is new Fixture (String_Reclamation);
   procedure Recovery_Case is new Fixture (Memory_Recovery);
   procedure Table_Case is new Fixture (Table_Buffer_Accounting);
   procedure Survivor_Case is new Fixture (Mixed_Heap_Survivors);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "managed runtime: allocation-free metafield",
                        Metafield_Case'Access);
      Test_Support.Add (Suite, "managed runtime: NUL weak mode boundary",
                        Weak_Nul_Case'Access);
      Test_Support.Add (Suite, "managed runtime: program operation root",
                        Program_Case'Access);
      Test_Support.Add (Suite, "managed runtime: string lifetime",
                        String_Case'Access);
      Test_Support.Add (Suite, "managed runtime: memory failure recovery",
                        Recovery_Case'Access);
      Test_Support.Add (Suite, "managed runtime: table buffer accounting",
                        Table_Case'Access);
      Test_Support.Add (Suite, "managed runtime: mixed heap stable survivors",
                        Survivor_Case'Access);
   end Register;
end Lua.Managed_Runtime_Tests;
