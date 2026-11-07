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
cannot depend on register layout or heap addresses. Checked native chunk
loading/dumping uses the actual canonical model; its tested interoperability
and remaining configuration gates are recorded in [binary chunks](docs/binary-chunks.md).

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
implicit native destructor. Finalizer scheduling and IO lifecycle integration
are implemented; the accepted GC/IO scope owns their bounded coverage while
complete public ABI acceptance remains separate.

The collector implements incremental marking/sweeping and generational minor
and major collection over actual managed objects and prototype graphs. Roots
include the live scalar-stack union, authoritative capture cells, native
argument/result packets, errors, registries, metatables and pending finalizers.
Incremental work runs at scheduler safe points; atomic reconciliation is
indivisible. Allocation refusal can restart a full emergency collection from
the published roots before retrying, so construction values must already have
an owning root. Dead weak entries and table-key tombstones are cleared before
object reclamation. Repeated chunks can reclaim compiled code.

Uncaptured scalar writes do not eagerly shade a transient weak read during
propagation. Their live intervals are published without an intervening
allocation and rescanned at atomic. Already traversed reachable suspended
threads remain on the gray-again list until that rescan. Captured-cell and
heap writes retain their barriers, including old-to-young edges. Consumed
condition temporaries are retired before allocating branch/loop bodies; lexical
bindings and short-circuit result operands retain their normal lifetimes.
The focused repairs have independent source reviews. Selected scope and final
publication evidence are recorded separately in [status](docs/status.md).

Tables use indexed lookup over owned entry storage and retain the applicable
Lua sequence-border rules. Neither iteration order nor C hash layout is a
compatibility promise. Weak tables use ephemeron fixed points. Finalizers are
queued and run through the ordinary continuation driver, including state-close
draining; physical disposal still completes when optional close storage is
refused. Coroutines share one universe through the iterative scheduler.

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
per-module random state and explicit native-work charging. The real C math
opener creates independently captured RNG state when reopened; native-matched
contract cases cover isolation and refusal cleanup. Selected runtime acceptance
is tracked separately. No downloaded production dependency is introduced.
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

## C interoperability and remaining acceptance

The root Lua_Ada project owns one mixed Ada/C standalone library named lua.
Ada sessions, CLI clients and the C facade import its same world/storage units;
the former C-library GPR only forwards to the root build. Its explicit SAL
interfaces preserve child AUnit inspection while Ada privacy remains unchanged.
See [ADR 0014](docs/decisions/0014-one-core-library.md) for initialization, exports
and the real mixed-consumer identity checks.

The C facade shares the same world, contexts, allocator and scheduler. Real
public calls, protected calls, resume/yield continuations and hooks return
through the Ada dispatcher before a C-owned guard invokes a callback or makes
a nonlocal transfer. No foreign longjmp crosses active Ada frames. Nested
drivers restore their previous caller and boundary ownership without resetting
the execution budget. See [ADR 0013](docs/decisions/0013-c-owned-call-boundary.md)
and [ADR 0017](docs/decisions/0017-c-continuations-and-resume.md).

Managed runtime vectors, byte buffers, scalar stacks and heap blocks use the
owning world's selected allocator. Allocation-refusal and balanced shutdown
cases exercise the actual public C boundary. Complete allocation-path auditing,
all public header obligations and drop-in ABI compatibility remain independent
acceptance gates. A selected source/API scope does not certify those wider
requirements. Reference Lua is built separately as an oracle and is never
linked into the Ada implementation.

## Implementation and remaining M3 gates

World registers private contexts, each owning frames, arguments, errors, hooks,
suspension and closing state. Main/host contexts and active resumers are roots;
Lua-owned suspended contexts follow reachable thread objects and can be
reclaimed before world finalization. Globals, heap, registries, output and work
accounting remain shared. Transfers use explicit scheduler state.

Normal text compilation and execution use canonical Lua 5.5.1 words, real
prototypes, scalar registers and source/upvalue metadata. Checked binary
load/dump uses the same representation. The owned frontend remains the only
grammar/resolver. The retained packet backend is a migration comparison path;
its removal requires the separately recorded expanded acceptance gates.

Ada sessions retain bounded defaults and offer deliberate Lua-compatible
execution. The normal CLI and C-created states select compatible defaults.
Catchable Lua errors remain distinct from explicit host aborts. Public layouts,
extra space, stable addresses and allocator callbacks need their own real
runtime evidence; a test adapter never substitutes fabricated reference values.
The [M3 contract](docs/milestones/m3.md) and [status](docs/status.md) own the
remaining aggregate, heavy, unrelated source/API, CLI and module requirements.
Exact final-head acceptance is recorded separately from implementation and
candidate adjudication; see the [conformance catalog](tests/conformance/README.md).

All changes keep strict compiler/style flags, runtime checks, readable comments,
focused AUnit cases and the standard-Ada dependency policy. Necessary C ABI,
varargs, stdio, lifecycle and OS glue stays isolated from interpreter logic.
Reference C Lua remains a separate oracle. Native upstream test fixtures enter
M3; the pinned ecosystem module fixtures remain future consumers only.

## Language lifecycle delivery

[ADR 0009](docs/decisions/0009-language-lifecycle.md) records the implemented
lifecycle design first delivered on the private backend. Normal execution now
uses canonical words. Explicit scheduler transfers replace running flags;
context lifecycle and closing phase are separate. Captured declarations own
stable cells, closures retain exact ordered captures, and jumps use resolver
frontiers to clean up scopes and create fresh declaration instances on reentry.
Closing and hook callbacks use owned native continuations; outgoing packets,
errors and temporary values stay traced across every callback.

The context registry uses stable reusable slots. Main/host contexts and active
resumers are roots; Lua-owned suspended contexts follow reachable thread objects.
Weak tables use ephemeron fixed points and dead-entry cleanup before sweeping.
Abandoned threads are reclaimed without executing coroutine close handlers.
Collector atomic tracing and generational minors are indivisible; incremental
marking/sweeping yields between work slices. Object finalizers and state-close
draining are implemented and separately exercised by the GC/IO scope.

Inspection uses prototype source ranges/names, actual local and upvalue cells,
logical native frames and per-thread hook state. The CLI selects compatible
execution quotas while Ada sessions remain bounded by default. Semantic stack
checks and physical-storage aborts retain separate failure policies. None of
these component results completes full C ABI or upstream-suite acceptance.
