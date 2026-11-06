with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Conformance_Adapter;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.Conformance_Adapter_Tests is
   use type Lua.Storage.Byte_Count;
   procedure Check (Source : String);
   procedure Check (Source : String) is
      State : World;
   begin
      Initialize (State, (others => <>));
      begin
         Conformance_Adapter.Install (State);
         Assert (Execute (State, Source, "adapter"),
                 To_String (State.Current.Failure_Text));
      exception
         when others =>
            Lua.Storage.Clear_Failures (State.Memory);
            Finalize (State);
            raise;
      end;
      Finalize (State);
      Assert (Lua.Storage.Statistics (State.Memory).Live_Blocks = 0,
              "adapter universe released actual managed allocations");
   end Check;

   procedure Userdata;
   procedure Color;
   procedure Age;
   procedure Counts;
   procedure Failure;
   procedure Phases;
   procedure Parameters;
   procedure Independent_Ceiling;
   procedure Frame_Reset;
   procedure Stack_Resize;
   procedure Collector_Lists;
   procedure Corrupt_Registry;
   procedure Refused_Weak_Set;
   procedure Stored_Warning;
   procedure Invalid_Count_Type;

   procedure Userdata is
   begin
      --  The C helper calls the actual lua_newuserdatauv export. Debug slots
      --  observe the same full userdata, not an adapter-side stand-in.
      Check ("local u=T.newuserdata(17,2); assert(type(u)=='userdata'); " &
        "assert(debug.setuservalue(u,42,2)==u); " &
        "assert(debug.getuservalue(u,2)==42)");
   end Userdata;

   procedure Color is
   begin
      --  A stopped collector leaves newly allocated objects genuinely white.
      Check ("collectgarbage('stop'); local t={}; " &
        "assert(T.gccolor(t)=='white'); " &
        "assert(T.gccolor(42)=='no collectable')");
   end Color;

   procedure Age is
   begin
      --  Actual full generational collection promotes the rooted object.
      Check ("collectgarbage('generational'); local t={}; " &
        "collectgarbage(); assert(T.gcage(t)=='old')");
   end Age;

   procedure Counts is
   begin
      --  Stop automatic collection so unrelated dead tables cannot change
      --  the before/after count; four new table identities must be counted.
      Check ("collectgarbage(); collectgarbage('stop'); " &
        "local n=T.totalmem('table'); local t={{},{},{}}; " &
        "assert(T.totalmem('table')==n+4); " &
        "local bytes,blocks,peak=T.totalmem(); " &
        "assert(bytes>0 and blocks>0 and peak>=bytes)");
   end Counts;

   procedure Failure is
      Memory : Lua.Storage.Owner;
      Block : System.Address;
      Refused : Boolean := False;
   begin
      --  A one-shot refusal must be consumed before the engine retries. The
      --  second allocation really reaches the provider without clearing it.
      Lua.Storage.Fail_Next_Growth (Memory);
      begin
         Block := Lua.Storage.Allocate (Memory, 64);
      exception
         when Lua.Storage.Allocation_Error => Refused := True;
      end;
      Assert (Refused, "next managed growth was refused");
      Lua.Storage.Acknowledge_Refusal (Memory);
      Block := Lua.Storage.Allocate (Memory, 64);
      Lua.Storage.Release (Memory, Block);
      Assert (Lua.Storage.Statistics (Memory).Live_Blocks = 0,
              "one-shot retry retained balanced allocation ownership");
   end Failure;

   procedure Phases is
   begin
      --  These are the states used by gc.lua's barrier regressions. Each
      --  request runs the real collector and reports its actual stop point.
      Check ("collectgarbage('incremental'); collectgarbage('stop'); " &
        "T.gcstate('propagate'); assert(T.gcstate()=='propagate'); " &
        "T.gcstate('enteratomic'); assert(T.gcstate()=='enteratomic'); " &
        "T.gcstate('sweepallgc'); assert(T.gcstate()=='sweepallgc'); " &
        "T.gcstate('pause'); assert(T.gcstate()=='pause')");
   end Phases;

   procedure Parameters is
   begin
      --  Exercise the production compressed percentage representation over
      --  the pinned gengc.lua input grid, with its integer rounding bound.
      Check ("for _,p in ipairs{5,10,12,20,50,100,200,500} do " &
        "local code=T.codeparam(p); " &
        "for _,v in ipairs{1,2,10,100,257,1023,6500,100000} do " &
        "local exact=v*p//100; " &
        "assert(math.abs(T.applyparam(code,v)-exact)<=exact/10+1) end end");
   end Parameters;

   procedure Independent_Ceiling is
      Memory : Lua.Storage.Owner;
      Block : System.Address;
      Refused : Boolean := False;
   begin
      --  Clearing the test limit must not lift the independent host ceiling.
      Lua.Storage.Set_Ceiling (Memory, 64);
      Lua.Storage.Set_Test_Ceiling (Memory, 32);
      Lua.Storage.Set_Test_Ceiling (Memory, 0);
      begin
         Block := Lua.Storage.Allocate (Memory, 128);
         Lua.Storage.Release (Memory, Block);
      exception
         when Lua.Storage.Allocation_Error => Refused := True;
      end;
      Assert (Refused, "test reset preserved the host ceiling");
      Assert (Lua.Storage.Statistics (Memory).Live_Blocks = 0,
              "ceiling refusal did not retain storage");
   end Independent_Ceiling;

   procedure Frame_Reset is
   begin
      --  Build a real cache with non-tail calls. Reset releases its storage
      --  while the current Lua and C activations remain executable.
      Check ("collectgarbage('stop'); " &
        "local function f(n) if n==0 then return 1 end " &
        "return 1+f(n-1) end; assert(f(20)==21); " &
        "local before=T.totalmem(); T.resetCI(); " &
        "assert(T.totalmem()<before); assert(f(20)==21)");
   end Frame_Reset;

   procedure Stack_Resize is
   begin
      --  Reallocation must preserve the parent's live scalar and open cell.
      --  Grow first, then require real bytes to decrease on exact shrink.
      Check ("collectgarbage('stop'); local x=17; " &
        "local function captured() return x end; " &
        "T.reallocstack(1000); local before=T.totalmem(); " &
        "T.reallocstack(0); assert(T.totalmem()<before); " &
        "x=29; assert(captured()==29)");
   end Stack_Resize;

   procedure Collector_Lists is
      State : World;
      Done : Boolean;
   begin
      --  Validate independently of collection: every intermediate phase and
      --  both modes must maintain coherent intrusive ownership lists.
      Initialize (State, (others => <>));
      begin
         Assert (Execute (State, "a={{},{},{}}", "lists"), "setup");
         for Step in 1 .. 500 loop
            Advance_Collection (State, 1, Done);
            Conformance_Adapter.Verify_Collector_Lists (State);
         end loop;
         Assert (Execute (State,
           "collectgarbage('generational'); collectgarbage(); " &
           "a[1]={}; collectgarbage('step')", "lists"), "generation");
         Conformance_Adapter.Verify_Collector_Lists (State);
      exception
         when others => Finalize (State); raise;
      end;
      Finalize (State);
   end Collector_Lists;

   procedure Corrupt_Registry is
      State : World;
      Item : Object_Access;
      Slot : Natural;
      Rejected : Boolean := False;
   begin
      --  A negative inspector test must fail on the actual owning registry,
      --  not merely on an invented diagnostic fixture. Restore before free.
      Initialize (State, (others => <>));
      Item := Global_Environment (State).Reference;
      Slot := Item.Registry_Slot;
      Item.Registry_Slot := 0;
      begin
         Conformance_Adapter.Verify_Collector_Lists (State);
      exception
         when Program_Error => Rejected := True;
      end;
      Item.Registry_Slot := Slot;
      Finalize (State);
      Assert (Rejected, "registry corruption was detected");
   end Corrupt_Registry;

   procedure Refused_Weak_Set is
   begin
      --  events.lua's weak delegation regression: allocation recovery may
      --  clear __newindex before dispatch, while the receiver stays rooted.
      Check ("local mt=setmetatable({__newindex={}}, {__mode='v'}); " &
        "local t=setmetatable({},mt); T.allocfailnext(); " &
        "for i=1,10 do t[i]=1 end; assert(t[10]==1)");
   end Refused_Weak_Set;

   procedure Stored_Warning is
   begin
      --  The actual C warning callback joins fragments, stores while off,
      --  and resets only after a complete message. Lua consumes each value.
      Check ("T._installwarning(); warn('@store'); warn('@off'); " &
        "warn('first',' second'); assert(_WARN=='first second'); " &
        "_WARN=false; warn('next'); assert(_WARN=='next'); _WARN=false; " &
        "warn('@normal'); warn('@off'); warn('ignored'); assert(not _WARN)");
   end Stored_Warning;

   procedure Invalid_Count_Type is
   begin
      --  Unsupported names must not fabricate a zero count that could make
      --  an upstream assertion pass without measuring the requested kind.
      Check ("assert(not pcall(T.totalmem,'invented')); " &
        "assert(T.totalmem('userdata')>=3); " &
        "assert(T.totalmem('string')>0)");
   end Invalid_Count_Type;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "adapter: real C userdata export",
                        Userdata'Access);
      Test_Support.Add (Suite, "adapter: actual collector color",
                        Color'Access);
      Test_Support.Add (Suite, "adapter: actual generational age", Age'Access);
      Test_Support.Add (Suite, "adapter: real object and byte counts",
                        Counts'Access);
      Test_Support.Add (Suite, "storage: one-shot refusal permits retry",
                        Failure'Access);
      Test_Support.Add (Suite, "adapter: real incremental phase control",
                        Phases'Access);
      Test_Support.Add (Suite, "adapter: production parameter codec",
                        Parameters'Access);
      Test_Support.Add (Suite, "storage: independent test and host ceilings",
                        Independent_Ceiling'Access);
      Test_Support.Add (Suite, "adapter: physical unused frame reset",
                        Frame_Reset'Access);
      Test_Support.Add (Suite, "adapter: physical stack resize preserves cell",
                        Stack_Resize'Access);
      Test_Support.Add (Suite, "adapter: collector list invariants",
                        Collector_Lists'Access);
      Test_Support.Add (Suite, "adapter: rejects corrupt registry",
                        Corrupt_Registry'Access);
      Test_Support.Add (Suite, "adapter: refused weak delegation recovers",
                        Refused_Weak_Set'Access);
      Test_Support.Add (Suite, "adapter: fragmented warning storage",
                        Stored_Warning'Access);
      Test_Support.Add (Suite, "adapter: rejects unknown object count kind",
                        Invalid_Count_Type'Access);
   end Register;
end Lua.Conformance_Adapter_Tests;
