# Project Status

Updated: 2026-11-05 (Asia/Tokyo). M0 complete; **M1 active pending platform
acceptance**. The [M1 target](milestones/m1.md) owns scope.

## Implemented

The reusable Ada runtime executes the M1 language subset through
`Lua.Sessions` and the batch CLI. It includes a resolving frontend, private
register bytecode, explicit frames and tail calls, lexical captures, tables,
and iterative tracing collection of objects and compiled prototypes.

The base functions listed in M1 are available. Sessions retain globals,
capture output, isolate state, bound execution, and return structured errors.
The CLI supports files, repeated snippets, stdin, arguments, help/version,
byte-preserving output, and controlled failure status.

There are 168 individually named AUnit cases across lexical, integer, numeric,
language, and lifetime groups. Six differential fixtures compare raw bytes
against pinned C Lua, including 2,366 arithmetic combinations. Nineteen CLI
process cases exercise input/output and exit behavior.

## Verification in progress

Windows x86-64 validation/static acceptance passed with 168 successes, no
failed assertions or unexpected errors, 19 CLI cases, and all six differential
fixtures. Final profile/shared checks and Linux/macOS CI are in progress.
Do not infer all-platform completion from this snapshot.

Tools: Alire 2.1.1, GNAT 16.1.0, AUnit 26.0.0, GPRbuild package 26.0.1
(binary banner 26.0.0). Required warning/style flags and runtime checks remain
enabled. ADR 0003 explains the floating-validity exception.

ABI experiments cover reference allocation/failure, varargs, extra space,
C-only jump checkpoints, callbacks/reentry, yield after Ada returns, and Ada
startup/shutdown. Windows observations: integer/number=8, lua_Debug=144,
extra space=8, currentline offset=48 bytes. These are host facts.

## Scope limits

This is a documented Lua subset, not complete Lua 5.5 compatibility.
Metatables, coroutines, userdata, close/goto, remaining libraries, binary
chunks, full C API/ABI, dynamic modules, and LuaRocks remain later milestones.
No unchanged whole upstream test file has passed on Ada; the
[inventory](upstream-tests.md) explains prerequisites and equivalent subset
coverage. GNATdoc rendering, GNATtest generation, fuzz campaigns, and formal
proof have not been exercised.

See [session evidence](sessions/2026-11-05-m1-interpreter.md) and
[backlog](backlog.md).
