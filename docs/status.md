# Project Status

Updated: 2026-11-06 (Asia/Tokyo). **M0, M1, M2a, and M2b complete.**
**M3 remains in progress. The bounded language lifecycle delivery has verified
runtime acceptance; publication-head checks gate PR readiness.**

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

## Current M3 language lifecycle work

Merged PR #6, master bbc6e230cc1fcf4d20eb3caf02077b6bb0c0f46a, is the baseline.
The approved [combined delivery](milestones/m3-language-lifecycle.md) implements
goto/labels, closing, all Lua-facing coroutine exports, thread identities,
reachability-based context ownership, weak tables/ephemerons, debug inspection
and hooks, collection controls, and compatible CLI execution quotas. This
advances portions of M3-02/06/07/08/11; their full broader gates remain open.

Local Windows validation/static has passed 576 focused AUnit cases at the
latest recorded test checkpoint. Hash-verified unchanged goto.lua and
coroutine.lua have passed fresh independent same-host C/Ada process comparisons,
with identical stdout, empty stderr and OK markers. The coroutine result is
**default-configuration execution with documented upstream omissions**, not
complete coroutine or C-API conformance. Exact omitted source anchors and the
900-second/2 GiB sampled resident-process policy are in the acceptance owner.

The runtime revision 4b71475e8a84eaf9a34787695e9ac82f1b2a9b84 passed all
18 Windows/Linux/macOS profile/linking jobs and Windows static-PIC; every job
log was inspected. All three static-validation jobs passed the retained ABI,
frontend/opcode/layout/library campaigns and the new 1,024-case seeded lifecycle
campaign. [Validation evidence](validation-m3-lifecycle.md) records the exact
run, job IDs, tool versions, marker counts and scope limits. The final handoff
commit initially changed documentation and evidence retention only. A later
C-oracle edge comparison corrected dead/closed coroutine yieldability and added
one case; its current full matrix must pass before [PR #7](https://github.com/itsuki-hayashi/lua-ada/pull/7) is ready.
Reference/module pins remain unchanged and ecosystem fixtures remain unused.

## Earlier evidence and remaining work

Historical [M1 validation](validation.md) and [M2a validation](validation-m2a.md)
retain their original counts and configurations. M2a's complete checking
interface and 85 canonical opcode definitions remain independent of execution.
Checking and execution now share executable goto/label/close constructs.

This remains a documented Lua subset. Userdata, finalizers, collector modes,
remaining debug/io/os facilities and libraries, binary chunks, canonical code
generation/execution, full C API/ABI, native modules and LuaRocks remain later
work. Five selected default-configuration files do not establish the complete
standard suite or T-enabled C-API conformance.

The eight [consumer module fixtures](../tests/modules/README.md) retain their
pins and remain unbuilt/unexecuted future inputs. GNATdoc rendering, GNATtest
generation, fuzz campaigns, and formal proof were not run.

See [upstream coverage](upstream-tests.md), [roadmap](roadmap.md),
[backlog](backlog.md), and the
[current session](sessions/2026-11-06-m3-language-lifecycle.md).
