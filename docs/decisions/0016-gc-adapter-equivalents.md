# ADR 0016: Real Collector Inspection and Storage Equivalents

- Date: 2026-11-07
- State: implemented candidate; independent conformance review pending
- Owners: `Lua.Engine.Collector`, test adapter, conformance runner

## Context

The pinned tests combine observable Lua behavior with C collector colors and
fixed byte allowances. Ada uses separately owned capture cells, controlled
packet containers and different table/frame sizes. Pretending that those
objects have C colors or consume C bytes would conceal real ownership defects.
Conversely, a guard returning early without T cannot establish that its
failure/recovery behavior was exercised.

## Decision

The test adapter returns actual storage and collector measurements and calls
real public C exports for userdata, warning callbacks and native descriptors.
`T.checkmemory` checks the actual Ada allocator headers, registry/list ownership,
heap/code edges, active stack windows and finalizer queues. The allocator header
type is shared through the private storage specification; the inspector exists
only in the test crate. No copied private C layout is interpreted as Ada data.

Running-thread roots are rescanned at atomic. Temporary native argument packets
published at the enter-atomic boundary therefore do not eagerly mark values
that disappear before that rescan. Live registers still retain their objects;
heap writes retain their forward/backward barriers. Backward barriers during
incremental sweep mark their already-live owner gray; completion removes the
revisit links after sweeping, before a later cycle can reclaim those owners.

Plain table reads bypass allocation when no delegation is needed. GC control
results move into caller-owned actions, and unprotected result delivery may
borrow an independent action packet across frame retirement. This preserves
normal returns under actual allocator refusal without turning off fault
injection. Packets owned by a retiring frame still receive an independent copy.

The `gc-ada-instrumented` equivalent candidate replaces only source-hashed spans:

- Measure live storage before collecting the weak long-string graph and require
  both original 4 MiB payloads to be reclaimed. Empty Ada table capacity is not
  constrained to the C one-KiB residual allowance.
- Observe the actual gray child of a black independently owned Ada capture cell,
  preserving the same-cycle weak coroutine collection and final captured value.
- Allocate 200 real tables under a ceiling of one measured Ada table beyond
  current live storage. Require actual refusals and emergency collection retries,
  retain the enclosing operation roots and restore the test ceiling afterward.

The equivalent generator preserves upstream source bytes and rejects drift,
overlap, missing counterparts and unreviewed acceptance. An explicit diagnostic
mode emits `diagnostic_only: true`; successful execution cannot itself approve
the mapping. Scope acceptance must separately validate review and original-C
evidence. These candidates do not close full M3 or the four-file batch.

## Alternatives and consequences

Returning invented C colors/bytes, increasing an unexplained fixed allowance,
disabling allocation failures or dropping guarded assertions were rejected.
Changing Ada's stable cells to C open-upvalue layouts would change ownership
architecture without improving the tested lifetime guarantee. Each proposed
equivalent instead has a named focused regression and retains its ordering and
cleanup obligations. Native-platform differences require their own mappings.

## Verification implications

Require default and instrumented regressions, negative inspector/generator tests,
complete state-close execution, balanced allocator telemetry, source/runner
hashes and independent mapping review in every applicable acceptance context.
The session record owns incremental results; this decision records no new
accepted upstream pass.
