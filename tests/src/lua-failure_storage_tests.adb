with AUnit.Assertions; use AUnit.Assertions;
with Lua.Diagnostic_Text;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with Test_Support;

package body Lua.Failure_Storage_Tests is
   use type Lua.Storage.Byte_Count;
   Long_Source : constant String (1 .. 1_024) := [others => 'x'];
   procedure Selected_Builder (State : in out World);
   procedure Original_Error (State : in out World);
   procedure Counted_Error (State : in out World);
   procedure Shared_Contexts (State : in out World);
   procedure Refused_Builder (State : in out World);
   procedure Bounded_Builder (State : in out World);
   procedure Compatible_Load (State : in out World);
   procedure Long_Load_Mode (State : in out World);

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
         when others =>
            Lua.Storage.Clear_Failures (State.Memory);
            Finalize (State);
            raise;
      end;
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "failure delivery retained selected allocations");
   end Fixture;

   procedure Selected_Builder (State : in out World) is
      Before : constant Lua.Storage.Allocation_Statistics :=
        Lua.Storage.Statistics (State.Memory);
      Item : Value;
   begin
      --  Build an actual pending runtime diagnostic through its universe,
      --  then publish a Lua object directly from the managed borrowed bytes.
      Set_Failure_Text (State, State.Current, Long_Source);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks =
                Before.Live_Blocks + 1 and then
                Lua.Diagnostic_Text.Length (State.Current.Failure_Text) =
                  Long_Source'Length,
              "pending diagnostic bypassed selected storage");
      Assert (Failure_Image (State.Current) = Long_Source,
              "pending diagnostic bytes");
      Item := Ensure_Error_Object (State, State.Current);
      Assert (State.Current.Has_Failure_Value and then
                Item.Reference = State.Current.Failure.Reference and then
                Lua.Diagnostic_Text.Length (State.Current.Failure_Text) = 0,
              "published error retained a duplicate diagnostic payload");
      Collect (State);
      Assert (Failure_Image (State.Current) = Long_Source,
              "published diagnostic lost its collector root");
   end Selected_Builder;

   procedure Original_Error (State : in out World) is
      Item, Delivered : Value;
      Before : Lua.Storage.Byte_Count;
   begin
      --  The real Lua error path must retain its existing long string. An
      --  allocator freeze after failure cannot require a reporting copy.
      Assert (not Execute
        (State, "error(string.rep('x',1024),0)", "=original-error"),
        "long Lua error unexpectedly succeeded");
      Item := State.Current.Failure;
      Assert (State.Current.Has_Failure_Value and then
                Item.Kind = String_Kind and then
                Lua.Diagnostic_Text.Length (State.Current.Failure_Text) = 0,
              "actual Lua error duplicated its message storage");
      Before := Lua.Storage.Statistics (State.Memory).Growth_Attempts;
      Lua.Storage.Set_Failure_Countdown (State.Memory, 0);
      Delivered := Ensure_Error_Object (State, State.Current);
      Assert (Delivered.Reference = Item.Reference and then
                Failure_Image (State.Current) = Long_Source and then
                Lua.Storage.Statistics (State.Memory).Growth_Attempts = Before,
              "error publication allocated or replaced original identity");
   end Original_Error;

   procedure Counted_Error (State : in out World) is
      Item : Value;
   begin
      --  Counted Lua error strings retain embedded NULs. No C-prefix display
      --  convention may alter the actual object delivered to a catcher.
      Assert (not Execute
        (State, "error(string.rep('x',200)..string.char(0)..'tail',0)",
         "=counted-error"), "counted error unexpectedly succeeded");
      Item := State.Current.Failure;
      Assert (Item.Kind = String_Kind and then
                Length (Item.Reference.Bytes) = 205 and then
                Element (Item.Reference.Bytes, 201) = Character'Val (0)
                and then
                Failure_Image (State.Current)'Length = 205 and then
                Lua.Diagnostic_Text.Length (State.Current.Failure_Text) = 0,
              "error storage truncated NUL or duplicated counted bytes");
   end Counted_Error;

   procedure Shared_Contexts (State : in out World) is
      Original : constant Context_Access := State.Current;
      Other : constant Context_Id := Create_Context (State);
      Target : Context_Access;
      Before : Lua.Storage.Byte_Count;
   begin
      --  Failure routing between contexts shares the immutable selected block
      --  without growth. Releasing the source cannot invalidate the receiver.
      Set_Failure_Text (State, Original, Long_Source);
      Select_Context (State, Other);
      Target := State.Current;
      Before := Lua.Storage.Statistics (State.Memory).Growth_Attempts;
      Lua.Storage.Set_Failure_Countdown (State.Memory, 0);
      Target.Failure_Text := Original.Failure_Text;
      Lua.Diagnostic_Text.Clear (Original.Failure_Text);
      Assert (Failure_Image (Target) = Long_Source and then
                Lua.Storage.Statistics (State.Memory).Growth_Attempts = Before,
              "cross-context failure copied or lost selected payload");
      Select_Context (State, 1);
   end Shared_Contexts;

   procedure Refused_Builder (State : in out World) is
      Before : Lua.Storage.Byte_Count;
      Refused : Boolean := False;
   begin
      --  Actual long diagnostic construction may refuse, but its previous
      --  state survives and the preallocated memory error needs no new block.
      Set_Failure_Text (State, State.Current, "previous diagnostic");
      Before := Lua.Storage.Statistics (State.Memory).Growth_Attempts;
      Lua.Storage.Set_Failure_Countdown (State.Memory, 0);
      begin
         Set_Failure_Text (State, State.Current, Long_Source);
      exception
         when Lua.Storage.Allocation_Error => Refused := True;
      end;
      Assert (Refused and then
                Failure_Image (State.Current) = "previous diagnostic",
              "refused diagnostic destroyed the old message");
      Record_Memory_Error (State);
      Assert (State.Current.Failure_Class = Memory_Failure and then
                State.Current.Failure.Reference =
                  State.Memory_Error_Value.Reference and then
                Failure_Image (State.Current) = "not enough memory" and then
                Lua.Storage.Statistics (State.Memory).Growth_Attempts =
                  Before + 1,
              "memory-error recovery attempted secondary growth");
   end Refused_Builder;

   procedure Bounded_Builder (State : in out World) is
      Before : constant Lua.Storage.Byte_Count :=
        Lua.Storage.Statistics (State.Memory).Growth_Attempts;
      Stopped : Boolean := False;
   begin
      --  Input-sized diagnostic copies consume the same explicit host budget.
      --  Exhaustion publishes a bounded host abort before provider allocation.
      State.Bounds.Instructions := 64;
      State.Steps := 0;
      begin
         Set_Failure_Text (State, State.Current, Long_Source);
      exception
         when Language_Error => Stopped := True;
      end;
      Assert (Stopped and then
                State.Current.Failure_Class = Host_Abort and then
                State.Current.Transfer.Kind = Host_Stopped and then
                Failure_Image (State.Current) = "instruction limit exceeded"
                and then Lua.Storage.Statistics
                  (State.Memory).Growth_Attempts = Before,
              "diagnostic copy bypassed or reclassified host policy");
   end Bounded_Builder;

   procedure Compatible_Load (State : in out World) is
   begin
      --  Lua-compatible execution ignores the instruction quota and retains
      --  allocation limits. The same source exceeds a bounded quota.
      State.Policy := Lua_Compatible;
      State.Bounds.Instructions := 1;
      Assert (Execute
        (State, "assert(assert(load('return 37'))()==37)",
         "=compatible-load"), Failure_Image (State.Current));
   end Compatible_Load;

   procedure Long_Load_Mode (State : in out World) is
   begin
      --  The mode is a counted Lua value but a C-prefix option. Its full
      --  applicable prefix must survive owned diagnostic construction.
      Assert (Execute
        (State, "local prefix=string.rep('z',300);" &
         "local mode=prefix..string.char(0)..'t';" &
         "local f,e=load('return 37','mode',mode);" &
         "assert(f==nil and e==""attempt to load a text chunk " &
         "(mode is '""..prefix..""')"")", "=long-load-mode"),
         Failure_Image (State.Current));
   end Long_Load_Mode;

   procedure Selected_Case is new Fixture (Selected_Builder);
   procedure Original_Case is new Fixture (Original_Error);
   procedure Counted_Case is new Fixture (Counted_Error);
   procedure Context_Case is new Fixture (Shared_Contexts);
   procedure Refusal_Case is new Fixture (Refused_Builder);
   procedure Budget_Case is new Fixture (Bounded_Builder);
   procedure Compatible_Case is new Fixture (Compatible_Load);
   procedure Mode_Case is new Fixture (Long_Load_Mode);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "failure storage: selected builder publication",
                        Selected_Case'Access);
      Test_Support.Add (Suite, "failure storage: original long error identity",
                        Original_Case'Access);
      Test_Support.Add (Suite, "failure storage: counted Lua error bytes",
                        Counted_Case'Access);
      Test_Support.Add (Suite, "failure storage: allocation-free context copy",
                        Context_Case'Access);
      Test_Support.Add (Suite, "failure storage: refused builder recovery",
                        Refusal_Case'Access);
      Test_Support.Add (Suite, "failure storage: bounded copy policy",
                        Budget_Case'Access);
      Test_Support.Add (Suite, "failure storage: compatible load policy",
                        Compatible_Case'Access);
      Test_Support.Add (Suite, "failure storage: long C-prefix load mode",
                        Mode_Case'Access);
   end Register;
end Lua.Failure_Storage_Tests;
