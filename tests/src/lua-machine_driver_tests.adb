with Ada.Unchecked_Deallocation;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Compiler;
with Lua.Engine.Machine;
with Test_Support;

package body Lua.Machine_Driver_Tests is
   use type Integer_Value;
   package VM renames Lua.Engine.Machine;
   procedure Free_World is new Ada.Unchecked_Deallocation
     (World, World_Access);

   generic
      with procedure Action (State : World_Access);
   procedure Fixture;

   procedure Fixture is
      State : World_Access := new World;
   begin
      Initialize (State.all, (others => <>));
      begin
         Action (State);
      exception
         when others =>
            Finalize (State.all);
            Free_World (State);
            raise;
      end;
      Finalize (State.all);
      Free_World (State);
   end Fixture;

   procedure Drain (Driver : in out VM.Driver);
   procedure Incremental_Progress (State : World_Access);
   procedure Terminal_Packet_Roots (State : World_Access);
   procedure Budget_Preservation (State : World_Access);
   procedure Protected_Error_Packet (State : World_Access);
   procedure Active_Finish_Guard (State : World_Access);
   procedure Active_Start_Guard (State : World_Access);
   procedure Interleaved_Worlds (State : World_Access);
   procedure Synchronous_Discard (State : World_Access);
   procedure Premature_Inspection (State : World_Access);
   procedure Completed_Step_Guard (State : World_Access);
   procedure Native_Call_Arguments (State : World_Access);
   procedure Closing_Slot_Snapshot (State : World_Access);
   procedure Outer_Closing_Cell_Mutation (State : World_Access);
   procedure Inactive_Close_Mutation (State : World_Access);

   procedure Drain (Driver : in out VM.Driver) is
   begin
      --  The guard protects the test harness from a broken completion flag.
      --  It is a test bound, not a replacement VM instruction counter.
      for Iteration in 1 .. 10_000 loop
         exit when VM.Is_Complete (Driver);
         VM.Step (Driver);
      end loop;
      Assert (VM.Is_Complete (Driver), "driver did not complete");
   end Drain;

   procedure Incremental_Progress (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "local x=1; x=x+41; return x", "incremental");
      Driver : VM.Driver;
   begin
      --  Start publishes a frame; one Step must return while the multi-op
      --  program is unfinished. Further steps produce its actual return value.
      VM.Start (Driver, State, Code);
      Assert (not VM.Is_Complete (Driver), "start executed the chunk");
      VM.Step (Driver);
      Assert (not VM.Is_Complete (Driver), "one step drained the VM");
      Drain (Driver);
      Assert (VM.Outcome (Driver) = Completed, "completion transfer");
      Assert (VM.Results (Driver).First_Element.Integer_Data = 42,
              "incremental result");
      VM.Finish (Driver);
   end Incremental_Progress;

   procedure Terminal_Packet_Roots (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "return {answer=42},false,nil", "packet-roots");
      Driver : VM.Driver;
      Packet : Values.Vector;
      Table : Object_Access;
   begin
      --  The completed packet alone retains the table across collection.
      --  Finish releases that root after a foreign caller could copy it.
      VM.Start (Driver, State, Code);
      Drain (Driver);
      Packet := VM.Results (Driver);
      Assert (Natural (Packet.Length) = 3, "multiple result count");
      Table := Packet (1).Reference;
      Assert (Packet (2) = Value'(Boolean_Kind, False) and then
                Packet (3).Kind = Nil_Kind, "packet values");
      Collect (State.all);
      Assert (State.Heap.Contains (Table), "terminal packet was unrooted");
      Packet.Clear;
      VM.Finish (Driver);
      Collect (State.all);
      Assert (not State.Heap.Contains (Table), "finish retained results");
   end Terminal_Packet_Roots;

   procedure Budget_Preservation (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "for i=1,100 do end", "driver-quota");
      Driver : VM.Driver;
      Rejected : Boolean := False;
   begin
      --  A driver is not a public execution boundary. Starting it at an
      --  exhausted quota must fail before work, then permit normal recovery.
      State.Bounds.Instructions := 9;
      State.Steps := 9;
      VM.Start (Driver, State, Code);
      Assert (State.Steps = 9, "start reset the shared quota");
      begin
         VM.Step (Driver);
      exception
         when Language_Error => Rejected := True;
      end;
      Assert (Rejected and then State.Current.Failure_Class = Host_Abort,
              "exhaustion became catchable success");
      VM.Finish (Driver);
      VM.Clear_Frames (State.all);
      State.Bounds.Instructions := 1_000;
      Assert (Execute (State.all, "assert(true)", "driver-recovery"),
              "session did not recover after driver abort");
   end Budget_Preservation;

   procedure Protected_Error_Packet (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "return pcall(function()error({code=17})end)",
         "driver-protection");
      Driver : VM.Driver;
      Packet : Values.Vector;
   begin
      --  Protected failure must survive repeated returns to the driver host
      --  as false plus the same arbitrary Lua object, with a usable session.
      VM.Start (Driver, State, Code);
      Drain (Driver);
      Packet := VM.Results (Driver);
      Assert (Natural (Packet.Length) = 2 and then
                Packet (1) = Value'(Boolean_Kind, False) and then
                Packet (2).Kind = Table_Kind, "protected results");
      Collect (State.all);
      Assert (Get (Packet (2), New_String (State.all, "code")) =
                Value'(Integer_Kind, 17), "arbitrary error object lost");
      VM.Finish (Driver);
      Assert (Execute (State.all, "assert(true)", "protected-recovery"),
              "protected failure damaged later execution");
   end Protected_Error_Packet;

   procedure Active_Finish_Guard (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "return 23", "active-finish");
      Driver : VM.Driver;
      Rejected : Boolean := False;
   begin
      --  Accidental release of an active borrow must be rejected without
      --  silently abandoning its continuation or corrupting later progress.
      VM.Start (Driver, State, Code);
      begin
         VM.Finish (Driver);
      exception
         when Program_Error => Rejected := True;
      end;
      Assert (Rejected, "active driver was abandoned");
      Drain (Driver);
      Assert (VM.Results (Driver).First_Element.Integer_Data = 23,
              "rejected finish changed the drive");
      VM.Finish (Driver);
      VM.Finish (Driver);
   end Active_Finish_Guard;

   procedure Active_Start_Guard (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "return 31", "active-start");
      Driver : VM.Driver;
      Rejected : Boolean := False;
   begin
      --  A second Start cannot replace a live driver, even on the same world.
      --  Rejecting that misuse must preserve the original call and its roots.
      VM.Start (Driver, State, Code);
      begin
         VM.Start (Driver, State, Code);
      exception
         when Program_Error => Rejected := True;
      end;
      Assert (Rejected, "nested driver start was accepted");
      Drain (Driver);
      Assert (VM.Results (Driver).First_Element.Integer_Data = 31,
              "rejected start damaged the drive");
      VM.Finish (Driver);
   end Active_Start_Guard;

   procedure Interleaved_Worlds (State : World_Access) is
      Other : World_Access := new World;
      Left, Right : VM.Driver;
   begin
      --  Alternate two worlds instruction by instruction. Any hidden global
      --  current-world shortcut would write one world's answer into the other.
      Initialize (Other.all, (others => <>));
      begin
         VM.Start (Left, State, Compiler.Compile
           (State.all, "answer=11;return answer", "left-driver"));
         VM.Start (Right, Other, Compiler.Compile
           (Other.all, "answer=29;return answer", "right-driver"));
         for Iteration in 1 .. 10_000 loop
            exit when VM.Is_Complete (Left) and VM.Is_Complete (Right);
            if not VM.Is_Complete (Left) then
               VM.Step (Left);
            end if;
            if not VM.Is_Complete (Right) then
               VM.Step (Right);
            end if;
         end loop;
         Assert (VM.Is_Complete (Left) and VM.Is_Complete (Right),
                 "interleaved drives did not complete");
         Assert (VM.Results (Left).First_Element.Integer_Data = 11 and then
                   VM.Results (Right).First_Element.Integer_Data = 29,
                 "worlds shared driver state");
         VM.Finish (Left);
         VM.Finish (Right);
      exception
         when others =>
            Finalize (Other.all);
            Free_World (Other);
            raise;
      end;
      Finalize (Other.all);
      Free_World (Other);
   end Interleaved_Worlds;

   procedure Synchronous_Discard (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "return {discard=true}", "synchronous-discard");
   begin
      --  Ordinary Ada execution still discards chunk results. The stepping
      --  API must not introduce a new permanent root through the Run wrapper.
      VM.Run (State.all, Code);
      Assert (State.Current.Transfer.Kind = No_Transfer and then
                State.Current.Transfer.Results.Is_Empty,
              "synchronous wrapper retained chunk results");
      Assert (State.Current.Stack.Is_Empty, "synchronous frame leaked");
   end Synchronous_Discard;

   procedure Premature_Inspection (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "return 7", "premature-outcome");
      Driver : VM.Driver;
      Kind : Transfer_Kind := No_Transfer;
      Packet : Values.Vector;
      Outcome_Rejected, Packet_Rejected : Boolean := False;
   begin
      --  Inspecting an active drive must not masquerade as an empty successful
      --  return. Both query failures leave the driver available to continue.
      VM.Start (Driver, State, Code);
      begin
         Kind := VM.Outcome (Driver);
      exception
         when Program_Error => Outcome_Rejected := True;
      end;
      begin
         Packet := VM.Results (Driver);
      exception
         when Program_Error => Packet_Rejected := True;
      end;
      Assert (Outcome_Rejected and then Packet_Rejected and then
                Kind = No_Transfer and then Packet.Is_Empty,
              "active drive exposed completion data");
      Drain (Driver);
      VM.Finish (Driver);
   end Premature_Inspection;

   procedure Completed_Step_Guard (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "return 53", "completed-step");
      Driver : VM.Driver;
      Rejected : Boolean := False;
   begin
      --  A completed packet remains usable after an accidental extra Step.
      --  Reject that misuse without clearing its result or restarting work.
      VM.Start (Driver, State, Code);
      Drain (Driver);
      begin
         VM.Step (Driver);
      exception
         when Program_Error => Rejected := True;
      end;
      Assert (Rejected and then VM.Is_Complete (Driver) and then
                VM.Results (Driver).First_Element.Integer_Data = 53,
              "extra step destroyed terminal data");
      VM.Finish (Driver);
   end Completed_Step_Guard;

   procedure Native_Call_Arguments (State : World_Access) is
      Driver : VM.Driver;
      Arguments : Values.Vector;
   begin
      --  The function-value entry accepts a real native callable without a
      --  source wrapper. Its frame must root arguments after the host drops
      --  its local packet and collects between Start and the next Step.
      Arguments.Append (New_String (State.all, "0x2a"));
      VM.Start (Driver, State, (Native_Kind_Value, Tonumber_Function),
                Arguments);
      Arguments.Clear;
      Collect (State.all);
      Drain (Driver);
      Assert (VM.Results (Driver).First_Element.Integer_Data = 42,
              "native function arguments were unrooted");
      VM.Finish (Driver);
   end Native_Call_Arguments;

   procedure Closing_Slot_Snapshot (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all,
         "local log=''; local read; " &
         "local function object(name) return setmetatable({name=name}," &
         "{__close=function(self) log=log..self.name end}) end; " &
         "do local first <close> = object('first'); " &
         "read=function() return first end; " &
         "local last <close> = setmetatable({}, {__close=function() " &
         "log=log..'last'; debug.setupvalue(read,1,object('replacement')); " &
         "collectgarbage() end}) end; return log,read().name",
         "closing-snapshot");
      Driver : VM.Driver;
   begin
      --  The later declaration closes first and replaces an earlier shared
      --  upvalue. Lua has already separated that cell from its departing
      --  stack slot: the original object must still close and survive GC.
      VM.Start (Driver, State, Code);
      Drain (Driver);
      Assert (Image (VM.Results (Driver) (1)) = "lastfirst",
              "a closing callback replaced a departing stack-slot value");
      Assert (Image (VM.Results (Driver) (2)) = "replacement",
              "debug mutation did not update the actual closed upvalue");
      VM.Finish (Driver);
   end Closing_Slot_Snapshot;

   procedure Outer_Closing_Cell_Mutation (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all,
         "local log=''; local function object(name) " &
         "return setmetatable({name=name},{__close=function(self) " &
         "log=log..self.name end}) end; " &
         "do local outer <close> = object('original'); " &
         "local read=function() return outer end; " &
         "do local inner <close> = setmetatable({}, {__close=function() " &
         "debug.setupvalue(read,1,object('replacement')) end}) end end; " &
         "return log", "outer-close-mutation");
      Driver : VM.Driver;
   begin
      --  An inner-scope exit must snapshot only its own closer. The outer
      --  declaration remains live, so a callback can change its upvalue
      --  before the later outer exit chooses the value to close.
      VM.Start (Driver, State, Code);
      Drain (Driver);
      Assert (Image (VM.Results (Driver).First_Element) = "replacement",
              "an inner exit froze a still-live outer closing variable");
      VM.Finish (Driver);
   end Outer_Closing_Cell_Mutation;

   procedure Inactive_Close_Mutation (State : World_Access) is
      Code : constant Prototype_Access := Compiler.Compile
        (State.all, "local log='';do local x <close> = false;" &
         "local read=function()return x end;" &
         "debug.setupvalue(read,1,setmetatable({}," &
         "{__close=function()log='closed' end})) end;return log",
         "inactive-close-mutation");
      Driver : VM.Driver;
   begin
      --  An inactive false initializer creates no close entry. Even a debug
      --  mutation to a real closable value must not change that decision.
      VM.Start (Driver, State, Code);
      Drain (Driver);
      Assert (Image (VM.Results (Driver).First_Element) = "",
              "false-initialized declaration acquired a close obligation");
      VM.Finish (Driver);
   end Inactive_Close_Mutation;

   procedure Progress_Case is new Fixture (Incremental_Progress);
   procedure Root_Case is new Fixture (Terminal_Packet_Roots);
   procedure Budget_Case is new Fixture (Budget_Preservation);
   procedure Protection_Case is new Fixture (Protected_Error_Packet);
   procedure Finish_Case is new Fixture (Active_Finish_Guard);
   procedure Start_Case is new Fixture (Active_Start_Guard);
   procedure Worlds_Case is new Fixture (Interleaved_Worlds);
   procedure Discard_Case is new Fixture (Synchronous_Discard);
   procedure Inspection_Case is new Fixture (Premature_Inspection);
   procedure Completed_Case is new Fixture (Completed_Step_Guard);
   procedure Native_Case is new Fixture (Native_Call_Arguments);
   procedure Closing_Snapshot_Case is new Fixture (Closing_Slot_Snapshot);
   procedure Outer_Closing_Case is new Fixture (Outer_Closing_Cell_Mutation);
   procedure Inactive_Close_Case is new Fixture (Inactive_Close_Mutation);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "driver: incremental progress",
                        Progress_Case'Access);
      Test_Support.Add (Suite, "driver: terminal packet roots",
                        Root_Case'Access);
      Test_Support.Add (Suite, "driver: preserved budget", Budget_Case'Access);
      Test_Support.Add (Suite, "driver: protected error packet",
                        Protection_Case'Access);
      Test_Support.Add (Suite, "driver: active finish guard",
                        Finish_Case'Access);
      Test_Support.Add
        (Suite, "driver: active start guard", Start_Case'Access);
      Test_Support.Add (Suite, "driver: interleaved worlds",
                        Worlds_Case'Access);
      Test_Support.Add (Suite, "driver: synchronous discard",
                        Discard_Case'Access);
      Test_Support.Add (Suite, "driver: premature inspection",
                        Inspection_Case'Access);
      Test_Support.Add (Suite, "driver: completed step guard",
                        Completed_Case'Access);
      Test_Support.Add (Suite, "driver: native argument roots",
                        Native_Case'Access);
      Test_Support.Add (Suite, "driver: departing close slot snapshot",
                        Closing_Snapshot_Case'Access);
      Test_Support.Add (Suite, "driver: live outer close cell mutation",
                        Outer_Closing_Case'Access);
      Test_Support.Add (Suite, "driver: inactive close mutation",
                        Inactive_Close_Case'Access);
   end Register;
end Lua.Machine_Driver_Tests;
