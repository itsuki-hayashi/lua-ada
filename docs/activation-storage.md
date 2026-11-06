# Context-Owned Activation Storage

Each execution context owns its reusable activation records. This guide
documents their implemented ownership contract; allocation-free error delivery
and complete C allocation/layout parity retain separate acceptance obligations.

## Borrowing and publication

Every Frame has one stable Context owner and the same universe Memory owner.
The Context link also identifies its shared scalar-stack window owner.
There is no process-global frame cache or current-allocator fallback.

New_Frame(State, Context) first borrows a clean record from that context's
intrusive cache. If none is available, it allocates through the explicit
universe subpool and binds every managed component before returning. The
New_Frame(State) convenience overload selects State.Current and rejects a
missing context. Passing another universe's context is private API misuse.

The caller publishes a borrowed record in Context.Stack before performing any
later allocation that can reach a collector safe point. Machine reserves the
activation-stack capacity first and uses its existing central rollback path
for partially initialized calls. Lifecycle distinguishes Active, Retiring and
Available records. A record belongs to one active stack or one cache list;
caller-local ownership exists only during this explicit construction gap.

Debug inspection and collector frame traversal visit active stacks, never the
cache. Cached capacity is real allocator-owned storage, but it is not a live
Lua frame and does not consume semantic stack slots or call-depth quota.

## Retirement and retained capacity

Machine.Release_Frame first balances foreign windows, hook/message/unwind
state, semantic slots, non-yieldability and native-call depth. It then passes
the detached record to Engine.Return_Frame. Return nulls the caller's pointer
after transferring ownership to the context. A stale alias cannot return an
already Available record a second time.

Retirement detaches canonical open-cell associations before clearing register
storage. Actual captured cells retain their authoritative values and survive
through closure ownership. It clears every retained Lua value and pointer,
including captures, pending results, error packets, close entries, callee,
scope, source program, handler and unwind state. An Available frame contains
no hidden strong edge to a table, closure, thread, cell or program.

Clear preserves each managed container's capacity. Private packet registers
also preserve their nested buffers: shrinking the outer packet vector would
finalize those rows and lose their reserved emergency capacity. Active_Registers
separates live private rows from the cleared retained arena. A later smaller
activation can reuse that arena without exposing inactive rows as GC roots.

Allocation-free result delivery can move an entire packet into another traced
owner. The moved-from packet is intentionally empty and unbound. Retirement
rebinds emptied packet owners explicitly; merely calling Clear would otherwise
leave a later append without an allocator. It never replaces a Frame with a
default aggregate, which would finalize and copy controlled components.

Outgoing results must be published in another traced owner before their source
frame is returned. A cache does not make a borrowed register/packet view valid
after retirement. Tail calls, callbacks, closing and protected failures obey
the same ownership transition.

## Context teardown

Destroy_Frames(State, Context) destroys both active and cached lists exactly
once. It bypasses recycling and invokes no Lua __close handler, including when
collection reclaims an abandoned coroutine. It removes owning links before
typed deallocation and runs while the context and universe owner remain live.

Suspended native frames retain their context-local native depth. Scheduler
yield has already excluded that depth from the universe's active resumer-chain
count, so destroying an unreachable context must not subtract it a second time.
Context-local counters and borrowed frame pointers are cleared at teardown;
complete world finalization clears the remaining global count. Instruction
budgets are never reset by caching or GC.

## Boundaries

Retained capacities appear in actual allocator statistics. This cache neither
imitates C CallInfo sizes nor claims C allocation-count equality. Caching itself
does not remove ordinary packet copies, perform emergency retry for every managed
growth, or guarantee delivery under permanent allocation refusal. The integrated
shared-window checkpoint below advances argument/result storage separately.

## Verification

The 2026-11-06 Windows/default/static validation checkpoint passed strict GNAT
16.1.0 compilation and all 951 AUnit cases, including eleven focused cache
cases. They cover stable identity, per-context ownership, retained packet and
nested-arena capacity, continuation reset, real-cell detachment, root removal,
permanent-refusal reuse, duplicate-return rejection, teardown and active-chain
depth preservation while an abandoned native context is collected. The latter
case includes a nonzero active main boundary, preventing a vacuous zero-count
assertion.

The complete retained pipeline passed the Ada consumer, 35 CLI contracts,
10 binary CLI C/Ada comparisons, 11 differential fixtures and five unchanged
upstream execution files. The coroutine file retains its documented T-absent
omissions. A separate frontend campaign passed 85 opcode definitions and 4096
words, 10000 byte inputs, an allocation-pressure diagnostic, 2000 grammar
inputs with 2000 mutations and lex/parse checks for all 34 unchanged upstream
files. That campaign executes no Lua source.

Local evidence is reports/m3-activation-cache-build3.log,
reports/m3-activation-cache-tests2.log, reports/m3-activation-cache-check1.log
and reports/m3-owned-numeric-frontend.log. The full-pipeline log includes the
final strengthened depth case. Earlier local attempts exposed a missing
unrelated driver import and an incorrect double subtraction of suspended
native depth; both were repaired before the passing run. Other platforms,
profiles, C-consumer checks and final-revision full M3 acceptance remain
separately recorded requirements.

