with Ada.Characters.Latin_1;
with Ada.Strings.Fixed;
with Ada.Unchecked_Deallocation;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Canonical_Compiler;
with Lua.Engine; use Lua.Engine;
with Lua.Engine.Canonical;
with Lua.Engine.Machine;
with Lua.Engine.Stacks;
with Lua.Opcodes;
with Lua.Prototypes;
with Lua.Storage;
with Lua.Syntax;
with Lua.Syntax_Trees;
with Test_Support;

package body Lua.Canonical_Runtime_Tests is
   use type Integer_Value;
   use type Lua.Canonical_Compiler.Status;
   use type Lua.Syntax.Check_Status;
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

   function Compile_Source
     (State : World_Access; Source : String;
      Name : String := "=canonical-runtime") return Value;
   function Run_Source
     (State : World_Access; Source : String;
      Name : String := "=canonical-runtime") return Values.Vector;
   procedure Drain (Driver : in out VM.Driver);

   function Compile_Source
     (State : World_Access; Source : String;
      Name : String := "=canonical-runtime") return Value
   is
      Unit : Lua.Syntax_Trees.Compilation_Unit;
   begin
      --  Parsing owns no runtime objects. The subsequent compiler allocates
      --  its complete graph through the same managed owner as this session;
      --  adoption moves that graph instead of inventing private instructions.
      Lua.Syntax_Trees.Parse (Unit, Source, Name, (others => <>));
      Assert (Unit.Result.Status = Lua.Syntax.Success,
              "invalid runtime fixture: " &
              Lua.Syntax_Trees.Text (Unit, Unit.Result.Error.Message));
      declare
         Lowered : Lua.Canonical_Compiler.Compilation_Result :=
           Lua.Canonical_Compiler.Compile
             (Unit, Lua.Storage.Reference (State.Memory), Name);
         Callee : Value;
      begin
         Assert (Lowered.Outcome = Lua.Canonical_Compiler.Succeeded,
                 "runtime fixture did not lower");
         Begin_Operation (State.all);
         begin
            Callee := Canonical.Adopt
              (State.all, Lowered.Code, (Table_Kind, State.Globals));
         exception
            when others => End_Operation (State.all); raise;
         end;
         End_Operation (State.all);
         return Callee;
      end;
   end Compile_Source;

   procedure Drain (Driver : in out VM.Driver) is
   begin
      --  This guard detects a broken scheduler termination condition. Actual
      --  Lua work still uses the session's ordinary instruction accounting.
      for Iteration in 1 .. 100_000 loop
         exit when VM.Is_Complete (Driver);
         VM.Step (Driver);
      end loop;
      Assert (VM.Is_Complete (Driver), "canonical drive did not terminate");
   end Drain;

   function Run_Source
     (State : World_Access; Source : String;
      Name : String := "=canonical-runtime") return Values.Vector
   is
      Callee : constant Value := Compile_Source (State, Source, Name);
      Driver : VM.Driver;
      Packet : Values.Vector;
   begin
      VM.Start (Driver, State, Callee, Values.Empty_Vector);
      begin
         Drain (Driver);
         Packet := VM.Results (Driver);
         --  Publish host-visible values before Finish drops the transfer
         --  root. Replacing only Foreign_Stack would break its paired cell
         --  arena; physical storage and logical C top are separate now.
         Lua.Engine.Stacks.Reserve
           (State.all, State.Current, Natural (Packet.Length));
         Lua.Engine.Stacks.Trim (State.Current, 0);
         for Index in Packet.First_Index .. Packet.Last_Index loop
            Lua.Engine.Stacks.Write
              (State.all, State.Current, Index, Packet (Index));
         end loop;
         State.Current.Foreign_Top := Natural (Packet.Length);
         State.Current.Host_Stack_Top := State.Current.Foreign_Top;
         VM.Finish (Driver);
      exception
         when Language_Error => VM.Finish (Driver); raise;
      end;
      return Packet;
   end Run_Source;

   procedure Debug_Upvalue_Names (State : World_Access);
   procedure Debug_Local_Mutation (State : World_Access);
   procedure Debug_Parameter_Names (State : World_Access);
   procedure Debug_Source_Metadata (State : World_Access);
   procedure Debug_Current_Line (State : World_Access);
   procedure Debug_Traceback_Source (State : World_Access);
   procedure Debug_Named_Vararg_Local (State : World_Access);
   procedure Fixed_Vararg_Prefix (State : World_Access);
   procedure Primitive_Arithmetic (State : World_Access);
   procedure Parallel_Assignment (State : World_Access);
   procedure Numeric_Loops (State : World_Access);
   procedure Generic_Loops (State : World_Access);
   procedure Multiple_Results (State : World_Access);
   procedure Native_Callback (State : World_Access);
   procedure Tail_Recursion (State : World_Access);
   procedure Captured_Mutation (State : World_Access);
   procedure Collection_Of_Open_Cells (State : World_Access);
   procedure Goto_Fresh_Bindings (State : World_Access);
   procedure Named_Varargs (State : World_Access);
   procedure Arithmetic_Metamethod (State : World_Access);
   procedure Index_Metamethods (State : World_Access);
   procedure Protected_Error (State : World_Access);
   procedure Error_Source_Line (State : World_Access);
   procedure Coroutine_Results (State : World_Access);
   procedure Coroutine_Close (State : World_Access);
   procedure Scope_Close (State : World_Access);
   procedure Close_Error (State : World_Access);
   procedure Malformed_Opcode_Recovery (State : World_Access);
   procedure Callback_Collection (State : World_Access);
   procedure Concatenation_Order (State : World_Access);
   procedure Returned_Closure_Collection (State : World_Access);
   procedure Inactive_Close_Mutation (State : World_Access);
   procedure Dead_Temporary_Collection (State : World_Access);

   procedure Primitive_Arithmetic (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "return nil,true,3+4*5,7/2,(-7)//3,(-7)%3,5<<2,~0");
   begin
      --  Mixed scalar kinds must stay distinct, with integer floor/modulo
      --  and bitwise operations using Lua's signed 64-bit semantics.
      Assert (Natural (Packet.Length) = 8 and then
                Packet (1).Kind = Nil_Kind and then
                Packet (2) = Value'(Boolean_Kind, True) and then
                Packet (3) = Value'(Integer_Kind, 23) and then
                Packet (4) = Value'(Real_Kind, 3.5) and then
                Packet (5) = Value'(Integer_Kind, -3) and then
                Packet (6) = Value'(Integer_Kind, 2) and then
                Packet (7) = Value'(Integer_Kind, 20) and then
                Packet (8) = Value'(Integer_Kind, -1), "primitive results");
   end Primitive_Arithmetic;

   procedure Parallel_Assignment (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local i=1;local t={10,20};i,t[i]=2,99;" &
         "return i,t[1],t[2]");
   begin
      --  Assignment targets are evaluated before any destination is changed;
      --  the saved old index must survive scalar register reuse.
      Assert (Packet (1) = Value'(Integer_Kind, 2) and then
                Packet (2) = Value'(Integer_Kind, 99) and then
                Packet (3) = Value'(Integer_Kind, 20), "parallel targets");
   end Parallel_Assignment;

   procedure Numeric_Loops (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local a,b=0,0;for i=5,1,-2 do a=a+i end;" &
         "for x=0.5,1.5,0.5 do b=b+x end;return a,b");
   begin
      --  FORPREP/FORLOOP use different integer and floating control layouts.
      --  Check both progressions rather than only a final loop variable.
      Assert (Packet (1) = Value'(Integer_Kind, 9) and then
                Packet (2) = Value'(Real_Kind, 3.0), "numeric loop layout");
   end Numeric_Loops;

   procedure Generic_Loops (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local n=0;for i,v in ipairs({4,5,6}) do n=n+i*v end;" &
         "return n");
   begin
      --  TFORCALL invokes an ordinary native iterator and resumes into the
      --  canonical control/result slots before TFORLOOP tests the new key.
      Assert (Packet.First_Element = Value'(Integer_Kind, 32),
              "generic iterator result adjustment");
   end Generic_Loops;

   procedure Multiple_Results (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local function f()return 1,2,3 end;" &
         "local function g(...)return select('#',...),... end;" &
         "return g(0,f())");
   begin
      --  An open CALL result extends the next argument list and an open
      --  RETURN preserves its complete packet, including the leading count.
      Assert (Natural (Packet.Length) = 5 and then
                Packet (1) = Value'(Integer_Kind, 4) and then
                Packet (2) = Value'(Integer_Kind, 0) and then
                Packet (5) = Value'(Integer_Kind, 3), "open call/return");
   end Multiple_Results;

   procedure Native_Callback (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "return string.gsub('a1b2','%d',function(x)" &
         "return tostring(tonumber(x)*2) end)");
   begin
      --  A library continuation calls canonical Lua, which calls more native
      --  functions. All three return boundaries must use the same scheduler.
      Assert (Image (Packet (1)) = "a2b4" and then
                Packet (2) = Value'(Integer_Kind, 2), "nested callbacks");
   end Native_Callback;

   procedure Tail_Recursion (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local function f(n,x)if n==0 then return x end;" &
         "return f(n-1,x+n) end;return f(400,0)");
   begin
      --  Real TAILCALL replaces the frame instead of growing an Ada stack or
      --  leaving a canonical pending-result owner behind the replacement.
      Assert (Packet.First_Element = Value'(Integer_Kind, 80_200),
              "tail frame replacement");
   end Tail_Recursion;

   procedure Captured_Mutation (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local function counter()local n=0;" &
         "return function()n=n+1;return n end end;" &
         "local f=counter();return f(),f(),f()");
   begin
      --  Returning from the creator closes its register association, while
      --  the closure retains one actual cell for every later mutation.
      Assert (Packet (1) = Value'(Integer_Kind, 1) and then
                Packet (2) = Value'(Integer_Kind, 2) and then
                Packet (3) = Value'(Integer_Kind, 3), "closed shared cell");
   end Captured_Mutation;

   procedure Collection_Of_Open_Cells (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local x={n=7};local function f()x.n=x.n+1;return x.n end;" &
         "collectgarbage();local a=f();collectgarbage();return a,f()");
   begin
      --  Collection while the creator is active must trace scalar registers,
      --  the captured cell and the canonical graph/constants together.
      Assert (Packet (1) = Value'(Integer_Kind, 8) and then
                Packet (2) = Value'(Integer_Kind, 9), "open-cell GC roots");
   end Collection_Of_Open_Cells;

   procedure Goto_Fresh_Bindings (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local f={};local i=0;::again::local x=i;" &
         "f[i+1]=function()return x end;i=i+1;" &
         "if i<3 then goto again end;return f[1](),f[2](),f[3]()");
   begin
      --  The backward jump closes the previous local instance. Reusing its
      --  register must allocate a new cell rather than change old captures.
      Assert (Packet (1) = Value'(Integer_Kind, 0) and then
                Packet (2) = Value'(Integer_Kind, 1) and then
                Packet (3) = Value'(Integer_Kind, 2), "fresh goto bindings");
   end Goto_Fresh_Bindings;

   procedure Named_Varargs (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local function f(a,...v)v[1]=9;v.n=2;return a,... end;" &
         "return f(1,2,3,4)");
   begin
      --  Named varargs expose live table storage. VARARG must read the mutated
      --  n/entries instead of replaying the original hidden argument packet.
      Assert (Natural (Packet.Length) = 3 and then
                Packet (1) = Value'(Integer_Kind, 1) and then
                Packet (2) = Value'(Integer_Kind, 9) and then
                Packet (3) = Value'(Integer_Kind, 3), "named vararg table");
   end Named_Varargs;

   procedure Arithmetic_Metamethod (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local t=setmetatable({v=10},{__add=function(a,b)" &
         "return a.v+b end,__unm=function(a,b)return a.v+b.v end});" &
         "return t+7,-t");
   begin
      --  An arithmetic word unable to use its primitive path must execute the
      --  real MMBIN companion; unary dispatch duplicates the operand.
      Assert (Packet (1) = Value'(Integer_Kind, 17) and then
                Packet (2) = Value'(Integer_Kind, 20), "arithmetic handlers");
   end Arithmetic_Metamethod;

   procedure Index_Metamethods (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local backing={};local t=setmetatable({}," &
         "{__index=function(_,k)return backing[k] end," &
         "__newindex=function(_,k,v)backing[k]=v*2 end});" &
         "t.answer=21;return t.answer,rawget(t,'answer')");
   begin
      --  GET/SET helpers may call Lua and then resume the original scalar
      --  destination, while raw operations must still bypass the handlers.
      Assert (Packet (1) = Value'(Integer_Kind, 42) and then
                Packet (2).Kind = Nil_Kind, "index/newindex continuations");
   end Index_Metamethods;

   procedure Protected_Error (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local marker={code=17};local ok,e=pcall(function()" &
         "error(marker) end);return ok,e==marker,e.code");
   begin
      --  A protected boundary returns false plus the real error object; the
      --  scheduler must not stringify or discard canonical closure state.
      Assert (Packet (1) = Value'(Boolean_Kind, False) and then
                Packet (2) = Value'(Boolean_Kind, True) and then
                Packet (3) = Value'(Integer_Kind, 17), "protected failure");
   end Protected_Error;

   procedure Error_Source_Line (State : World_Access) is
      LF : constant Character := Ada.Characters.Latin_1.LF;
      Packet : constant Values.Vector := Run_Source
        (State, "local ok,e=pcall(function()" & LF &
         "error('canonical failure')" & LF & "end);return ok,e",
         "=canonical-lines");
   begin
      --  Error() uses the current canonical PC's real delta-decoded source
      --  line, even though no private instruction/location vector exists.
      Assert (Packet (1) = Value'(Boolean_Kind, False) and then
                Ada.Strings.Fixed.Index
                  (Image (Packet (2)), ":2:") /= 0,
              "canonical failure lost its source line");
   end Error_Source_Line;

   procedure Coroutine_Results (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local co=coroutine.create(function(a)" &
         "local b,c=coroutine.yield(a,a+1);return b+c end);" &
         "local ok,a,b=coroutine.resume(co,10);" &
         "local done,sum=coroutine.resume(co,20,30);" &
         "return ok,a,b,done,sum,coroutine.status(co)");
   begin
      --  Suspended canonical CALL destinations must receive resumed values
      --  with normal adjustment; final results travel through the same drive.
      Assert (Packet (1) = Value'(Boolean_Kind, True) and then
                Packet (2) = Value'(Integer_Kind, 10) and then
                Packet (3) = Value'(Integer_Kind, 11) and then
                Packet (4) = Value'(Boolean_Kind, True) and then
                Packet (5) = Value'(Integer_Kind, 50) and then
                Image (Packet (6)) = "dead", "coroutine transfers");
   end Coroutine_Results;

   procedure Coroutine_Close (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local log='';local co=coroutine.create(function()" &
         "local x <close> = setmetatable({}, {__close=function()" &
         "log=log..'closed' end});coroutine.yield('paused') end);" &
         "local ok,word=coroutine.resume(co);" &
         "return ok,word,coroutine.close(co),log");
   begin
      --  Explicitly closing a suspended context must visit its live canonical
      --  TBC slot through ordinary close continuations without resuming code.
      Assert (Packet (1) = Value'(Boolean_Kind, True) and then
                Image (Packet (2)) = "paused" and then
                Packet (3) = Value'(Boolean_Kind, True) and then
                Image (Packet (4)) = "closed", "suspended close ownership");
   end Coroutine_Close;

   procedure Scope_Close (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local log='';local function object(x)" &
         "return setmetatable({}, {__close=function()log=log..x end}) end;" &
         "do local a <close> = object('a');" &
         "do local b <close> = object('b') end;log=log..'x' end;return log");
   begin
      --  CLOSE uses a register threshold, not a private environment depth.
      --  Closing the inner range must leave the outer TBC slot live.
      Assert (Image (Packet.First_Element) = "bxa", "nested close ranges");
   end Scope_Close;

   procedure Close_Error (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local log='';local ok,e=pcall(function()" &
         "local a <close> = setmetatable({}, {__close=function(_,e)" &
         "log=log..e end});local b <close> = setmetatable({}," &
         "{__close=function()error('replacement',0) end});" &
         "error('original',0) end);return ok,e,log");
   begin
      --  A close error replaces the original arbitrary error packet and is
      --  passed to remaining closers before the outer pcall returns it.
      Assert (Packet (1) = Value'(Boolean_Kind, False) and then
                Image (Packet (2)) = "replacement" and then
                Image (Packet (3)) = "replacement", "close error replacement");
   end Close_Error;

   procedure Malformed_Opcode_Recovery (State : World_Access) is
      Unit : Lua.Syntax_Trees.Compilation_Unit;
      Rejected : Boolean := False;
   begin
      --  Mutate one instruction to an unused seven-bit opcode. This models a
      --  hostile imported graph, not source grammar; it must produce a Lua
      --  failure before enum conversion and leave the session recoverable.
      Lua.Syntax_Trees.Parse
        (Unit, "return 1", "=invalid-word", (others => <>));
      declare
         Lowered : Lua.Canonical_Compiler.Compilation_Result :=
           Lua.Canonical_Compiler.Compile
             (Unit, Lua.Storage.Reference (State.Memory), "=invalid-word");
         Callee : Value;
         Driver : VM.Driver;
      begin
         Lua.Prototypes.Root (Lowered.Code).Code.Replace_Element
           (1, Lua.Opcodes.Word (127));
         Begin_Operation (State.all);
         Callee := Canonical.Adopt
           (State.all, Lowered.Code, (Table_Kind, State.Globals));
         End_Operation (State.all);
         VM.Start (Driver, State, Callee, Values.Empty_Vector);
         begin
            Drain (Driver);
         exception
            when Language_Error => Rejected := True;
         end;
         Assert (Rejected and then
                   State.Current.Failure_Class = Language_Failure,
                 "invalid opcode escaped as an Ada failure");
         VM.Finish (Driver);
      end;
      VM.Clear_Frames (State.all);
      Assert (Execute (State.all, "assert(6*7==42)", "word-recovery"),
              "invalid canonical word damaged later session execution");
   end Malformed_Opcode_Recovery;

   procedure Callback_Collection (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local suffix='!';return string.gsub('aa','a'," &
         "function(x)collectgarbage();return x..suffix end)");
   begin
      --  Native pending results, callback arguments and the canonical closure
      --  captures remain rooted while the callback explicitly collects.
      Assert (Image (Packet (1)) = "a!a!" and then
                Packet (2) = Value'(Integer_Kind, 2), "callback GC roots");
   end Callback_Collection;

   procedure Concatenation_Order (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local calls='';local function obj(x)" &
         "return setmetatable({x=x},{__concat=function(a,b)" &
         "calls=calls..a.x..b.x;return obj(a.x..b.x) end}) end;" &
         "local r=obj('a')..obj('b')..obj('c');return r.x,calls");
   begin
      --  CONCAT callbacks resume right to left. The intermediate object must
      --  be written back before requesting the next pair of actual registers.
      Assert (Image (Packet (1)) = "abc" and then
                Image (Packet (2)) = "bcabc", "concat continuation order");
   end Concatenation_Order;

   procedure Returned_Closure_Collection (State : World_Access) is
      Callee : Value;
      Driver : VM.Driver;
      Packet : Values.Vector;
      Before : constant Natural := Natural (State.Programs.Length);
   begin
      --  Only the returned closure roots this canonical bundle after its
      --  creator dies. Its captured table has no live frame/register owner;
      --  marking the closure's actual ordered upvalues must keep it alive.
      Packet := Run_Source
        (State, "local t={n=40};return function()t.n=t.n+1;return t.n end");
      Callee := Packet.First_Element;
      Collect (State.all);
      VM.Start (Driver, State, Callee, Values.Empty_Vector);
      Drain (Driver);
      Assert (VM.Results (Driver).First_Element = Value'(Integer_Kind, 41),
              "returned closure lost its canonical cell or graph");
      VM.Finish (Driver);
      State.Current.Foreign_Top := 0;
      State.Current.Host_Stack_Top := 0;
      Lua.Engine.Stacks.Trim (State.Current, 0);
      Packet.Clear;
      Collect (State.all);
      Assert (Natural (State.Programs.Length) = Before,
              "unreachable canonical bundle remained registered");
   end Returned_Closure_Collection;

   procedure Inactive_Close_Mutation (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local log='';do local x <close> = false;" &
         "local read=function()return x end;" &
         "debug.setupvalue(read,1,setmetatable({}," &
         "{__close=function()log='closed' end})) end;return log");
   begin
      --  A false initializer does not create a TBC obligation. Mutating its
      --  captured cell later must not enroll a declaration retroactively.
      Assert (Image (Packet.First_Element) = "", "inactive close enrolled");
   end Inactive_Close_Mutation;

   procedure Dead_Temporary_Collection (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local w=setmetatable({}, {__mode='v'});" &
         "do local x={};w[1]=x end;collectgarbage();return w[1]==nil");
   begin
      --  Registers above the active VM top may still contain stale bytes.
      --  Marking their old values would make a weakly held dead local live.
      Assert (Packet.First_Element = Value'(Boolean_Kind, True),
              "stale canonical temporary became a collector root");
   end Dead_Temporary_Collection;

   procedure Debug_Upvalue_Names (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local left,right=3,4;" &
         "local f=function()return left+right end;" &
         "local a,x=debug.getupvalue(f,1);local b,y=debug.getupvalue(f,2);" &
         "return a,x,b,y");
   begin
      --  Ordered descriptors name the actual cells. The legacy symbol map is
      --  empty for canonical prototypes and must not be indexed by this API.
      Assert (Image (Packet (1)) = "left" and then
                Packet (2) = Value'(Integer_Kind, 3) and then
                Image (Packet (3)) = "right" and then
                Packet (4) = Value'(Integer_Kind, 4),
              "canonical upvalue names");
   end Debug_Upvalue_Names;

   procedure Debug_Local_Mutation (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local function f(a,b)local x=a+b;" &
         "local name,value=debug.getlocal(1,3);debug.setlocal(1,3,40);" &
         "return name,value,x end;return f(2,3)");
   begin
      --  The caller's third active local occupies its third scalar slot.
      --  Mutating it must change execution, not a detached debug-only copy.
      Assert (Image (Packet (1)) = "x" and then
                Packet (2) = Value'(Integer_Kind, 5) and then
                Packet (3) = Value'(Integer_Kind, 40),
              "canonical local write");
   end Debug_Local_Mutation;

   procedure Debug_Parameter_Names (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local function f(first,second)return first+second end;" &
         "return debug.getlocal(f,1),debug.getlocal(f,2)," &
         "debug.getlocal(f,3)");
   begin
      --  A function-valued query inspects PC zero without starting a frame.
      --  Only parameters are live there; no nonexistent third name is made up.
      Assert (Image (Packet (1)) = "first" and then
                Image (Packet (2)) = "second" and then
                Packet (3).Kind = Nil_Kind, "canonical parameter names");
   end Debug_Parameter_Names;

   procedure Debug_Source_Metadata (State : World_Access) is
      LF : constant Character := Ada.Characters.Latin_1.LF;
      Packet : constant Values.Vector := Run_Source
        (State, "local f=function(first,second)" & LF &
         "return first+second" & LF & "end;local i=debug.getinfo(f,'SuL');" &
         "return i.source,i.short_src,i.linedefined,i.lastlinedefined," &
         "i.nparams,i.isvararg,i.what,i.activelines[2]", "=metadata-source");
   begin
      --  Source identity and line ranges come from the canonical model. Empty
      --  private instructions/parameter vectors must not fabricate metadata.
      Assert (Image (Packet (1)) = "=metadata-source" and then
                Image (Packet (2)) = "metadata-source" and then
                Packet (3) = Value'(Integer_Kind, 1) and then
                Packet (4) = Value'(Integer_Kind, 3) and then
                Packet (5) = Value'(Integer_Kind, 2) and then
                Packet (6) = Value'(Boolean_Kind, False) and then
                Image (Packet (7)) = "Lua" and then
                Packet (8) = Value'(Boolean_Kind, True),
              "canonical function metadata");
   end Debug_Source_Metadata;

   procedure Debug_Current_Line (State : World_Access) is
      LF : constant Character := Ada.Characters.Latin_1.LF;
      Packet : constant Values.Vector := Run_Source
        (State, "local function f()" & LF &
         "return debug.getinfo(1,'l').currentline" & LF & "end;return f()");
   begin
      --  A suspended caller reports the call instruction's saved zero-based
      --  PC, not the following instruction or an empty private code vector.
      Assert (Packet.First_Element = Value'(Integer_Kind, 2),
              "canonical current line");
   end Debug_Current_Line;

   procedure Debug_Traceback_Source (State : World_Access) is
      LF : constant Character := Ada.Characters.Latin_1.LF;
      Packet : constant Values.Vector := Run_Source
        (State, "local function f()" & LF &
         "local text=debug.traceback('message',0);return text" & LF &
         "end;return f()",
         "=traceback-source");
   begin
      --  The logical stack formats real source/line metadata and excludes
      --  scheduler phases. Traceback must work without private instructions.
      Assert (Ada.Strings.Fixed.Index (Image (Packet.First_Element),
                "traceback-source:2:") /= 0,
              "canonical traceback source");
   end Debug_Traceback_Source;

   procedure Debug_Named_Vararg_Local (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local function f(a,...v)" &
         "local name,value=debug.getlocal(1,2);" &
         "local i=debug.getinfo(1,'u');" &
         "return name,value.n,value[1],i.nparams,i.isvararg end;" &
         "return f(1,9)");
   begin
      --  Named varargs are a real final parameter table with live debug
      --  storage, while numparams still counts only the fixed parameters.
      Assert (Image (Packet (1)) = "v" and then
                Packet (2) = Value'(Integer_Kind, 1) and then
                Packet (3) = Value'(Integer_Kind, 9) and then
                Packet (4) = Value'(Integer_Kind, 1) and then
                Packet (5) = Value'(Boolean_Kind, True),
              "canonical named-vararg debug local");
   end Debug_Named_Vararg_Local;

   procedure Fixed_Vararg_Prefix (State : World_Access) is
      Packet : constant Values.Vector := Run_Source
        (State, "local function f(...v)v.n=1000001;local x=...;return x end;" &
         "return f(17)");
   begin
      --  A huge valid n does not require a huge allocation for a fixed one-
      --  result request. Only open VARARG expands the complete list.
      Assert (Packet.First_Element = Value'(Integer_Kind, 17),
              "fixed vararg request expanded its unused suffix");
   end Fixed_Vararg_Prefix;

   procedure Arithmetic_Case is new Fixture (Primitive_Arithmetic);
   procedure Assignment_Case is new Fixture (Parallel_Assignment);
   procedure Numeric_Case is new Fixture (Numeric_Loops);
   procedure Generic_Case is new Fixture (Generic_Loops);
   procedure Results_Case is new Fixture (Multiple_Results);
   procedure Callback_Case is new Fixture (Native_Callback);
   procedure Tail_Case is new Fixture (Tail_Recursion);
   procedure Capture_Case is new Fixture (Captured_Mutation);
   procedure Open_Cell_Case is new Fixture (Collection_Of_Open_Cells);
   procedure Goto_Case is new Fixture (Goto_Fresh_Bindings);
   procedure Vararg_Case is new Fixture (Named_Varargs);
   procedure Metamethod_Case is new Fixture (Arithmetic_Metamethod);
   procedure Index_Case is new Fixture (Index_Metamethods);
   procedure Protection_Case is new Fixture (Protected_Error);
   procedure Line_Case is new Fixture (Error_Source_Line);
   procedure Coroutine_Case is new Fixture (Coroutine_Results);
   procedure Coroutine_Close_Case is new Fixture (Coroutine_Close);
   procedure Scope_Case is new Fixture (Scope_Close);
   procedure Close_Error_Case is new Fixture (Close_Error);
   procedure Invalid_Case is new Fixture (Malformed_Opcode_Recovery);
   procedure GC_Case is new Fixture (Callback_Collection);
   procedure Concat_Case is new Fixture (Concatenation_Order);
   procedure Returned_Closure_Case is new Fixture
     (Returned_Closure_Collection);
   procedure Inactive_Close_Case is new Fixture (Inactive_Close_Mutation);
   procedure Dead_Temporary_Case is new Fixture (Dead_Temporary_Collection);

   procedure Debug_Upvalues_Case is new Fixture (Debug_Upvalue_Names);
   procedure Debug_Locals_Case is new Fixture (Debug_Local_Mutation);
   procedure Debug_Parameters_Case is new Fixture (Debug_Parameter_Names);
   procedure Debug_Source_Case is new Fixture (Debug_Source_Metadata);
   procedure Debug_Current_Line_Case is new Fixture
     (Debug_Current_Line);
   procedure Debug_Traceback_Case is new Fixture
     (Debug_Traceback_Source);
   procedure Debug_Varargs_Case is new Fixture (Debug_Named_Vararg_Local);
   procedure Fixed_Vararg_Case is new Fixture (Fixed_Vararg_Prefix);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "canonical runtime: debug upvalue names",
                        Debug_Upvalues_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: debug local mutation",
                        Debug_Locals_Case'Access);
      Test_Support.Add
        (Suite, "canonical runtime: debug parameter names",
                        Debug_Parameters_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: debug source metadata",
                        Debug_Source_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: debug current line",
                        Debug_Current_Line_Case'Access);
      Test_Support.Add
        (Suite, "canonical runtime: debug traceback source",
                        Debug_Traceback_Case'Access);
      Test_Support.Add
        (Suite, "canonical runtime: debug named vararg local",
                        Debug_Varargs_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: fixed vararg prefix",
                        Fixed_Vararg_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: primitive arithmetic",
                        Arithmetic_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: parallel assignment",
                        Assignment_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: numeric loops",
                        Numeric_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: generic loops",
                        Generic_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: multiple results",
                        Results_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: native callback nesting",
                        Callback_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: tail recursion",
                        Tail_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: captured mutation",
                        Capture_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: open cells survive GC",
                        Open_Cell_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: fresh goto bindings",
                        Goto_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: named varargs",
                        Vararg_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: arithmetic metamethods",
                        Metamethod_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: index continuations",
                        Index_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: protected error identity",
                        Protection_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: error source lines",
                        Line_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: coroutine transfers",
                        Coroutine_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: suspended close",
                        Coroutine_Close_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: scope close ranges",
                        Scope_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: close error replacement",
                        Close_Error_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: invalid word recovery",
                        Invalid_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: callback collection",
                        GC_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: concat order",
                        Concat_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: returned closure GC",
                        Returned_Closure_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: inactive close mutation",
                        Inactive_Close_Case'Access);
      Test_Support.Add (Suite, "canonical runtime: dead temporary GC",
                        Dead_Temporary_Case'Access);
   end Register;
end Lua.Canonical_Runtime_Tests;
