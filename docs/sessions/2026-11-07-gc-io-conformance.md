# Four-file GC/IO conformance implementation

Date: 2026-11-07, Asia/Tokyo. Status: in progress, not accepted.

The maintainer approved complete events.lua, gc.lua, gengc.lua and files.lua
coverage, including T obligations and all 26 contexts. Branch
codex/m3-gc-io-conformance starts at merged PR #8, deed8e6. This bounded
follow-up supersedes the old delivery-branch instruction for these files only.
The maintainer subsequently authorized merge after CI passes and automated
review comments are addressed. Neither condition has been established yet.

The original .vscode directory is preserved. Stash
231eecf3933a3cc012496ebf073acc5ed3ad1d63 was applied without dropping it.
Reference and consumer-module pins have not been changed.

## Executed validation

- reports/m3-gc-io-baseline.log: retained validation/static pipeline passed,
  including 1,086 AUnit cases, consumers, CLI and retained upstream checks.
- reports/m3-gc-io-recovery-build2.log: recovered draft builds after wrapping
  an overlength comment; strict flags remain enabled.
- reports/m3-gc-io-recovery-tests.log: 1,270 tests, 1,186 successful and 84
  assertion failures. IO/OS registration and dispatch were missing.
- reports/m3-gc-io-registration-tests.log: registration/dispatch integration
  improved the result to 1,253 successful, 17 failed assertions.
- reports/m3-gc-io-fixes-tests.log: all 1,270 cases pass, zero failed
  assertions or unexpected errors.
- reports/m3-gc-io-integrated-check.log: complete retained validation/static
  pipeline passes, including the new core-callback and IO/OS differential
  fixtures. This is Windows/default evidence only.

The fixes preserve incremental completion across a work-budget boundary, poll
object pressure at rooted VM safe points, isolate queue-component fixtures
from standard-file finalizers, use modular C integer narrowing for iterator
counts, and prohibit yielding through OS calendar callbacks.

## Unaccepted upstream observations and next work

Exploratory disposable copies under reports/gc-io-probes reached OK for
events.lua and gengc.lua with T absent. They are not reviewed acceptance.
gc.lua printed OK but then reported EXCEPTION_ACCESS_VIOLATION at line 752;
the run is failed and needs a minimized collector/lifecycle regression.
The exploratory watchdog was 60 seconds, not the final 900-second contract.

Investigate that failure before expanding claims. The ordinary CLI still
needs explicit successful Lua-state shutdown rather than relying on Ada
physical finalization. Complete the real T adapter, scoped ledger/runner,
platform equivalents, independent reviews, and all 26 contexts. No selected
file has newly accepted full coverage. No PR or merge has occurred.

## Coroutine teardown repair

Physical Destroy_Frames called normal Close_Cells after dead cells could
already have been swept in reused heap slots. It now discards stack/cell
associations without reading reclaimed objects; live captured cells own their
values independently. A separate collector regression exercises dead suspended
coroutines and independently retained captures. Strict validation/static build
and all 1,271 AUnit cases pass in reports/m3-gc-io-context-build.log and
reports/m3-gc-io-context-tests.log.

The CLI now explicitly closes its Lua state on normal completion and snippet
failure. Two process regressions require reachable finalizers after the chunk
marker and after an error. The complete CLI test script passes in
reports/m3-gc-io-close-cli-tests.log.

The unmodified disposable gc.lua copy now exits zero with empty stderr,
including its post-OK closing-state marker. Its report is
reports/gc-io-probes/gc-close-fix.json: 29,415 milliseconds, 900-second limit,
default configuration, T absent. events.lua and gengc.lua also exit zero;
files.lua skips its tmpname block and fails at line 896 on %Ex, as observed
in the same-host C baseline. These are observations, not reviewed scope
acceptance or evidence for omitted T/platform blocks. Next work is the real
test adapter and the source-cited platform/internal equivalents.

## Test adapter and shared launcher checkpoint

The signed integration checkpoint `1cd294e` is published on
`codex/m3-gc-io-conformance`. No PR or merge has occurred yet.

The subsequent worktree adds actual C userdata allocation, distinct one-shot
and persistent allocation refusal, an independent test allocation ceiling,
actual byte/block/object counts, collector colors/ages/phases, the production
parameter codec, physical unused-frame release and stack resize preserving
live windows/cells. A private list verifier tests registry, generation, gray
and remembered ownership, including a deliberate corruption rejection.
Complete `checkmemory` and `nonblock` coverage remain open.

