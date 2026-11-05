# M1 Interpreter Implementation

Date: 2026-11-05, Asia/Tokyo. Objective: deliver and verify the accepted M1
interpreter, with extensive explanatory comments and focused human-readable tests.

## Changes and decisions

Implemented exact numeric parsing, private typed register compilation/execution,
lexical cells and closures, tables, all M1 control flow, packet result adjustment,
tail calls, protected failures, bounded execution, tracing cycles/prototypes,
the base subset, owned Ada sessions, and batch CLI execution.

Expanded AUnit from six broad cases to 168 separately named cases with explanatory
comments. Added process-level CLI acceptance and raw-byte differential comparison,
including binary output and a 2,366-operation numeric matrix. ABI probes now
exercise yield after Ada returns, variadic GC, and inherited extra space.

AGENTS and contributor guides now require implementation comments at nontrivial
algorithms/ownership transitions and focused documented cases. ADRs 0003–0005
record IEEE validity, ownership/C boundary limits, and narrowly justified host
exponentiation. Source representations and bytecode remain private.

## Evidence so far

Windows validation/static: 168 successful AUnit cases, no failures/unexpected
errors; 19 CLI cases; six differential fixtures match pinned C Lua byte for
byte. The oracle is a separately built C interpreter and is never linked into
production. Final profile/link and remote platform checks are ongoing.

Tool versions: Alire 2.1.1; native GNAT 16.1.0; GPRbuild package 26.0.1
(binary 26.0.0); AUnit 26.0.0. Standard Ada runtime dependencies plus isolated
system math; AUnit is test-only.

## Checks and handoff

Run `scripts/check.ps1` for each profile/library combination. It overrides the
parent dependency profile explicitly, runs AUnit, CLI processes, and differential
fixtures. `experiments/abi/abi_probe.gpr` independently checks C/Ada feasibility.
Logs are ignored under reports. Required flags and runtime checks remain on;
only optional floating validity classification is narrowed by ADR 0003.

M1 remains active until all Windows/Linux/macOS static/shared acceptance jobs
pass. No full upstream suite, drop-in C ABI, LuaRocks, binary chunks, generated
GNATdoc, GNATtest, fuzz campaign, or formal proof is claimed.
