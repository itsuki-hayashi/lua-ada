with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Conformance_Adapter;
with Lua.Conformance_Memory;
with Lua.Engine; use Lua.Engine;
with Lua.Storage;
with System;
with Test_Support;

package body Lua.Conformance_Adapter_Tests is
   use type Lua.Storage.Byte_Count;
   procedure Check (Source : String; Platform : Boolean := False);
   procedure Check (Source : String; Platform : Boolean := False) is
      State : World;
   begin
      Initialize (State, (others => <>));
      begin
         Conformance_Adapter.Install (State);
         if Platform then Conformance_Adapter.Install_Platform (State); end if;
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
   procedure Atomic_Transient_Root;
   procedure Atomic_Retained_Root;
   procedure Atomic_Orphan_Cell;
   procedure Sweep_Back_Barrier;
   procedure Memory_Inspection;
   procedure Corrupt_Heap_Edge;
   procedure Refusal_Reset;
   procedure Iterator_Call_Refusal;
   procedure Finalizer_Frame_Refusal;
   procedure Finalizer_Stack_Refusal;
   procedure Measured_Emergency_Headroom;
   procedure Weak_String_Payloads;
   procedure Native_Flush_Failure;
   procedure Darwin_Flush_Failure;
   procedure Native_Flush_Validation;
   procedure Native_Write_Refusal;
   procedure Native_Partial_Write;
   procedure Native_Pipe_Validation;

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

   procedure Atomic_Transient_Root is
   begin
      --  A temporary native argument at enteratomic is gone before the root
      --  rescan. Inspection must not accidentally strengthen a weak edge.
      Check ("collectgarbage('incremental'); collectgarbage('stop'); " &
        "local w=setmetatable({{}},{__mode='v'}); " &
        "T.gcstate('enteratomic'); assert(type(w[1])=='table'); " &
        "T.gcstate('pause'); assert(w[1]==nil)");
   end Atomic_Transient_Root;

   procedure Atomic_Retained_Root is
   begin
      --  The same publication retained in a live register must survive the
      --  atomic rescan. This protects against simply omitting root tracing.
      Check ("collectgarbage('incremental'); collectgarbage('stop'); " &
        "local w=setmetatable({{}},{__mode='v'}); " &
        "T.gcstate('enteratomic'); local keep=w[1]; " &
        "T.gcstate('pause'); assert(w[1]==keep and type(keep)=='table')");
   end Atomic_Retained_Root;

   procedure Atomic_Orphan_Cell is
   begin
      --  Ada's independently owned cell uses a forward barrier, so the new
      --  value is gray (C's open upvalue leaves it white). The important
      --  ordering remains: collect the weak coroutine in this same cycle,
      --  then read its last assigned value through the surviving closure.
      Check ("collectgarbage('incremental'); local function foo() " &
        "local a={x=20}; coroutine.yield(function() return a.x end); " &
        "assert(a.x==20); a={x=30}; assert(T.gccolor(a)=='gray'); " &
        "coroutine.yield(100) end; " &
        "local t=setmetatable({}, {__mode='kv'}); " &
        "collectgarbage(); collectgarbage('stop'); " &
        "t.co=coroutine.wrap(foo); local f=t.co(); " &
        "T.gcstate('enteratomic'); assert(t.co()==100); " &
        "assert(T.gccolor(t.co)=='white'); T.gcstate('pause'); " &
        "assert(t.co==nil and f()==30)");
   end Atomic_Orphan_Cell;

   procedure Sweep_Back_Barrier is
   begin
      --  Pinned gc.lua distinguishes a userdata backward barrier from the
      --  forward barrier's sweep-time whitening. Check immediate gray and
      --  complete two cycles to expose stale intrusive links after sweep.
      Check ("collectgarbage('incremental'); " &
        "local u=T.newuserdata(0,1); collectgarbage('stop'); " &
        "T.gcstate('sweepallgc'); local x={}; " &
        "assert(T.gccolor(u)=='black' and T.gccolor(x)=='white'); " &
        "debug.setuservalue(u,x); assert(T.gccolor(u)=='gray'); " &
        "T.gcstate('pause'); collectgarbage(); collectgarbage(); " &
        "assert(debug.getuservalue(u)==x)");
   end Sweep_Back_Barrier;

   procedure Memory_Inspection is
   begin
      --  Inspect every named incremental phase with real Lua/C activations,
      --  uservalues and finalizer enrollment present. Inspection changes no
      --  collector state and must keep working after generational promotion.
      Check ("collectgarbage('incremental'); collectgarbage('stop'); " &
        "local u=T.newuserdata(0,1); debug.setuservalue(u,{}); " &
        "debug.setmetatable(u,{__gc=function() end}); " &
        "for _,s in ipairs{'propagate','enteratomic','sweepallgc','pause'} " &
        "do T.gcstate(s); T.checkmemory(); assert(T.gcstate()==s) end; " &
        "collectgarbage('generational'); collectgarbage(); T.checkmemory()");
   end Memory_Inspection;

   procedure Corrupt_Heap_Edge is
      State, Other : World;
      Cell : Object_Access;
      Rejected : Boolean := False;
   begin
      --  A pointer from another valid universe is still a dangling edge for
      --  this registry. Reject it without dereferencing foreign ownership.
      Initialize (State, (others => <>));
      Initialize (Other, (others => <>));
      Cell := New_Cell (State, Nil_Value);
      Cell.Cell_Value := Global_Environment (Other);
      begin
         Conformance_Memory.Verify (State);
      exception
         when Program_Error => Rejected := True;
      end;
      Cell.Cell_Value := Nil_Value;
      Finalize (State);
      Finalize (Other);
      Assert (Rejected, "foreign heap edge was detected");
   end Corrupt_Heap_Edge;

   procedure Refusal_Reset is
   begin
      --  Retrieving an existing table field is not an allocating operation.
      --  The actual C callback can therefore restore a persistent refusal;
      --  the test does not clear it through a privileged Ada escape hatch.
      Check ("T.alloccount(0); T.alloccount(); local t={}; " &
        "assert(type(t)=='table')");
   end Refusal_Reset;

   procedure Iterator_Call_Refusal is
   begin
      --  The initial Lua iterator installs persistent allocation refusal
      --  before attempting the real C userdata operation. Refused growth on
      --  that rooted call path must unwind protection with a memory error;
      --  a later loop executes after Lua restores its allocator normally.
      Check ("local calls=0;local function iter()calls=calls+1;" &
        "T.alloccount(0);return T.newuserdata(128)end;" &
        "local ok,msg=pcall(function()for u in iter do " &
        "error('body')end end);" &
        "T.alloccount();assert(not ok and msg=='not enough memory' " &
        "and calls==1);local sum=0;for _,v in ipairs{1,2,3}do " &
        "sum=sum+v end;assert(sum==6)");
   end Iterator_Call_Refusal;

   procedure Finalizer_Frame_Refusal is
   begin
      --  Remove actual unused frames, forbid all growth, and require the
      --  library call to return without running its pending finalizer. The
      --  same object must finalize after Lua restores allocation normally.
      Check ("local done=false; local obj=setmetatable({}, " &
        "{__gc=function() done=true end}); " &
        "local function loop(n) if n>0 then loop(n-1) end end; loop(20); " &
        "T.resetCI(); T.alloccount(0); obj=nil; collectgarbage(); " &
        "T.alloccount(); assert(not done); collectgarbage(); assert(done)");
   end Finalizer_Frame_Refusal;

   procedure Finalizer_Stack_Refusal is
   begin
      --  Keep cached frames but physically remove excess scalar stack rows.
      --  Failure to grow that arena must defer, not lose, finalizer work.
      Check ("local done=false; local obj=setmetatable({}, " &
        "{__gc=function() done=true end}); " &
        "local function loop(n) if n>0 then loop(n-1) end end; loop(5); " &
        "T.reallocstack(0); T.alloccount(0); obj=nil; collectgarbage(); " &
        "T.alloccount(); assert(not done); collectgarbage(); assert(done)");
   end Finalizer_Stack_Refusal;

   procedure Measured_Emergency_Headroom is
   begin
      --  The C test's 200 bytes cannot hold one Ada table. Use measured real
      --  storage and require both actual refusals and successful GC retries,
      --  preserving the original 200 allocations and bounded live memory.
      Check ("collectgarbage('incremental'); " &
        "local refused,cycles,bytes=T.ada_emergency_tables(200); " &
        "assert(refused>=199 and cycles>=199 and bytes>0); " &
        "T.checkmemory(); local t={}; assert(type(t)=='table')");
   end Measured_Emergency_Headroom;

   procedure Weak_String_Payloads is
   begin
      --  Repeat the upstream weak-string graph at a focused 64 KiB size.
      --  The complete equivalent runner uses its unchanged 4 MiB operands.
      --  Count actual live bytes before collection, then require both string
      --  payloads to disappear while the empty table remains inspectable.
      Check ("for pass=1,3 do collectgarbage(); collectgarbage(); " &
        "local a=setmetatable({}, {__mode='kv'}); " &
        "a[string.rep('a',2^16)]=25; a[string.rep('b',2^16)]={}; " &
        "a[{}]=14; local live=collectgarbage('count'); collectgarbage(); " &
        "local k,v=next(a); assert(k==string.rep('a',2^16) and v==25); " &
        "assert(next(a,k)==nil); assert(a[string.rep('b',2^16)]==nil); " &
        "a[k]=nil; k=nil; collectgarbage(); assert(next(a)==nil); " &
        "assert(a[string.rep('b',100)]==nil); " &
        "assert(collectgarbage('count')<=live-2^7) end");
   end Weak_String_Payloads;

   procedure Native_Flush_Failure is
   begin
      --  The Windows counterpart keeps the actual FILE pointer and closer,
      --  replacing only its descriptor with a broken pipe. Buffering succeeds;
      --  both file/global flush fail at the OS, then explicit close succeeds.
      Check ("local old=io.output(); local f=io.tmpfile(); " &
        "assert(_test_failing_stream(f)==f); io.output(f); " &
        "assert(f:write('abcd')==f); assert(not f:flush()); " &
        "assert(f:write('abcd')==f); assert(not io.flush()); " &
        "assert(f:close()); assert(io.type(f)=='closed file'); " &
        "io.output(old)", Platform => True);
   end Native_Flush_Failure;

   procedure Darwin_Flush_Failure is
   begin
      --  Darwin retains failed buffered bytes. Closing retries the native
      --  write and reports its error, but still releases the owned FILE.
      --  Observe that result rather than replacing the closer or suppressing
      --  the native failure to imitate another libc's buffer policy.
      Check ("local old=io.output(); local f=io.tmpfile(); " &
        "assert(_test_failing_stream(f)==f); io.output(f); " &
        "assert(f:write('abcd')==f,'first buffered write'); " &
        "assert(not f:flush(),'first native flush'); " &
        "assert(f:write('abcd')==f,'second buffered write'); " &
        "assert(not io.flush(),'second native flush'); " &
        "local ok,msg,err=f:close(); " &
        "assert(ok==nil and type(msg)=='string' and err>0, " &
        "'native close failure'); assert(io.type(f)=='closed file'); " &
        "io.output(old)", Platform => True);
   end Darwin_Flush_Failure;

   procedure Native_Flush_Validation is
   begin
      --  Reject nonfiles and closed files before touching native descriptors.
      --  The protected error must return through the existing C guard.
      Check ("assert(not pcall(_test_failing_stream, {})); " &
        "local f=io.tmpfile(); f:close(); " &
        "assert(not pcall(_test_failing_stream, f))", Platform => True);
   end Native_Flush_Validation;

   procedure Native_Write_Refusal is
   begin
      --  Unbuffered output must report the actual native refusal and zero
      --  transferred bytes, then release the real pipe endpoint on close.
      Check ("local f=_test_failing_stream(assert(io.tmpfile())); " &
        "assert(f:setvbuf('no')); local ok,msg,err,n=f:write('abcd'); " &
        "assert(ok==nil and type(msg)=='string' and err>0 and n==0); " &
        "assert(f:close())", Platform => True);
   end Native_Write_Refusal;

   procedure Native_Partial_Write is
   begin
      --  Windows rejects a single oversized pipe write without progress.
      --  Preserve the multiargument write invariant: earlier bytes really
      --  reach the reader and are counted when a later argument is refused.
      Check ("local w,r=io.tmpfile(),io.tmpfile(); " &
        "local a,b=_test_nonblocking_pair(w,r); assert(a==w and b==r); " &
        "assert(w:setvbuf('no')); assert(r:setvbuf('no')); " &
        "assert(w:write(string.rep('a',100))); " &
        "local ok,msg,err,n=w:write(string.rep('b',10000), " &
        "string.rep('c',2^17)); " &
        "assert(ok==nil and type(msg)=='string' and err>0 and n==10000); " &
        "assert(r:read(10100)==string.rep('a',100)..string.rep('b',10000)); " &
        "assert(w:close()); assert(r:read(1)==nil); assert(r:close())",
        Platform => True);
   end Native_Partial_Write;

   procedure Native_Pipe_Validation is
   begin
      --  No descriptor is replaced when either input is invalid or the two
      --  endpoints alias. The surviving file remains usable afterward.
      Check ("local f=io.tmpfile(); " &
        "assert(not pcall(_test_nonblocking_pair,f,f)); " &
        "assert(not pcall(_test_nonblocking_pair,f,{})); " &
        "assert(f:write('ok')); assert(f:seek('set')==0); " &
        "assert(f:read('a')=='ok'); assert(f:close())", Platform => True);
   end Native_Pipe_Validation;

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
      Test_Support.Add (Suite, "collector: atomic transient root expires",
                        Atomic_Transient_Root'Access);
      Test_Support.Add (Suite, "collector: atomic live register survives",
                        Atomic_Retained_Root'Access);
      Test_Support.Add (Suite, "collector: orphan cell survives atomic sweep",
                        Atomic_Orphan_Cell'Access);
      Test_Support.Add (Suite, "collector: sweep userdata backward barrier",
                        Sweep_Back_Barrier'Access);
      Test_Support.Add (Suite, "adapter: real heap inspection across phases",
                        Memory_Inspection'Access);
      Test_Support.Add (Suite, "adapter: rejects foreign heap edge",
                        Corrupt_Heap_Edge'Access);
      Test_Support.Add (Suite, "allocator: Lua restores persistent refusal",
                        Refusal_Reset'Access);
      Test_Support.Add (Suite, "allocator: iterator call refusal recovers",
                        Iterator_Call_Refusal'Access);
      Test_Support.Add (Suite, "finalizer: Lua frame refusal and later retry",
                        Finalizer_Frame_Refusal'Access);
      Test_Support.Add (Suite, "finalizer: Lua stack refusal and later retry",
                        Finalizer_Stack_Refusal'Access);
      Test_Support.Add (Suite, "collector: measured emergency table headroom",
                        Measured_Emergency_Headroom'Access);
      Test_Support.Add (Suite, "collector: weak string payload reclamation",
                        Weak_String_Payloads'Access);
      if Conformance_Adapter.Has_Failing_Stream then
         if Conformance_Adapter.Has_Nonblocking_Pair then
            Test_Support.Add
              (Suite, "Windows IO: buffered native flush failure",
               Native_Flush_Failure'Access);
         else
            Test_Support.Add (Suite, "macOS IO: buffered failure and close",
                              Darwin_Flush_Failure'Access);
         end if;
         Test_Support.Add (Suite, "native IO: failure driver validates files",
                           Native_Flush_Validation'Access);
         Test_Support.Add
           (Suite, "native IO: refused write counts zero bytes",
            Native_Write_Refusal'Access);
      end if;
      if Conformance_Adapter.Has_Nonblocking_Pair then
         Test_Support.Add
           (Suite, "Windows IO: nonblocking partial write count",
            Native_Partial_Write'Access);
         Test_Support.Add
           (Suite, "Windows IO: pipe driver validates endpoints",
            Native_Pipe_Validation'Access);
      end if;
   end Register;
end Lua.Conformance_Adapter_Tests;
