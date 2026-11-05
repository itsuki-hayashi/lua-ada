# Roadmap

M0, M1, and M2a are complete. M1 expanded infrastructure into the accepted
[basic interpreter target](milestones/m1.md). Milestones are acceptance gates,
not calendar promises. The [M1 validation record](validation.md) closes all five
gates on the named Windows/Linux/macOS configurations.

| Milestone | Target                                    | Completion gate                            |
| --------- | ----------------------------------------- | ------------------------------------------ |
| M0        | Foundation                                | Layout, policies, references, docs         |
| M1        | Basic Lua scripting interpreter           | Core scripts, Ada API, batch CLI, GC       |
| M2a       | Frontend and opcode definitions           | Full checking, shared lowering, format     |
| M2b       | Core libraries and metamethods            | Three unchanged execution files and matrix |
| M2        | Remaining language and standard libraries | Deferred syntax, metatables, libraries     |
| M3        | Full C embedding and binary compatibility | C API/ABI, chunks, lifecycle evidence      |
| M4        | Modules and ecosystem                     | Native loading and LuaRocks fixtures       |
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
table/math operations, and Lua-only text/module loading. Implementation is in
progress; missing platform evidence prevents acceptance.

| M2b gate            | Bounded work                                                    | Backlog owner             |
| ------------------- | --------------------------------------------------------------- | ------------------------- |
| 1: Contracts        | Scope, unchanged baseline, disposable runner, host layout probe | M2B-FND-001               |
| 2: Native execution | Continuations, captures/roots, protected errors, shared budgets | M2B-VM-001                |
| 3: Metamethods      | Raw lookup, handler ordering, string state, isolation           | M2B-META-001              |
| 4: Strings/bytes    | Patterns/format callbacks, packing, UTF-8 boundaries            | M2B-STR-001, M2B-BIN-001  |
| 5: Loading/helpers  | Text environments, Lua package searchers, table/math exports    | M2B-LOAD-001, M2B-LIB-001 |
| 6: Acceptance       | Three files, focused tests, 18 jobs, probes, verified PR        | M2B-ACCEPT-001            |

Remaining M2 work includes closing/goto execution, coroutines, userdata,
weak/finalized objects, remaining libraries, and debug facilities. Canonical
code generation/execution, binary chunks, C ABI, and native ecosystem modules
remain independent gates; M2b does not advance those claims.
