# Expanded T conformance delivery

Date: 2026-11-07, Asia/Tokyo. Status: implementation in progress; not accepted.

The maintainer approved one delivery on `codex/m3-expanded-t-conformance`,
starting at merged PR #9 (`b87c58f`). Preserve and complete the existing draft.
The scope retains tpack.lua, utf8.lua, bitwise.lua, goto.lua, coroutine.lua,
events.lua, gc.lua, gengc.lua and files.lua, adding constructs.lua, closure.lua,
pm.lua and math.lua. bwcoercion.lua is a covered helper, not a fourteenth
primary. All selected T obligations require actual instrumented evidence.
Reviewed source-linked Ada/internal and native-platform equivalents remain
permitted. Unrelated M3 obligations, all.lua and heavy.lua remain pending.

Merge is authorized after complete scoped acceptance, passing current-head
checks and resolution of every automated review finding. This delivery
supersedes earlier branch/no-merge instructions only within this scope.

## Starting evidence

PR #9 was accepted at `6b263193e8c165df75158f144cf4738dbb040def` and merged.
Its final workflows 42330407879 and 42330402884 each passed all 24 jobs,
covering 26 contexts. Independent reconciliation accepted 104 paired operations
and 208 process reports. Its source and API evidence retains that revision;
changes here require fresh runs rather than inheriting old process results.

The initial tracked diff and untracked-file list are preserved under ignored
reports/expanded-t-conformance. The initial nested test build used:

```text
alr -n -C tests build --validation --profiles=lua_ada=validation -- -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_PREBUILT=false
```

It failed strict compilation: redundant C_Continuation visibility, several
foreign-driver layout diagnostics, and missing long_long operator visibility
in the C-hook unit. Log: reports/expanded-t-conformance/baseline-build.log.
No baseline test pass is claimed. Tools: Alire 2.1.1, native GNAT 16.1.0,
GPRbuild package 26.0.1. Required flags and runtime checks remain enabled.

## Acceptance protocol

The new expanded-t-conformance scope must preserve the old gc-io-events scope,
all source anchors and reference/consumer-module pins. Audit generated code,
aliases, callbacks, configuration/T guards and shutdown behavior independently.
Every applicable obligation needs actual evidence; a T-absent process does not
certify its omitted body. Instrumented runs must contain no skipped applicable
cases. Original sources remain unchanged in disposable work directories.

Final acceptance requires 13 primary files in all 26 contexts: 338 C/Ada pairs
and 676 process reports, plus helper, dynamic-branch and named regression
witnesses. Preserve the 900-second/2 GiB primary policy, measured runtime and
oracle identities, raw streams, seeds, shutdown accounting and independently
reviewed contracts. Source/classification reviews, candidate observations and
final-revision acceptance remain distinct evidence.

constructs.lua chooses one of two generated-expression templates randomly;
both branches need seeded source-preserving executions in each context.
math.lua's printed random-seed pair must be retained for reproduction.

## Implementation in progress

Parallel work completes the real C resume/continuation/hook/library paths,
generalizes scoped validation and prepares source-hashed audit proposals.
The arithmetic diagnostic now resolves the failed operand from real canonical
reaching definitions; pattern fixes retain original gsub identity when every
replacement is unchanged. Added cases remain unverified until the next build
and execution reports are inspected.

## First integrated checks

The strict default runtime build passed after the baseline layout/visibility
repairs. Its first AUnit run passed 1,321 of 1,323 cases, with one assertion
failure and one unexpected error. The new numeric-metamethod case exposed a
real primitive-applicability defect for nonintegral floats; bitwise fallbacks
must try a numeric type's handler before reporting integer conversion failure.
The existing replacement-root case also needed its actual capture index updated
after the separately traced changed flag was added. Neither failure is counted
as passing evidence; later full reruns remain required.

The integrated upstream-test strict build passes. The focused T script reaches
all five phase markers and T COROUTINE API OK in
reports/expanded-t-conformance/t-api-smoke-6.log. It exercises actual public C
drivers, yielded captures, immediate protected errors, yielding count hooks and
independent states. This is focused Windows evidence, not whole-file acceptance.

The new permanent public foreign consumer has 32 separately identified cases:
18 continuations, nine portable hook/closing/error cases and five math reopen
cases. The identical sources pass the separately built native C oracle in both
configurations, with strict C99 warnings, in native-foreign-{configuration}.log.
Native observations corrected two initial test assumptions: resume-error stack
counts can retain traceback values, and completed results must be removed
before testing an empty dead root. Normal Lua 5.5 close callbacks receive only
self; error close callbacks receive the actual error object as well.

The standalone Ada consumer currently passes its first four cases and aborts
on the suspended fixed-result call, as recorded in
foreign-consumer-instrumented.log. The corresponding AUnit process aborts too;
no complete integrated suite pass is claimed. The retained GDB logs locate
the scheduler's foreign-boundary adjustment rather than hiding that failure.

