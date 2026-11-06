# Architecture

The M1 runtime and M2a frontend are accepted. M2b extends the runtime with core
metamethods, resumable native calls, libraries, and text loading, with all platform
gates verified in [M2b validation](docs/validation-m2b.md).
Complete Lua and C compatibility remain later
gates. [Decisions](docs/decisions/README.md) record compatibility tradeoffs.

## Components and dependencies

```text
Batch CLI / Ada host
        |
  Lua.Sessions / Lua.Syntax       Partial C facade
        |                               |
  Lua.Engine (private) <----------------+
     |          |
  Compiler    Machine / native continuation drivers
     |          |                   |
  Parser     values / heap      library helpers / source files
     |          |
  Lexers     roots / collector
                |
         integers / numbers / narrow platform numerics
```

The root library never depends on AUnit, CLI, or reference C sources. The C
oracle and ABI experiments are separate test artifacts. `Lua.Engine` and its
descendants are implementation units beneath a private ancestor; public clients
cannot depend on register layout or heap addresses. No serialized bytecode
compatibility is implied.

The [real-world module fixtures](tests/modules/README.md) are future consumer
compatibility inputs. They are separate from implementation/API references,
excluded from GPR source paths, and introduce no runtime dependency.

| Component                 | Responsibility                                              |
| ------------------------- | ----------------------------------------------------------- |
| Lexers / Parser           | Incremental scanning, owned resolved syntax, limits         |
| Numbers / Integers        | Exact conversion, wrapping arithmetic, comparisons          |
| Engine.Compiler           | Select text lowering or checked native binary decoding      |
| Engine.Machine            | Iterative scheduler, Lua/native/C transfers and protection  |
| Engine                    | Values, metatables, heap, roots, tracing, lifecycle         |
| Engine library helpers    | Strings, patterns, packing, UTF-8, bounded table/math work  |
| Engine native drivers     | Stateful iterators, Lua callbacks, text and package loading |
| Sessions / Syntax         | Small owned execution and independent checking interfaces   |
| CLI / source file helpers | Batch streams, preambles, diagnostics, process status       |

## Compilation and execution

One incremental scanner feeds an owned parser/resolver. Indexed discriminated
syntax nodes retain source order, lexical symbols, captures, and label targets.
Lua.Syntax.Check validates this representation without VM/runtime allocation.
Lua.Canonical_Compiler lowers it to the pinned typed instruction words. Declaration
lookup happens at the source point; later shadowing cannot retarget a capture.
Nested runtime functions retain ordered references to stable capture cells. See
[ADR 0006](docs/decisions/0006-shared-frontend.md) and
[frontend compatibility](docs/frontend.md).

Lua.Opcodes defines the pinned 32-bit instruction format. Production execution
now uses scalar canonical registers and explicit top/result adjustment. The
older packet instruction lowerer remains an internal migration comparison path
until the expanded platform acceptance is complete. Native continuation frames
still own argument/result packets; they do not turn a Lua scalar register into
a permanent multivalue container.

Lua.Prototypes owns canonical graphs separately from runtime values. One managed
program owns nodes, byte strings, words, constants and debug records. Runtime
wrappers retain its actual nodes and materialized constants; shared graph
ownership ends when the final reachable wrapper is released. Lua.Chunks validates
and decodes native binary graphs, and serializes a selected real subtree without
changing the owning root. Text checking still uses the independent frontend.
See [canonical ownership](docs/decisions/0012-canonical-program-ownership.md) and
[binary verification](docs/binary-chunks.md) for current evidence and limits.

Open captured registers refer to stable individually owned cells. Reads/writes
consult those cells; CLOSE detaches associations so reused registers create
fresh instances. Closing snapshots preserve the exiting stack value before a
handler can mutate a closed upvalue. Outgoing results/errors remain rooted
through cleanup continuations. Collection traces only live canonical stack
slots and authoritative open cells, preventing stale temporaries from retaining
weak values. Debug inspection uses real local PC lifetimes and ordered captures;
call-name inference scans actual caller words lazily when requested.

Each context has an explicit activation stack; one iterative scheduler drives
context transfers without mapping Lua recursion onto Ada recursion. Tail calls replace activations. Protected calls establish VM
boundaries; errors unwind VM frames to the nearest boundary. Resource failures
leave the VM altogether so Lua cannot restart an exhausted budget.

