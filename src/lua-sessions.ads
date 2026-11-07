with Ada.Finalization;
with Ada.Strings.Unbounded;
with Lua.Diagnostics;
with Interfaces.C;
private with Lua.Engine;

package Lua.Sessions is
   --  A session uniquely owns a Lua universe. It cannot be copied, and
   --  finalization releases its heap even when host code leaves by exception.
   --  Calls on one session must be serialized by its owner; distinct sessions
   --  share no mutable interpreter state.

   type Session is new Ada.Finalization.Limited_Controlled with private;

   type Execution_Policy is (Bounded, Lua_Compatible);
   --  Ada sessions start bounded. Compatible policy removes project host
   --  quotas, not Lua semantic stack checks or checked representation limits.
   procedure Set_Execution_Policy
     (Self : in out Session; Policy : Execution_Policy);
   --  Select policy for later executions without discarding globals.
   --  @param Self Owning session; calls must be serialized by its owner.
   --  @param Policy Bounded restores the last explicitly configured limits.

   type Output_Policy is (Captured, Process_Streams);
   --  Captured returns stdout bytes through Execute.Output and its optional
   --  borrowed sink. Process_Streams writes actual C stdout immediately and
   --  leaves Output empty; explicit file/stderr streams remain separate.
   --  @enum Captured Retain stdout for the result and post-execution sink.
   --  @enum Process_Streams Publish byte strings directly to native stdout.
   procedure Set_Output_Policy
     (Self : in out Session; Policy : Output_Policy);
   --  Select output delivery without discarding globals or changing quotas.
   --  @param Self Owning session; serialize all operations on it.
   --  @param Policy Sessions initialize/reset to Captured. The batch CLI and
   --  C-created states explicitly select Process_Streams.

   type Execution_Status is
     (Succeeded, Syntax_Error, Runtime_Error, Resource_Error, Host_Error,
      Unsupported_Feature, Exit_Requested);
   --  Host_Error identifies a failing output sink, not a Lua language error.
   --  Unsupported_Feature identifies valid syntax awaiting runtime support;
   --  the complete chunk is checked and rejected before executing any code.

   subtype Process_Exit_Code is Interfaces.C.int;
   --  Preserve the native C status before the process applies OS narrowing.
   type Process_Exit_Request is record
      Code : Process_Exit_Code := 0;
      Close_State : Boolean := False;
   end record;
   --  os.exit is a typed execution transfer for an Ada host. It never exits
   --  the host process. Close_State reports whether Lua state cleanup ran.

   subtype Diagnostic is Lua.Diagnostics.Diagnostic;
   --  Source names and byte positions remain separate from message wording.

   type Execution_Result is record
      Status : Execution_Status := Succeeded;
      Output : Ada.Strings.Unbounded.Unbounded_String;
      Error  : Diagnostic;
      Exit_Request : Process_Exit_Request;
   end record;
   --  Captured output preceding an error is preserved. Process output has
   --  already been written and leaves Output empty. No chunk return values
   --  or internal object references escape through this embedding API.

   type Execution_Limits is record
      Source_Bytes  : Positive := 1_000_000;
      Tokens        : Positive := 100_000;
      Instructions  : Positive := 1_000_000;
      Call_Depth    : Positive := 1_024;
      Heap_Objects  : Positive := 100_000;
      Table_Entries : Positive := 100_000;
      String_Bytes  : Positive := 1_000_000;
      Output_Bytes  : Positive := 1_000_000;
      Registers     : Positive := 4_096;
      Syntax_Nodes  : Positive := 200_000;
      Syntax_Depth  : Positive := 200;
   end record;
   --  These bounds apply under Bounded policy; Set_Limits selects it.
   --  Instruction budgets restart for each public chunk, not a resume or
   --  callback. Heap/table limits cover the universe. Semantic Lua stack
   --  checks and physical-storage failure handling apply under both policies.

   type Argument_Array is array (Integer range <>) of
     Ada.Strings.Unbounded.Unbounded_String;
   --  Arbitrary bounds support CLI arg[-n], arg[0], and positive parameters.

   No_Arguments : constant Argument_Array (1 .. 0) := [others => <>];
   --  An explicit null range avoids Integer'First as an empty array bound.

   type Output_Sink is limited interface;
   procedure Write (Sink : in out Output_Sink; Bytes : String) is abstract;
   --  Receive captured bytes synchronously after execution. The session does
   --  not retain Sink. Sink exceptions become Host_Error results. Under
   --  Process_Streams there are no captured stdout bytes to deliver.

   function Execute
     (Self : in out Session; Source : String;
      Name : String := "(source)";
      Arguments : Argument_Array := No_Arguments;
      Sink : access Output_Sink'Class := null) return Execution_Result;
   --  Execute named text or a checked native binary chunk, retaining globals.
   --  @param Self Unique owner of the heap and global environment.
   --  @param Source Lua source bytes or a native Lua 5.5.1 binary chunk.
   --  @param Name Source label used by diagnostics and Lua error prefixes.
   --  @param Arguments Values supplied to the chunk's vararg parameter.
   --  @param Sink Optional borrowed output destination; never retained.
   --  @return Success or structured error, including output already produced.

   function Execute_Display
     (Self : in out Session; Source : String;
      Name : String := "=stdin"; Display_Failed : out Boolean)
      return Execution_Result;
   --  Execute Source like Execute, then call the session's current global
   --  print with every value the chunk returned, in a second sequential
   --  drive (no helper Lua frame). The results stay in a traced root across
   --  allocation, collection and printing; no VM value escapes. Nothing is
   --  printed for an empty result list, a failed chunk or a process exit.
   --  @param Display_Failed True when the chunk succeeded and the failure
   --  came from calling print; Error.Message is then the raw error text
   --  and the host adds its "error calling 'print'" framing.

   function Set_Arguments
     (Self : in out Session; Arguments : Argument_Array)
      return Execution_Result;
   --  Replace arg in the actual current registry global table, without
   --  exposing a general object API or retargeting existing _ENV cells.
   --  @param Self Session whose global arg table is replaced.
   --  @param Arguments Index-preserving strings, including zero/negative keys.
   --  @return Structured success/resource failure; never an engine exception.

   function Set_Warnings_Enabled
     (Self : in out Session; Enabled : Boolean) return Execution_Result;
   --  Send the native @on/@off control to the owning warning handler without
   --  consulting the replaceable Lua warn global. Custom callbacks use the
   --  same guarded scheduler as execution. Serialize this host operation
   --  with all other calls on Self; it starts its own bounded work epoch.

   function Configure_Package_Environment
     (Self : in out Session; Ignore_Environment : Boolean := False)
      return Execution_Result;
   --  Select pinned native package defaults and optional environment paths
   --  for the current package table, recording LUA_NOENV in the real registry.
   --  Intended for a CLI/host before initialization code; ordinary bounded
   --  session construction retains its existing local Lua search path.
   --  Serialize with Self's other operations. Failures use the same typed
   --  work/allocation policy as execution; no runtime values escape.

   procedure Set_Limits (Self : in out Session; Bounds : Execution_Limits);
   --  Select bounded policy and change limits for later calls. This
   --  does not discard existing globals.

   procedure Collect (Self : in out Session);
   --  Force tracing collection between executions; useful for host idle time.

   type Heap_Statistics is record
      Live_Objects : Natural;
      Table_Entries : Natural;
      Programs : Natural;
      Collections : Natural;
   end record;
   function Statistics (Self : Session) return Heap_Statistics;
   --  Return owned-allocation counts, not process memory or coverage metrics.

   procedure Close (Self : in out Session);
   --  Idempotently close the main thread and finalize Lua objects, then
   --  release the universe. Execute then returns Runtime_Error. Host aborts
   --  stop Lua cleanup; physical owned-resource disposal still completes.

   procedure Reset (Self : in out Session);
   --  Start a fresh universe with default limits and standard libraries.
   --  Reset selects Bounded/Captured and discards globals, module caches,
   --  hooks, coroutine contexts, collector controls and metatable mutations.

private
   type Session is new Ada.Finalization.Limited_Controlled with record
      State : Lua.Engine.World_Access;
   end record;
   overriding procedure Initialize (Self : in out Session);
   overriding procedure Finalize (Self : in out Session);
end Lua.Sessions;
