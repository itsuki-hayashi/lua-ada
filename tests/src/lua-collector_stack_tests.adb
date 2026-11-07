with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Stacks;
with Lua.Storage; use Lua.Storage;
with Test_Support;

package body Lua.Collector_Stack_Tests is
   use type Byte_Count;

   generic
      with procedure Behavior (State : in out World);
   procedure Fixture;
   procedure Fixture is
      State : World;
   begin
      Initialize (State, (others => <>));
      Collect (State);
      begin
         Behavior (State);
      exception
         when others =>
            Clear_Failures (State.Memory);
            Finalize (State);
            raise;
      end;
      Clear_Failures (State.Memory);
      Finalize (State);
      Assert (Statistics (State.Memory).Live_Blocks = 0,
              "scalar-root fixture released every managed allocation");
   end Fixture;

   function Contains (State : World; Serial : Positive) return Boolean;
   procedure Finish (State : in out World);
   procedure Stack_Case
     (State : in out World; Retained, Suspended : Boolean);
   procedure Main_Transient (State : in out World);
   procedure Main_Retained (State : in out World);
   procedure Suspended_Transient (State : in out World);
   procedure Suspended_Retained (State : in out World);
   procedure Incremental_Lua (State : in out World);

   function Contains (State : World; Serial : Positive) return Boolean is
   begin
      --  A swept address can be reused. Inspect only current owned slots and
      --  the target's immutable serial, never a stale target pointer.
      for Item of State.Heap loop
         if Item /= null and then Item.Serial = Serial then
            return True;
         end if;
      end loop;
      return False;
   end Contains;

   procedure Finish (State : in out World) is
      Done : Boolean := False;
      Steps : Natural := 0;
   begin
      while not Done loop
         Advance_Collection (State, 8, Done);
         Steps := Steps + 1;
         Assert (Steps < 100_000, "real incremental cycle made progress");
      end loop;
   end Finish;

   procedure Stack_Case
     (State : in out World; Retained, Suspended : Boolean)
   is
      Target : constant Value := New_Table (State);
      Serial : constant Positive := Target.Reference.Serial;
      Weak : constant Value := New_Table (State);
      Meta : constant Value := New_Table (State);
      Thread : Value := Nil_Value;
      Context : Context_Access := State.Current;
      Done : Boolean;
   begin
      State.GC_Running := False;
      Set (State, Meta, New_String (State, "__mode"),
           New_String (State, "v"));
      Set_Metatable (State, Weak, Meta.Reference);
      Set (State, Weak, Value'(Integer_Kind, 1), Target);
      Append_Root (State, State.Operation_Roots, Weak);
      if Suspended then
         Thread := New_Thread (State, Nil_Value);
         Append_Root (State, State.Operation_Roots, Thread);
         Context := State.Contexts (Thread.Reference.Context_Index);
         Context.Host_Owned := False;
         Context.Status := Suspended_Context;
      end if;
      Lua.Engine.Stacks.Reserve (State, Context, 1);
      Context.Foreign_Top := 1;
      Lua.Engine.Stacks.Write (State, Context, 1, Nil_Value);
      Advance_Collection (State, 1, Done);
      Assert (not Done and State.GC.Phase = Propagating,
              "fixture exposes a real unfinished marking phase");
      if Suspended then
         --  Make the reachable inactive thread a previously scanned owner.
         --  Its mandatory gray-again rescan, rather than an active-root
         --  shortcut, must discover any later live scalar publication.
         for Attempt in 1 .. 100_000 loop
            exit when Thread.Reference.Gray_List = Revisit_Gray;
            Advance_Collection (State, 1, Done);
            Assert (not Done, "thread was visited before cycle completion");
         end loop;
         Assert (Thread.Reference.Gray_List = Revisit_Gray and
                 State.GC.Phase = Propagating,
                 "suspended thread awaits its real atomic revisit");
      end if;
      Assert (Target.Reference.Color = State.GC.Current_White,
              "weak target has no accidentally published strong root");
      Lua.Engine.Stacks.Write (State, Context, 1, Target);
      if not Retained then
         --  Model a consumed weak lookup between marking slices. The final
         --  live interval contains nil, so atomic must not rescue the value
         --  merely because it passed briefly through a scalar register.
         Lua.Engine.Stacks.Write (State, Context, 1, Nil_Value);
      end if;
      Finish (State);
      if Retained then
         Assert (Contains (State, Serial) and
                 Get (Weak, Value'(Integer_Kind, 1)).Kind = Table_Kind,
                 "atomic retained the actually live scalar root");
      else
         Assert (not Contains (State, Serial) and
                 Get (Weak, Value'(Integer_Kind, 1)).Kind = Nil_Kind,
                 "atomic discarded the consumed scalar temporary");
      end if;
   end Stack_Case;

   procedure Main_Transient (State : in out World) is
   begin
      Stack_Case (State, Retained => False, Suspended => False);
   end Main_Transient;

   procedure Main_Retained (State : in out World) is
   begin
      Stack_Case (State, Retained => True, Suspended => False);
   end Main_Retained;

   procedure Suspended_Transient (State : in out World) is
   begin
      Stack_Case (State, Retained => False, Suspended => True);
   end Suspended_Transient;

   procedure Suspended_Retained (State : in out World) is
   begin
      Stack_Case (State, Retained => True, Suspended => True);
   end Suspended_Retained;

   procedure Incremental_Lua (State : in out World) is
   begin
      --  This native-matched public Lua program interleaves consumed reads
      --  with many deliberately small real collector slices. The retained
      --  graph forces propagation to span calls instead of finishing at once.
      Assert (Execute (State,
        "collectgarbage('stop'); collectgarbage('collect'); " &
        "local keep={}; for i=1,1000 do keep[i]={} end; " &
        "local w=setmetatable({{}},{__mode='v'}); " &
        "collectgarbage('param','stepsize',100); for i=1,2000 do " &
        "if w[1] then local unused=0 end; collectgarbage('step',0) end; " &
        "assert(#keep==1000 and w[1]==nil); collectgarbage('restart')",
        "incremental-scalar-roots"),
        "incremental weak lookup made native-matched progress");
   end Incremental_Lua;

   procedure Main_Transient_Case is new Fixture (Main_Transient);
   procedure Main_Retained_Case is new Fixture (Main_Retained);
   procedure Suspended_Transient_Case is new Fixture (Suspended_Transient);
   procedure Suspended_Retained_Case is new Fixture (Suspended_Retained);
   procedure Lua_Case is new Fixture (Incremental_Lua);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "collector stack: transient main scalar",
                        Main_Transient_Case'Access);
      Test_Support.Add (Suite, "collector stack: retained main scalar",
                        Main_Retained_Case'Access);
      Test_Support.Add (Suite, "collector stack: transient suspended scalar",
                        Suspended_Transient_Case'Access);
      Test_Support.Add (Suite, "collector stack: retained suspended scalar",
                        Suspended_Retained_Case'Access);
      Test_Support.Add (Suite, "collector stack: incremental Lua weak lookup",
                        Lua_Case'Access);
   end Register;
end Lua.Collector_Stack_Tests;
