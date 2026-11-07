# Project Status

## Active four-file follow-up (2026-11-07)

The maintainer resumed implementation after merged PR #8 on
codex/m3-gc-io-conformance. The target is complete events.lua, gc.lua,
gengc.lua and files.lua coverage, including T obligations and all 26 contexts.
PR #9 remains a draft. The [current handoff](sessions/2026-11-07-gc-io-conformance.md)
records exact revisions, reports and limits. Local Windows default and
instrumented validation/static AUnit runs pass 1,306 cases. Reviewed GC and
Windows file equivalents execute against the actual Ada runtime; unchanged
Linux file observations pass in both configurations. The C-specific GC byte
allowance remains an explicitly reviewed Ada equivalent, never an unchanged pass.
All Windows and Linux jobs at 04b9968 passed, including both Windows static-PIC
steps. Mac C/Ada GC and events observations passed, and the Mac file oracle
passed the repaired shell counterpart before reaching a calendar difference.
At e028dae, the Mac C oracle normalized seconds 60 and 61 at maximum `tm_year`
to midnight on the same date; direct input of the next year was rejected.
The fifth Mac equivalent span now checks those native results, reverse conversion
and recovery. Complete corrected Mac C/Ada file runs remain pending.
The scoped events launcher also verifies the unchanged file returns 12 through
`dofile`, matching the check in upstream `all.lua`. The test warning observer
measures all ten instrumented
GC shutdown errors after their original ordering assertions; actual local C
and Ada runs report ten with balanced storage. Independent semantic reviews
are recorded separately from final-revision execution acceptance.
These observations do not close
any selected file's full coverage; complete T inspection, reviewed equivalents,
scoped harness acceptance and the final 26-context matrix remain open.
The C facade now exposes real IO/OS module openers with shared Ada export
construction, stable file-metatable identity on reopen, and public FILE/closer
consumer regressions. Both Linux instrumented jobs pass on published 915df28;
final-revision acceptance remains outstanding.
Real lua_gc controls now share the production collector, with C-owned finalizer
calls and explicit state-close finalizer drainage. Seven shared public C
contracts compare controls, steps, finalizers, warnings, allocator refusal and
physical cleanup against the pinned oracle. Full scoped acceptance remains open.
The gc-io-events scope now selects all four partitions (762 original anchors)
and 77 direct API entries while preserving full-inventory validation. Its
completion and per-operation acceptance commands remain fail-closed on pending
reviews/coverage. The actual launcher supplies measured configuration reports
for parent, bare-lua and arg-selected child checks. Both matrices now schedule
all four selected files; this does not replace final-revision evidence or review.
Independent classification review has now expanded those 762 original anchors
with 137 source-hashed runtime blocks for generated code, helper invocations,
callbacks and shutdown. All original identities and bytes are preserved.
The ledger has 191 reviewed lexical entries and 708 pending runtime/audit
entries; all 77 scoped API entries retain pending execution evidence. Native
calendar counterparts record actual C/Ada guard facts separately from unchanged
source execution. New direct C macro tests close identified mapping gaps, and
a focused minormul regression checks actual minor collection debt sensitivity.
These additions do not establish scoped completion or full M3 acceptance.
File equivalents now use the same scoped operation/report path, with native
counterpart tests retained separately. Platform launchers verify measured
parent/bare-child/arg-child settings and balanced probe/main-child telemetry.
Full local default and instrumented validation/static pipelines retain 1,305
AUnit cases. Shared harness regressions total 40, scope regressions 38, plus
two actual launcher-isolation regressions in each configuration.
The subsequent reviewed macro/native-branch checkpoint passes the full local
instrumented pipeline with 1,306 AUnit cases and a default AUnit rerun at the
same count. Scope regressions are now 41, matrix regressions 33 and review
binding regressions 32. All 18 Windows/Linux contexts passed at c247afb;
macOS and the later checkpoint's complete matrix remain pending.
The matrix reconciliation command requires all 104 file/context pairs and
paired C/Ada reports. It rehashes captures, replays completion/acceptance checks,
and verifies compiled runtime/launcher profiles and library type against each
context. Thirty synthetic matrix and thirty review-artifact binding regressions
pass; they establish harness behavior only. Accepted equivalent decisions now
bind actual reviewed files, spans, replacement bytes and counterpart sources.
The complete reviewed real matrix remains outstanding.
The same three public IO/OS consumer cases now also run in an isolated C-oracle
executable, comparing real FILE/closer layout, module reopening and native
closure with Ada. The shared contract requires zero allocator bytes/blocks
after state closure; it does not establish unrelated C exports.
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
