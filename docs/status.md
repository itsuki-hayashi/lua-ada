# Project Status

## Remaining upstream compatibility (2026-11-07)

The [public value/auxiliary checkpoint](sessions/2026-11-08-public-value-auxiliary.md)
has matching local C/Ada evidence for three core and 28 auxiliary exports.
Its 20,000-value binary64 text fingerprint matches both C configurations;
the six scalar and two auxiliary quota regressions pass within 1,664 AUnit
cases. Full surface, runtime matrix and whole-target acceptance remain pending.

The [public C numeric checkpoint](sessions/2026-11-08-c-numeric-conversion.md)
adds allocation-free string conversion and exact `lua_ident` data. Eleven
identical-source C cases match default and native T, including refusal and
two thousand seeded round trips. Strict local default builds and 1,641 AUnit
cases pass; integrated T/shared/platform and full acceptance remain pending.

The [fixed numeric scratch checkpoint](sessions/2026-11-08-fixed-numeric-scratch.md)
reuses the exact parser with a bounded local provider. Strict local default
builds and 1,640 AUnit cases pass. Public C conversion wiring, integrated T,
shared/platform and complete-suite acceptance remain separate obligations.

The [C varargs formatting checkpoint](sessions/2026-11-08-c-varargs-formatting.md)
passes strict Windows validation/static builds and all 1,551 current AUnit
cases. Its four public C contracts also pass unchanged against default and
instrumented C Lua, including actual growth-refusal sweeps and recovery.
This completes two exports locally; full C surface and target acceptance
remain open.

The [external string checkpoint](sessions/2026-11-08-external-string-ownership.md)
passes strict local Windows/default/static builds and 1,557 AUnit cases.
Eighteen public C/Ada ownership/reentry cases match pinned default C;
thirteen ownership cases match native T, with five reentry cases explicitly
skipped because the native instrumented lock rejects them. Ordinary short
strings now have weak universe-wide identity. Integrated Ada T, native-module
unload ordering, all platforms and full acceptance remain pending.

The [syntax diagnostic checkpoint](sessions/2026-11-08-syntax-diagnostic-tokens.md)
passes strict Windows validation/static builds and 1,534 AUnit cases. Its
focused Lua witness matches both C configurations; unchanged unreduced
calls.lua reaches OK locally. Full file protocols, runtime error diagnostics,
instrumented paths and final matrix acceptance remain open.

The [table length checkpoint](sessions/2026-11-08-table-length-results.md)
matches pinned conversion diagnostics and unpack ordering, with 1,507 passing
local AUnit cases. Unchanged unreduced sort.lua reaches OK locally; literals.lua
has a matching default C/Ada runner observation. Both require final-head matrix
and relevant instrumented evidence before target acceptance.

The [runtime numeric locale checkpoint](sessions/2026-11-08-runtime-numeric-locale.md)
adds native-point string conversion while retaining source grammar and exact
rounding. Its strict Windows validation/static component build passes 1,418
AUnit cases, including eight new focused cases. Final integrated acceptance
remains pending.

The [CLI process checkpoint](sessions/2026-11-08-cli-process-controls.md)
passes strict Windows validation/static builds, 1,422 component AUnit cases,
86 Ada process protocols and 32 corresponding pinned-C protocols. Native
loading, signals/readline and complete main.lua acceptance remain open.

Implementation resumes from merged PR #10 on
codex/m3-remaining-upstream-compatibility. The approved target includes all
remaining primary files, aggregate, heavy case, helpers and native fixtures.
Public C/Lua behavior remains mandatory; independently reviewed private T
exclusions are reported separately under ADR 0018. Full acceptance, PR review
and merge remain pending. See the
[session](sessions/2026-11-07-remaining-upstream-compatibility.md).

The first binary-module searcher repair passes the strict Windows validation/
static build and 1,391 AUnit cases, with zero assertion failures or unexpected
errors. This is component evidence, not a full upstream or platform pass.

## Expanded T conformance (2026-11-07)

The delivery on codex/m3-expanded-t-conformance retains the nine previously
exercised primary files and adds constructs.lua, closure.lua, pm.lua and
math.lua, including selected T paths and the bwcoercion.lua helper. The
installed scope resolves 850 runtime/audit obligations and 159 selected API
entries. Its 1,643 non-runtime classifications remain separately reviewed
source inventory, not executed test cases. The historical gc-io-events scope
and unrelated global obligations remain distinct.

