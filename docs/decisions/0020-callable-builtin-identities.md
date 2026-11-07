# ADR 0020: Callable scalar builtin identities

- Date: 2026-11-08, Asia/Tokyo.
- Status: implemented scoped checkpoint; local default validation completed.
- Scope: native function identity, C invocation and real result publication.

## Context

The interpreter already distinguishes stateless primitives, captured Ada
closures and actual foreign C functions. Ordinary named library construction
previously allocated a new native closure even without captures. That made
repeated `ipairs` iterators unequal, left `lua_tocfunction(math.deg)` null and
formatted a scalar builtin as a null `%p`. A fabricated pointer or identity-only
stub would not satisfy C consumers that save, push or directly call a function.

Native execution uses explicit scheduler activations and packets. Returning a
packet alone also leaves debug return hooks looking at old arguments rather
than the actual outgoing values. Return ranges, setters and tracing must refer
to the same physical scalar window.

## Decision

`Lua.Builtin_Registry` owns a strong enumeration and immutable name lookup for
161 existing primitive/library/iterator implementations. It retains the sixteen
original primitive identities. An adjacent C X-macro list defines one real
`lua_CFunction` wrapper per ID. Standalone-library initialization checks the
count, every ordinal/name and non-null callable address. C converts function
pointer bytes through checked same-size `memcpy`; no integer tokens or foreign
universe-specific callback objects represent these functions.

An uncaptured known builtin is a scalar ID. It needs no heap closure, universe
cache or hidden root. Captured functions keep distinct owned closures and real
stable cells. C push/inspection recognizes the actual wrapper address and
reconstructs the corresponding scalar or captured Ada callable. Ordinary Lua
calls continue to select the existing Ada phase directly. Strict/lax UTF-8
iterators have distinct stateless identities, as the pinned implementation does.

A direct C pointer call enters the existing guarded foreign pump on the same
driver, context, allocator and work budget. A hidden `@builtin.direct` phase
borrows the original C callee/capture owner and selects its semantic operation
through the scalar ID. This phase adds no public logical frame, hook event or
native-depth charge. The semantic operation retains its normal yield policy.
Subdrivers share `Native_Operation_Name`; no parallel library implementation or
executor is introduced. A real C continuation owns completion after a yielding
callback abandons the original C stack. Errors and host aborts retain the typed
C-only transfer boundary from ADR 0013.

Finishing visible Ada builtins publish their actual result range into the same
physical window used by inspection and collection, before a return hook runs.
Placement follows the pinned operation's stack transformation, not equality of
input/output values. A phase that normalizes its top can retain that decision
as scalar metadata rather than repeating a user callback. Publication retires
obsolete argument/capture/result packets while retaining the actual raw result
borrow until its continuation owns it. Internal phases without a physical
window do not fabricate one for inspection.

`pcall` and `xpcall` retain their real activation on protected failure so their
ordinary return phase exposes status/error values and a return hook. Reserved
error packets move into the caller before their owner is retired, preserving
permanent allocator-refusal behavior without another workspace allocation.

## Alternatives and consequences

Caching a fresh zero-capture closure by name would introduce immortal heap
objects solely for identity. A shared dispatcher address without per-function
identity would conflate distinct functions. Non-callable markers would break
direct invocation. Calling C from a waiting Ada scheduler phase would expose it
to nonlocal transfers. Reentering another executor would split roots and policy.
Those alternatives are rejected.

Registry descriptors are first-party source and require synchronized review.
Startup validates the complete C/Ada map before state construction. Optional
library exports remain controlled by their existing configuration; a registry
entry does not publish an otherwise disabled export. Pointer formatting remains
implementation-defined, but actual callable identity is stable and distinct.

Managed continuation storage may allocate; this decision makes no native private
allocation-layout/count claim. Direct C invocation follows the standard C
function result-tail/count convention. It does not establish equivalence of
every private intermediate stack workspace inside the C reference libraries.
No reference interpreter is linked into the Ada image.

## Verification

The default Windows/validation/static root, C consumers and nested test builds
pass with the strict Ada policy. All 1,515 AUnit cases pass, including thirteen
native-backed result-window cases and two real direct-C budget/error cases.
The unchanged fifteen-case builtin C consumer passes Ada and both pinned native
configurations with byte-identical output; the twenty-case C debug consumer and
retained C/foreign consumers pass. Fifty-one observed native operation labels
match the first-transfer/count ranges. The native hook library's own extra
registry-table scratch slot is not fabricated in the Ada activation; that
observation does not establish private workspace parity.

The [component session](../sessions/2026-11-08-callable-builtins.md) records
repaired validation failures, commands and limits. Complete configuration,
shared-library/platform and full upstream acceptance remain final-delivery
gates. External strings, remaining core exports and auxiliaries are later
checkpoints in that delivery.
