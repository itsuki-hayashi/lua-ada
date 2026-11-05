# Roadmap

Milestones are dependency gates, not calendar promises. The backlog owns concrete
work and status owns verified capabilities. No interpreter completion date is set.

| Milestone | Deliverable                             | Completion gate                       |
| --------- | --------------------------------------- | ------------------------------------- |
| M0        | Foundation                              | Layout, policies, references, docs    |
| M1        | Libraries, AUnit, ABI feasibility       | Both link modes; C-boundary evidence  |
| M2        | Values, heap, roots, numeric primitives | Ownership and failure tests           |
| M3        | Frontend, chunks, VM                    | Incremental language/dump tests       |
| M4        | GC, coroutines, standard libraries      | Lifetime/yield/library regressions    |
| M5        | Ada/C interfaces and module ecosystem   | Embedders, modules, LuaRocks fixtures |
| M6        | Conformance and release hardening       | Published platform acceptance matrix  |

GC and coroutine architecture must be considered during M1/M2, even though full
behavior lands later. ABI feasibility is early because it can change ownership,
allocation, and unwinding design. Do not defer these constraints until M5.

M1 adds static/shared targets with artifact isolation, a nested test-only AUnit
crate, meaningful initial tests, and Windows/Linux/macOS CI. M2 onward expands
tests with behavior, keeping detailed APIs and representations subject to focused
decisions. M6 requires applicable upstream tests, reviewed internal equivalents,
differential regressions, C API/ABI, chunks, and module evidence without hidden
failures or unsupported platform claims.
