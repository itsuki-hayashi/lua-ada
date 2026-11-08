# ADR 0026: Real base C closing ownership

Date: 2026-11-08, Asia/Tokyo. Status: scoped implementation.

## Context

Lua permits a host to call `lua_toclose` directly on its idle API stack.
Its auxiliary buffer implementation relies on this base CallInfo behavior.
Requiring an active C callback incorrectly rejects that ordinary public use.
A valid registration also makes no allocator request in the pinned runtime.
The existing Ada closing entries captured an upvalue cell and grew a frame
vector, neither of which represents the public C slot's actual ownership.

## Decision

Each execution context reserves one base C activation during construction.
It acquires its real scalar window lazily, without inserting a function slot
or manufacturing a C function pointer. Its offset is zero, its callee is nil,
and its internal name excludes it from public debug levels, as the pinned
base CallInfo is excluded. It carries no native-call charge. Ordinary root
calls retain the activation; actual state closing includes it in the same
iterative `@close.thread` walk. Retirement clears it in place and retains its
reserved metadata until physical context destruction.

C closing predecessors occupy a typed array reserved with the scalar/cell
stack arrays. A real frame retains only its absolute closing-head index.
`lua_toclose` writes the existing slot's predecessor and the real frame head;
it captures no upvalue, copies no value and grows no closing vector. The
ordinary `@unwind` driver consumes these links and reads the actual scalar
slot. Normal return, error recovery, settop, closeslot and state close use
that driver. Lua closing entries keep their lexical-cell ownership. An
additive `Close_Entry.Stack_Level` identifies an actual scalar when applicable;
zero preserves the private packet backend's existing cell path.

All three stack arrays reserve before any length publication and shrink by
preparing typed prefix owners before moving any of them. Closing links are
metadata, never a second set of value roots. Collection traces the actual
scalar windows and independently owned lexical cells as before.

Reset/error cleanup additionally has a context-owned `Closing_Stack_Prefix`.
Its setter publishes only a live interval and recomputes real stack bounds;
it copies no values and blindly clears no former interval. Window retirement
clears only above that prefix, and union tracing includes both the prefix
and all surviving real windows. Canonical closing entries record their actual
absolute slot. A cleanup owner must preserve its previous floor, lower the
prefix to each pending close level and restore that floor on completion.
This primitive is implemented; automatic error/reset callers are separate
checkpoints and are not certified by its internal lifetime tests alone.

### Public reset and self-close extension

The reset caller now uses the same physical windows, closing links and saved
prefix floors. It first adopts held error scopes after their genuine C guard
acknowledgements, then retires abandoned execution top-down. Frozen lexical
cells and the actual scalar prefix retain pending closers and pre-close locals.
The existing iterative close controller lowers the prefix per handler and
publishes either an empty reset stack or the actual final error object. It
clears pending error-recovery continuations before starting this new execution.

A self-close is a distinct typed C action. It marks live guards for that
addressed state and unwinds only the nearest C checkpoint. Each reader,
writer, formatter, warning or foreign callback owner performs its own cleanup
and echoes its actual callback identity before propagation continues. Only
the final guard starts reset. This avoids both jumping over waiting Ada
finalization and executing old Lua PCs after a C body has been abandoned.
An Ada-owned borrowed callback returns the same action to its existing driver;
it does not start another executor. A recursive request during a closer keeps
the genuine outer native-depth base.

Each C surface reserves an idle reset driver, one transport record and eight
real continuation frames with bounded argument/error/result capacity. Normal
execution cannot consume this frame pool. It covers the bounded reset/close
controllers and a simple C handler without a new allocation after refusal.
Ignored C close results stay in the actual scalar window for return inspection;
no unused packet is materialized. Reserved packet owners are copied into
already reserved destinations rather than moved away between closers. This
does not promise allocation-free arbitrary Lua handlers, hooks or metacall
chains. Those still use the actual allocator and the original work budget.

The extra metadata belongs to the same context/provider and is destroyed once
with that context. It introduces no new value store or reference runtime.
Protected reset errors retain their real Lua object and status. A self-reset
error preserves the pinned outer-resume publication (the reset error followed
by the terminal resume copy); subsequent non-self reset consumes that failure
and leaves the normal zero-status reset thread.

Thread C surfaces are prepared during thread construction when the world's
main C surface exists. The first borrowed C entry into an Ada-only session
prepares existing contexts before invoking native code. `lua_tothread` and
thread `lua_topointer` subsequently borrow that stable context-owned surface
without allocating. Extra-space initialization and physical release retain
their existing ownership rules.

## Alternatives and consequences

A separate auxiliary-buffer guard list would duplicate closing ownership
and miss ordinary host C slots. A lazily allocating base registration would
violate the observed refusal behavior. Reserving a close vector when every C
frame is entered was tried and rejected: cached Lua-to-C frame reuse could
allocate before an existing `T.alloccount()` callback restored refusal. The
retained iterator refusal assertion exposed that error and remains unchanged.

The context now pays for its reserved base activation and one small link per
physical scalar slot during construction or stack growth. Cached frames need
no extra registration allocation. There is still one allocator, universe,
grammar and iterative executor. Every callback returns through the existing
C-owned guarded transfer; no C callback is invoked within an Ada dispatch.

## Verification and limits

The [component record](../sessions/2026-11-08-base-c-closing.md) records strict
default/static builds, thirteen identical C cases matching both native
configurations and thirteen named AUnit wrappers within 1,695 passing cases.
The retained persistent-refusal iterator test and twelve other C consumers
also pass. This decision does not certify `lua_closethread`, initial coroutine
function-stack behavior, logical error-scope retirement, auxiliary buffer
completion, integrated Ada T/shared/platform gates or full upstream acceptance.

The later [reset record](../sessions/2026-11-08-thread-reset.md) separately
verifies this extension with 24 native-default C matches, 23 native-T matches
and one explicit warning-lock skip, 15 named new cases within 1,737 AUnit
cases, sixteen passing standalone C contracts and refusal/recovery sweeps.
Initial coroutine function slots, integrated Ada T/shared/platform and final
upstream acceptance remain open. Native partial-reader reset skips parser
scratch cleanup; that diagnostic failure is retained separately while Ada's
additional borrowed-reader regression requires balanced ownership.
