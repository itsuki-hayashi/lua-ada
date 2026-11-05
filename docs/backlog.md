# Backlog

IDs are stable. A done item must link evidence. Milestone M1 remains active.
Implementation is distinct from verification on all target platforms.

| ID         | Work                                  | State   | Depends on |
| ---------- | ------------------------------------- | ------- | ---------- |
| FND-001    | Foundation                            | done    | None       |
| PLAN-001   | Accepted M1 target and gates          | done    | FND-001    |
| BUILD-001  | Static/shared library and consumers   | active  | FND-001    |
| TEST-001   | Nested AUnit crate and failing runner | done    | BUILD-001  |
| CI-001     | Three-platform profile/link matrix    | active  | TEST-001   |
| LEX-001    | Byte lexer with locations and limits  | done    | TEST-001   |
| ABI-001    | C boundary feasibility                | active  | FND-001    |
| COMP-001   | Upstream inventory and differential   | active  | FND-001    |
| CORE-001   | Ownership/roots representation        | planned | ABI-001    |
| NUM-001    | Numeric grammar and primitive rules   | active  | TEST-001   |
| PARSE-001  | Resolving parser and diagnostics      | planned | LEX-001    |
| VM-001     | Typed register bytecode and frames    | planned | CORE-001   |
| HEAP-001   | Tables, roots, tracing cycles         | planned | CORE-001   |
| LANG-001   | Control flow/functions/results        | planned | PARSE-001  |
| API-001    | Owned sessions and structured errors  | planned | VM-001     |
| CLI-001    | Batch execution modes and arguments   | planned | API-001    |
| BASE-001   | M1 base library                       | planned | LANG-001   |
| ACCEPT-001 | M1 acceptance on all platforms        | planned | BASE-001   |

## Acceptance and evidence

FND-001: [foundation session](sessions/2026-11-05-foundation.md).
PLAN-001: [M1 target](milestones/m1.md) and ADR 0002.

BUILD-001: static/shared targets and isolated artifacts exist; both consumer
paths pass on Windows. Remains active pending Linux/macOS evidence.
TEST-001: AUnit is test-only, parent-pinned, with status-returning runner and
meaningful lexical tests. Evidence: [current session](sessions/2026-11-05-m1-gates.md).
CI-001: 18-job OS/profile/link matrix exists; remote execution is unverified.

LEX-001: keywords/operators, byte strings/escapes, long comments, source bounds,
locations, malformed input, token limits, and independent scans are tested.
Numeric spelling is retained; NUM-001 owns grammar/range validation.
This is not a claim of complete frontend conformance.

ABI-001: allocator failure/balance, varargs, extra space, public layout, Ada
lifecycle, callbacks, and C-only jump checkpoints have Windows evidence.
General Lua API error integration, yields, stable heap addresses, and all target
ABIs still require experiments. See [probe](../experiments/abi/README.md).

COMP-001: isolated C oracle, comparison driver, and three project fixtures exist.
Fixtures pass on C Lua only. Ada execution parity and upstream inventory/mappings
remain undone; do not mark the work done from oracle-only runs.

CORE-001: review cycles, roots, allocator callbacks, stable addresses, and
cleanup before representation commitments. NUM-001: decimal/hex integers/floats,
overflow, coercion, division/modulo, shifts, and reference boundary tests.
PARSE-001: precedence, lexical resolution, 5.5 globals/constants, unsupported
syntax, and located diagnostics with AUnit coverage.

VM-001: typed instructions, bounded registers/frames, checked execution, calls,
protected errors, and instruction budgets. HEAP-001: identity, key rules,
root traversal, reclamation of cycles, and live captured references.

LANG-001: all scoped M1 statements, functions, closures, varargs, result
adjustment, and proper tail calls; depends also on VM-001, HEAP-001, NUM-001.
API-001: independent sessions, output sink, persistent globals, and recoverability;
depends also on LANG-001. CLI-001: all accepted batch modes with process tests.
BASE-001: the exact base functions in the milestone target and regressions.

ACCEPT-001 depends also on CLI-001, CI-001, BUILD-001, COMP-001, ABI-001 and
HEAP-001: all scoped behavior, both link modes, all OS targets, no hidden skips.
