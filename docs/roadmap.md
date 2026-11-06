# Roadmap

M0, M1, M2a, and M2b are complete. M1 expanded infrastructure into the accepted
[basic interpreter target](milestones/m1.md). Milestones are acceptance gates,
not calendar promises. The [M1 validation record](validation.md) closes all five
gates on the named Windows/Linux/macOS configurations.

[M3](milestones/m3.md) is now the active umbrella milestone for complete pinned
upstream coverage. It absorbs the remaining M2 runtime/libraries and the former
C/binary compatibility target, including upstream native C fixture libraries.
It is delivered through staged PRs, with reviewed Ada/platform equivalents
where original assertions depend on C internals or unsupported native facilities.
M3-01 is implemented and verified in
[merged PR #5](https://github.com/itsuki-hayashi/lua-ada/pull/5). M3-02A implements
context ownership in [PR #6](https://github.com/itsuki-hayashi/lua-ada/pull/6).
Typed transfers and error-policy changes remain open in the parent M3-02 gate;
no later M3 runtime gate is complete.

| Milestone | Target                                    | Completion gate                            |
| --------- | ----------------------------------------- | ------------------------------------------ |
| M0        | Foundation                                | Layout, policies, references, docs         |
| M1        | Basic Lua scripting interpreter           | Core scripts, Ada API, batch CLI, GC       |
| M2a       | Frontend and opcode definitions           | Full checking, shared lowering, format     |
| M2b       | Core libraries and metamethods            | Three unchanged execution files and matrix |
| M2        | Remaining runtime work absorbed by M3     | Tracked by M3-02 through M3-12             |
| M3        | Complete Lua 5.5.1 upstream coverage      | All covered behavior, C ABI, full matrix   |
| M4        | Ecosystem modules and LuaRocks            | Real-world fixture and rock acceptance     |
| M5        | Conformance and release hardening         | Published platform acceptance matrix       |

M1's five gates cover build/tests, constraints, execution substrate, language
execution, and usable interfaces. ABI experiments stay early because allocation
and unwinding can affect representation choices. The backlog owns bounded work;
status owns evidence. A Lua subset does not imply full conformance.

| M1 gate        | Bounded tasks                                                        | Evidence owner                         |
| -------------- | -------------------------------------------------------------------- | -------------------------------------- |
| 1: Build/tests | Static/shared consumers, strict profiles, focused AUnit, CI          | BUILD-001, TEST-001, CI-001            |
| 2: Constraints | ABI probes, 34-file inventory, raw-byte oracle driver, ownership ADR | ABI-001, COMP-001, CORE-001            |
| 3: Substrate   | Numbers, tables, roots, explicit frames, tracing cycles/prototypes   | NUM-001, VM-001, HEAP-001              |
| 4: Execution   | Resolving parser, control flow, closures, packets/tail calls         | PARSE-001, LANG-001                    |
| 5: Usability   | Base subset, Ada sessions, CLI, diagnostics, platform acceptance     | BASE-001, API-001, CLI-001, ACCEPT-001 |

The [backlog](backlog.md) records dependencies and acceptance for each task;
[status](status.md) records implemented behavior and actual platform results.

[M2a](milestones/m2a.md) is the first bounded M2 delivery: full lexer and
grammar/static semantics, shared checking/lowering, and canonical opcode
definitions. Canonical code generation and execution remain separate gates.
Its [18-job validation](validation-m2a.md) closes this frontend delivery;
remaining M2 runtime/library work is still open.

[M2b](milestones/m2b.md) is the next bounded runtime delivery. Its primary
unchanged execution targets are tpack.lua, utf8.lua, and bitwise.lua;
bwcoercion.lua is a dependency/helper, not a fourth suite. It adds resumable
native callbacks, core metamethods, strings/patterns/packing, UTF-8, common
table/math operations, and Lua-only text/module loading. Its
[18-job validation](validation-m2b.md) closes all six gates.

| M2b gate            | Bounded work                                                    | Backlog owner             |
| ------------------- | --------------------------------------------------------------- | ------------------------- |
| 1: Contracts        | Scope, unchanged baseline, disposable runner, host layout probe | M2B-FND-001               |
| 2: Native execution | Continuations, captures/roots, protected errors, shared budgets | M2B-VM-001                |
| 3: Metamethods      | Raw lookup, handler ordering, string state, isolation           | M2B-META-001              |
| 4: Strings/bytes    | Patterns/format callbacks, packing, UTF-8 boundaries            | M2B-STR-001, M2B-BIN-001  |
| 5: Loading/helpers  | Text environments, Lua package searchers, table/math exports    | M2B-LOAD-001, M2B-LIB-001 |
| 6: Acceptance       | Three files, focused tests, 18 jobs, probes, verified PR        | M2B-ACCEPT-001            |

The language lifecycle delivery below adds closing/goto execution, coroutines,
weak objects and the documented debug subset on the private backend. Userdata,
finalization, remaining libraries/debug facilities, canonical execution, binary
chunks and the C ABI remain required by M3. M2b did not advance those claims.

## M3 delivery order

The [M3 acceptance owner](milestones/m3.md) defines thirteen bounded gates,
M3-01 through M3-13, and their exact exit evidence. Foundation/inventory precedes
execution contexts, allocator storage, and real C-boundary feasibility. Canonical
execution and language lifecycle precede complete collectors, debug/chunks,
public C APIs, remaining libraries, full CLI, internal equivalents and acceptance.

The approved [language lifecycle delivery](milestones/m3-language-lifecycle.md)
supersedes that sequential PR order for selected language, collector, debug and
CLI portions. Its six checkpoints stay in one substantial PR on
codex/m3-language-lifecycle; allocator/ABI/canonical work remains separate. No
automatic merge is authorized. M3 remains in progress until every required
coverage entry, default/instrumented configuration, and final review passes.
Ecosystem fixtures remain unbuilt/unexecuted future M4 inputs.

The bounded lifecycle runtime acceptance is complete: 587 AUnit cases, five
selected unchanged execution files and all 18 inspected platform jobs plus
Windows static-PIC. [Its validation record](validation-m3-lifecycle.md) owns the
exact revision and scope; PR #7 records final publication-head checks.

## Complete upstream implementation delivery

Merged PR #7 is the starting point for one approved full-M3 implementation PR
on codex/m3-upstream-conformance. [ADR 0010](decisions/0010-full-upstream-delivery.md)
supersedes the earlier separate-PR sequence. Eight dependent checkpoints cover
contracts, allocator-aware storage, a real C-boundary pilot, canonical execution
and binary chunks, collection/finalization, complete APIs/libraries/CLI,
source-cited coverage/equivalents, and all 26 final acceptance contexts.

The [M3 acceptance owner](milestones/m3.md) defines exact exit evidence. Current
inventory/harness work is partial infrastructure; the remaining runtime and
review gates stay open. Do not stop after one checkpoint and present it as the
requested full-suite delivery. Ecosystem testing/LuaRocks remains M4.