The CLI driver is now shared by production and the test launcher. Default
launchers leave T absent; instrumented launchers install the adapter and real
C warning callback, with per-state registry-owned fragmented-message storage.
The test launcher applies the independent 2 GiB managed ceiling. Configuration
and subprocess/hash/telemetry acceptance still require harness integration.
The extraction/change manifest is `tests/c/conformance_adapter.sources.md`.

Instrumented events.lua initially failed at its one-shot refusal regression:
the canonical table-write argument packet did not retry allocation. GDB
identified the actual managed vector growth. The packet now reserves capacity
with one emergency collection retry while operands remain rooted; a separate
AUnit case protects weak delegation across this collection. Byte-identical
events.lua and gengc.lua then reached OK with T installed, as exploratory
runs only. gc.lua reached the missing warning-storage assertion; the subsequent
warning implementation is being checked against that file.

Local Windows validation/static evidence:

- `reports/m3-t-warning-tests.log`: all 1,285 instrumented AUnit cases pass.
- `reports/m3-t-warning-build.log`: strict instrumented build passes.
- `reports/m3-shared-cli-tests.log`: production CLI regressions pass after
  sharing the driver.
- `reports/m3-t-events-probe2.log` and `reports/m3-t-gengc-probe.log`: preliminary
  T-enabled successful execution, not scoped acceptance or final-revision
  cross-platform evidence.

Four existing lexical/session fixtures now assert the selected configuration's
global-keyword contract. The collector corruption fixture no longer assumes
that 1,000 work units reaches its invalid frame in both library configurations.
No failures were skipped. Default rebuild, full final-revision validation,
platform equivalents, reviewed obligation mappings and the 26-context matrix
remain required.

The warning callback advanced gc.lua to its line-477 fixed one-KiB memory
allowance. A separately named diagnostic copy (not accepted upstream evidence)
measured 877.3369140625 KiB versus 874.70703125 KiB before the block. The cause
and an invariant-preserving equivalent remain under investigation; no byte
allowance was relaxed. The warning process regression script passes all seven
positive/negative cases, including a warning failure during state shutdown.
The complete retained default pipeline passes in
`reports/m3-t-default-full-check.log` at the 1,285-case checkpoint.
The final object-kind validation adds one separately named test; both default
and instrumented validation/static builds and all 1,286 AUnit cases pass in
`reports/m3-t-adapter-final-{default,instrumented}-{build,tests}.log`.
The default incremental build reused the prior runner, detected by its case
count. A forced test-runner rebuild in
`reports/m3-t-adapter-default-forced-build.log` established the final 1,286-case
default result. The source manifest records the pinned ltests.c hash.

## Atomic barriers, refusal recovery and GC equivalent candidate

