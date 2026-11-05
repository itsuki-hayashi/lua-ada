# Roadmap

M0 and M1 are complete. M1 expanded infrastructure into the accepted
[basic interpreter target](milestones/m1.md). Milestones are acceptance gates,
not calendar promises. The [M1 validation record](validation.md) closes all five
gates on the named Windows/Linux/macOS configurations.

| Milestone | Target                                    | Completion gate                        |
| --------- | ----------------------------------------- | -------------------------------------- |
| M0        | Foundation                                | Layout, policies, references, docs     |
| M1        | Basic Lua scripting interpreter           | Core scripts, Ada API, batch CLI, GC   |
| M2        | Remaining language and standard libraries | Deferred syntax, metatables, libraries |
| M3        | Full C embedding and binary compatibility | C API/ABI, chunks, lifecycle evidence  |
| M4        | Modules and ecosystem                     | Native loading and LuaRocks fixtures   |
| M5        | Conformance and release hardening         | Published platform acceptance matrix   |

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
