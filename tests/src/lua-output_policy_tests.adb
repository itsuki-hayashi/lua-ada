with Ada.Characters.Latin_1;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions; use AUnit.Assertions;
with Lua.Engine;
with Lua.Sessions; use Lua.Sessions;
with Test_Support;

package body Lua.Output_Policy_Tests is
   use type Engine.Failure_Kind;
   LF : constant Character := Ada.Characters.Latin_1.LF;
   HT : constant Character := Ada.Characters.Latin_1.HT;

   type Recording_Sink is new Output_Sink with record
      Calls : Natural := 0;
      Bytes : Unbounded_String;
   end record;
   overriding procedure Write
     (Self : in out Recording_Sink; Bytes : String);

   overriding procedure Write
     (Self : in out Recording_Sink; Bytes : String) is
   begin
      Self.Calls := Self.Calls + 1;
      Append (Self.Bytes, Bytes);
   end Write;

   procedure Captured_Default;
   procedure Captured_Sink;
   procedure Reset_Restores_Capture;
   procedure Independent_Policies;
   procedure Closed_Setter;
   procedure Callback_Output_Order;
   procedure Partial_Error_Output;
   procedure Per_Chunk_Quota;
   procedure Fragment_Quota;
   procedure Newline_Quota;
   procedure Separator_Quota;
   procedure Protected_Quota;

   generic
      with procedure Action (State : in out Engine.World);
   procedure Engine_Fixture;

   procedure Engine_Fixture is
      State : Engine.World;
   begin
      Engine.Initialize (State, (others => <>));
      begin
         Action (State);
      exception
         when others => Engine.Finalize (State); raise;
      end;
      Engine.Finalize (State);
   end Engine_Fixture;

   procedure Arbitrary_Bounds (State : in out Engine.World);
   procedure Empty_Process_Write (State : in out Engine.World);
   procedure Process_Quota (State : in out Engine.World);
   procedure Compatible_Counter (State : in out Engine.World);
   procedure Captured_Flush (State : in out Engine.World);

   procedure Captured_Default is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        ("print('a'..string.char(0,255), 7)", "capture-default");
   begin
      --  A fresh embedding session captures bytes, including NUL/high bytes,
      --  without applying a host text encoding or writing process stdout.
      Assert (Result.Status = Succeeded, To_String (Result.Error.Message));
      Assert (To_String (Result.Output) =
              "a" & Character'Val (0) & Character'Val (255) & HT & "7" & LF,
              "captured print bytes were altered");
   end Captured_Default;

   procedure Captured_Sink is
      Universe : Session;
      Sink : aliased Recording_Sink;
      Result : constant Execution_Result := Universe.Execute
        ("print('sink')", "capture-sink", Sink => Sink'Access);
   begin
      --  The borrowed sink remains post-execution delivery. It receives one
      --  complete capture while the same bytes remain available in Result.
      Assert (Result.Status = Succeeded, "captured sink execution failed");
      Assert (Sink.Calls = 1 and then Sink.Bytes = Result.Output and then
                To_String (Sink.Bytes) = "sink" & LF,
              "captured sink delivery changed");
   end Captured_Sink;

   procedure Reset_Restores_Capture is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  A host may deliberately select immediate streams, but Reset starts
      --  an independent default universe rather than inheriting that policy.
      Universe.Set_Output_Policy (Process_Streams);
      Universe.Reset;
      Result := Universe.Execute ("print('reset')", "capture-reset");
      Assert (Result.Status = Succeeded and then
                To_String (Result.Output) = "reset" & LF,
              "reset retained process-stream output policy");
   end Reset_Restores_Capture;

   procedure Independent_Policies is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  Delivery selection must not remove an explicitly bounded output
      --  quota. Conversely selecting quotas must not choose a delivery mode.
      Universe.Set_Limits ((Output_Bytes => 2, others => <>));
      Universe.Set_Output_Policy (Process_Streams);
      Universe.Set_Output_Policy (Captured);
      Result := Universe.Execute ("print('abc')", "independent-policies");
      Assert (Result.Status = Resource_Error and then
                Length (Result.Output) = 0,
              "output setter changed execution quota policy");
   end Independent_Policies;

   procedure Closed_Setter is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  Match the existing policy setters: configuring a closed session is
      --  harmless and does not create an implicit replacement universe.
      Universe.Close;
      Universe.Set_Output_Policy (Process_Streams);
      Result := Universe.Execute ("print('unreachable')", "closed-output");
      Assert (Result.Status = Runtime_Error and then
                Length (Result.Output) = 0,
              "output setter reopened a closed session");
   end Closed_Setter;

   procedure Callback_Output_Order is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        ("local a=setmetatable({}, {__tostring=function() " &
         "print('inner'); return 'first' end}); " &
         "local b=setmetatable({}, {__tostring=function() " &
         "error('later conversion') end}); print(a,b)", "print-order");
   begin
      --  Each conversion is followed by its write before the next callback.
      --  In particular no separator is written before the failed conversion.
      Assert (Result.Status = Runtime_Error and then
                To_String (Result.Output) = "inner" & LF & "first",
              "later tostring failure erased/reordered earlier output");
   end Callback_Output_Order;

   procedure Partial_Error_Output is
      Universe : Session;
      Result : constant Execution_Result := Universe.Execute
        ("print('before'); error('failure')", "partial-output");
   begin
      --  Lua errors preserve already published/captured output. The new
      --  producer must not defer its whole chunk until successful completion.
      Assert (Result.Status = Runtime_Error and then
                To_String (Result.Output) = "before" & LF,
              "language error discarded earlier output");
   end Partial_Error_Output;

   procedure Per_Chunk_Quota is
      Universe : Session;
      First, Second : Execution_Result;
   begin
      --  Exactly three bytes fit this chunk. A later execution gets a new
      --  public budget without requiring a reset that would discard globals.
      Universe.Set_Limits ((Output_Bytes => 3, others => <>));
      First := Universe.Execute ("n=1; print('ab')", "first-budget");
      Second := Universe.Execute ("assert(n==1); print('cd')", "next-budget");
      Assert (First.Status = Succeeded and then Second.Status = Succeeded,
              "output quota was retained across public chunks");
      Assert (To_String (First.Output) = "ab" & LF and then
                To_String (Second.Output) = "cd" & LF,
              "capture storage leaked between public chunks");
   end Per_Chunk_Quota;

   procedure Fragment_Quota is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  Reject the entire oversized byte fragment before any of it becomes
      --  observable. This is equally important for immediate process writes.
      Universe.Set_Limits ((Output_Bytes => 2, others => <>));
      Result := Universe.Execute ("print('abc')", "fragment-quota");
      Assert (Result.Status = Resource_Error and then
                Length (Result.Output) = 0,
              "oversized fragment was partly captured");
   end Fragment_Quota;

   procedure Newline_Quota is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  Argument bytes fit exactly; the distinct final newline does not.
      --  Preserve the argument when aborting rather than rolling it back.
      Universe.Set_Limits ((Output_Bytes => 2, others => <>));
      Result := Universe.Execute ("print('ab')", "newline-quota");
      Assert (Result.Status = Resource_Error and then
                To_String (Result.Output) = "ab",
              "newline quota lost the completed argument");
   end Newline_Quota;

   procedure Separator_Quota is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  The tab is a real output byte. Once written it remains visible even
      --  if the following argument exceeds the remaining explicit quota.
      Universe.Set_Limits ((Output_Bytes => 2, others => <>));
      Result := Universe.Execute ("print('a','b')", "separator-quota");
      Assert (Result.Status = Resource_Error and then
                To_String (Result.Output) = "a" & HT,
              "separator was not charged in output order");
   end Separator_Quota;

   procedure Protected_Quota is
      Universe : Session;
      Result : Execution_Result;
   begin
      --  Output limits remain host aborts, not catchable IO/language errors.
      --  pcall must not continue executing after the rejected publication.
      Universe.Set_Limits ((Output_Bytes => 2, others => <>));
      Result := Universe.Execute
        ("pcall(print,'abc'); touched=true", "protected-output-quota");
      Assert (Result.Status = Resource_Error,
              "pcall caught an explicit host output limit");
      Universe.Set_Limits ((others => <>));
      Result := Universe.Execute ("assert(touched==nil)", "output-recovery");
      Assert (Result.Status = Succeeded, "aborted output resumed Lua code");
   end Protected_Quota;

   procedure Arbitrary_Bounds (State : in out Engine.World) is
      Bytes : constant String (11 .. 13) :=
        [Character'Val (0), Character'Val (255), LF];
      Empty : constant String (17 .. 16) := "";
      Result : Engine.Output_Result;
   begin
      --  Borrowed Ada arrays need not start at one. The empty call must not
      --  inspect a nonexistent first element, change accounting or allocate.
      Result := Engine.Emit_Output (State, Bytes);
      Assert (Result.Succeeded and then Result.Bytes_Written = 3,
              "arbitrary-bound output length changed");
      Result := Engine.Emit_Output (State, Empty);
      Assert (Result.Succeeded and then Result.Bytes_Written = 0 and then
                State.Output_Used = 3 and then
                To_String (State.Output) = Bytes,
              "empty/arbitrary-bound output changed capture");
   end Arbitrary_Bounds;

   procedure Empty_Process_Write (State : in out Engine.World) is
      Result : Engine.Output_Result;
   begin
      --  No actual process bytes are needed to check the empty-range path.
      --  The separate consumer verifies nonempty stdout with raw byte reads.
      State.Output_Mode := Engine.Process_Streams;
      Result := Engine.Emit_Output (State, "");
      Assert (Result.Succeeded and then Result.Bytes_Written = 0 and then
                Length (State.Output) = 0 and then State.Output_Used = 0,
              "empty process output allocated/captured bytes");
   end Empty_Process_Write;

   procedure Process_Quota (State : in out Engine.World) is
      Result : Engine.Output_Result;
      pragma Unreferenced (Result);
   begin
      --  A process stream cannot use empty capture storage to bypass quotas.
      --  The rejection occurs before fwrite, so AUnit stdout stays untouched.
      State.Output_Mode := Engine.Process_Streams;
      State.Bounds.Output_Bytes := 2;
      begin
         Result := Engine.Emit_Output (State, "abc");
         Assert (False, "process output ignored its bounded byte quota");
      exception
         when Engine.Language_Error => null;
      end;
      Assert (State.Current.Failure_Class = Engine.Host_Abort and then
                Length (State.Output) = 0 and then State.Output_Used = 0,
              "quota was charged/published after process rejection");
   end Process_Quota;

   procedure Compatible_Counter (State : in out Engine.World) is
   begin
      --  A long-running compatible process must not overflow a monotonically
      --  increasing quota counter. Seed its boundary and publish real bytes.
      Engine.Set_Policy (State, Engine.Lua_Compatible);
      State.Output_Used := Natural'Last;
      Engine.Emit_Output (State, "still works");
      Assert (State.Output_Used = Natural'Last and then
                To_String (State.Output) = "still works",
              "compatible output updated the bounded quota counter");
   end Compatible_Counter;

   procedure Captured_Flush (State : in out Engine.World) is
      Result : Engine.Output_Result;
   begin
      --  Flushing capture is a successful no-op, not fflush on the host's
      --  unrelated stdout. It neither consumes quota nor clears the capture.
      Engine.Emit_Output (State, "retained");
      Result := Engine.Flush_Output (State);
      Assert (Result.Succeeded and then State.Output_Used = 8 and then
                To_String (State.Output) = "retained",
              "captured flush changed output storage/accounting");
   end Captured_Flush;

   procedure Case_Bounds is new Engine_Fixture (Arbitrary_Bounds);
   procedure Case_Empty is new Engine_Fixture (Empty_Process_Write);
   procedure Case_Process_Quota is new Engine_Fixture (Process_Quota);
   procedure Case_Counter is new Engine_Fixture (Compatible_Counter);
   procedure Case_Flush is new Engine_Fixture (Captured_Flush);

   procedure Register (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Test_Support.Add (Suite, "output: embedding defaults to byte capture",
                        Captured_Default'Access);
      Test_Support.Add (Suite, "output: borrowed post-execution sink",
                        Captured_Sink'Access);
      Test_Support.Add (Suite, "output: reset restores capture policy",
                        Reset_Restores_Capture'Access);
      Test_Support.Add (Suite, "output: independent delivery/quota policies",
                        Independent_Policies'Access);
      Test_Support.Add (Suite, "output: setter preserves closed session",
                        Closed_Setter'Access);
      Test_Support.Add (Suite, "output: publish before next tostring callback",
                        Callback_Output_Order'Access);
      Test_Support.Add (Suite, "output: preserve output before language error",
                        Partial_Error_Output'Access);
      Test_Support.Add (Suite, "output: new byte budget for each public chunk",
                        Per_Chunk_Quota'Access);
      Test_Support.Add (Suite, "output: reject fragment before publication",
                        Fragment_Quota'Access);
      Test_Support.Add (Suite, "output: preserve argument on newline quota",
                        Newline_Quota'Access);
      Test_Support.Add (Suite, "output: charge tab before following argument",
                        Separator_Quota'Access);
      Test_Support.Add (Suite, "output: bounded rejection escapes pcall",
                        Protected_Quota'Access);
      Test_Support.Add (Suite, "output: arbitrary bounds and empty fragments",
                        Case_Bounds'Access);
      Test_Support.Add (Suite, "output: empty process write does not capture",
                        Case_Empty'Access);
      Test_Support.Add (Suite, "output: process writes retain bounded quota",
                        Case_Process_Quota'Access);
      Test_Support.Add (Suite, "output: compatible counter cannot overflow",
                        Case_Counter'Access);
      Test_Support.Add (Suite, "output: captured flush is a no-op",
                        Case_Flush'Access);
   end Register;
end Lua.Output_Policy_Tests;