The next signed checkpoint `35ab018` is published in
[draft PR #9](https://github.com/itsuki-hayashi/lua-ada/pull/9). The draft remains
open for implementation, not ready for acceptance or merge.

Further instrumented execution found and repaired eager root retention at the
enter-atomic boundary and backward-barrier whitening during sweep. Focused
cases require temporary roots to expire, live roots to survive, a weak coroutine
to die in the same cycle while its independently owned cell survives, and a
userdata backward barrier to turn gray then survive subsequent cycles.

`T.checkmemory` now inspects actual allocator headers/accounting, collector
lists, heap/prototype edges, live activation windows and finalizer queues.
The actual header type is private to Lua.Storage; only test code implements
inspection. Negative tests reject registry corruption and foreign heap edges.
POSIX `T.nonblock` now uses actual luaL_Stream payloads and descriptor flags;
Windows retains its native absence, whose counterpart obligation is still open.

Persistent refusal exposed unnecessary allocations in plain table lookup and
GC result delivery. Existing fields now use an allocation-free raw fast path
when no delegation applies. GC actions receive results by ownership transfer;
unprotected independent result packets do not allocate redundant copies.
Separate Lua-driven cases now prove finalizer deferral and eventual progress
under real frame-cache and scalar-stack refusal, without an Ada-only reset.

The source-hashed `gc-ada-instrumented` equivalent candidate completes through
OK and its state-close assertions in
`reports/m3-t-gc-equivalent-candidate.log`. It replaces three C-specific
assumptions through four exact spans: measured weak-string payload reclamation,
the real stable-cell child color, and measured emergency allocation headroom.
There are no omitted diagnostic assertions in this candidate. All mappings
remain pending independent review; this is not an accepted upstream pass.
The generator rejects unreviewed acceptance, drift, overlapping spans, absent
counterparts, identical author/reviewer, and reference-tree output.
[ADR 0016](../decisions/0016-gc-adapter-equivalents.md) records the rationale.

Instrumented validation/static has 1,299 passing AUnit cases in
`reports/m3-t-load-mode-tests.log`. The latest two cases repair Lua-facing mode
B rejection before reader invocation or file opening. They were exposed by
opening files.lua's Windows-skipped temporary-file block in a disposable
diagnostic runner. That runner then passed the IO/iterator block up to Unix
device assumptions at line 467. A same-host C/Ada subprocess observation
confirmed Windows stdin seek returns 1000 even for redirected input; this needs
a platform mapping, not a runtime assertion copied from POSIX. Windows tmpnam
returns a root-directory name that cannot be opened here; relocating its unique
basename to the disposable directory is also a pending platform equivalent.

Next required work includes native-platform file counterparts, C collector/IO
openers and consumers, launcher shutdown/allocator telemetry, scoped ledger and
acceptance integration, review artifacts, and the complete 26-context matrix.

The complete retained default validation/static pipeline subsequently passed
with 1,299 AUnit cases in `reports/m3-gc-adapter-expanded-check.log`. All eight
equivalent-generator positive/negative checks passed again before committing.

## Instrumented matrix integration

Commit 40b6ca7 is signed and published. Its remote default jobs stopped at a
documentation table-alignment error added after the local pipeline run; the
decision index is corrected and the documentation check passes on the edited
tree. This failure supplied no new remote runtime evidence.

The instrumented regression command now builds the actual adapter in six
OS/link validation jobs and Windows static-PIC, retaining the existing default
matrix. Local Windows static execution passes all 1,299 cases, warning and
equivalent-generator checks, unchanged events.lua/gengc.lua and the GC
equivalent including state closure. Shared execution initially exposed missing
GNAT support DLLs in the subprocess search path; the command now obtains that
path from Alire and prepends the exact instrumented library directory.
Raw observations remain diagnostic, with scoped acceptance explicitly false.
The corrected Windows shared run also passes all of these regressions,
including the late GC shutdown witness, in
`reports/m3-instrumented-matrix-shared.log`.

Windows instrumented static-PIC also passes the new regression command in
`reports/m3-instrumented-matrix-pic.log`. Signed commit f11c056 publishes the
matrix integration; remote run 42257414493 was queued when first observed.

A native Windows `_pipe` probe establishes the buffered sequence needed for a
`/dev/full` counterpart: write 4 bytes, fail flush, write 4 bytes, fail flush,
then close successfully. The test-only driver preserves the actual FILE pointer
and closer by replacing only its descriptor with `_dup2`. Two separately named
Windows AUnit cases verify this sequence and reject invalid/closed arguments.
Instrumented validation/static passes all 1,301 cases in
`reports/m3-file-native-driver-tests.log`. The disposable files.lua diagnostic
now reaches the shell tests at line 786, after passing native flush, iterators,
loading and large-file behavior. Its current failure is the unavailable POSIX
`cat` command. Source mappings and matching C evidence are still pending; no
whole-file acceptance is claimed.
Default validation/static also passes all 1,301 cases in
`reports/m3-file-native-driver-default-tests.log`; its launcher still has
T absent while exposing the explicitly named native counterpart. Replacing
cat's byte-copy operation with the same launcher through bare lua completes
both pipe directions. The next diagnostic failure is the Windows-absent Unix
signal commands at line 814, not an IO byte-transfer failure.

The native descriptor drivers are extracted into conformance_platform.c, which
uses public Lua APIs only. It builds independently as a C-oracle module while
the Ada launcher invokes the same functions through its existing guarded C
callback path. The shared windows-buffered-failure.lua fixture passes against
both instrumented implementations in `reports/m3-windows-buffered-counterpart.log`.
The complete default validation/static pipeline, now including the same C/Ada
counterpart, passes in `reports/m3-platform-full-default-check.log` with 1,301
AUnit cases. Both pipeline commands retain counterpart artifact hashes and
stdout/stderr. The mapping remains pending independent review.

The complete instrumented regression command also passes after extraction in
`reports/m3-platform-full-instrumented-check.log`. A separately compiled native
Windows process fixture uses TerminateProcess with explicit 129/137 exit codes,
providing actual forced termination rather than normal process return. The
disposable files.lua diagnostic then completes its final date/version output
against both instrumented Ada and C. Explicit diagnostic changes cover native
null/full streams, temporary paths, stdin seek, shell commands/quoting and host
date ranges. Ada evidence is `reports/files-probe/files-temp-diagnostic10.log`;
C evidence is under reports/files-c-oracle/31b8997038b248bf92082bdf860c9e16.
This diagnostic still omits the guarded Windows nonblocking-write block and
has not become a reviewed equivalent manifest. That obligation needs a real
native partial-write counterpart before any selected-file coverage is closed.
