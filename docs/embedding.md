# Ada Embedding

## Syntax checking

Use Lua.Syntax.Check without constructing a session. It returns structured
syntax/resource diagnostics and never runs source. See the
[frontend guide](frontend.md) for CLI --check and limits.

Execution_Status retains Unsupported_Feature for future valid deferred syntax.
Goto, labels and closing declarations now execute; complete-source validation
still precedes all chunk effects. Syntax_Error remains invalid source.
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

M2b extends that rule to `xpcall` and callbacks reached through metamethods,
pattern replacement, loading readers, and package searchers. Lua/native calls
share an explicit activation stack within each context and one execution-wide
budget across the scheduler chain. A callback language error
can be protected; resource exhaustion unwinds all abandoned continuation state
and aborts the chunk. Later `Execute` calls remain usable with a fresh per-chunk
instruction budget.

`Set_Limits` controls source/tokens, instructions, call depth, objects, table
entries, strings, output, and registers. Limits are positive; instructions
restart for each execution. These are explicit host allocation/work quotas, not a
hard operating-system memory quota. Compiler nesting has an additional guard.
A host memory allocation failure is returned as a controlled resource error.
The work budget also covers native helper loops and pattern backtracking;
calling a library is not an escape from bounded execution. Mathematical
`string.packsize` results do not allocate a corresponding string. Invalid
format-size overflow is a Lua error; valid sizes which exceed actual allocation
quotas produce resource failure when allocation is requested.

`Set_Arguments` installs the CLI-style `arg` table with index-preserving string
entries. Use `No_Arguments` for an empty array; arbitrary integer bounds also
support negative option indexes and the script at index zero.

`Collect` traces between executions. `Statistics` reports owned object/program
counts and collections, not process memory. `Close` is idempotent; execution
on a closed session returns an error. `Reset` creates a fresh default universe.
The M2b default universe includes its [listed libraries](capabilities.md), a
private string metatable, and loaded/preload registries. Reset removes previous
module caches and metatable mutations; separate sessions never share these
mutable objects.

Lua code may load text through `load`, `loadfile`, `dofile`, and Lua-only
`require`. Loaded closures retain their initial `_ENV`, including an explicitly
nil environment. Compilation errors from `load` return nil/message; resource
failures retain the execution-abort policy. Binary sources are unsupported.
File preambles are handled as file input; source passed to `Execute` or `load`
is raw text. Default package lookup is local (`./?.lua;./?/init.lua`), without
native modules or environment-driven path initialization. The library does not
promise a filesystem sandbox.

Host callbacks, exposed object handles, C exports, and thread synchronization
are deferred. A sink is an output destination, not a Lua host-function API.

## Execution policy and lifecycle

New and reset sessions select Execution_Policy.Bounded. Set_Execution_Policy
(Lua_Compatible) removes project host quotas without discarding globals. Switching
back to Bounded restores the last explicit limits; Set_Limits always selects
Bounded. Limits remain serialized operations on the owning session. Compatible
execution does not reset work during resumes, callbacks, hooks or closing.
Bounded instruction accounting starts only at a new public Execute.

Lua semantic stack overflow (1,000,000 slots) and native-call depth overflow
(200 active native calls across the scheduler chain) are catchable runtime
errors. Explicit host limits and physical Ada allocation failure abort the active
scheduler chain without running cleanup callbacks or permitting pcall to restart
work. A later Execute remains usable. Private register packets, argument storage
and a minimum twenty slots per activation determine this backend's slot charges;
exact canonical register-allocation overflow boundaries remain deferred. Error
cleanup has a fixed emergency reserve rather than a larger ordinary stack limit.

Suspended Lua coroutines belong to reachable thread values; the host session
does not retain every registry entry forever. Stable cells preserve captured
identity when coroutine storage is reclaimed. Explicit close runs handlers;
collection of abandoned threads releases storage without invoking handlers.
The public API still exposes no object handles or host callback registration.
See [ADR 0009](decisions/0009-language-lifecycle.md) for ownership and cleanup.
