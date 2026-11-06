# Project Status

Updated: 2026-11-06 (Asia/Tokyo). **M0, M1, M2a, and M2b complete.**
**M3 remains in progress. The bounded language lifecycle delivery has completed
runtime acceptance; final publication checks are linked from PR #7.**

## Complete upstream delivery in progress

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

Published checkpoint 852aff6196da38fb7bf4eb5ace26efe74cd9f698 passes all 18
jobs in [run 42221667221](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42221667221),
including Windows static-PIC. Every required job log was inspected. That
revision contains 1,038 focused cases; newer local changes require a new
platform run. Native C aggregate observations still record the pinned macOS
readline-assumption failure, not a full M3 pass.

The newer local group adds allocation-free warning events and actual C warning
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
