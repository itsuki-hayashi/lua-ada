with Ada.Unchecked_Deallocation;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Compiler;
with Lua.Engine.Machine;
with Lua.Engine.Stacks;
with Lua.Storage;
with Test_Support;

package body Lua.Closing_Prefix_Tests is
   use type Lua.Storage.Byte_Count;
   package VM renames Lua.Engine.Machine;
   procedure Free_World is new Ada.Unchecked_Deallocation
     (World, World_Access);

   generic
      with procedure Behavior
        (State : World_Access; Driver : in out VM.Driver;
         Item : not null Frame_Access);
   procedure Fixture;
   procedure Fixture is
      State : World_Access := new World;
      Driver : VM.Driver;
      Code : Prototype_Access;
      Item : Frame_Access;
      Ready : Value;
   begin
      Initialize (State.all, (others => <>));
      State.Canonical_Compilation := True;
      Code := Compiler.Compile
        (State.all,
         "prefix_tail=setmetatable({},{__mode='v'});local x={};" &
         "local c <close> =setmetatable({},{__close=function()end});" &
         "local y={};prefix_tail[1]=y;prefix_ready=true;return 0",
         "=actual-closing-prefix");
      VM.Start (Driver, State, Code);
      for Step in 1 .. 1_000 loop
         Item := State.Current.Stack.Last_Element;
         Ready := Get
           (Global_Environment (State.all),
            New_String (State.all, "prefix_ready"));
         exit when not Item.Is_Native and then Truth (Ready);
         Assert (not VM.Is_Complete (Driver), "pending scope ran too early");
         VM.Step (Driver);
      end loop;
      Assert (not Item.Is_Native and then Item.C_Closing_Level /= 0,
              "missing actual canonical closing declaration");
      Behavior (State, Driver, Item);
      VM.Set_Closing_Stack_Prefix (State.all, 0);
      VM.Cancel (Driver);
      VM.Clear_Frames (State.all);
      Finalize (State.all);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "prefix fixture leaked physical ownership");
      Free_World (State);
   exception
      when others =>
         if State /= null then
            VM.Cancel (Driver);
            Finalize (State.all);
            Free_World (State);
         end if;
         raise;
   end Fixture;

   function Tail_Value (State : World_Access) return Object_Access;
   function Tail_Value (State : World_Access) return Object_Access is
      Weak : constant Value := Get
        (Global_Environment (State.all),
         New_String (State.all, "prefix_tail"));
   begin
      return Get (Weak, (Integer_Kind, 1)).Reference;
   end Tail_Value;

   procedure Exact_Level
     (State : World_Access; Driver : in out VM.Driver;
      Item : not null Frame_Access);
   procedure Exact_Level
     (State : World_Access; Driver : in out VM.Driver;
      Item : not null Frame_Access)
   is
      pragma Unreferenced (State, Driver);
      Level : constant Natural := Item.C_Closing_Level;
   begin
      Assert (Level > Item.Stack_Base and then
              Level <= Item.Stack_Base + Item.Stack_Window_Length,
              "canonical closing level is not its actual absolute slot");
      Assert (VM.Pending_Closing_Level (Item) = Level,
              "pending level did not retain the actual closing slot");
   end Exact_Level;

   procedure Retained_Prefix
     (State : World_Access; Driver : in out VM.Driver;
      Item : not null Frame_Access);
   procedure Retained_Prefix
     (State : World_Access; Driver : in out VM.Driver;
      Item : not null Frame_Access)
   is
      pragma Unreferenced (Driver);
      Target : constant Object_Access :=
        Stacks.Read (State.Current, Item.Stack_Base + 1).Reference;
   begin
      --  x has no captured cell or strong table edge. After execution is
      --  abandoned only its genuine scalar prefix can keep it observable
      --  while a later closing declaration still awaits its handler.
      VM.Set_Closing_Stack_Prefix
        (State.all, VM.Pending_Closing_Level (Item));
      VM.Retire_Frame_Execution (State.all, Item);
      Collect (State.all);
      Assert (State.Heap.Contains (Target),
              "retiring execution prematurely discarded its close prefix");
      VM.Set_Closing_Stack_Prefix (State.all, 0);
      Collect (State.all);
      Assert (not State.Heap.Contains (Target),
              "restoring an empty floor retained an abandoned scalar");
   end Retained_Prefix;

   procedure Dropped_Tail
     (State : World_Access; Driver : in out VM.Driver;
      Item : not null Frame_Access);
   procedure Dropped_Tail
     (State : World_Access; Driver : in out VM.Driver;
      Item : not null Frame_Access)
   is
      pragma Unreferenced (Driver);
      Target : constant Object_Access := Tail_Value (State);
   begin
      --  y was created after the closing slot. Its weak edge must disappear
      --  when that genuine tail is abandoned, even while the lower prefix
      --  remains live for pending handlers.
      VM.Set_Closing_Stack_Prefix
        (State.all, VM.Pending_Closing_Level (Item));
      VM.Retire_Frame_Execution (State.all, Item);
      Collect (State.all);
      Assert (not State.Heap.Contains (Target),
              "retained prefix incorrectly rooted the abandoned upper tail");
   end Dropped_Tail;

   procedure Surviving_Window
     (State : World_Access; Driver : in out VM.Driver;
      Item : not null Frame_Access);
   procedure Surviving_Window
     (State : World_Access; Driver : in out VM.Driver;
      Item : not null Frame_Access)
   is
      pragma Unreferenced (Driver);
      Target : constant Object_Access := Tail_Value (State);
   begin
      --  Restoring a cleanup floor must not blanket-clear its former range:
      --  a real outer handler can still own values there. Exercise this
      --  using an actual live Lua window, then retire it to prove that the
      --  earlier collection did not manufacture another persistent root.
      VM.Set_Closing_Stack_Prefix
        (State.all, Item.Stack_Base + Item.Canonical_GC_Top);
      VM.Set_Closing_Stack_Prefix (State.all, 0);
      Collect (State.all);
      Assert (State.Heap.Contains (Target),
              "lowering a prefix destroyed a surviving real window");
      VM.Retire_Frame_Execution (State.all, Item);
      Collect (State.all);
      Assert (not State.Heap.Contains (Target),
              "surviving-window test retained a synthetic root");
   end Surviving_Window;

   procedure No_Allocation
     (State : World_Access; Driver : in out VM.Driver;
      Item : not null Frame_Access);
   procedure No_Allocation
     (State : World_Access; Driver : in out VM.Driver;
      Item : not null Frame_Access)
   is
      pragma Unreferenced (Driver);
      Attempts : constant Lua.Storage.Byte_Count :=
        Lua.Storage.Statistics (State.Memory).Growth_Attempts;
   begin
      --  Prefix publication and execution retirement are needed precisely
      --  when memory can already be exhausted. Both must use reserved real
      --  metadata rather than copying the preserved values elsewhere.
      Lua.Storage.Set_Failure_Countdown (State.Memory, 0);
      VM.Set_Closing_Stack_Prefix
        (State.all, VM.Pending_Closing_Level (Item));
      VM.Retire_Frame_Execution (State.all, Item);
      VM.Set_Closing_Stack_Prefix (State.all, 0);
      Assert (Lua.Storage.Statistics (State.Memory).Growth_Attempts = Attempts,
              "closing prefix requested allocator growth");
      Lua.Storage.Clear_Failures (State.Memory);
   end No_Allocation;

   procedure Level_Case is new Fixture (Exact_Level);
   procedure Prefix_Case is new Fixture (Retained_Prefix);
   procedure Tail_Case is new Fixture (Dropped_Tail);
   procedure Window_Case is new Fixture (Surviving_Window);
   procedure Refusal_Case is new Fixture (No_Allocation);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "closing prefix: actual slot",
                        Level_Case'Access);
      Test_Support.Add (Suite, "closing prefix: scalar lifetime",
                        Prefix_Case'Access);
      Test_Support.Add (Suite, "closing prefix: abandoned tail",
                        Tail_Case'Access);
      Test_Support.Add (Suite, "closing prefix: surviving window",
                        Window_Case'Access);
      Test_Support.Add (Suite, "closing prefix: refusal",
                        Refusal_Case'Access);
   end Register;
end Lua.Closing_Prefix_Tests;
