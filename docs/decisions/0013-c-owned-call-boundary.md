# ADR 0013: C-Owned Calls over the Iterative Driver

- Date: 2026-11-06
- Status: accepted
- Scope: the foreign-call boundary; complete C API acceptance remains pending.

## Context

Lua C callbacks may raise errors through nonlocal transfer and may call back
into Lua. A C `longjmp` must never cross a live internal Ada activation. The
runtime already has one explicit scheduler, stable cells and traced activation
packets; saving or recursively reentering Ada executor stacks would discard
those ownership guarantees.

## Decision

The private engine's driver exposes one-step execution and typed pending foreign
requests. A foreign native activation first publishes arguments in its owning
context's C stack window, then returns. Only after the Ada dispatcher returns
does the C boundary establish a live C guard and invoke the real function
pointer. C results and arbitrary error objects return as explicit packets; the
scheduler performs their ordinary Lua result adjustment and protected unwind.

Reentrant C calls add explicit protected sentinels to the same driver. A nested
C pump stops at its own sentinel and restores its caller's stack window. It does
not recursively call `Machine.Run` or `Engine.Execute`. The driver's retained
world/context references are borrowed for a documented lifetime; managed driver
allocation belongs to that world, with no process-wide current-world pointer.

Ordinary Ada execution can lend its existing driver to the same C boundary.
General access views express that borrow; separate pool-specific owner pointers
identify the allocations the C facade may free. Context-owned C surfaces may
retain their owning world's stable address, while the lent driver view is
restored before its Ada Run activation ends. C cannot close an Ada-owned world.
This does not add public Ada callback registration or object handles.

The narrow borrowed-invoke helper establishes its C guard above the waiting
Ada host frame. A host quota or physical host abort propagates through every
nested C guard as a private abort action, bypassing protected Lua error returns.
That outer helper then returns the action to Ada; it does not terminate the
Ada host. Pending scalar C boundary records are released without Lua callbacks
or budget resets. C-owned outer boundaries retain their panic/abort policy.

Zero-upvalue C functions use actual function-pointer identity. C closures with
upvalues own the same stable cells used by pseudo-index reads and mutations.
Their frames do not copy old upvalue values into extra collector roots: replacing
an upvalue must allow its previous weakly referenced value to die during the
callback. Pending arguments, result packets and real closure/cell references
remain traced across every callback boundary.

Source and binary buffer loading adopt the real canonical program graph without
executing it. Production C glue contains startup, ABI marshalling, callback and
nonlocal-transfer mechanics; it links no reference interpreter object.

Windows x86-64 partial linking uses the configured Ada compiler and GNU linker's
`pe-bigobj-x86-64` intermediate format. The merged closure exceeded ordinary
COFF's section limit at 34,845 sections. This changes only the intermediate
object representation and preserves compiler/runtime checks. GPR documents the
[partial-linker attribute](https://docs.adacore.com/gprbuild-docs/html/gprbuild_ug/attributes.html);
the selected installed linker reports support for this format.

## Alternatives and consequences

Directly invoking a C callback inside Ada would expose live Ada frames to
`longjmp`. Recursively invoking another executor for a nested API call would
split budgets, roots, close boundaries and suspension state. Both alternatives
are rejected. Explicit driver phases require more state and ownership comments,
but make transfer and cleanup reviewable without relying on abandoned stacks.

Message handlers now use protected holders and explicit scheduler phases above
the intact failed stack. A recursive handler error targets the same holder;
the eventual transformation or error-in-handling result unwinds the failed chain
once. Internal close protection inherits the active handler, and transformed
errors carry handled metadata across C guards to avoid applying it twice.
Nil is normalized after the handler, following pinned Lua 5.5.1 behavior.

Continuation, yielding and C-resume phases must extend this same protocol.
Yieldable non-null call continuations still fail explicitly before execution.
Non-yieldable calls ignore an unused continuation and return synchronously,
matching pinned Lua.
This checkpoint supplies no substitute success stubs for missing APIs and does
not establish complete C ABI, stack-accounting,
allocator or upstream-instrumentation parity. Ada builtins still need stable
C trampolines for full `lua_tocfunction` and open-library behavior.

## Verification

The Windows validation/static standalone consumer passed twenty-six named cases,
including real callbacks, mutable C upvalues, table error identity, nested C
calls, canonical Lua calling C, native/Lua handlers, recursive errors, permanent
callback refusal, panic recovery and independent-world reentry. The strict Ada
regression suite passed 877 cases, including eleven focused message-handler
regressions. A reserved false/error packet and traced boundary storage avoid
allocation during the tested C failure publication path. Full Lua memory-error
parity still needs reusable metadata and shared stack capacity. Required
cross-platform/static/shared acceptance remains separate evidence; continuation
and same-world cross-thread calls still need their own real tests.

The later borrowed-driver checkpoint passes 1,085 AUnit cases and retains 39
standalone C consumer cases in Windows validation/static. Six separately named
mixed-language cases execute a real C addition callback, nested C-to-Lua calls,
arbitrary protected errors, an uncatchable bounded quota inside C lua_pcall with
subsequent session recovery, deferred warning reentry and a deferred warning
error. Five semantic fixtures pass independently against pinned C Lua; the host
quota case tests the explicitly bounded Ada policy. Reports are
`reports/m3-borrowed-pump-tests1.log` and
`reports/m3-borrowed-pump-c-consumer1.log`. Full continuation and platform gates
remain pending.
