# Test adapter source manifest

Status: implemented test drivers. The GC/IO delivery has accepted scoped
evidence from merged PR #9. Expanded coroutine/API acceptance belongs to the
current scope, execution contracts and final-context reports; this manifest
records source provenance and does not independently certify those results.

The source is pinned Lua 5.5.1 commit
`7579fc9d7ed90240487251dfb69168f8e64e9294`, under `references/lua`.
The upstream files remain unchanged. This driver is linked only into test
executables and calls the actual Ada implementation's public C exports.
Pinned `ltests.c` SHA-256:
`62a7015b036d366addd131e4f046f38557d66b8f48aae120e8aad992f3d90199`.

| Driver | Pinned source | Changes |
| --- | --- | --- |
| `userdata` | `ltests.c:1279`, `newuserdata` | Explicit public argument checks instead of auxiliary macros; actual `lua_newuserdatauv`; zero payload bytes. |
| `test_warning` | `ltests.c:85`, `warnf` | Per-state registry-owned userdata replaces static state; public raw global access replaces private locking/auxiliary calls; same controls, fragment bound, unconsumed `_WARN` rejection and unexpected-warning abort. |
| `inspect` | Original Ada adapter boundary | Returns scalars from private Ada inspection before C API publication; no foreign nonlocal jump crosses the Ada inspection call. |
| `nonblock` | `ltests.c:2154`, `nonblock` | Validate real public stream payload/metatable with exported APIs; use actual POSIX descriptor flags; report native errors. Absent on Windows, matching the pinned driver's platform guard. |
| `conformance_api.c` command driver | `ltests.c:1496-2060`, `runC`, `testC`, `Cfunc`, `Cfunck`, `makeCfunc` | Delegate 96 command names to actual exports or the real test-provider control. Bound token/int parsing; permit registry U0 and absent U256; unsupported commands raise. Continuation contexts refer to the actual retained stack/upvalue script. Lexical implementation is not execution coverage. |
| `set_hook`, `command_hook`, `resume_thread` | `ltests.c:2075-2144`, `Chook`, `sethookaux`, `sethook`, `coresume` | Registry-owned scripts, actual public hooks and resume; explicit event and argument checks. The error branch copies the resumed coroutine's actual error object text. |
| Independent-state drivers | `ltests.c:1338-1399`, `newstate`, `getstate`, `loadlib`, `closestate`, `doremote` | Real seeded construction using the parent allocator; selected public library opening and repeated requiref identity assertion. Remote T exposes this public driver subset. No private C state or fabricated return values. |
| Public API helpers | `ltests.c:1223-1324,1469-1490`, reference/upvalue/address/double/new-stack/external-string helpers | Use the real reference free list, capture cells, C addresses, host-double bytes, same-world thread calls and original external payload allocator. Replace unaligned double dereference with memcpy and reject short input before reading. |
| Panic helper | `ltests.c:1412-1465`, `panicback`, `checkpanic` | Actual child allocator, selected C panic callback and C-owned setjmp. Protect jump-context setup before installing panic and protect parent result publication so child ownership is released on refusal. Optional panic commands use the actual child API stack. |
| Shared allocation controls | `ltests.c:211`, `debug_realloc`; `ltests.c:949`, `alloc_count`; `ltests.c:1884`, runC alloccount | Test-only common provider measures and limits inherited raw allocations, preserving host ceiling, old-block ownership and free/shrink behavior. Registry-bound real C leaf takes a scalar count without allocating a Lua call boundary. Exact private allocation positions/type-tag accounting are not emulated. |

The driver now implements 96 of the pinned runC's 98 nonempty command names.
The remaining commands are `traceback` and the private `printstack` inspection.
Unsupported commands raise an actual Lua error.
No requirement is excluded merely because its driver is still missing.
The implemented groups cover stack/index/rotation, scalar/type/conversion,
raw/handler table operations, arithmetic/comparison/length/concatenation,
buffers/formatting, userdata/metatables, text-buffer loading, errors, hooks,
warnings, closing and the retained coroutine/continuation commands. Operands retain
the source driver's stack-top (`.`), stack-count (`*`), registry (`R`, `!M`,
`!G`) and closure-upvalue (`U`) behavior. Tokens and native-int conversions
have explicit bounds. Rejection of an overflowing operand is an additional
first-party driver safety regression; native `ltests.c` does not enforce that
same bound and is not its behavioral oracle. Invalid comparison options and
short double byte strings also have explicit first-party safety rejection.

Public C helpers install as real light C function values with no hidden heap
wrapper or captures. Only Ada inspection callbacks retain the operation/world
pair they actually consume. TestC's U1 is therefore absent, U0 is the real
registry, and a zero-upvalue pushcclosure round-trips to testC's genuine address.
Status strings are rooted in the actual registry before refusal campaigns,
matching regcodes' purpose. Added helper names are d2s, s2d, pushuserdata,
udataval, ref, getref, unref, upvalue, doonnewstack and externstr.

Continuation scripts remain in actual rooted stack/upvalue slots. The Ada
runtime retains their explicit continuation pointer, context, result adjustment
and protection state after the original C body has unwound. Nested suspended
calls retain distinct activation-owned boundaries. C guards perform every
foreign error/yield transfer after Ada dispatch returns. Yieldable protected
errors invoke the saved continuation even without an earlier yield, while a
synchronous successful call returns through its original C body. `toclose`
marks an actual stable stack cell; normal/error return and resumed continuation
return use the same Ada close scheduler and retain outgoing values through
collecting close callbacks. Public top-lowering and explicit `lua_closeslot`
also use that scheduler before returning to their original C body; the focused
public consumer cases check immediate closure, slot reuse and nil publication.

