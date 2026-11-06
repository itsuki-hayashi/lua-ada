# ADR 0009: Language Lifecycle on the Private VM

Date: 2026-11-06. Status: accepted and implemented; runtime matrix verified.

## Context

The maintainer requested one major implementation PR combining useful language
and lifetime behavior, superseding ADR 0008's sequential PR order for selected
portions of M3-02, M3-06, M3-07, M3-08 and M3-11. Canonical execution and C ABI
storage remain separate gates. [The delivery contract](../milestones/m3-language-lifecycle.md)
owns acceptance rather than treating any original M3 gate as wholly complete.

## Decision

Contexts have explicit lifecycle and closing phases. An iterative scheduler
moves owned transfer packets between resumers and suspended native continuations.
Neither Lua recursion nor coroutine switching recursively enters the executor or
retains an Ada stack. Protected native calls are real logical activations; their
protection metadata survives suspension. Host aborts invalidate the active resume
chain and never become catchable Lua failures or cleanup callbacks.

Each dynamic lexical declaration owns a nonmoving heap cell. Closures snapshot
ordered references to the actual captured cells, not a mutable scope container.
Backward jumps prune the resolved declaration frontier and create fresh cells on
reentry. Lua and native upvalue identities use those actual cell identities.

Closing lists belong to activations. Explicit cleanup continuations retain
outgoing values and the current error, remove each closing entry before calling
its handler, and process handlers in reverse declaration order. Generic-for has
one outer closing scope and separate per-iteration binding scopes. Yield preserves
live closers; unreachable coroutine collection releases storage without handlers.
Error cleanup has a fixed 4,096-slot emergency reserve, unavailable to ordinary
execution. Explicit host quotas remain hard abort boundaries during cleanup.

The context registry has stable reusable slots. Host-owned contexts, main thread
and active resumer chains are roots; suspended Lua contexts are traced through
reachable thread objects. Weak tables use raw __mode, iterative marking and an
ephemeron fixed point. Strings retain Lua value semantics in weak entries.
Collection remains stop-the-world; modes, finalizers and allocator parity are
not inferred from this implementation.

Debug queries inspect retained source metadata, logical frames, declaration
cells and ordered upvalues. Internal cleanup/hook phases do not appear as fake
Lua calls. Hooks are per-thread, suppressed throughout their callbacks, and run
through native continuations. Lua hook callbacks cannot yield across that native
boundary. Count hooks count private VM instructions and remain backend dependent.

Embedding defaults remain Bounded. Lua_Compatible removes project host quotas,
while retaining checked representations, frontend nesting, a 1,000,000 semantic
slot ceiling and a 200 native-call depth ceiling. This backend charges register
packets, argument storage and a minimum twenty slots per activation; its exact
stack-overflow boundary differs from canonical Lua register allocation. Expanded
register packets charge extra live result slots. Semantic failures are catchable;
physical Ada allocation failure and explicit host limits abort execution.

## Alternatives and consequences

Ada tasks and recursive interpreter entry were rejected because they would keep
abandoned host stacks alive and obscure budget/root ownership. Keeping every
registered coroutine rooted was rejected because it leaks unreachable cycles.
Whole-environment capture was rejected because backward declarations would change
older closures and retain unrelated values. A canonical backend rewrite remains
valuable but is not a prerequisite for these private-backend language facilities.

## Verification

Focused AUnit cases cover transfers, close paths, shared/fresh captures, weak
cycles, ephemerons, hooks, native callback restrictions and policy recovery.
Unchanged goto.lua and coroutine.lua require independent hash-verified C/Ada
process runs; T-absent omissions are inventoried explicitly. Final platform jobs
and the retained M2b/frontend/opcode/ABI campaigns remain mandatory.

The [validation record](../validation-m3-lifecycle.md) records 575 passing AUnit
cases, all five selected files, the 1,024-case campaign, all 18 inspected jobs
and Windows static-PIC. Publication-head CI remains the final readiness gate.
