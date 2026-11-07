# ADR 0017: C Continuations and Public Resume Windows

- Date: 2026-11-07, Asia/Tokyo
- State: accepted implementation and scoped contracts; final revision separately certified
- Scope: expanded-t-conformance, extending ADR 0013

## Context

coroutine.lua's T tests cross real C/Lua calls, protected errors, hooks,
independent states and repeated suspensions. A C continuation cannot retain
the original C stack. Publishing yielded results over a suspended activation's
live register window would also discard its rooted arguments and captures.
The public API must expose yielded values while the owning runtime preserves
the suspended execution state.

## Decision

Extend the existing explicit driver protocol with continuation function,
full-width lua_KContext and status fields. The scheduler publishes a callback
request and returns through the Ada dispatcher before C invokes that callback
or makes a nonlocal transfer. Resuming K is another explicit callback phase;
ordinary synchronous success returns to the original C body. Yieldable
protected-error recovery follows the pinned K semantics, including immediate
errors which invoke K without an earlier suspension.

A public resume operation saves the current context, driver ownership,
pending-call chain, native-call depth and host status in owned boundary
metadata. Suspended execution keeps its actual frames and stack windows.
Yielded values are published into a separate rooted public window above that
retained storage. The next resume takes arguments from the public window and
restores the real activation window before advancing execution. Completion
restores the caller's host prefix and ownership. No process-wide current-state
pointer or recursively invoked Ada executor is introduced.

Real C hooks use the same callback protocol and inspect the interrupted logical
frame. Their callback identity, masks and count belong to the owning context;
permitted hook yields suspend that frame rather than executing Lua recursively.
Public table operations request existing metamethod-aware native drivers.
Raw table operations continue to bypass handlers. C-frame closing slots use the
actual stable cells and normal unwind machinery.

Standard-library C constructors create the real Ada module implementations.
Registry publication/caching remains the responsibility of requiref and the
selected-library initializer. Loading wins over preloading for a shared mask
bit. Reopening a module must not corrupt an earlier instance's owned state;
in particular, separately opened math modules require separate RNG state.

## Alternatives and consequences

Retaining native C stacks or recursively entering another Ada executor would
split transfer, rooting, protection and work accounting. Overwriting live
stack storage with public yielded values would lose suspended roots. Those
approaches are rejected. Explicit saved ownership and public windows introduce
more private state, which needs failure, reuse and cleanup regression coverage.

This changes no public Ada interface or pinned C header. The first-party C
boundary record is private ABI glue and remains layout-checked at startup.
The test command driver implements only source-reviewed required commands and
reports unsupported commands as errors; it never fabricates T success.

## Verification requirements

Separately named real C/AUnit cases must cover synchronous versus abandoned C
bodies, immediate protected errors, repeated yields, zero/fixed/open results,
full-width contexts, captured roots, forbidden yields, resume reuse/errors,
nested driver restoration, hooks, C closing slots and module reopening.
Run matching native-C baselines before interpreting a test expectation.
Whole-file coroutine execution must reach its instrumented tail without
omissions. The clean 3107dd6 candidate reaches both API phases and the hook-yield
phase in all seven instrumented contexts. Separately reviewed source/API
projections cover all 26 contexts, including real native/Ada continuation,
closing, hook, opener and refusal witnesses. Independent compiler/scalar-root
repairs address the macOS weak-table progress failures exposed by this campaign.

These candidate results establish implementation and contract evidence. Exact
final-head runtime acceptance additionally requires the fresh complete matrix
and independent reconciliation, published in the tested head's conformance
Git note. [Status](../status.md) and the
[session](../sessions/2026-11-07-expanded-t-conformance.md) own those boundaries;
unrelated C debug selectors, full public ABI and complete M3 remain separate.