Native activations use that same stack. A native step completes, requests a
Lua/native call, or requests another bounded step. It stores continuation phase,
arguments, captures, and pending results in its owned activation before control
returns to the VM. A library callback never recursively starts an executor.
The instruction counter covers both frame kinds and helper loops/backtracking.
Language errors unwind abandoned native phases as well as Lua frames; a new
chunk receives a fresh budget. See [ADR 0007](docs/decisions/0007-native-libraries.md).

Metamethod lookup is raw. Ordinary indexing, assignment, calls, primitive
fallbacks, and applicable library functions request handlers through the VM.
Raw library operations remain genuine bypasses. Each session owns its string
metatable; numeric-string arithmetic lives in its initial arithmetic handlers,
so user overrides remain observable. Callable chains have a separate bound
from index/newindex chains. Lua 5.5 equality selection and the absence of an
obsolete less-than fallback for less-or-equal are explicit compatibility rules.

See [runtime ownership](docs/decisions/0004-runtime-ownership.md) and
[embedding](docs/embedding.md).

## Ownership and collection

One limited controlled session owns globals, heap objects, prototype graphs,
context registry, per-context stacks/arguments/errors, and roots. Private discriminated
values distinguish scalars from string/table/environment/closure references.
Objects do not move. Ada finalization releases a universe but does not
substitute for tracing cycles.

[Full userdata](docs/userdata.md) owns inline C-aligned payload blocks,
independent logical size, traced uservalues and an object metatable. C borrows
the actual stable payload address. A reasoned first-party host cleanup
attachment is separate from Lua finalizer scheduling; generic userdata has no
implicit native destructor. Finalization and IO lifecycle integration remain
independent acceptance requirements.

An iterative stop-the-world mark/sweep collector traces globals, live frames,
register packets, environments/captures, arguments, named vararg tables, error
objects, table/type metatables, native-closure captures, native activation
arguments/results, module registries, and reachable compiled prototypes. It runs
at instruction safe points,
after temporaries have entered traced storage. Allocation itself does not
collect unrooted instruction temporaries. Dead table-key tombstones are cleared
before object reclamation. Repeated chunks can reclaim compiled code.

Tables currently use linear entries and insertion traversal. Sequence length
uses a valid contiguous-prefix border. Neither order nor C hash layout is a
compatibility promise. Weak tables/ephemerons and reachability-owned coroutine
contexts are implemented. Collector modes, barriers and finalization remain
later work. Coroutines share one universe through the iterative scheduler.

## Safety and platform constraints

Strong types, bounded indexes, contracts, private representations, generics,
and a tagged output interface express actual invariants. Scalars are not forced
into an inheritance hierarchy. Required warning/style flags and ordinary Ada
runtime checks remain enabled in every profile. Explicit modular operations
implement integer wrapping. Strings remain bytes.

Numeric text conversion uses standard Ada big integers for exact binary64
rounding; formatting implements Lua's 15/17-digit general format. The private
host-math adapter extends ADR 0005's pow boundary to the pinned transcendental,
decomposition and scaling primitives. [ADR 0011](docs/decisions/0011-host-mathematics.md)
records their names, IEEE/domain/rounding rationale and verification limits.
Argument handling and both xoshiro256** arithmetic paths remain Ada, with owned
per-universe random state and explicit native-work charging. Full C-facade
construction of independent reopened math libraries remains a later integration
requirement. No downloaded production dependency is introduced.
Packing and UTF-8 helpers use standard Ada types and explicit
byte/bit operations. Native pack widths and maximum alignment come from C
interface types, including long double; an isolated C99 probe verifies the host
layout. Virtual packsize arithmetic does not allocate. Semantic size overflow
is a Lua error; valid allocation/work quotas remain resource failures.

Text loading reuses the shared frontend and file preamble handling. A loaded
closure retains its initial environment rather than acquiring session globals
when called. Omitted and explicitly nil environments remain distinct. Module
loading uses owned loaded/preload registries and callable Lua searchers. The
public package fields initially expose those tables, but replacing a field does
not replace the registry root. The default search path is local and portable;
native loading and environment-driven initialization remain deferred.

Selective SPARK may protect suitable bounded algorithms; no whole-runtime
proof is claimed. Fuzz/proof tools are optional. AUnit and differential tests
provide current behavioral evidence.

## Future interoperability

