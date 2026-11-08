# Session Records

Correction: [declaration activation](2026-11-08-declaration-activation-correction.md).

Component: [compiler limit context](2026-11-08-compiler-limit-context.md).

Component: [instruction hook-mask transitions](2026-11-08-hook-mask-transitions.md).

Component: [parser stack limits](2026-11-08-parser-stack-limits.md).

Observation: [retained T source replay](2026-11-08-retained-t-source-replay.md).

Source review: [exact API/calls equivalents](2026-11-08-exact-api-calls-equivalents.md).

Component: [assert argument presence](2026-11-08-assert-arguments.md).
Component: [reader refusal and self-close](2026-11-08-reader-refusal-lifecycle.md).

Component: [runtime failure storage](2026-11-08-runtime-failure-storage.md).
Component: [public T traceback command](2026-11-08-t-traceback-command.md).

Component: [coroutine result portals](2026-11-08-coroutine-result-portals.md).

Component: [managed diagnostic text](2026-11-08-managed-diagnostic-text.md).
Component: [linear Lua readers and declaration lines](2026-11-08-linear-lua-readers.md).

Component: [memory-verifier ordering](2026-11-08-memerr-verifier.md).

Component: [actual stack inspection](2026-11-08-stack-inspection.md).

Component: [C API self-valued assignments](2026-11-08-c-api-self-values.md).

Component: [hidden named varargs](2026-11-08-hidden-named-varargs.md).
Component: [label semantic boundaries](2026-11-08-label-semantic-boundaries.md).

Component: [function definition store sites](2026-11-08-function-store-sites.md).

Component: [base setmetatable arguments](2026-11-08-metatable-argument-phases.md).
Component: [return windows through closers](2026-11-08-close-return-windows.md).

Correction: [native tail return publication](2026-11-08-native-tail-return-windows.md).

Component: [actual return-hook windows](2026-11-08-return-hook-windows.md).

Component: [sort argument phases](2026-11-08-sort-argument-phases.md).

Component: [binary source display](2026-11-08-binary-source-nul.md).

Component: [owned argument labels](2026-11-08-owned-argument-labels.md).

Component: [selected debug-line baselines](2026-11-08-selected-line-baselines.md).

Component: [string arguments and scalar results](2026-11-08-string-arguments-results.md).

Component: [owned argument details](2026-11-08-owned-argument-detail.md).

Component: [borrowed C stack views](2026-11-08-borrowed-c-stack-views.md).

Component: [public-boundary integration](2026-11-08-public-boundary-integration.md).

Component: [scalar logical negation](2026-11-08-scalar-not-refusal.md).

Component: [panic and provider controls](2026-11-08-panic-provider-controls.md).

Component: [shared traceback rendering](2026-11-08-shared-traceback.md).

Component: [I/O and collector arguments](2026-11-08-io-collector-arguments.md).
Component: [argument registry continuations](2026-11-08-argument-registry-continuations.md).

Component: [public value identities](2026-11-08-public-value-identities.md).

Component: [public C concat windows](2026-11-08-c-concat-windows.md).

Component: [public file loading](2026-11-08-public-file-loading.md).

Component: [literal auxiliary substitution](2026-11-08-auxiliary-substitution.md).

Component: [public auxiliary allocator](2026-11-08-public-auxiliary-allocator.md).

Current: [remaining upstream compatibility](2026-11-07-remaining-upstream-compatibility.md).

Previous: [expanded T conformance](2026-11-07-expanded-t-conformance.md).

Component: [runtime numeric locale](2026-11-08-runtime-numeric-locale.md).

Component: [CLI process controls](2026-11-08-cli-process-controls.md).

Component: [table length results](2026-11-08-table-length-results.md).

Component: [syntax diagnostic tokens](2026-11-08-syntax-diagnostic-tokens.md).

Previous: [four-file GC/IO conformance](2026-11-07-gc-io-conformance.md).

Previous checkpoint: [complete M3 upstream conformance](2026-11-06-m3-upstream-conformance.md).

Previous: [major M3 language lifecycle](2026-11-06-m3-language-lifecycle.md).
The current delivery follows merged PR #7 and combines all remaining M3 work
into one major PR. Historical session results retain their original scope.

| Date       | Session                                                                    |
| ---------- | --------------------------------------------------------------------       |
| 2026-11-05 | [Initial foundation](2026-11-05-foundation.md)                             |
| 2026-11-05 | [Initial M1 gates](2026-11-05-m1-gates.md)                                 |
| 2026-11-05 | [M1 interpreter](2026-11-05-m1-interpreter.md)                             |
| 2026-11-06 | [Module fixture setup](2026-11-06-ecosystem-fixtures.md)                   |
| 2026-11-06 | [M2a frontend implementation](2026-11-06-m2a-frontend.md)                  |
| 2026-11-06 | [M2b core libraries](2026-11-06-m2b-core-libraries.md)                     |
| 2026-11-06 | [M3-01 contracts and harness](2026-11-06-m3-01-contracts.md)               |
| 2026-11-07 | [Reader input](2026-11-07-demand-driven-input.md)                          |
| 2026-11-08 | [Public C debug identity](2026-11-08-c-debug-identity.md)                  |
| 2026-11-08 | [Callable builtins](2026-11-08-callable-builtins.md)                       |
| 2026-11-08 | [C varargs formatting](2026-11-08-c-varargs-formatting.md)                 |
| 2026-11-08 | [Public value and auxiliary](2026-11-08-public-value-auxiliary.md)         |
| 2026-11-08 | [External string ownership](2026-11-08-external-string-ownership.md)       |
| 2026-11-08 | [Fixed numeric scratch](2026-11-08-fixed-numeric-scratch.md)               |
| 2026-11-08 | [C numeric conversion](2026-11-08-c-numeric-conversion.md)                 |
| 2026-11-08 | [C operator windows](2026-11-08-c-operator-windows.md)                     |
| 2026-11-08 | [Native module loading](2026-11-08-native-module-loading.md)               |
| 2026-11-08 | [Host base C closing](2026-11-08-base-c-closing.md)                        |
| 2026-11-08 | [Closing scalar prefixes](2026-11-08-closing-stack-prefix.md)              |
| 2026-11-08 | [Auxiliary buffers](2026-11-08-auxiliary-buffer-ownership.md)              |
| 2026-11-08 | [Protected error closing](2026-11-08-protected-error-closing.md)           |
| 2026-11-08 | [Concatenation operations](2026-11-08-concat-operation-diagnostics.md)     |
| 2026-11-08 | [Library argument diagnostics](2026-11-08-library-argument-diagnostics.md) |
| 2026-11-08 | [Metamethod argument roots](2026-11-08-metamethod-argument-roots.md)       |

| 2026-11-08 | [Concat operations](2026-11-08-concat-operation-diagnostics.md) |

| 2026-11-08 | [Public thread reset](2026-11-08-thread-reset.md)            |
| 2026-11-08 | [Public API command driver](2026-11-08-public-api-driver.md) |

Add one record per substantive AI session, using `YYYY-MM-DD-topic.md` and
the user's timezone (currently Asia/Tokyo). Include objective, changes, decisions,
commands/tool versions, results, limits, and next steps. Use a suffix for multiple
records on one date. Historical evidence is immutable except for factual fixes;
current capability belongs in [status](../status.md).
