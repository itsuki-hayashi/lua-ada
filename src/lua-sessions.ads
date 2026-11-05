with Ada.Finalization;
with Ada.Strings.Unbounded;
with Lua.Diagnostics;
private with Lua.Engine;

package Lua.Sessions is
   --  A session uniquely owns a Lua universe. It cannot be copied, and
   --  finalization releases its heap even when host code leaves by exception.
   --  Calls on one session must be serialized by its owner; distinct sessions
   --  share no mutable interpreter state.

   type Session is new Ada.Finalization.Limited_Controlled with private;

   type Execution_Status is
     (Succeeded, Syntax_Error, Runtime_Error, Resource_Error, Host_Error,
      Unsupported_Feature);
   --  Host_Error identifies a failing output sink, not a Lua language error.
   --  Unsupported_Feature identifies valid syntax awaiting runtime support;
   --  the complete chunk is checked and rejected before executing any code.

   subtype Diagnostic is Lua.Diagnostics.Diagnostic;
   --  Source names and byte positions remain separate from message wording.

   type Execution_Result is record
      Status : Execution_Status := Succeeded;
      Output : Ada.Strings.Unbounded.Unbounded_String;
      Error  : Diagnostic;
   end record;
   --  Output preceding an error is preserved. No chunk return values or
   --  internal object references escape through this initial embedding API.

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
   --  Positive bounds prevent accidental unbounded execution. Instruction
   --  budgets restart for each chunk; heap/table limits cover the universe.

   type Argument_Array is array (Integer range <>) of
     Ada.Strings.Unbounded.Unbounded_String;
   --  Arbitrary bounds support CLI arg[-n], arg[0], and positive parameters.

   No_Arguments : constant Argument_Array (1 .. 0) := [others => <>];
   --  An explicit null range avoids Integer'First as an empty array bound.

   type Output_Sink is limited interface;
   procedure Write (Sink : in out Output_Sink; Bytes : String) is abstract;
   --  Receive captured bytes synchronously after execution. The session does
   --  not retain Sink. Sink exceptions become Host_Error results.

   function Execute
     (Self : in out Session; Source : String;
      Name : String := "(source)";
      Arguments : Argument_Array := No_Arguments;
      Sink : access Output_Sink'Class := null) return Execution_Result;
   --  Execute a named text chunk, retaining globals across calls.
   --  @param Self Unique owner of the heap and global environment.
   --  @param Source Lua source bytes, not a serialized binary chunk.
   --  @param Name Source label used by diagnostics and Lua error prefixes.
   --  @param Arguments Values supplied to the chunk's vararg parameter.
   --  @param Sink Optional borrowed output destination; never retained.
   --  @return Success or structured error, including output already produced.

   function Set_Arguments
     (Self : in out Session; Arguments : Argument_Array)
      return Execution_Result;
   --  Replace the Lua arg table without exposing a general object API.
   --  @param Self Session whose global arg table is replaced.
   --  @param Arguments Index-preserving strings, including zero/negative keys.
   --  @return Structured success/resource failure; never an engine exception.

   procedure Set_Limits (Self : in out Session; Bounds : Execution_Limits);
   --  Change limits for later calls. This does not discard existing globals.

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
   --  Idempotently release the universe. Execute then returns Runtime_Error.

   procedure Reset (Self : in out Session);
   --  Start a fresh universe with default limits and only the M1 base library.

private
   type Session is new Ada.Finalization.Limited_Controlled with record
      State : Lua.Engine.World_Access;
   end record;
   overriding procedure Initialize (Self : in out Session);
   overriding procedure Finalize (Self : in out Session);
end Lua.Sessions;
