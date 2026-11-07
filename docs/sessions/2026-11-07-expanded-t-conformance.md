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
pass strict builds, all registered AUnit cases and the retained pipeline, then
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

## Consumed condition root repair

Clean a1ffa07 runs the complete Windows upstream-test validation/static
pipeline successfully in instrumented-full-check-2.log, including all 13
primary files, both constructs templates, the helper and matched native
GC/IO/foreign consumers. Linux and Windows default/shared/T jobs also pass.
Their pre-repair AUnit totals differ by applicable platform cases: Windows
1,380, Linux 1,375 and macOS 1,378. Those totals are not skipped test cases.

Workflow 42342542403 finds a real macOS failure: Ada closure.lua times out
after 900 seconds before its first plus marker while unchanged C passes.
The killed process has no shutdown sidecar; the missing file is a secondary
capture error, not the initial failure. This candidate cannot be accepted.

Independent native/owned-bytecode inspection locates the weak-table loop at
closure.lua:39-42. Its consumed guard stays in register R5 while inner string
concatenations allocate in higher registers. Repeated root snapshots can mark
that dead value indefinitely; allocation layout and GC phase determine whether
the bug appears. A bounded explicit-collection reproduction fails on old Ada
and passes on native C, without depending on automatic collection cadence.

The compiler now retires only the temporary on truthy if/while/repeat edges,
before body evaluation or closing callbacks. Lexical/captured values, closing
locals and and/or operand values remain live. Five separately named AUnit and
native-matched Lua regressions cover consumed while, if and repeat guards,
repeat closing, and short-circuit result retention. Independent review is
expanded-condition-roots.cross-review.json. Both strict Windows builds and
all 1,385 AUnit cases pass in both configurations; unchanged closure.lua and
coroutine.lua with T pass again, along with all seven focused T API phases.
Fresh macOS execution and the entire corrected 26-context matrix remain
required. The 900-second/2 GiB primary policy is unchanged.

## Multi-slice scalar root repair

Clean 95baf85 passes both complete local pipelines again in
default-full-check-5.log and instrumented-full-check-3.log. The broader ABI,
frontend/opcode, layout, 1,120-library and 1,024-lifecycle campaigns also pass
again in retained-campaigns-2.log. Its first Linux and Windows CI jobs pass.
Fresh macOS executions still time out in unchanged closure.lua despite all
1,383 applicable AUnit cases passing, including the consumed-condition tests.
The first repair is necessary but does not finish automatic GC progress.

Propagation spans multiple work slices on this graph. Every uncaptured scalar
write previously shaded its value immediately, so repeatedly reading a weak
entry could rescue it in each cycle even after the compiler retired the slot.
The new public Lua regression interleaves weak reads with deliberately small
real collection steps; it passes native default/T and fails the 95baf85 Ada
binary's exact transient-scalar assertion. This removes the host-timing
dependency from the second failure too.

Uncaptured scalar writes now defer marking to the collector's mandatory atomic
stack snapshot. Active/host-owned threads are rescanned directly, and already
visited reachable suspended threads are revisited through gray-again before
weak clearing. Captured-cell, heap-edge, generation and root-packet barriers
remain intact. The private Write contract requires callers to publish the live
interval before the next allocating or collection safe point; Write itself
cannot allocate between storage and publication.

Five separate collector-stack tests cover retained/transient values in both
main and already-visited suspended contexts, plus the native-matched Lua
program. Both strict Windows configurations pass all 1,390 AUnit cases with
zero failed assertions or unexpected errors. The new Lua program, unchanged
closure.lua, unchanged coroutine.lua with T and all seven project T API phases
pass on the repaired local runtime. New cross-platform execution, the entire
26-context gate and final independent adjudication remain pending.

## Complete candidate and independent adjudication

Clean 3107dd6e43e028ae7cd107222802fcf852ded62a passes both complete local
pipelines in default-full-check-6.log and instrumented-full-check-4.log. The
retained-campaigns-3.log passes the isolated ABI experiments, 85 opcodes and
4,096 words, 10,000 lexer cases, 2,000 grammar programs and 2,000 mutations,
native C99/Ada layout, 1,120 library cases and 1,024 lifecycle cases. Lexing and
parsing the other upstream files remains syntax-only evidence.

