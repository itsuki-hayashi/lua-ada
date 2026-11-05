# Roadmap

M0 is complete. M1 was expanded from infrastructure into the accepted
[basic interpreter target](milestones/m1.md). Milestones are acceptance gates,
not calendar promises.

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
