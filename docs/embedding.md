# Ada Embedding

## Syntax checking

Use Lua.Syntax.Check without constructing a session. It returns structured
syntax/resource diagnostics and never runs source. See the
[frontend guide](frontend.md) for CLI --check and limits.

Execution_Status adds Unsupported_Feature for valid deferred syntax. This is
returned before any chunk effects; Syntax_Error remains invalid source.
Diagnostic aliases Lua.Diagnostics.Diagnostic, preserving its record fields.
Execution limits additionally expose Syntax_Nodes and Syntax_Depth.

`Lua.Sessions` is the small ownership-aware public runtime interface. Each
limited controlled `Session` owns a separate universe and finalizes its storage.
Serialize calls on one session; distinct sessions share no mutable Lua state.

```ada
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Lua.Sessions; use Lua.Sessions;

procedure Example is
   Universe : Session;
   Result : Execution_Result;
begin
   Result := Universe.Execute ("count = 40", "initialization");
   if Result.Status = Succeeded then
      Result := Universe.Execute ("count = count + 2; print(count)", "answer");
   end if;
   if Result.Status = Succeeded then
      Ada.Text_IO.Put (To_String (Result.Output));
   else
      Ada.Text_IO.Put_Line (To_String (Result.Error.Message));
   end if;
end Example;
```

Build a consumer against the root GPR using the same library-kind scenario.
The AUnit lifecycle group is a real Ada consumer of persistent state, captured
output, recovery, independent universes, roots, and finalization.

`Execute` accepts source bytes, a diagnostic name, optional chunk varargs, and a
borrowed output sink. Returns are intentionally discarded; result packets and
heap pointers remain private. Output preceding a failure is retained. The sink
receives the completed output synchronously and is never retained. Sink
exceptions produce `Host_Error`; Lua syntax/runtime/resource failures have
separate statuses and do not escape as unhandled Ada language exceptions.

Diagnostics separate source, line, column, and message. Wording is not a C Lua
error-text ABI. Writes completed before a runtime failure remain observable;
execution is not transactional. Recoverable failures leave the session usable.
Resource failures abort the current chunk even inside `pcall`.

`Set_Limits` controls source/tokens, instructions, call depth, objects, table
entries, strings, output, and registers. Limits are positive; instructions
restart for each execution. These are semantic allocation/work limits, not a
hard operating-system memory quota. Compiler nesting has an additional guard.
A host memory allocation failure is returned as a controlled resource error.

`Set_Arguments` installs the CLI-style `arg` table with index-preserving string
entries. Use `No_Arguments` for an empty array; arbitrary integer bounds also
support negative option indexes and the script at index zero.

`Collect` traces between executions. `Statistics` reports owned object/program
counts and collections, not process memory. `Close` is idempotent; execution
on a closed session returns an error. `Reset` creates a fresh default universe.

Host callbacks, exposed object handles, C exports, and thread synchronization
are deferred. A sink is an output destination, not a Lua host-function API.
