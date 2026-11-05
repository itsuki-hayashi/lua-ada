# Architecture Decision Log

Latest: [ADR 0007: Native continuations](0007-native-libraries.md).

ADR 0007 records explicit native continuation frames, traced library/module
state, shared budgets, and text loading. Its design is accepted; M2b platform
acceptance remains open. ADR 0006's shared frontend and independent canonical
opcode layer remain in force.

| ID   | Decision                                                       | State    |
| ---- | -------------------------------------------------------------- | -------- |
| 0001 | [Foundation policies](0001-foundation.md)                      | accepted |
| 0002 | [Executable M1](0002-m1-execution.md)                          | accepted |
| 0003 | [IEEE values and validity](0003-ieee-values.md)                | accepted |
| 0004 | [Runtime ownership](0004-runtime-ownership.md)                 | accepted |
| 0005 | [Host exponentiation primitive](0005-host-power.md)            | accepted |
| 0006 | [Shared frontend and opcodes](0006-shared-frontend.md)         | accepted |
| 0007 | [Native continuations and libraries](0007-native-libraries.md) | accepted |

Add numbered records for consequential choices. Include date, status, context,
decision, alternatives, consequences, and verification implications. Supersede
records explicitly instead of silently rewriting historical rationale.