Hook scripts are registry-owned per addressed thread. They execute real public
hooks, and line/count yields preserve the interrupted frame and register window.
The C trampoline is transport and does not become a public debug stack level.
Frame/line inspection uses actual active frames and the implemented public
debug selectors. A separate stale-frame rejection
regression is an Ada safety extension, not a portable native C witness.
Independent-state drivers construct separate real universes, preserve the
source allocator and use public library openers and module registries. Remote
scalar results retain the pinned driver's textual transfer behavior. A resume
source state supplies C-call depth without sharing values or registry ownership.
New states retain the exported runtime's ordinary panic policy; the source's
private `tpanic` test callback is not installed. The remote `T` table contains
the nineteen public drivers/helpers listed above. It does not pretend to expose
the Ada-specific inspection operations of a different world.

A protected C call on another context uses a genuine entry drive while scalar
metadata preserves the suspended caller's driver/context/depth. Completion
restores that ownership before result publication; host abort carries the exact
saved C caller surface through a typed response when the target has no guard.
The same iterative executor, allocator and host budget remain authoritative.
The [component record](../../docs/sessions/2026-11-08-public-api-driver.md)
separates nineteen native-paired witnesses, twenty-three named AUnit cases,
actual api.lua progress and the still-missing panic/refusal drivers.

Collector color, age, phase, allocation statistics, parameter codec and physical
storage controls use real Ada state. They do not emulate C private layouts.
The warning adapter also counts completed deliveries containing the distinct
`@expected warning` token used only by `gc.lua`'s ten state-close callbacks.
The test launcher writes this measured count after state closure. The separate
C oracle's `bounded_ltests.c` wraps warning installation while preserving the
original callback/data and fragment/control semantics, and observes the same
completed deliveries. Neither observer edits upstream Lua or supplies a count
from registered objects. Instrumented GC acceptance requires exactly ten,
in addition to the original ordering assertions and closing-state output.
This counter is process-scoped for the isolated single-file launcher and resets
when its test warning handler is installed; it is not a general per-state API.
`T.checkmemory` inspects the real registry, collector lists, heap/code edges,
live activation windows, finalizer queues and allocator headers/accounting.
The GC/IO scope's reviewed mappings and named positive/negative witnesses are
recorded in its [accepted contract index](../conformance/scopes/gc-io-events.contracts.json).
`T.nonblock` has POSIX execution and a separately reviewed Windows counterpart;
the Windows driver's native absence alone never discharges its guarded source
obligation. Expanded acceptance must replay these retained obligations too.
Native descriptor drivers now reside in conformance_platform.c, independently
linkable to the C oracle without Ada inspection symbols. The same source builds
the oracle-only conformance_platform module and the guarded Ada test callback.
The first-party `_test_failing_stream` Windows counterpart uses `_pipe` and
`_dup2` to replace a fresh temporary file's descriptor with a pipe whose reader
is closed. It retains the real FILE pointer, C closer and external ownership
metadata. Buffered writes succeed, native flushes fail, and native close still
releases the descriptor. This test-only driver is available in both launcher
configurations; it does not create T in the default configuration. Its reviewed
mapping to the `/dev/full` source span belongs to the accepted GC/IO scope. The shared
windows-buffered-failure.lua fixture supplies matching C/Ada driver assertions;
check-windows-buffered-failure.ps1 retains executable, module and source hashes.
The first-party `_test_nonblocking_pair` driver creates a native Windows
PIPE_NOWAIT byte pipe and installs both descriptors into caller-owned files.
Windows CRT refuses an oversized single write without progress. The named
counterpart therefore checks zero-byte refusal and actual multiargument partial
progress, including exact bytes received, EOF and both endpoint closes. It does
not fabricate POSIX partial counts or register T.nonblock on Windows.
The files-windows-platform.json manifest replaces the guarded source block
explicitly and executes it whenever T is present. Ten exact source-hashed spans
also map paths/devices, shell quoting/termination and native date ranges. Each
span links to the independently reviewed named counterpart and execution protocol.
`T.ada_emergency_tables` is an explicitly named Ada
counterpart for the C-specific 200-byte emergency allowance, with measured
table storage and actual allocation refusal/recovery. Its reviewed source mapping
is `tests/conformance/equivalents/gc-ada-instrumented.json`.

The macOS failing-stream driver in `conformance_platform.c` is first-party
native test glue. It replaces the descriptor of a fresh owned FILE with a
read-only `/dev/null` descriptor, preserving FILE/closer identity and avoiding
SIGPIPE or global signal-handler changes. Its separately named Lua counterpart
checks repeated buffered writes, flush errors, default stream restoration and
closure. The `files-macos-platform.json` candidate replaces both unavailable
`/dev/full` opens and separately checks Darwin's buffered-close error with
closed FILE ownership. The unbuffered zero-byte refusal and actual POSIX
nonblocking pipe assertions remain intact. The accepted GC/IO scope records
the independent mapping review and completed native-platform executions.

Upstream license notice (also retained in the pinned public `lua.h`):

Copyright (C) 1994-2026 Lua.org, PUC-Rio.

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
