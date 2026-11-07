with Ada.Unchecked_Deallocation;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Compiler;
with Lua.Engine.Machine;
with Lua.Storage;
with Test_Support;

package body Lua.Execution_Retirement_Tests is
   use type Lua.Storage.Byte_Count;
   package VM renames Lua.Engine.Machine;
   procedure Free_World is new Ada.Unchecked_Deallocation
     (World, World_Access);

   generic
      with procedure Behavior (State : World_Access);
   procedure Fixture;
   procedure Fixture is
      State : World_Access := new World;
   begin
      Initialize (State.all, (others => <>));
      State.Canonical_Compilation := True;
      begin
         Behavior (State);
      exception
         when others =>
            Finalize (State.all);
            Free_World (State);
            raise;
      end;
      Finalize (State.all);
      Free_World (State);
   end Fixture;

   function Await_Native
     (State : World_Access; Driver : in out VM.Driver) return Frame_Access;
   function Await_Native
     (State : World_Access; Driver : in out VM.Driver) return Frame_Access
   is
      Item : Frame_Access;
   begin
      for Step in 1 .. 100 loop
         Item := State.Current.Stack.Last_Element;
         if Item.Is_Native and then
           Native_Operation_Name (Item) = "base.tostring"
         then
            return Item;
         end if;
         Assert (not VM.Is_Complete (Driver), "native target ran too early");
         VM.Step (Driver);
      end loop;
      Assert (False, "native target did not become an explicit activation");
      return null;
   end Await_Native;

   procedure Stop (State : World_Access; Driver : in out VM.Driver);
   procedure Stop (State : World_Access; Driver : in out VM.Driver) is
   begin
      VM.Cancel (Driver);
      VM.Clear_Frames (State.all);
   end Stop;

   procedure Native_Charges_Once (State : World_Access);
   procedure Native_Charges_Once (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "return tostring(42)", "=retire-native");
      Driver : VM.Driver;
      Item : Frame_Access;
      Depth, Barriers : Natural;
   begin
      --  Pause a genuinely scheduled native call before its body executes,
      --  then abandon it as a host transfer would. Both real charges retire
      --  once; later physical frame cleanup must not subtract either again.
      VM.Start (Driver, State, Code);
      Item := Await_Native (State, Driver);
      Depth := State.Native_Depth;
      Barriers := State.Current.Non_Yieldable;
      Assert (Item.Native_Charge and Item.Blocks_Yield and
              Depth > 0 and Barriers > 0, "missing real native charges");
      VM.Retire_Frame_Execution (State.all, Item);
      VM.Retire_Frame_Execution (State.all, Item);
      Assert (Item.Logically_Unwound and not Item.Has_Stack_Window and
              State.Native_Depth = Depth - 1 and
              State.Current.Native_Depth = Depth - 1 and
              State.Current.Non_Yieldable = Barriers - 1,
              "retired execution retained or duplicated depth/barriers");
      Stop (State, Driver);
      Assert (State.Native_Depth = 0 and
              State.Current.Native_Depth = 0 and
              State.Current.Non_Yieldable = 0,
              "physical release subtracted a retired charge again");
   end Native_Charges_Once;

   procedure Argument_Root_Release (State : World_Access);
   procedure Argument_Root_Release (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "return tostring({})", "=retire-arguments");
      Driver : VM.Driver;
      Item : Frame_Access;
      Argument : Object_Access;
   begin
      --  The scheduled call and its Lua caller retain this otherwise
      --  unreachable argument. Abandon the actual path from top to bottom:
      --  both owners must relinquish dead execution roots while their old
      --  records still remain in the context's cleanup stack.
      VM.Start (Driver, State, Code);
      Item := Await_Native (State, Driver);
      Argument := Item.Native_Arguments.First_Element.Reference;
      Assert (Argument /= null, "missing native table argument");
      for Activation of reverse State.Current.Stack loop
         VM.Retire_Frame_Execution (State.all, Activation);
      end loop;
      Collect (State.all);
      Assert (not State.Heap.Contains (Argument),
              "abandoned argument remained a hidden execution root");
      Stop (State, Driver);
   end Argument_Root_Release;

   procedure Reused_Activation_Reset (State : World_Access);
   procedure Reused_Activation_Reset (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "return tostring(42)", "=retire-reuse");
      Driver : VM.Driver;
      Item, Previous : Frame_Access;
   begin
      --  Borrow the same cached native record for a second real call. Its
      --  prior abandonment cannot hide the new activation or lose new charges.
      VM.Start (Driver, State, Code);
      Previous := Await_Native (State, Driver);
      VM.Retire_Frame_Execution (State.all, Previous);
      Stop (State, Driver);
      VM.Start (Driver, State, Code);
      Item := Await_Native (State, Driver);
      Assert (Item = Previous and not Item.Logically_Unwound and
              Item.Native_Charge and Item.Blocks_Yield,
              "frame reuse inherited an abandoned execution state");
      Stop (State, Driver);
   end Reused_Activation_Reset;

   procedure Refusal_Does_Not_Allocate (State : World_Access);
   procedure Refusal_Does_Not_Allocate (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "return tostring({})", "=retire-refusal");
      Driver : VM.Driver;
      Item : Frame_Access;
      Attempts : Lua.Storage.Byte_Count;
   begin
      --  Error cleanup must work after a permanently refusing allocator.
      --  An already constructed real activation needs no fresh storage to
      --  relinquish its depth, barrier, scalar slots or argument packet.
      VM.Start (Driver, State, Code);
      Item := Await_Native (State, Driver);
      Attempts := Lua.Storage.Statistics (State.Memory).Growth_Attempts;
      Lua.Storage.Set_Failure_Countdown (State.Memory, 0);
      VM.Retire_Frame_Execution (State.all, Item);
      Assert (Lua.Storage.Statistics (State.Memory).Growth_Attempts =
                Attempts and then
              not Lua.Storage.Refusal_Pending (State.Memory),
              "abandonment attempted allocator growth");
      Lua.Storage.Clear_Failures (State.Memory);
      Stop (State, Driver);
   end Refusal_Does_Not_Allocate;

   procedure Frozen_Close_Root (State : World_Access);
   procedure Frozen_Close_Root (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "local x <close> =setmetatable({}," &
         "{__close=function()end});return 0", "=retire-close-root");
      Driver : VM.Driver;
      Item : Frame_Access;
      Target : Object_Access;
   begin
      --  Pause after a real TBC declaration, then abandon before RETURN.
      --  Its frozen close value remains a root after scalar execution storage
      --  retires, and only physical cleanup relinquishes that final owner.
      VM.Start (Driver, State, Code);
      for Step in 1 .. 100 loop
         Item := State.Current.Stack.Last_Element;
         exit when not Item.Is_Native and not Item.Closers.Is_Empty;
         Assert (not VM.Is_Complete (Driver), "TBC declaration ran too early");
         VM.Step (Driver);
      end loop;
      Assert (not Item.Is_Native and not Item.Closers.Is_Empty,
              "TBC declaration did not become a real pending closer");
      VM.Retire_Frame_Execution (State.all, Item);
      Target := Item.Closers.Last_Element.Frozen_Value.Reference;
      Collect (State.all);
      Assert (Item.Closers.Last_Element.Frozen and
              State.Heap.Contains (Target),
              "pending close value was unrooted");
      Stop (State, Driver);
      Collect (State.all);
      Assert (not State.Heap.Contains (Target),
              "physical cleanup retained its frozen close owner");
   end Frozen_Close_Root;

   procedure Charges_Case is new Fixture (Native_Charges_Once);
   procedure Arguments_Case is new Fixture (Argument_Root_Release);
   procedure Reuse_Case is new Fixture (Reused_Activation_Reset);
   procedure Closing_Case is new Fixture (Frozen_Close_Root);
   procedure Refusal_Case is new Fixture (Refusal_Does_Not_Allocate);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "execution retirement: charges once", Charges_Case'Access);
      Test_Support.Add
        (Suite, "execution retirement: argument roots", Arguments_Case'Access);
      Test_Support.Add
        (Suite, "execution retirement: cached state", Reuse_Case'Access);
      Test_Support.Add
        (Suite, "execution retirement: frozen close root",
         Closing_Case'Access);
      Test_Support.Add
        (Suite, "execution retirement: allocator refusal",
         Refusal_Case'Access);
   end Register;
end Lua.Execution_Retirement_Tests;
