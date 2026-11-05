# Backlog

IDs are stable. Completion requires evidence, including relevant platform gates.
M1 is complete; [all five gates passed](validation.md).

| ID         | Work                          | State          | Depends on                                   |
| ---------- | ----------------------------- | -------------- | -------------------------------------------- |
| FND-001    | Foundation                    | done           | None                                         |
| PLAN-001   | Accepted M1 scope             | done           | FND-001                                      |
| BUILD-001  | Static/shared consumers       | done           | FND-001                                      |
| TEST-001   | Focused AUnit runner          | done           | BUILD-001                                    |
| CI-001     | Three-OS strict matrix        | done           | TEST-001                                     |
| LEX-001    | Byte lexer/diagnostics        | done           | TEST-001                                     |
| ABI-001    | Isolated boundary feasibility | done           | FND-001                                      |
| COMP-001   | Inventory/differential driver | done           | FND-001                                      |
| CORE-001   | Ownership/roots decision      | done           | ABI-001                                      |
| NUM-001    | Numeric grammar/primitives    | done           | TEST-001                                     |
| PARSE-001  | Resolving parser              | done           | LEX-001                                      |
| VM-001     | Register instructions/frames  | done           | CORE-001                                     |
| HEAP-001   | Tables/tracing cycles         | done           | CORE-001                                     |
| LANG-001   | Functions/control/results     | done           | PARSE-001, VM-001, HEAP-001, NUM-001         |
| API-001    | Owned sessions/errors         | done           | VM-001, LANG-001                             |
| CLI-001    | Batch interface               | done           | API-001                                      |
| BASE-001   | Scoped base library           | done           | LANG-001                                     |
| ACCEPT-001 | All-platform M1 acceptance    | done           | CLI-001, BASE-001, CI-001, COMP-001, ABI-001 |

## Acceptance and evidence

FND-001: [foundation record](sessions/2026-11-05-foundation.md).
PLAN-001: [accepted target](milestones/m1.md), ADR 0002.
Current implementation evidence: [interpreter session](sessions/2026-11-05-m1-interpreter.md).

- BUILD-001/CI-001: three profiles, static/shared library, real Ada consumers,
  all target OSes. All 18 jobs passed; see the [platform evidence](validation.md).
- TEST-001: failing-status runner, test-only AUnit, 171 focused documented cases.
- LEX-001: keywords/operators, byte escapes, long literals/comments, positions,
  malformed input, budgets, deterministic arbitrary-byte scans.
- ABI-001: allocator failure/balance, varargs, callbacks/reentry, C-only jump
  guards, extra space, layout, yield after Ada returns, startup/shutdown.
  Scope is feasibility; complete exported API/yield integration is M3.
- COMP-001: six raw-byte C/Ada differential fixtures, including 2,366 arithmetic
  rows, and [all 34 upstream files inventoried](upstream-tests.md).
- CORE-001: [ADR 0004](decisions/0004-runtime-ownership.md), explicit roots and
  nonmoving ownership; future allocator/layout constraints recorded.
- NUM-001: exact decimal/hex rounding, integer wrapping, mixed comparisons,
  IEEE limits, modulo, shifts, and host exponentiation regression evidence.
- PARSE-001: precedence, lexical symbols, global/const rules, explicit deferred
  syntax failures, bounded nesting, source diagnostics.
- VM-001: private instructions, packet registers, explicit calls, tail frames,
  protected errors, instruction/call/register bounds.
- HEAP-001: key rules/identity, sequence border, root traversal, iterative
  cycle/prototype reclamation, live captures, automatic collection.
- LANG-001: all scoped statements/loops, closures/mutation, varargs including
  named tables, result adjustment, recursion and proper tail calls.
- API-001: persistent independent sessions, named chunks, structured failures,
  recovery, output preservation/sinks, close/reset ownership.
- CLI-001: 19 process cases for files/stdin/snippets/options/arguments/status.
- BASE-001: exact M1 inventory, protected failures, raw/iteration behavior.
- ACCEPT-001: every above gate, all three OSes, no hidden skips. No full Lua,
  upstream-suite, drop-in ABI, or LuaRocks claim follows from M1.

## Post-M1 fixture preparation

TEST-MOD-001: **done**, depends on FND-001. Acceptance: the eight requested
repositories are separate test-only submodules with exact URLs and immutable
pins, clean detached checkouts, preserved notices, and documented checkout/update
rules. No production source paths, runtime dependencies, or parity execution are
introduced. Evidence: [fixture catalog](../tests/modules/README.md) and
[setup session](sessions/2026-11-06-ecosystem-fixtures.md).

Future module execution remains MOD-001 work; fixture checkout is not parity
evidence and does not complete that gate.

## M2a frontend parity

The [accepted target](milestones/m2a.md) owns acceptance; the
[session](sessions/2026-11-06-m2a-frontend.md) records evidence.

- FRONT-001, depends ACCEPT-001: owned syntax design/inventory and baseline;
  implemented, pending final acceptance.
- ORACLE-002, depends FRONT-001: protected isolated C lex/parse/opcode probes;
  implemented, pending final acceptance.
- LEX-002, depends ORACLE-002: incremental tokens/payloads/failures/locations;
  implemented, pending final acceptance.
- PARSE-002, depends LEX-002: full grammar/resolution and scope/jump checks;
  implemented, pending final acceptance.
- OPCODE-001, depends ORACLE-002: all canonical definitions/bit operations;
  implemented, pending final acceptance.
- CHECK-001, depends PARSE-002 and OPCODE-001: shared lowering, Ada/CLI checking;
  implemented, pending final acceptance.
- ACCEPT-002, depends all above: 18 platform/profile/link jobs, ABI probes,
  Windows static-PIC, final verified PR; pending.

## Later runtime work

| ID        | Work                              | Dependency                     | Acceptance                                                   |
| --------- | --------------------------------- | ------------------------------ | ------------------------------------------------------------ |
| LANG-002  | Deferred language facilities      | ACCEPT-001                     | Metamethod/coroutine/close/goto regressions                  |
| LIB-002   | Remaining libraries and loading   | ACCEPT-001                     | Library differential and unchanged-file coverage             |
| ABI-002   | Full C facade/storage integration | ABI-001, CORE-001              | Public header clients, callbacks/unwinding, allocator parity |
| CHUNK-001 | Binary chunk interoperability     | ABI-002                        | Pinned C/Ada load/dump fixtures                              |
| MOD-001   | Native modules/LuaRocks           | ABI-002, LIB-002, TEST-MOD-001 | Pure Lua and native rock acceptance                          |
| CONF-001  | Complete upstream validation      | LANG-002, LIB-002, ABI-002     | Unchanged suite and reviewed full internal mappings          |
