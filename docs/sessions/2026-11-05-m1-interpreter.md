# M1 Interpreter Implementation

Date: 2026-11-05, Asia/Tokyo. Objective: deliver and verify the accepted M1
interpreter, with extensive explanatory comments and focused human-readable tests.
Outcome: **all five M1 gates complete**; [validation evidence](../validation.md).

## Implementation and decisions

Implemented exact numeric parsing, private typed register compilation/execution,
lexical cells and closures, tables, all M1 control flow, packet result adjustment,
tail calls, protected failures, bounded execution, tracing cycles/prototypes,
the base subset, owned Ada sessions, and batch CLI execution.

Expanded AUnit from six broad cases to 171 separately named cases with explanatory
comments. Added 19 CLI process cases and six raw-byte differential fixtures,
including binary output and a 2,366-operation numeric matrix. ABI probes exercise
allocation/failure, callbacks/reentry, varargs, extra space, yield after Ada
returns, and C-host startup/shutdown.

AGENTS and coding/testing guides require extensive implementation explanations
at algorithms/ownership transitions and focused documented test cases. ADRs
0003–0005 record IEEE validity, ownership/C boundary limits, and justified host
exponentiation. Source representations and bytecode remain private.

## Verification

The [final runtime CI run](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42045878008)
passed all 18 OS/profile/link jobs. Every log was inspected: 171 successful AUnit
cases, no failures/unexpected errors, 19 CLI cases, six differential fixtures,
stable GNAT selection, and documentation checks. ABI probes passed in all three
static/validation jobs. Windows static-PIC also passed with 171 cases.

Tool versions: Alire 2.1.1; stable GNAT 16.1.0; GPRbuild package 26.0.1
(binary 26.0.0); AUnit 26.0.0. Compiler argument records retain mandatory flags
and ordinary runtime checks in all profiles; only optional floating validity
classification is narrowed by ADR 0003. Reference pins remain unchanged.

Portability checks found and resolved explicit Linux math linkage, overlapping
oracle source ownership, byte-stream encoding, macOS NaN spelling, prerelease
toolchain selection, and macOS C-host Ada-runtime linkage. Download HTTP 504
failures now retry the same selected stable release, without compiler fallback.
A final ownership review moved partial frame ownership ahead of failing scope
allocation and added a focused recovery regression. A final compatibility check
distinguished primitive bitwise operands from API integer coercion: numeric
strings are rejected on both binary operand sides and by unary complement.
Three focused AUnit cases and differential guards protect that distinction.

Native HTTPS Git push lacked credentials. After explicit user approval for
publication, the connected GitHub transport published the reviewed source to
`codex/m1-interpreter`. Local/remote trees were synchronized and reference
submodules remained clean. No merge or production release was performed.

## Handoff

Run `scripts/check.ps1` for each profile/library combination. It overrides the
parent dependency profile, runs AUnit, CLI processes, differential fixtures, and
documentation checks. `scripts/check-abi.ps1` resolves platform runtime linkage
and runs isolated C/Ada feasibility. Logs belong under ignored reports.

M1 is complete within its accepted subset. Later work is bounded in the backlog:
remaining language/libraries, complete C facade/storage integration, binary
chunks, module loading/LuaRocks, and full unchanged upstream conformance.
No full upstream suite, drop-in C ABI, LuaRocks, generated GNATdoc, generated
GNATtest coverage, fuzz campaign, formal proof, or benchmark is claimed.
