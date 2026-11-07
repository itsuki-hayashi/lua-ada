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

`Execute_Display` supports host read-eval-print loops without exposing returned
objects. It executes one chunk, retains all returned values as traced roots,
then resolves and calls the current global `print` through a second sequential
drive. Environment lookup and callable metamethods retain ordinary Lua behavior.
The two phases share one instruction budget; callbacks cannot restart it.
`Display_Failed` distinguishes a failure during display from a failed chunk.
An empty result packet does not call `print`. Output policy and typed exit
requests have the same meaning as for `Execute`.

`Set_Warnings_Enabled` sends an actual warning control from an idle session.
It is independent of the public `warn` global, so host options retain their
meaning after Lua code replaces that global. Custom C warning handlers use the
same guarded callback portal. Both methods require serialized session access;
neither may be called recursively from an active callback.

Sessions initialize and reset to Output_Policy.Captured. Set_Output_Policy
can explicitly select Process_Streams without changing globals or execution
quotas. That mode publishes bytes to actual C stdout during execution and
leaves Execute.Output empty; a borrowed sink therefore receives no duplicate
bytes. Native text-mode newline translation and buffering follow the host C
runtime. print flushes after its newline and retains Lua's behavior of ignoring
ordinary stdio write/flush errors. Explicit bounded output quotas are checked
before each fragment, including separators and newlines. Compatible execution
does not maintain an overflowing lifetime output counter. Explicit files and
stderr remain separate from captured stdout as file/OS support is integrated.

New source chunks and omitted load environments read the actual global table
from registry entry LUA_RIDX_GLOBALS. Replacing it does not rewrite previously
created _ENV cells. Set_Arguments targets that current table too. The engine
retains no independent bootstrap-global root; ordinary owners such as
package.loaded._G or an old closure can still keep the earlier table alive.

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
failures retain the execution-abort policy. Native Lua 5.5.1 binary chunks are
validated and executed through the canonical backend; string.dump serializes a
real selected function subtree. The codec checks native widths/byte order.
File preambles are handled as file input; bytes passed to Execute or load are
raw text or native chunks. See [binary chunks](binary-chunks.md) for current
verification and explicit limits. Default package lookup is local (`./?.lua;./?/init.lua`), without
native modules or environment-driven path initialization. The library does not
promise a filesystem sandbox.

Ada host callback registration, exposed object handles and thread synchronization
remain deferred. The separate C facade has a partial real exported surface;
its current pilot is not complete public API/ABI acceptance. A sink is an output destination, not a Lua host-function API.

The public C value/auxiliary checkpoint implements metamethod-aware length,
right-fold concatenation and fixed-buffer number output, plus 28 argument,
metatable, reference, registration and error/result helpers. Their actual
operations share the Ada runtime and C-owned continuation portal. Scalar
number output uses fixed owned scratch and requests no Lua allocator storage.
See [ADR 0023](decisions/0023-public-value-auxiliary-operations.md) and its dated
validation record for the local scope and remaining C-surface obligations.

The real C surface includes luaopen_io and luaopen_os. Each pushes a fresh
module table without publishing a global or loaded-module entry. IO opening
initializes registry-owned defaults and retains the existing FILE* metatable
when reopened, so earlier live file objects remain valid. The public userdata
payload is the actual luaL_Stream (FILE pointer and callable C closer); private
ownership metadata lives outside that payload. These exports use the same Ada
library continuations as owned sessions. They do not establish completion of
the full auxiliary API or complete C ABI.

The expanded implementation also supplies the base, package, coroutine, debug,
math, string, table and UTF-8 constructors through the real Ada library drivers.
Ordinary module constructors push their value without publishing a global or
a loaded-module entry; requiref and selected-library initialization own that
publication. The base opener instead initializes the existing global table.
Reopened math modules retain independent RNG captures. Public
callk/pcallk, yieldk/resume and C hooks use explicit callback phases and separate
rooted public resume windows, as specified in
[ADR 0017](decisions/0017-c-continuations-and-resume.md). Source-hashed native
and Ada contract cases cover these paths. Independent scope review and the
separate final-head certificate own runtime acceptance; see [status](status.md).

lua_gc operates on the actual collector and managed byte statistics. Its
stop/restart, count, running and parameter controls do not allocate Lua storage.
Collection and mode changes share the Lua collectgarbage implementation;
pending finalizers execute through the guarded C call driver after the control
operation returns from Ada. Refusal of optional call storage defers queued
finalizers until another collection opportunity. lua_close drains finalizers
through the shared idle-state close driver before physical allocator release;
refused close storage still permits physical cleanup. The public GC contract
is compiled and executed against both the Ada library and pinned C oracle.

The private execution driver can call real C functions and warning handlers
while borrowing an Ada-owned world. Their nested Lua calls use the same driver
and budget. Explicit host aborts abandon C bodies through C-owned guards and
return controlled resource diagnostics to the Ada host, which remains usable.
Private mixed-language tests exercise this path; public Ada host-function
registration and native-module loading remain deferred. See
[the callback boundary](decisions/0013-c-owned-call-boundary.md).

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
work. A later Execute remains usable. Canonical register storage and a retained minimum activation charge currently
determine semantic slot accounting; exact C shared-stack overlap boundaries
remain a required M3 migration obligation. Error
cleanup has a fixed emergency reserve rather than a larger ordinary stack limit.

Suspended Lua coroutines belong to reachable thread values; the host session
does not retain every registry entry forever. Stable cells preserve captured
identity when coroutine storage is reclaimed. Explicit close runs handlers;
collection of abandoned threads releases storage without invoking handlers.
The public API still exposes no object handles or host callback registration.
See [ADR 0009](decisions/0009-language-lifecycle.md) for ownership and cleanup.