The root Lua_Ada project owns one mixed Ada/C standalone library named lua.
Ada sessions, CLI clients and the C facade import its same world/storage units;
the former C-library GPR only forwards to the root build. Its explicit SAL
interfaces preserve child AUnit inspection while Ada privacy remains unchanged.
See [ADR 0014](docs/decisions/0014-one-core-library.md) for initialization, exports
and the real mixed-consumer identity checks.

The C facade shares the core without contaminating it with ABI layouts.
Early experiments investigate C allocation, varargs, callbacks, extra space,
startup/shutdown, and nonlocal transfer. No foreign longjmp may cross active
Ada frames. Status returns and C-only guarded checkpoints are feasibility
mechanisms, not a public Lua API.

Ada containers currently allocate outside a `lua_Alloc` callback. Full C
allocator parity needs replaceable storage and an allocation audit. Private
representations and absence of exposed handles preserve room for that work.
Binary chunks, C layouts/addresses, native modules, and LuaRocks have independent
future acceptance gates.

## Accepted M3 direction: not yet implemented

M3-02A now implements the ownership split: World registers private contexts,
each owning frames, arguments and diagnostic/error roots. The current-context
selector borrows a registered context and cannot switch while its driver runs.
Collection visits inactive contexts too; finalization releases every context.
Globals, heap, module registries, output and budgets remain shared. Contexts
live until world finalization. Suspension/closing transfers, hooks and coroutine
values remain planned; the direction below is not a claim those features exist.

The [M3 contract](docs/milestones/m3.md) expands the next milestone to complete
covered upstream behavior. Its first gate adds inventory/baseline infrastructure
only. The runtime described above remains implemented M2b behavior; the following
changes are intent until their numbered gates provide acceptance evidence.

Execution will move to canonical Lua 5.5.1 instructions and prototypes. The shared
owned frontend remains the only grammar/resolver. Canonical code generation,
upvalue/debug metadata and chunk import/export must pass before removing the
private packet backend; the opcode definition table alone is insufficient.

A shared universe will own allocator-controlled storage and objects, while
coroutine contexts own activation stacks, errors, hooks, suspension and closing
state. Stable cells and indexed tables precede full weak/finalized object support
and real incremental/generational collectors. Centralized writes supply barriers.
Catchable Lua allocation/stack errors remain distinct from explicit host aborts.

The C facade needs a reviewed foreign-API reentry portal for synchronous C calls.
It shares roots, contexts, allocator and counters, and never starts a new public
session execution or resets budgets. Ordinary Ada/native libraries continue to
request callbacks through explicit continuations. This future portal is not an
exception available to M3-01 production code. No foreign jump may cross active
internal Ada frames; nested errors, yields and panic need proven C-owned guards.

The planned public execution policy preserves bounded Ada session defaults and
offers deliberate Lua-compatible execution. The normal CLI and C-created states
will adopt compatible defaults at their later gates. A test configuration/ceiling
is not a hidden product default. Public C layouts, extra space, stable addresses,
external strings and allocator callbacks need actual runtime evidence, not an
adapter that fabricates reference results.

All changes keep strict compiler/style flags, runtime checks, readable comments,
focused AUnit cases and the standard-Ada dependency policy. Necessary C ABI,
varargs, stdio, lifecycle and OS glue stays isolated from interpreter logic.
Reference C Lua remains a separate oracle. Native upstream test fixtures enter
M3; the pinned ecosystem module fixtures remain future consumers only.

## Language lifecycle delivery

[ADR 0009](docs/decisions/0009-language-lifecycle.md) records the implemented
private-backend lifecycle design. Explicit scheduler transfers replace running
flags; context lifecycle and closing phase are separate. Each declaration owns a
stable cell, closures retain exact ordered captures, and jumps use resolver
frontiers to clean up scopes and create fresh declaration instances on reentry.
Closing and hook callbacks use owned native continuations; outgoing packets,
errors and temporary values stay traced across every callback.

The context registry uses stable reusable slots. Main/host contexts and active
resumers are roots; Lua-owned suspended contexts follow reachable thread objects.
Weak tables use ephemeron fixed points and dead-entry cleanup before sweeping.
Abandoned threads are reclaimed without executing close handlers. The collector
remains stop-the-world, without finalizers or incremental/generational modes.

Inspection uses prototype source ranges/names, actual local and upvalue cells,
logical native frames and per-thread hook state. The CLI selects compatible
execution quotas while Ada sessions remain bounded by default. Semantic stack
checks and physical-storage aborts retain separate failure policies. None of
these changes replaces the private instruction backend or fixes C ABI layouts.