Workflow 42348074001 passes all 24 jobs and 26 contexts on that same revision.
Its first attempt has 23 passing jobs and one macOS shared-validation checkout
failure while fetching the pinned submodule from GitHub. Only that job is
retried; attempt 2 job 128338436583 passes. GitHub rekeys the 23 reused jobs,
whose actual logs are independently verified byte-identical to their originals.
Those jobs are not counted as fresh executions. Earlier failing campaigns stay
rejected. All eight macOS contexts now pass unchanged closure.lua.

The actual AUnit totals are Windows 1,390, Linux 1,385 and macOS 1,388, with
zero failures/errors; differences are applicable platform registrations. Both
Windows static-PIC configurations pass. Every host selects Alire 2.1.1, native
GNAT 16.1.0 and GPRbuild package 26.0.1. The GPRBUILD banner is 26.0.0, targeting
x86_64-w64-mingw32, x86_64-pc-linux-gnu or aarch64-apple-darwin24.6.0. macOS setup
initially prints bootstrap GNAT 16.2.0, then repository stable selection chooses
16.1.0 for the actual build. No machine-specific pin is committed.

Digest-verified artifacts collect all 338 primary C/Ada pairs and 26 additional
constructs pairs into 728 reports, with helper witnesses and all 26 warning
indices/170 warning processes. Official diagnostic replay passes, explicitly
without final acceptance. Independent actual-observation authoring freezes the
39,041,021-byte proposal at e2534c2745d888f474d19f00a206c8cb4f9cd934af4fe1357d1ad1f5b4619acd.
Lossless canonical compaction preserves every one of its 1,009 projection hashes.

Separate reviewers accept the exact 142 new runtime obligations with 3,488
context associations, 708 retained obligations with 16,824 associations and
159 API entries with 4,134 associations. Ten T-only blocks require their actual
seven instrumented contexts; 26 false lower-precision body links remain reviewed
applicability references and never claim that inactive body executed. Every
instrumented applicable case runs without omission. Default messages retain
only their exact absence provenance and source-linked instrumented coverage.

Root independently checks all 338 contract semantics against all 728 captures
and reviews their 22 distinct protocols, including fresh current math/helper
source applicability. All 104 retained contracts preserve their prior semantics
plus measured source-profile evidence. A separate decision checks all 338 final
LF byte hashes, canonical paths and original-C/default-omission pointers.
Historical whole-file source reviews remain dated; later scalar, condition and
current math/helper decisions own their changed-source applicability.

The guarded installer reconstructs all approved outputs, replays named witnesses
and shared Ada/native-oracle identities, and verifies all 24,446 evidence
fragments. Its dry run authorizes 360 constrained writes. Apply completes 361
writes including its certificate, validates both scopes as complete and preserves
the historical gc-io-events scope. This installs 850 source runtime/audit records,
159 scoped API records and 338 contracts; full M3 and final matrix acceptance
remain false at installation.

## Final revision and handoff protocol

Owning architecture, capability, embedding, testing, backlog and decision guides
are reconciled with merged PR #9 and the implemented continuations/openers/root
repairs. Dated partial observations above remain historical evidence.

The publication revision must be clean and freshly execute all 26 contexts with
the installed contracts enabled. Independent final reconciliation must bind its
338 primary pairs, 52 supplemental reports, named C/AUnit and warning identities,
source/report hashes, actual phases/returns/shutdown and shared runtime images.
The tested head's immutable refs/notes/expanded-t-conformance certificate owns
that exact final result without inserting its own SHA into the tested tree.
The PR records automatic review findings and fixes. Merge verification and final
workflow results are recorded separately against the merge revision, preserving
the accepted head certificate. No candidate or installation receipt replaces
these final gates. Other upstream files, all.lua, heavy.lua, full M3 and global
public ABI completion remain outside this delivery.