## Shared arena component checkpoint

This is historical component evidence, superseded for current runtime selection
by the integrated checkpoint below. Its temporary test bridge has been removed.

The later Windows/default/static component build passed strict compilation and
987/987 AUnit cases, including nineteen Lua.Stack_Storage_Tests cases. The
private Engine.Stacks helper now provides paired physical reservation, stable
absolute indices, authoritative cell access/detachment, physical tail clearing
and allocation-free ordered-union tracing. Its physical Reserve never publishes
a semantic stack top: the current real frame can reserve less than a wide
ancestor, whose dead tail is reusable. Window/predecessor metadata is present,
but the production VM and collector still use their previous register path at
this checkpoint.

The component tests explicitly bridge Trace outputs into pre-reserved existing
operation/native-cell roots before invoking the old collector. This validates
the helper's overlap, prefix, cell and refusal decisions independently; it does
not validate integrated production shared-stack execution or collection. The
bridge must be removed for that later integration evidence. Initial stack
reservation, overflow phases and direct argument/result windows remain parts
of the coordinated Machine/Canonical migration.

Evidence is reports/m3-shared-stack-component-build1.log and
reports/m3-shared-stack-component-tests1.log. No complete pipeline, C consumer
or additional platform run is implied by this component-only checkpoint.

## Integrated shared windows

The subsequent strict Windows/default/static build passed 1009/1009 AUnit cases.
Canonical execution and the public C stack now share Context.Foreign_Stack and
the parallel Context.Stack_Cells arena. Registers, arguments and results use
absolute indices; growth never leaves a retained vector-element address in a
frame. An open cell is authoritative. Writes synchronize it, closing detaches
its association, and the cell can outlive every stack window through closure
ownership. Native continuation packets remain additional explicit roots.

Physical initialized storage, current real-frame ci.top, logical C API top and
the host prefix retained during a drive are distinct. Stack_Used describes the
current actual window's reserved end, rather than the maximum ancestor end.
A tiny child can therefore reuse a wide caller's dead tail. Each actual window
borrows its predecessor; retirement restores the predecessor's current extent
in constant time. Internal protection/continuation holders have no artificial
scalar window or twenty-slot Lua-frame charge.

Hidden varargs retain the original argument prefix at Call_Base when R0 shifts.
The collector marks the union of ordered Lua/native live windows, including
that prefix and the host-owned stack prefix. A currently entered top C frame
uses its actual API top; a waiting C caller uses its saved live prefix while
Lua executes above it. Gaps and the initialized tail are cleared only after
validating the complete window ordering. Clearing each parent's dead tail would
corrupt overlapping child data; tracing all initialized capacity would retain
dead values. Live cells are traced through their actual value, and stale scalar
caches are refreshed without allocation.

Native tail-call continuations retain the logical Lua caller through pending
native work, hooks, closing and errors. Captures and outgoing results remain
rooted during that transition. Complete call-origin/name attribution retains
its separately tracked obligations.

## Stack growth and overflow policy

The selected configuration supplies the pinned semantic maximum. Default builds
use 1,000,000 slots. A new context starts with an allocated semantic bound of
40 slots plus five physical extra rows, and the base C reservation has inclusive
top 20. A requested inclusive last offset must stay below the allocated bound.
Normal growth follows the pinned 1.5 strategy capped at the semantic maximum.
The first overflow reserves the maximum plus 200 error slots and five extra
rows, then reports the catchable stack-overflow error. Further growth beyond
that error bound produces error-handler failure; nonraising C checks return
false instead. This replaces the former private 4096-slot cleanup allowance.

The bound describes initialized stack policy, not an invented C byte size.
Managed vectors may retain larger physical capacity after geometric growth;
selected-provider statistics report their real storage. Physical Reserve obtains
and initializes both arenas before callers publish a new semantic top. A refused
pair can retain newly acquired spare capacity but preserves the old initialized
lengths and live values. One allocation-free emergency collection can precede
the retry. A raw freed address can be reused by a successful arena allocation;
reclamation tests therefore identify Lua objects by their immutable serials.

The 1009-case run exercises the actual production collector with the component
bridges removed, plus shared-window execution, hidden varargs, overlap, native
tail calls and overflow regressions. Evidence is
reports/m3-shared-windows-build5.log and reports/m3-shared-windows-tests4.log.
The complete Windows/default/validation/static pipeline also passed the 32-case
C consumer, retained five upstream execution targets, API/CLI contracts and
first-party differential fixtures. Its log is reports/m3-shared-windows-check1.log.
These local checks do not imply final-revision platform acceptance.

Ordinary packet copies, complete allocation-free delivery under permanent
refusal, provider-visible object categories, actual cache/arena shrinking and
complete call-origin attribution retain separate work. GC measurements must use
the selected provider's real live bytes/counts, rather than semantic capacity
estimates or imitated C layouts. Full upstream, allocator and C API parity are
not established by this storage checkpoint.
