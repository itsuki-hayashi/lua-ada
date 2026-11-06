# Architecture Decision Log

Latest: [ADR 0009: language lifecycle](0009-language-lifecycle.md).

ADR 0007 records explicit native continuation frames, traced library/module
state, shared budgets, and text loading. Its implementation passed M2b acceptance.
ADR 0008 defines the staged M3 target and its separately verified configurations;
its runtime changes are planned, not implemented by the foundation gate.

| ID   | Decision                                                           | State    |
| ---- | ------------------------------------------------------------------ | -------- |
| 0001 | [Foundation policies](0001-foundation.md)                          | accepted |
| 0002 | [Executable M1](0002-m1-execution.md)                              | accepted |
| 0003 | [IEEE values and validity](0003-ieee-values.md)                    | accepted |
| 0004 | [Runtime ownership](0004-runtime-ownership.md)                     | accepted |
| 0005 | [Host exponentiation primitive](0005-host-power.md)                | accepted |
| 0006 | [Shared frontend and opcodes](0006-shared-frontend.md)             | accepted |
| 0007 | [Native continuations and libraries](0007-native-libraries.md)     | accepted |
| 0008 | [M3 conformance and boundaries](0008-m3-conformance.md)            | accepted |
| 0009 | [Language lifecycle on the private VM](0009-language-lifecycle.md) | accepted |

ADR 0009 records the approved combined delivery order, iterative scheduler,
stable cells, explicit cleanup, weak thread ownership and execution policies.

Add numbered records for consequential choices. Include date, status, context,
decision, alternatives, consequences, and verification implications. Supersede
records explicitly instead of silently rewriting historical rationale.