Independent source review found configuration/host-branch applicability gaps
in the initial author packet. Corrections must bind default coroutine omission
reports to default contexts and measure width, endian and precision conditions
before adjudicating inactive alternatives. No reviewed classification or
lexical inventory count is runtime acceptance. The source author and harness
reviewer are correcting those bindings before any coverage promotion.

## Reviewed boundary repairs

The later native-matched consumer has 48 public cases: 25 continuation/stack
cases, 14 portable hook/closing/refusal/indexing cases, five math reopen cases
and four direct debug/string/table/UTF-8 opener cases. The stale-frame-token
check remains a separate Ada safety invariant outside the native API lifetime
contract. Both native configurations pass all 48 cases; source-bound local
logs are reports/expanded-native48-default.log and expanded-native48-upstream.log.

Native checking corrected two further first-party test preconditions. A hook
can expose the Lua frame's complete ci.top, so pushing arguments requires
lua_checkstack and weak-reachability checks must first retire the extra public
tail. A failed coroutine cannot execute lua_pcall without resetting; recovery
therefore calls the healthy parent and checks only the failed child's scalar
stack API. Those changes preserve valid native behavior rather than bypassing
an Ada failure.

Independent runtime review identified nested boundary ownership, unprotected
post-yield errors, exceptional driver restoration, C API execution above
suspended frames, immediate C closing, invalid hook-yield mutation, resume
error consistency, Lua/C takeover, combined hook event ordering and hidden
root retention. Focused fixes and regressions address these. Detached public
windows are traced as a separate ordered interval; interrupted Lua hooks
discard resume arguments. Due count and line events precede one suspension.
Error prefixes now share the actual bounded chunk identifier with debug info.

The strict upstream-test validation/static build12 passes, and its fresh
runtime-instrumented-tests-7.log records 1,380 successful cases with zero
assertion failures or unexpected errors. The seven-phase project T script
and the unchanged full coroutine.lua with T pass again in
t-api-smoke-review.log and coroutine-t-review.json/.stdout/.stderr.
All these observations are local and dirty; final matrix acceptance is pending.

The scoped audit now selects 159 directly exercised API/header entries.
Source-only review resolves 1,452 lexical classifications while 142 actual
runtime/audit obligations remain pending execution adjudication. The API,
consumer and AUnit witness mappings require independent approval and fresh
context evidence. Final collection schedules 338 primary operation pairs and
26 additional constructs branch pairs: 728 process reports in 26 contexts.

## Local default pipeline

The complete Windows/default/validation/static pipeline passes in
reports/expanded-t-conformance/default-full-check-4.log. It executes all 13
primary files, both constructs templates and the helper witness, with exact
default T-absence provenance. Retained AUnit, public consumers, CLI, binary,
differential, warning and shutdown checks also pass. Runtime implementation is
committed as dc55aae; the local observations span the dirty draft and that
checkpoint, so they are diagnostic evidence rather than frozen-tree acceptance.
The complete upstream-test pipeline and clean 26-context candidate remain next.

## Evidence freeze corrections

Candidate f6b96b0 starts workflow 42341677097. Its first Linux and macOS logs
pass strict builds, 1,380 AUnit cases and the retained preceding pipeline, then
reject stale review hashes before expanded execution. Six locally authored
review JSON files used Windows line endings while Git published LF bytes.
Normalize the review artifacts before hashing and cascade all bound identities;
the rejected candidate is not conformance acceptance.

The first complete local upstream-test pipeline likewise stops on a stale
review binding after passing the focused T script, eight actual warning probes
and unchanged GC/events executions. Its retained log is
reports/expanded-t-conformance/instrumented-full-check-1.log. It is incomplete.

Independent adjudication preparation also found that the matrix collector
did not require the retained warning-regression index. Bind and replay all
26 context indices, including exact per-target diagnostics, real return and
shutdown behavior, source identity and captures, before final acceptance.

The retained local Windows campaigns pass in
reports/expanded-t-conformance/retained-campaigns-1.log: isolated ABI checks,
pinned frontend/opcode comparisons, native C99/Ada layout equality, all 1,120
seeded library cases and all 1,024 seeded lifecycle cases. Frontend lexing and
parsing of other upstream sources is syntax evidence, not runtime acceptance
for files outside the selected 13.

The corrected harness has independent approval f3dbf724, bound to 41 actual
LF source/review inputs. It now requires all 26 warning indices and 170 named
warning processes (19 default contexts with six probes and seven T contexts
with eight). Validation passes 21 warning-evidence, 58 expanded-scope, 46
review-binding, 18 native-mapping and ten bundle-collector regressions, plus
the retained suites. Fourteen actual Windows default/T warning captures pass
the shared exact-byte verifier. Foreign-platform verifier fixtures remain
synthetic until the replacement CI campaign executes them.
