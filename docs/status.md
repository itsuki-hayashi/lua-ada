# Project Status

Updated: 2026-11-06 (Asia/Tokyo). **M0, M1, and M2a complete.**
**M2b is in progress; its platform acceptance is not complete.**
The [M1 target](milestones/m1.md) owns scope; the
[validation record](validation.md) owns exact platform/configuration evidence.

## Implemented and verified

The reusable Ada runtime executes the M1 language subset through
`Lua.Sessions` and the batch CLI. It includes a resolving frontend, private
register bytecode, explicit frames and tail calls, lexical captures, tables,
and iterative tracing collection of objects and compiled prototypes.

The scoped base library is available. Sessions retain globals, capture output,
isolate state, bound execution, and return structured errors. The CLI supports
files, repeated snippets, stdin, arguments, help/version, byte-preserving output,
and controlled failure status. See [capabilities](capabilities.md) and
[embedding](embedding.md).

M1 acceptance: all 18 Windows/Linux/macOS x
development/validation/release x static/shared
jobs passed. Each passed 171 individually named AUnit cases, zero failed
assertions/unexpected errors, 19 CLI cases, and six raw-byte differential
fixtures against pinned C Lua, including 2,366 arithmetic combinations.
The ABI probe passed on each target OS. Final Windows static-PIC acceptance
also passed. Required flags and runtime checks remain enabled; ADR 0003
explains the floating-validity exception.

Tools: Alire 2.1.1, stable native GNAT 16.1.0, AUnit 26.0.0, GPRbuild package
26.0.1 (binary banner 26.0.0). Compiler target triples, OS versions, test groups,
ABI observations, commands, and immutable CI evidence are recorded in
[validation](validation.md).

## M2a acceptance

[M2a frontend parity](milestones/m2a.md) is complete. Shared incremental
parsing/resolution and VM lowering, Ada/CLI checking, and canonical opcode
definitions are implemented. All 18 configurations passed 347 focused AUnit
cases, 30 CLI cases, and the public Ada consumer; each OS also passed the full
frontend/opcode campaign and ABI probe. Windows static-PIC passed as well.
Exact immutable [M2a validation](validation-m2a.md) records configurations,
limits, and the distinction between syntax and runtime compatibility.

Eight [real-world module fixtures](../tests/modules/README.md) are pinned under
tests/modules/ for future consumer parity work. This is source checkout and
documentation only: module builds, dependency installation, and C/Ada execution
have not been performed. The fixtures are not development references or runtime
dependencies. M2b does not build or execute them.

## M2b implementation and provisional evidence

[M2b](milestones/m2b.md) adds core metamethods, explicit native continuations,
strings/patterns/formatting/packing, UTF-8, common table/math helpers, and text
load/Lua-only require. The [capability/export inventory](capabilities.md) owns
the exact surface; [ADR 0007](decisions/0007-native-libraries.md) owns runtime
contracts. Focused tests cover callback roots, errors/recovery, metatable
selection/isolation, byte/numeric boundaries, and package environments/state.

Direct local Windows runs have completed the three unchanged primary files
tpack.lua, utf8.lua, and bitwise.lua at the default 1,000,000-instruction budget.
bitwise.lua loads bwcoercion.lua as a helper. These are provisional execution
results. The Windows disposable runner has also passed all three same-host
raw-byte comparisons at the default budget. The complete Windows
validation/static pipeline passes 472 AUnit cases, 30 CLI cases, the Ada
consumer, and seven differential fixtures with matching dependency profiles.
The independent C99/Ada layout probe also passes. Final matrix acceptance
must still pass before the milestone closes.
No Linux/macOS M2b passes or final-revision CI results are claimed here.

| M2b evidence                                | Windows                    | Linux      | macOS      |
| ------------------------------------------- | -------------------------- | ---------- | ---------- |
| Direct three-file execution, default budget | Local provisional pass     | Unverified | Unverified |
| Disposable same-host byte comparison        | Local pass, default budget | Pending    | Pending    |
| Final profiles × static/shared matrix       | Pending                    | Pending    | Pending    |
| Layout/differential/ABI acceptance          | Pending                    | Pending    | Pending    |

The [current session record](sessions/2026-11-06-m2b-core-libraries.md) owns
exact evolving commands/results. Intermediate failing or stale build results
are not accepted suite counts. Historical M1/M2a evidence remains unchanged.

This is a documented Lua subset, not complete Lua 5.5 compatibility. Coroutines,
userdata, weak/finalized objects, close/goto execution, debug/io/os, remaining
library functions, binary chunks, full C API/ABI, native modules, and LuaRocks
remain later work. Canonical opcode definitions exist; canonical code generation
and execution do not. The [upstream inventory](upstream-tests.md) distinguishes
three M2b targets from the complete suite. GNATdoc rendering, GNATtest generation,
fuzz campaigns, and formal proof have not been exercised.

See [session evidence](sessions/2026-11-05-m1-interpreter.md),
[roadmap](roadmap.md), and [backlog](backlog.md).
