with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Lifecycle_Tests is
   LF : constant Character := Ada.Characters.Latin_1.LF;
   HT : constant Character := Ada.Characters.Latin_1.HT;

   type Capture_Sink is new Output_Sink with record
      Bytes : Unbounded_String;
   end record;
   overriding procedure Write (Sink : in out Capture_Sink; Bytes : String);
   type Broken_Sink is new Output_Sink with null record;
   overriding procedure Write (Sink : in out Broken_Sink; Bytes : String);

   procedure Assert_OK (Result : Execution_Result);
   procedure Assert_Output (Result : Execution_Result; Expected : String);
   procedure Assert_Error
     (Result : Execution_Result; Expected : Execution_Status);
   procedure Persistent_Globals;
   procedure Independent_Sessions;
   procedure Syntax_Error_Recovery;
   procedure Runtime_Error_Recovery;
   procedure Partial_Output;
   procedure Source_Location;
   procedure Runtime_Source_Location;
   procedure Deferred_Goto;
   procedure Deferred_Close;
   procedure Const_Assignment;
   procedure Named_Global_Restriction;
   procedure Duplicate_Global;
   procedure Instruction_Budget;
   procedure Token_Budget;
   procedure Source_Budget;
   procedure Register_Budget;
   procedure Call_Depth_Budget;
   procedure Tail_Call_Reuses_Frame;
   procedure String_Budget;
   procedure Output_Budget;
   procedure Table_Entry_Budget;
   procedure Heap_Object_Budget;
   procedure Frame_Setup_Failure_Recovery;
   procedure Collect_Table_Cycle;
   procedure Collect_Closure_Cycle;
   procedure Keep_Captured_Root;
   procedure Automatic_Collection;
   procedure Closed_Session;
   procedure Reset_Session;
   procedure Argument_Table_Indices;
   procedure Chunk_Arguments;
   procedure Output_Sink_Capture;
   procedure Output_Sink_Failure;
   procedure Pcall_Arithmetic_Error;
   procedure Pcall_Nonfunction;
   procedure Nil_Table_Key;
   procedure NaN_Table_Key;

   overriding procedure Write (Sink : in out Capture_Sink; Bytes : String) is
   begin
      Append (Sink.Bytes, Bytes);
   end Write;

   overriding procedure Write (Sink : in out Broken_Sink; Bytes : String) is
      pragma Unreferenced (Sink, Bytes);
   begin
      raise Constraint_Error with "deliberate host sink failure";
   end Write;

   procedure Assert_OK (Result : Execution_Result) is
   begin
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
   end Assert_OK;

   procedure Assert_Output (Result : Execution_Result; Expected : String) is
   begin
      Assert_OK (Result);
      Assert (Result.Output = Expected & LF, "unexpected captured output");
   end Assert_Output;

   procedure Assert_Error
     (Result : Execution_Result; Expected : Execution_Status)
   is
   begin
      Assert (Result.Status = Expected,
              "status: " & Result.Status'Image & ": " &
              To_String (Result.Error.Message));
      Assert (Length (Result.Error.Message) > 0, "nonempty diagnostic");
      Assert (Ada.Strings.Unbounded.Index
        (Result.Error.Message, "internal Ada check") = 0,
        "a host runtime check is not an expected Lua failure");
   end Assert_Error;

   procedure Persistent_Globals is
      --  Two executions in one session must share their global environment.
      Universe : Session;
      Result : Execution_Result;
   begin
      Result := Universe.Execute ("answer=41");
      Assert_OK (Result);
      Result := Universe.Execute ("print(answer+1)");
      Assert_Output (Result, "42");
   end Persistent_Globals;

   procedure Independent_Sessions is
      --  Globals written in one universe must not enter a second universe.
      First, Second : Session;
      Result : Execution_Result;
   begin
      Result := First.Execute ("answer=42");
      Assert_OK (Result);
      Result := Second.Execute ("print(answer)");
      Assert_Output (Result, "nil");
   end Independent_Sessions;

   procedure Syntax_Error_Recovery is
      --  A failed compilation must release partial code and leave the
      --  session usable.
      Universe : Session;
      Result : Execution_Result;
   begin
      Result := Universe.Execute ("local =");
      Assert_Error (Result, Syntax_Error);
      Result := Universe.Execute ("print(42)");
      Assert_Output (Result, "42");
   end Syntax_Error_Recovery;

   procedure Runtime_Error_Recovery is
      --  A Lua error unwinds frames without discarding existing globals.
      Universe : Session;
      Result : Execution_Result;
   begin
      Result := Universe.Execute ("answer=42; error('expected',0)");
      Assert_Error (Result, Runtime_Error);
      Result := Universe.Execute ("print(answer)");
      Assert_Output (Result, "42");
   end Runtime_Error_Recovery;

   procedure Partial_Output is
      --  Output before a runtime failure must survive in the error result.
      Universe : Session;
      Result : Execution_Result;
   begin
      Result := Universe.Execute ("print(42); error('expected',0)");
      Assert_Error (Result, Runtime_Error);
      Assert (To_String (Result.Output) = "42" & LF, "partial output");
   end Partial_Output;

   procedure Source_Location is
      --  Syntax diagnostics expose the named source and precise source line.
      Universe : Session;
      Result : Execution_Result;
   begin
      Result := Universe.Execute ("local x=1" & LF & "local =", "named");
      Assert_Error (Result, Syntax_Error);
      Assert (Result.Error.Source = "named", "source label");
      Assert (Result.Error.Line = 2, "syntax line");
   end Source_Location;

   procedure Runtime_Source_Location is
      --  A deferred lvalue store must retain the failing statement's source
      --  line rather than inheriting the following statement's token.
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        ("local t=nil" & LF & "t.x=42" & LF & "print('unreachable')",
         "runtime-source");
   begin
      Assert_Error (Result, Runtime_Error);
      Assert (Result.Error.Line = 2, "runtime statement location");
   end Runtime_Source_Location;

   procedure Deferred_Goto is
      --  An undefined label is invalid even in an unchosen branch; valid
      --  deferred syntax has a separate Unsupported_Feature result.
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        ("if false then goto missing end");
   begin
      Assert_Error (Result, Syntax_Error);
   end Deferred_Goto;

   procedure Deferred_Close is
      --  To-be-closed declarations are explicitly outside the scoped
      --  milestone.
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        ("local x <close> = nil");
   begin
      Assert_Error (Result, Unsupported_Feature);
   end Deferred_Close;

   procedure Const_Assignment is
      --  Constant lexical cells reject reassignment before executing the
      --  chunk.
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        ("local x <const> = 1; x=2");
   begin
      Assert_Error (Result, Syntax_Error);
   end Const_Assignment;

   procedure Named_Global_Restriction is
      --  A named global declaration removes implicit undeclared-global
      --  access.
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        ("global x; print(x)");
   begin
      Assert_Error (Result, Syntax_Error);
   end Named_Global_Restriction;

   procedure Duplicate_Global is
      --  Global initializers must not overwrite a nonnil existing global.
      Universe : Session;
      Result : Execution_Result;
   begin
      Result := Universe.Execute ("global *; global x=1; global x=2");
      Assert_Error (Result, Runtime_Error);
      Result := Universe.Execute ("print(x)");
      Assert_Output (Result, "1");
   end Duplicate_Global;

   procedure Instruction_Budget is
      --  A nonterminating loop must stop at its budget and allow a later
      --  chunk.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Bounds.Instructions := 100;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute ("while true do end");
      Assert_Error (Result, Resource_Error);
      Universe.Set_Limits ((others => <>));
      Result := Universe.Execute ("print(42)");
      Assert_Output (Result, "42");
   end Instruction_Budget;

   procedure Token_Budget is
      --  The scanner's configured budget becomes a structured resource
      --  failure.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Bounds.Tokens := 3;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute ("local x=42");
      Assert_Error (Result, Resource_Error);
   end Token_Budget;

   procedure Source_Budget is
      --  Reject oversized source before creating compiler state.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Bounds.Source_Bytes := 3;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute ("print(42)");
      Assert_Error (Result, Resource_Error);
   end Source_Budget;

   procedure Register_Budget is
      --  Temporary register pressure is bounded independently of source
      --  length.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Bounds.Registers := 1;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute ("print(1+2)");
      Assert_Error (Result, Resource_Error);
   end Register_Budget;

   procedure Call_Depth_Budget is
      --  Non-tail recursion consumes frames and fails at the configured
      --  limit.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Bounds.Call_Depth := 4;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute
        ("local function f(n) if n==0 then return 0 end " &
         "return 1+f(n-1) end; print(f(20))");
      Assert_Error (Result, Resource_Error);
   end Call_Depth_Budget;

   procedure Tail_Call_Reuses_Frame is
      --  A tail-recursive function must outlive a very small frame-depth
      --  limit.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Bounds.Call_Depth := 4;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute
        ("local function f(n) if n==0 then return 42 end " &
         "return f(n-1) end; print(f(1000))");
      Assert_Output (Result, "42");
   end Tail_Call_Reuses_Frame;

   procedure String_Budget is
      --  Decoded string size is checked before allocating a Lua string
      --  object.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Bounds.String_Bytes := 8;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute ("print('123456789')");
      Assert_Error (Result, Resource_Error);
   end String_Budget;

   procedure Output_Budget is
      --  Printing an empty argument list still consumes one output newline.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Bounds.Output_Bytes := 2;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute ("print(); print(); print()");
      Assert_Error (Result, Resource_Error);
      Assert (Length (Result.Output) <= 2, "output stays within budget");
   end Output_Budget;

   procedure Table_Entry_Budget is
      --  A second table member must fail after one available entry is used.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Bounds.Table_Entries := Universe.Statistics.Table_Entries + 1;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute ("local t={}; t.a=1; t.b=2");
      Assert_Error (Result, Resource_Error);
   end Table_Entry_Budget;

   procedure Heap_Object_Budget is
      --  A universe with no room for execution roots reports resource
      --  exhaustion.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      Bounds.Heap_Objects := 1;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute ("print(42)");
      Assert_Error (Result, Resource_Error);
   end Heap_Object_Budget;

   procedure Frame_Setup_Failure_Recovery is
      --  Exhaust the heap before the first activation can create its scope.
      --  Repeated failures must release partial execution state; restoring
      --  the budget then permits a fresh chunk on the same owned session.
      Universe : Session;
      Bounds : Execution_Limits;
      Baseline : constant Heap_Statistics := Universe.Statistics;
      Result : Execution_Result;
   begin
      Bounds.Heap_Objects := Baseline.Live_Objects;
      Universe.Set_Limits (Bounds);
      for Attempt in 1 .. 20 loop
         Result := Universe.Execute ("print(42)", "frame-setup");
         Assert_Error (Result, Resource_Error);
         Assert (Universe.Statistics.Live_Objects = Baseline.Live_Objects,
                 "failed activation retains no owned objects");
         Assert (Universe.Statistics.Programs = 0,
                 "failed activation retains no compiled program");
      end loop;
      Bounds.Heap_Objects := 100_000;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute ("print(42)");
      Assert_Output (Result, "42");
   end Frame_Setup_Failure_Recovery;

   procedure Collect_Table_Cycle is
      --  Unreachable self-referencing tables must return to the bootstrap
      --  live count.
      Universe : Session;
      Before : constant Natural := Universe.Statistics.Live_Objects;
      Result : Execution_Result;
   begin
      Result := Universe.Execute ("do local t={}; t.self=t end");
      Assert_OK (Result);
      Universe.Collect;
      Assert (Universe.Statistics.Live_Objects = Before, "cycle reclaimed");
   end Collect_Table_Cycle;

   procedure Collect_Closure_Cycle is
      --  A table, closure, and captured environment may form one unreachable
      --  graph.
      Universe : Session;
      Before : constant Natural := Universe.Statistics.Live_Objects;
      Result : Execution_Result;
   begin
      Result := Universe.Execute
        ("do local t={}; local function f() return t end; t.f=f end");
      Assert_OK (Result);
      Universe.Collect;
      Assert (Universe.Statistics.Live_Objects = Before,
              "closure graph freed");
   end Collect_Closure_Cycle;

   procedure Keep_Captured_Root is
      --  A global closure keeps its captured table alive across collection
      --  and chunks.
      Universe : Session;
      Result : Execution_Result;
   begin
      Result := Universe.Execute
        ("local t={answer=42}; function read() return t.answer end");
      Assert_OK (Result);
      Universe.Collect;
      Result := Universe.Execute ("print(read())");
      Assert_Output (Result, "42");
   end Keep_Captured_Root;

   procedure Automatic_Collection is
      --  Repeated cyclic allocations must run within a small bounded heap.
      Universe : Session;
      Bounds : Execution_Limits;
      Result : Execution_Result;
   begin
      --  The expanded standard environment is permanent storage. Give this
      --  regression the same 128 transient-object allowance above its live
      --  bootstrap rather than assuming an M1-specific builtin count.
      Bounds.Heap_Objects := Universe.Statistics.Live_Objects + 128;
      Universe.Set_Limits (Bounds);
      Result := Universe.Execute
        ("local n=0; for i=1,5000 do local t={}; t.self=t; n=n+1 " &
         "end; print(n)");
      Assert_Output (Result, "5000");
      Assert (Universe.Statistics.Collections > 2, "automatic collection ran");
   end Automatic_Collection;

   procedure Closed_Session is
      --  Closing twice is harmless; executing a closed session is a
      --  structured error.
      Universe : Session;
      Result : Execution_Result;
   begin
      Universe.Close;
      Universe.Close;
      Result := Universe.Execute ("print(42)");
      Assert_Error (Result, Runtime_Error);
      Assert (Universe.Statistics.Live_Objects = 0, "closed heap empty");
   end Closed_Session;

   procedure Reset_Session is
      --  Reset clears globals and reopens a previously closed universe.
      Universe : Session;
      Result : Execution_Result;
   begin
      Result := Universe.Execute ("answer=42");
      Assert_OK (Result);
      Universe.Close;
      Universe.Reset;
      Result := Universe.Execute ("print(answer)");
      Assert_Output (Result, "nil");
   end Reset_Session;

   procedure Argument_Table_Indices is
      --  The host arg table preserves negative, zero, and positive indices.
      Universe : Session;
      Args : constant Argument_Array (-1 .. 1) :=
        [To_Unbounded_String ("lua"), To_Unbounded_String ("script"),
         To_Unbounded_String ("value")];
      Result : Execution_Result;
   begin
      Result := Universe.Set_Arguments (Args);
      Assert_OK (Result);
      Result := Universe.Execute ("print(arg[-1],arg[0],arg[1])");
      Assert_Output (Result, "lua" & HT & "script" & HT & "value");
   end Argument_Table_Indices;

   procedure Chunk_Arguments is
      --  Execution arguments become the main chunk's vararg packet.
      Universe : Session;
      Args : constant Argument_Array (1 .. 2) :=
        [To_Unbounded_String ("first"), To_Unbounded_String ("second")];
      Result : Execution_Result;
   begin
      Result := Universe.Execute ("print(...)", Arguments => Args);
      Assert_Output (Result, "first" & HT & "second");
   end Chunk_Arguments;

   procedure Output_Sink_Capture is
      --  A borrowed sink receives the same captured bytes as the result.
      Universe : Session;
      Sink : aliased Capture_Sink;
      Result : Execution_Result;
   begin
      Result := Universe.Execute ("print(42)", Sink => Sink'Access);
      Assert_Output (Result, "42");
      Assert (Sink.Bytes = Result.Output, "sink and result agree");
   end Output_Sink_Capture;

   procedure Output_Sink_Failure is
      --  A failing host sink becomes Host_Error without corrupting the
      --  universe.
      Universe : Session;
      Sink : aliased Broken_Sink;
      Result : Execution_Result;
   begin
      Result := Universe.Execute ("print(1)", Sink => Sink'Access);
      Assert_Error (Result, Host_Error);
      Result := Universe.Execute ("print(42)");
      Assert_Output (Result, "42");
   end Output_Sink_Failure;

   procedure Pcall_Arithmetic_Error is
      --  A primitive arithmetic exception must become a catchable Lua error.
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        ("local ok,e=pcall(function() return 1//0 end); " &
         "print(ok,type(e))");
   begin
      Assert_Output (Result, "false" & HT & "string");
   end Pcall_Arithmetic_Error;

   procedure Pcall_Nonfunction is
      --  pcall catches an invalid callee without creating a language frame.
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        ("local ok,e=pcall(42); print(ok,type(e))");
   begin
      Assert_Output (Result, "false" & HT & "string");
   end Pcall_Nonfunction;

   procedure Nil_Table_Key is
      --  Assigning a nil table key is a Lua error, not an Ada discriminant
      --  failure.
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        ("local t={}; t[nil]=1");
   begin
      Assert_Error (Result, Runtime_Error);
   end Nil_Table_Key;

   procedure NaN_Table_Key is
      --  NaN cannot become an equality-inconsistent table key.
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        ("local t={}; t[0/0]=1");
   begin
      Assert_Error (Result, Runtime_Error);
   end NaN_Table_Key;

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add
        (Suite, "lifecycle: runtime source location",
         Runtime_Source_Location'Access);
      Test_Support.Add
        (Suite, "lifecycle: persistent globals",
         Persistent_Globals'Access);
      Test_Support.Add
        (Suite, "lifecycle: independent sessions",
         Independent_Sessions'Access);
      Test_Support.Add
        (Suite, "lifecycle: syntax error recovery",
         Syntax_Error_Recovery'Access);
      Test_Support.Add
        (Suite, "lifecycle: runtime error recovery",
         Runtime_Error_Recovery'Access);
      Test_Support.Add
        (Suite, "lifecycle: partial output",
         Partial_Output'Access);
      Test_Support.Add
        (Suite, "lifecycle: source location",
         Source_Location'Access);
      Test_Support.Add
        (Suite, "lifecycle: undefined goto",
         Deferred_Goto'Access);
      Test_Support.Add
        (Suite, "lifecycle: deferred close",
         Deferred_Close'Access);
      Test_Support.Add
        (Suite, "lifecycle: const assignment",
         Const_Assignment'Access);
      Test_Support.Add
        (Suite, "lifecycle: named global restriction",
         Named_Global_Restriction'Access);
      Test_Support.Add
        (Suite, "lifecycle: duplicate global",
         Duplicate_Global'Access);
      Test_Support.Add
        (Suite, "lifecycle: instruction budget",
         Instruction_Budget'Access);
      Test_Support.Add
        (Suite, "lifecycle: token budget",
         Token_Budget'Access);
      Test_Support.Add
        (Suite, "lifecycle: source budget",
         Source_Budget'Access);
      Test_Support.Add
        (Suite, "lifecycle: register budget",
         Register_Budget'Access);
      Test_Support.Add
        (Suite, "lifecycle: call depth budget",
         Call_Depth_Budget'Access);
      Test_Support.Add
        (Suite, "lifecycle: tail call reuses frame",
         Tail_Call_Reuses_Frame'Access);
      Test_Support.Add
        (Suite, "lifecycle: string budget",
         String_Budget'Access);
      Test_Support.Add
        (Suite, "lifecycle: output budget",
         Output_Budget'Access);
      Test_Support.Add
        (Suite, "lifecycle: table entry budget",
         Table_Entry_Budget'Access);
      Test_Support.Add
        (Suite, "lifecycle: heap object budget",
         Heap_Object_Budget'Access);
      Test_Support.Add
        (Suite, "lifecycle: frame setup failure recovery",
         Frame_Setup_Failure_Recovery'Access);
      Test_Support.Add
        (Suite, "lifecycle: collect table cycle",
         Collect_Table_Cycle'Access);
      Test_Support.Add
        (Suite, "lifecycle: collect closure cycle",
         Collect_Closure_Cycle'Access);
      Test_Support.Add
        (Suite, "lifecycle: keep captured root",
         Keep_Captured_Root'Access);
      Test_Support.Add
        (Suite, "lifecycle: automatic collection",
         Automatic_Collection'Access);
      Test_Support.Add
        (Suite, "lifecycle: closed session",
         Closed_Session'Access);
      Test_Support.Add
        (Suite, "lifecycle: reset session",
         Reset_Session'Access);
      Test_Support.Add
        (Suite, "lifecycle: argument table indices",
         Argument_Table_Indices'Access);
      Test_Support.Add
        (Suite, "lifecycle: chunk arguments",
         Chunk_Arguments'Access);
      Test_Support.Add
        (Suite, "lifecycle: output sink capture",
         Output_Sink_Capture'Access);
      Test_Support.Add
        (Suite, "lifecycle: output sink failure",
         Output_Sink_Failure'Access);
      Test_Support.Add
        (Suite, "lifecycle: pcall arithmetic error",
         Pcall_Arithmetic_Error'Access);
      Test_Support.Add
        (Suite, "lifecycle: pcall nonfunction",
         Pcall_Nonfunction'Access);
      Test_Support.Add
        (Suite, "lifecycle: nil table key",
         Nil_Table_Key'Access);
      Test_Support.Add
        (Suite, "lifecycle: nan table key",
         NaN_Table_Key'Access);
   end Register;
end Lifecycle_Tests;
