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

Its applicability now includes default and upstream-test configurations: the
weak-string residual-storage assertion is unconditional in the original file.
The capture-color and fault-injection replacements remain inside their original
T guards. Default execution records the exact T-absent omission and cannot
certify those guarded obligations. The candidate name is retained for continuity;
the manifest configuration field owns applicability. Independent review remains
pending for both configurations.

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

The Windows files.lua candidate has a separate native-platform manifest.
Native descriptor drivers are compiled independently against both runtimes.
A closed-reader pipe supplies real buffered flush refusal; a PIPE_NOWAIT pair
supplies real unbuffered refusal and multiargument partial progress. Windows
CRT does not transfer part of an oversized individual write, so its equivalent
checks earlier arguments delivered before a later refusal and verifies the
reader's exact bytes. FILE pointers, C closers and external ownership metadata
are retained by replacing only descriptors. All temporary native handles are
owned or closed before any potentially raising Lua API call.

Other Windows mappings use native temporary basenames, NUL, actual forced
TerminateProcess statuses, cmd.exe quoting and representable calendar ranges.
No broad port/soft flag is set. The guarded Windows partial-write block is
explicitly replaced and executed with T; default omission remains linked to
that instrumented counterpart. Original file bytes remain pinned. These
mappings are candidates, not independent acceptance decisions.

The test launcher interposes on the actual universe allocator provider after
counting existing managed blocks. It delegates every request to that provider,
tracks successful allocation/release results, and snapshots owner-side refusal
counts during live callbacks. The observer is linked only into test executables.
Shutdown never dereferences the destroyed owner: the sidecar uses retained
counters and fails on any nonzero balance or observer fault.

The shared CLI records typed exits until its owned execution scope has returned.
Normal completion and exit(true) perform Lua state closure; exit(false) performs
only physical host disposal, with no Lua close handlers. The test Finish hook
then verifies balance before the C process exit is honored. Production supplies
no observer hook. This ordering preserves typed exit codes and prevents a C
exit from bypassing the Ada process driver's physical cleanup evidence.

## Verification implications

Require default and instrumented regressions, negative inspector/generator tests,
complete state-close execution, balanced allocator telemetry, source/runner
hashes and independent mapping review in every applicable acceptance context.
The session record owns incremental results; this decision records no new
accepted upstream pass.
