# Architecture Decision Log

Latest: [ADR 0021: External string ownership](0021-external-string-ownership.md), final acceptance pending.

ADR 0007 records explicit native continuation frames, traced library/module
state, shared budgets, and text loading. Its implementation passed M2b acceptance.
ADR 0008 defines the staged M3 target and its separately verified configurations;
its runtime changes are planned, not implemented by the foundation gate.

| ID   | Decision                                                                           | State                 |
| ---- | ---------------------------------------------------------------------------------- | --------------------- |
| 0001 | [Foundation policies](0001-foundation.md)                                          | accepted              |
| 0002 | [Executable M1](0002-m1-execution.md)                                              | accepted              |
| 0003 | [IEEE values and validity](0003-ieee-values.md)                                    | accepted              |
| 0004 | [Runtime ownership](0004-runtime-ownership.md)                                     | accepted              |
| 0005 | [Host exponentiation primitive](0005-host-power.md)                                | accepted              |
| 0006 | [Shared frontend and opcodes](0006-shared-frontend.md)                             | accepted              |
| 0007 | [Native continuations and libraries](0007-native-libraries.md)                     | accepted              |
| 0008 | [M3 conformance and boundaries](0008-m3-conformance.md)                            | accepted              |
| 0009 | [Language lifecycle on the private VM](0009-language-lifecycle.md)                 | accepted              |
| 0010 | [Complete upstream delivery in one PR](0010-full-upstream-delivery.md)             | accepted              |
| 0011 | [Host mathematics and owned RNG](0011-host-mathematics.md)                         | accepted              |
| 0012 | [Canonical programs and chunks](0012-canonical-program-ownership.md)               | accepted              |
| 0013 | [C-owned calls and driver phases](0013-c-owned-call-boundary.md)                   | accepted              |
| 0014 | [One Ada/C core image](0014-one-core-library.md)                                   | accepted              |
| 0015 | [Managed exact numeric scratch](0015-managed-numeric-scratch.md)                   | accepted              |
| 0016 | [Collector inspection and storage equivalents](0016-gc-adapter-equivalents.md)     | scoped acceptance     |
| 0017 | [C continuations and resume](0017-c-continuations-and-resume.md)                   | scoped implementation |
| 0018 | [Compatibility-relevant T coverage](0018-relevant-t-compatibility.md)              | accepted policy       |
| 0019 | [Demand-driven frontend input](0019-demand-driven-input.md)                        | scoped implementation |
| 0020 | [Callable builtin identities](0020-callable-builtin-identities.md)                 | scoped implementation |
| 0021 | [External strings and weak identities](0021-external-string-ownership.md)          | scoped implementation |
| 0022 | [Owned C varargs formatting](0022-c-varargs-formatting.md)                         | scoped implementation |
| 0023 | [Public value and auxiliary operations](0023-public-value-auxiliary-operations.md) | scoped implementation |
| 0024 | [Fixed numeric scratch](0024-fixed-numeric-scratch.md)                             | scoped implementation |
| 0025 | [Native module lifetimes](0025-native-module-lifetimes.md)                         | scoped implementation |
| 0026 | [Real base C closing ownership](0026-base-c-closing-ownership.md)                  | scoped implementation |
| 0028 | [Auxiliary buffer ownership](0028-auxiliary-buffer-ownership.md)                   | scoped implementation |

ADR 0009 records the approved combined delivery order, iterative scheduler,
stable cells, explicit cleanup, weak thread ownership and execution policies.
ADR 0010 supersedes the separate-PR gate order for the approved complete M3
delivery and distinguishes source review from actual conformance evidence.
ADR 0011 extends the host-math compatibility boundary and keeps reproducible
random generation in owned Ada state.
ADR 0012 separates canonical program ownership and native binary encoding
from the still independently verified execution backend.
ADR 0013 keeps foreign callbacks and nonlocal transfers on the C side of an
explicit scheduler boundary and retains real stack windows/upvalue cells.
ADR 0014 makes the root library the single compiled interpreter image shared by
Ada hosts, the C facade and native-module consumers.
ADR 0015 gives exact numeric conversion and formatting explicit managed scratch
ownership while preserving one parser and existing host convenience APIs.

Add numbered records for consequential choices. Include date, status, context,
decision, alternatives, consequences, and verification implications. Supersede
records explicitly instead of silently rewriting historical rationale.

ADR 0026 records [real base C closing ownership](0026-base-c-closing-ownership.md)
and stack-reserved closing links without registration allocation.

ADR 0027 records [protected error closing](0027-protected-error-closing.md),
actual C guard acknowledgement and retained failed-coroutine scope ownership.

ADR 0029 records [owned file input](0029-owned-file-input.md), native stream
cleanup before compilation and shared file/stdin/preamble policy.
