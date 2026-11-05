# ADR 0007: Native Continuations and Owned Library State

Date: 2026-11-06, Asia/Tokyo. Status: accepted design; M2b acceptance in progress.

## Context

Core metamethods and libraries call back into Lua. Pattern replacements,
formatting, iterators, protected errors, and module searchers must retain values
while those callbacks allocate or fail. Recursively entering the executor would
map Lua/native nesting onto the Ada stack, complicate roots, and risk restarting
resource budgets. Public heap handles are unnecessary for this milestone.

## Decision

Use the existing explicit activation stack for both Lua and native frames.
A native driver records its phase and retained values before requesting a call.
The VM invokes the requested Lua/native value and resumes the waiting phase with
its result packet. A driver may also continue bounded internal work or finish.
Private language-error transfers use the same protected unwind path for both
frame kinds. Resource exhaustion always aborts the chunk, including inside
pcall/xpcall; continuation resumption never restarts its work budget.

Trace native arguments, pending results, captures, and iterator closures, in
addition to Lua frames, metatables, globals, module registries, and environments.
No live callback state may remain only in an Ada local across a VM safe point.
Destroy abandoned activations during unwinding. Preserve tail-call replacement
and result adjustment rather than creating a separate callback execution model.

Keep pure byte, pattern, packing, and UTF-8 algorithms independent of callback
dispatch where practical. Charge helper loops and backtracking to the shared
instruction budget. Derive native packing widths/alignment from C interface
types and compare them with a separate C99 layout probe. Calculate virtual
packsize values without allocation; reject semantic overflow before applying
allocation quotas.

Each session owns table metatables, its string metatable, and loaded/preload
module registries. Metamethod lookup is raw. Numeric-string arithmetic belongs
to initial string handlers so replacement handlers take effect. Preserve the
pinned Lua 5.5 rules for unary operands, equality-handler selection, four pairs
results, and no less-than fallback for less-or-equal.

Text load compiles through the shared frontend. Loaded closures retain their
own initial environment, including explicit nil. Lua-only require uses real
preload/file searchers, mutable searcher lists, and registry tables which survive
replacement of public package fields. Use ./?.lua;./?/init.lua by default.
Do not introduce a Lua 5.1 loading sentinel, native module loading, or a public
host callback API.

## Alternatives and consequences

Recursive executor calls would make ownership and failure cleanup depend on
the host call stack. Synchronous-only native functions cannot implement Lua
callbacks correctly. Both approaches are rejected. Explicit continuation phases
require more private state and focused transition tests, but leave one owner,
collector, budget, and protected-error mechanism.

The public Sessions and Syntax interfaces remain small. The private packet VM
remains independent of the canonical opcode definition layer. These library
changes establish neither canonical code generation/execution nor binary chunk,
C API/ABI, native module, or LuaRocks compatibility.

## Verification implications

Require focused tests for nested callbacks, pending roots, error/resource
unwinding, recovery, metatable isolation/reset, and Lua/native handler selection.
Compare library boundaries against pinned C Lua. Execute the three unchanged
M2b primary files with byte-identical same-host output and empty stderr under
the disposable runner protocol. Run all platform/profile/link gates before
closing M2b; direct local successes alone do not complete the milestone.
