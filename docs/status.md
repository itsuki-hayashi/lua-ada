# Project Status

Updated: 2026-11-05 (Asia/Tokyo). **M0 complete; M1 regression revalidation active.**
The [M1 target](milestones/m1.md) owns scope; the
[validation record](validation.md) owns exact platform/configuration evidence.

## Implemented and verified baseline

The reusable Ada runtime executes the M1 language subset through
`Lua.Sessions` and the batch CLI. It includes a resolving frontend, private
register bytecode, explicit frames and tail calls, lexical captures, tables,
and iterative tracing collection of objects and compiled prototypes.

The scoped base library is available. Sessions retain globals, capture output,
isolate state, bound execution, and return structured errors. The CLI supports
files, repeated snippets, stdin, arguments, help/version, byte-preserving output,
and controlled failure status. See [capabilities](capabilities.md) and
[embedding](embedding.md).

Three additional focused cases now reject numeric strings in bitwise operands,
matching the pinned oracle. Local validation passes 171 cases and all fixtures;
the expanded platform matrix is running. The previously verified baseline follows.

All 18 Windows/Linux/macOS x development/validation/release x static/shared
jobs passed. Each passed 168 individually named AUnit cases, zero failed
assertions/unexpected errors, 19 CLI cases, and six raw-byte differential
fixtures against pinned C Lua, including 2,366 arithmetic combinations.
The ABI probe passed on each target OS. Final Windows static-PIC acceptance
also passed. Required flags and runtime checks remain enabled; ADR 0003
explains the floating-validity exception.

Tools: Alire 2.1.1, stable native GNAT 16.1.0, AUnit 26.0.0, GPRbuild package
26.0.1 (binary banner 26.0.0). Compiler target triples, OS versions, test groups,
ABI observations, commands, and immutable CI evidence are recorded in
[validation](validation.md).

## Later milestones

This is a documented Lua subset, not complete Lua 5.5 compatibility.
Metatables, coroutines, userdata, close/goto, remaining libraries, binary
chunks, full C API/ABI, dynamic modules, and LuaRocks remain later milestones.
No unchanged whole upstream test file has passed on Ada; the
[inventory](upstream-tests.md) explains prerequisites and equivalent subset
coverage. GNATdoc rendering, GNATtest generation, fuzz campaigns, and formal
proof have not been exercised.

See [session evidence](sessions/2026-11-05-m1-interpreter.md),
[roadmap](roadmap.md), and [backlog](backlog.md).