Clean candidate 3107dd6e43e028ae7cd107222802fcf852ded62a passed all 24 jobs
and 26 contexts in [workflow 42348074001](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42348074001).
The single checkout-only failure passed when retried on the same revision.
The verified bundle contains 338 primary C/Ada pairs and 26 additional
constructs pairs: 676 primary reports and 52 supplemental reports. It also
contains all 26 warning indices and 170 warning processes. All seven
upstream-test contexts reach their applicable guarded tests without omissions;
default T-absence messages retain explicit instrumented coverage links.

The complete pipelines pass 1,390 applicable AUnit cases on Windows, 1,385 on
Linux and 1,388 on macOS, with zero assertion failures or unexpected errors.
The scoped named catalog selects 100 C cases and 94 AUnit cases with explicit
semantic and platform bounds. The retained ABI, frontend/opcode, native layout,
CLI, binary, consumer and seeded differential campaigns also pass. All hosts
select Alire 2.1.1, stable native GNAT 16.1.0 and GPRbuild package 26.0.1;
the GPRBUILD executable banner is 26.0.0. Required flags and checks stay enabled.

The automatic review of [PR #10](https://github.com/itsuki-hayashi/lua-ada/pull/10)
identified a retained coroutine-status mismatch after allocation refusal.
The correction preserves the memory/error-handler classes already transported
by resume when lua_status queries a failed coroutine. The existing separately
named refusal witness now checks that status both immediately and after scalar
stack access. Its catalog counts stay unchanged. The corrected implementation
requires fresh 26-context execution and independent acceptance on its own head;
the earlier accepted certificate remains dated evidence for its original tree.

Independent decisions bind all 1,009 exact source/API projections, fresh
collector/platform applicability and the final bytes of all 338 execution
contracts. Candidate adjudication and installation do not establish final-head
acceptance. The fresh matrix, independent reconciliation and immutable
certificate in refs/notes/expanded-t-conformance on the tested PR head own
that exact revision's acceptance. The [conformance catalog](../tests/conformance/README.md)
documents retrieval; the [session](sessions/2026-11-07-expanded-t-conformance.md)
preserves failed candidates, repairs and review evidence. Other files, all.lua,
heavy.lua, full M3 and complete public ABI acceptance remain outside this scope.

## Four-file conformance follow-up (2026-11-07)

[PR #9](https://github.com/itsuki-hayashi/lua-ada/pull/9) covers
`events.lua`, `gc.lua`, `gengc.lua` and `files.lua` on Windows, Linux and
macOS. The [session record](sessions/2026-11-07-gc-io-conformance.md)
retains intermediate failures and fixes. The suite contains 1,306 AUnit cases;
the scoped replay selects 35 physical/runtime regressions and 41 named C
consumer cases for the four files and their 77 directly exercised API entries.

At ff93190 the combined pipeline builds one Ada runtime for the CLI, C
consumers and AUnit. Candidate reports identify the binaries by hash.
The events wrapper checks the unchanged chunk returns 12; the collector
observer verifies ten instrumented shutdown warnings after the terminal
`OK`. The collector equivalents replace reviewed implementation-specific
assumptions, including a C byte allowance, with measured Ada behavior.
File equivalents on Windows and macOS and supplemental native checks
are identified separately from unchanged Linux file executions.

The [candidate workflow](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42327273160)
supplied raw evidence for all 26 contexts: 60 unchanged Ada executions,
26 Ada collector equivalents and 18 native file equivalents. The
[observation index](../tests/conformance/reviews/gc-io-events.observation-index.json)
identifies the 42 archives and individual reports. Independent reviewers
resolved 708 runtime/audit entries and 77 scoped API entries; 191 lexical
entries retain their non-runtime classifications. The
[contract index](../tests/conformance/scopes/gc-io-events.contracts.json)
binds each operation to its approved protocol. Final scoped acceptance
passed at 6b263193e8c165df75158f144cf4738dbb040def in workflows
[42330407879](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42330407879)
and [42330402884](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42330402884).
Both passed all 24 jobs/26 contexts; independent reconciliation accepted all
104 operations and 208 process reports. PR #9 is merged. Final certificates
are published in its tested head's gc-io-events-conformance Git note.
Full M3, aggregate and heavy execution, and unrelated C ABI obligations remain
outside this scope.

The paused-checkpoint statements below retain the prior delivery's evidence.

Updated: 2026-11-06 (Asia/Tokyo). **M0, M1, M2a, and M2b complete.**
**M3 is paused at a verified checkpoint. The bounded language lifecycle delivery has completed
runtime acceptance; final publication checks are linked from PR #7.**

## Complete upstream delivery paused

Merged PR #7/master f7031f522006abfd9e2d3ef28975088984400faf is the baseline for
codex/m3-upstream-conformance. The maintainer approved completion of the full
[M3 contract](milestones/m3.md) in one major PR, including the remaining storage,
canonical backend, allocator/C ABI, collector, libraries, CLI and reviewed
coverage work. The [current session](sessions/2026-11-06-m3-upstream-conformance.md)
records actual checkpoint evidence. [ADR 0010](decisions/0010-full-upstream-delivery.md)
supersedes the earlier separate-PR order without reducing acceptance.

Checkpoint 1 distinguishes independently reviewed non-runtime candidates from
actual linked runtime obligations. Its 62 focused inventory regressions pass;
structural validation retains all 34 files, 4,490 pending source anchors and
473 pending header entries. These are harness results, not additional passing
Lua files, complete C API evidence or a full M3 pass. Production implementation
and final 26-context acceptance remain in progress.

## Implemented and verified

Owned Ada sessions and the batch CLI execute the M1 language subset plus
[M2b core libraries and metamethods](milestones/m2b.md). The shared resolving
frontend lowers to private register bytecode; explicit Lua/native activations
retain lexical captures, result packets, callback state, and load environments.
Iterative tracing reclaims unreachable tables, closures, cycles, and prototypes.

Fresh sessions provide the exact [export inventory](capabilities.md): core
metamethods, strings/patterns/formatting/packing, UTF-8, common table/math helpers,
protected calls, text loading, and Lua-only package searchers. State, metatables,
module registries, output, and budgets remain isolated per session.
See [embedding](embedding.md), [CLI](cli.md), and
[ADR 0007](decisions/0007-native-libraries.md).

The final [M2b matrix](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42090465632)
at revision 52e8eb62466c5852b3995dc99b751c1d477dc9c2 passed all 18
Windows/Linux/macOS × development/validation/release × static/shared jobs.
Every job passed 480 individually named AUnit cases, zero failed assertions or
unexpected errors, the public Ada consumer, 30 CLI cases, and seven differential
fixtures. Each executed three unchanged upstream primary files: tpack.lua,
utf8.lua, and bitwise.lua, with raw same-host C/Ada stdout equality, empty stderr,
default 1,000,000 instructions, and a 120-second timeout. bwcoercion.lua is an
unchanged helper, not a fourth suite.

All three OS static-validation jobs passed native C99/Ada layout comparisons,
the 1,120-case seeded library campaign, retained frontend/opcode campaigns, and
isolated ABI probes. Windows validation/static-PIC also passed the full pipeline.
The [validation record](validation-m2b.md) owns exact code revision, job logs,
tool versions, host layouts, and scope limits, including earlier intermediate
counts. PR #4 is merged; master f30be387720f3ddb7ef3e799b13658e9b6bce515 is
the M3-01 starting point. Historical session records retain their dated results.

Tools: Alire 2.1.1, stable native GNAT 16.1.0, AUnit 26.0.0, GPRbuild package
26.0.1 (banner 26.0.0). Strict flags and runtime checks remain enabled; the
existing ADR 0003 floating-validity exception is unchanged.

## Current full M3 checkpoint

The latest Windows/default/validation/static implementation passes 1,086
separately named AUnit cases with zero failed assertions or unexpected errors.
The complete retained pipeline also passes its 39-case C consumer, mixed/startup
and Ada consumers, nine raw-byte output processes, eleven PE-table structural
regressions, 35 CLI cases, ten binary CLI comparisons, twelve differential
fixtures and five unchanged upstream files. Strict flags and runtime checks
remain enabled. The session record owns exact commands and repairs.

Code checkpoint 32398fa64d5e5c2ec604dee31be6b37afb44eb99 passes all 18
jobs in [run 42234588442](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42234588442),
including Windows static-PIC. Every full job log was inspected. CI tested PR
merge 57c0be91079fa09b7f0a9634ab49b0509264a53e into master f7031f52.
Native C aggregate observations still record the pinned macOS readline-assumption
failure; neither those observations nor this retained matrix establish full M3.

At the maintainer's request, development is paused. The subsequent unfinished
collector/core-callback/typed-exit/IO integration is preserved in a local Git
stash and verified recovery bundle; it is excluded from the PR. Its exploratory
run passed 1,185 of 1,187 cases, with two assertion failures, and is explicitly
unaccepted. The session record owns recovery details and the next action.

**Verified upstream execution: five of 30 primary files.** The passes are
tpack.lua, utf8.lua, bitwise.lua, goto.lua and coroutine.lua. All use the
recorded default configuration with T absent; coroutine omissions remain
explicit. bwcoercion.lua executes as a helper and is not a sixth suite. The
other 25 primary files, all.lua aggregate, heavy.lua stress and tracegc.lua
helper remain pending whole-file acceptance. See the
[current inventory](upstream-tests.md#paused-m3-execution-status).

The verified checkpoint adds allocation-free warning events and actual C warning
callbacks, a borrowed iterative driver for Ada-to-C-to-Lua calls, and finalizer
queue/controller components. Default auxiliary states start with warnings on,
matching pinned Lua 5.5.1; bare C states have no default warning handler.
Finalizer component tests invoke actual Lua callbacks, preserve errors and roots,
and defer work when callback stack space is unavailable. Production metatable
enrollment, real collector modes, state-close draining and IO/OS integration
remain open. These component tests are not a claim of public finalizer support.
Physical disposal after an interrupted finalizer preserves resurrected resources
until their actual release. No additional whole upstream file is claimed.

The earlier checkpoint sequence below retains its original evidence counts.

The validation/static checkpoint passes 816 AUnit cases, the Ada consumer,
35 CLI cases, nine byte-exact differential scripts and the five retained
unchanged upstream files. The new mathematics campaign matches 714 same-host
C output records. Its initial integration failures exposed zero-argument RNG
routing and Windows' pinned C89 logarithm selection; both were repaired before
this passing run. Exact commands and limits are in the
[current session](sessions/2026-11-06-m3-upstream-conformance.md).

Owned scanner/arena/parser storage now uses the selected allocator. The retained
frontend campaign passes 10,000 arbitrary-byte lexer cases, 2,000 generated
syntax cases, 2,000 mutations, all 34 unchanged upstream parse-only inputs and
4,096 opcode records. These remain checking evidence, not whole-file execution.

Canonical compilation, native binary chunks and real scalar-register execution
are implemented internally. Thirty-six four-way cases compare C source, C
execution of Ada-produced chunks and Ada execution of both producers' chunks.
Focused cases cover captures, live stack roots, closing, coroutines, callbacks,
locals/upvalues and source metadata. Ordinary CLI/session compilation now uses canonical instructions. Its first
complete retained pipeline passes 818 AUnit cases, five upstream targets,
35 CLI cases, nine differential files and the Ada consumer. The later explicit
runtime-container ownership checkpoint passes that same pipeline with 829 cases.
The binary loading/dumping checkpoint passes the full retained pipeline with
848 AUnit cases and ten additional C/Ada binary CLI comparisons. Platform
evidence for that later revision remains pending.

The first published checkpoint failed a macOS arithmetic NaN-bit comparison.
A host arithmetic adapter replaces that x86-specific bit synthesis. The next
checkpoint passes all twelve Linux/Windows jobs, including Windows static-PIC,
but macOS stops in the new standalone-runtime link/startup checks. Follow-up
repairs propagate the selected GNARL archive and clean embedded/runtime search
paths. All six macOS jobs at a4e5e338a27630bd077bc7f7fe294500f10162b7
passed in run42207946868, and their logs were inspected. That run failed
all six Linux jobs on a measured libc alternate-general formatting carry
difference. The generic rounding/host-policy repair now passes the local
968-case pipeline and both formatting campaigns; its Linux CI rerun remains
required. No failure was masked or reclassified as passing.

The production root is now one liblua image for Ada and C consumers. Static
and shared C/API, mixed state/allocator/pool identity, and C-only startup checks
pass locally. The real C consumer passes eighteen cases; full continuations
and remaining ABI evidence are still required. Runtime inspection then passes
866 AUnit cases, including fifteen new metatable/registry/cell-joining cases.
The full retained validation/static pipeline also passes, including the
eighteen-case C consumer, mixed/C-only startup checks, ten binary CLI cases,
35 CLI cases, nine differential files and five retained upstream files.
The later managed numeric checkpoint passes 916 cases and all retained
checks, including 1,435 formatting records. Sorting and real table reservation
then pass 940 cases and eleven differential files, including 465 table
algorithm records. These are local Windows/default/validation/static results.
Later checkpoints add context-owned activation caching and real inline,
C-aligned full userdata with traced uservalues. The full retained local
pipeline passes 964 AUnit cases and 30 real C consumer cases; the formatting
carry repair then passes 968 cases. Output ownership, full foreign execution,
collector modes/finalizers, libraries and the complete test adapter remain
required.
The source-selected instrumented configuration has no full runtime/platform
acceptance yet. All 4,490 source anchors and 473 header entries remain pending;
no component result closes the final 26-context M3 acceptance gate.

## Current M3 language lifecycle work

Merged PR #6, master bbc6e230cc1fcf4d20eb3caf02077b6bb0c0f46a, is the baseline.
The approved [combined delivery](milestones/m3-language-lifecycle.md) implements
goto/labels, closing, all Lua-facing coroutine exports, thread identities,
reachability-based context ownership, weak tables/ephemerons, debug inspection
and hooks, collection controls, and compatible CLI execution quotas. This
advances portions of M3-02/06/07/08/11; their full broader gates remain open.

Runtime revision 830e0a1a2bad905ef34da3d553b24f8260ef35ff passes all 18
Windows/Linux/macOS × development/validation/release × static/shared jobs, plus
Windows static-PIC. Every job log was inspected: 587 successful AUnit cases
(99 new), zero failed assertions/errors, the Ada consumer, 35 CLI cases, eight
differential fixtures and five selected unchanged upstream files.

The new goto.lua and coroutine.lua pass fresh independent same-host C/Ada
process comparisons with identical stdout, empty stderr and OK markers.
coroutine.lua is **default-configuration execution with documented upstream
omissions**, not complete coroutine or C-API conformance. Exact omitted source
anchors and the 900-second/2 GiB sampled resident-process policy are in the
acceptance owner. The three M2b targets retain their bounded acceptance profile.

All three static-validation jobs pass ABI/frontend/opcode/layout/library checks
and the 1,024-case seeded lifecycle campaign. [Validation evidence](validation-m3-lifecycle.md)
records exact run/job IDs, tool versions, marker counts and scope limits. Final
publication-head checks and readiness are recorded in
[PR #7](https://github.com/itsuki-hayashi/lua-ada/pull/7); no merge is authorized.
Reference/module pins remain unchanged and ecosystem fixtures remain unused.

## Earlier evidence and remaining work

Historical [M1 validation](validation.md) and [M2a validation](validation-m2a.md)
retain their original counts and configurations. M2a's complete checking
interface and 85 canonical opcode definitions remain independent of execution.
Checking and execution now share executable goto/label/close constructs.

This remains a documented Lua subset. Finalizers, collector modes,
remaining debug/io/os facilities and libraries, full C API/ABI, native modules
and LuaRocks remain
required work. Five selected default-configuration files do not establish the complete
standard suite or T-enabled C-API conformance.

The eight [consumer module fixtures](../tests/modules/README.md) retain their
pins and remain unbuilt/unexecuted future inputs. GNATdoc rendering, GNATtest
generation, fuzz campaigns, and formal proof were not run.

See [upstream coverage](upstream-tests.md), [roadmap](roadmap.md),
[backlog](backlog.md), and the
[current session](sessions/2026-11-06-m3-upstream-conformance.md).
