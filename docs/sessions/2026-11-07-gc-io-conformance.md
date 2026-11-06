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

## Native partial writes and complete Windows file candidate

The next implementation uses a real PIPE_NOWAIT byte pipe, preserving both
FILE pointers/closers through descriptor replacement. A native probe showed
that Windows CRT refuses an oversized single write atomically. The target
target invariant is therefore represented by real earlier-argument delivery
before later-argument refusal, exact returned counts, received bytes and EOF.
Three separately named Windows AUnit cases add zero-byte refusal, partial
progress and endpoint validation. Instrumented validation/static passes 1,304
cases in `reports/m3-partial-write-tests.log`.

The same C driver and Lua assertions pass against both actual runtimes.
Ten source-hashed spans in files-windows-platform.json now replace only explicit
native assumptions; the original checkerr helper is restored, and the formerly
omitted T block executes on Windows. The runner requires its execution marker,
all major file-phase markers, the final date/version witness, successful process
shutdown and exact expected shell stderr. Both instrumented executions pass in
`reports/m3-windows-files-equivalent.log`, with separate named counterparts in
`reports/m3-windows-contracts.log`. The complete default pipeline passes in
`reports/m3-files-equivalent-default-check.log`. Mappings remain pending review.

Remote eb6f6d0 Windows shared default jobs exposed missing GNAT support DLLs in
direct counterpart children; the runner now obtains the selected support path
from Alire while preserving the caller's exact interpreter library precedence.
The POSIX instrumented jobs now execute unchanged files.lua through both C and
Ada with raw captures and completion witnesses, so remaining native assumptions
and runtime failures become explicit CI failures rather than absent evidence.
The complete updated instrumented command passes in
`reports/m3-files-equivalent-instrumented-check.log`. Explicit bare-lua and
arg-selected child configuration assertions pass against C and Ada in
`reports/m3-files-child-configuration.log`. The default shared counterpart run
now passes in `reports/m3-files-shared-counterparts.log`, verifying the support
DLL search-path fix that the earlier remote shared failures required.

## Shutdown allocator evidence and typed process exits

The test launcher now delegates actual managed allocation requests through a
test-only provider observer, counting existing bootstrap blocks and later
successful allocations/releases. It retains actual owner refusal counts before
the owner disappears. A shared CLI Finish hook runs after physical disposal;
typed process exits are honored afterward. Exit(false) performs no Lua close
handlers, whereas exit(true) completes their ordered execution first.

Normal closure, runtime error, both typed exit modes and real instrumented
refusal recovery produce balanced sidecars. Ten negative cases reject leaked
bytes/blocks, wrong process/run/configuration/ceiling, missing shutdown, observer
fault and invalid/missing counters in `reports/m3-telemetry-tests.log`.
The production CLI also has explicit exit-code/handler-order regressions.
The complete default pipeline passes in `reports/m3-telemetry-full-default.log`;
the instrumented pipeline passes in `reports/m3-telemetry-full-instrumented.log`.
Both retain the 1,304-case Windows AUnit suite. Windows file candidates verify
balanced parent and eight Ada Lua-child sidecars, including typed-exit children.
Pinned C normal-return children supply four separate sidecars; its os.exit
children bypass the oracle main-return writer, an explicitly retained limit.

Linux run 42261663287 reached the final unchanged files.lua witness in both
instrumented C and Ada, including the failed-write block. Its job then failed
in a PowerShell -replace expression, not the captured runtime assertions. The
comparison expression is corrected. Raw artifacts under reports/ci-linux-5df87e8
have matching output except the final timestamp and matching expected shell
stderr. A fresh complete job/report is still required; these archived captures
alone are not accepted whole-file evidence. macOS jobs remain queued.

## Real C IO/OS openers and native closer consumer

The C boundary now exports luaopen_io and luaopen_os through the real Ada
module constructors. Owned sessions share those constructors. As specified by
pinned liolib.c:797-841 and loslib.c's syslib/luaopen_os, openers return a new
table without publishing globals or loaded entries; IO resets registry default
streams and preserves an existing FILE* metatable. Reopening formerly replaced
that identity, invalidating earlier files against registry-based type checks.

Three separately named C consumer regressions check actual public FILE layout
and reopening, callable OS exports without global publication, and invocation
of the public luaL_Stream.closef pointer after clearing it as aux_close does.
The closer test writes through the actual FILE pointer, calls the C trampoline
under a protected boundary and observes the closed file afterward. No pinned
header or reference source changes are needed.

Local GNAT 16.1.0 / Alire 2.1.1 validation/static verification retains 1,304
AUnit cases in reports/m3-openers-full-default.log and completes the instrumented
pipeline in reports/m3-openers-full-instrumented.log. The added closer consumer
passes in reports/m3-openers-closer-core.log. Instrumented jobs now also run
the real C/Ada image consumers, preserving their reports as CI artifacts;
these builds remain serialized with AUnit and oracle builds.

Published 915df28 has successful Linux static/shared instrumented jobs in run
42264272904. The inspected static job 128051959836 records unchanged events,
gengc and POSIX files observations, GC equivalent shutdown, and telemetry and
equivalent-negative checks. PR #9 has no review comments at this observation.
Neither these jobs nor the opener checkpoint establishes reviewed scoped
completion. lua_gc, remaining platform evidence, scoped acceptance and
independent review remain required; no merge has occurred.

## Public collector controls and C state closure

The real lua_gc export now marshals the pinned Lua 5.5 variadic types (size_t
for steps; two int values for parameters) into the same private control
implementation used by collectgarbage. Counts use actual managed raw storage;
query/stop/restart/parameter operations allocate no result storage. Internal
collector/finalizer/state-close calls return -1. Mode returns and parameter
encoding use the production implementation, including real measured steps.

The control operation queues a separate C-owned protected drain opportunity.
Optional frame/stack refusal preserves pending objects; successful callbacks
use the existing iterative driver, yield barrier, warning protocol and C jump
guards. The C lua_close path previously performed physical disposal only. It
now borrows the existing idle-state close driver before disposal, so actual
Lua/C finalizers and warning callbacks run first. Allocation failure while
obtaining optional close storage cannot prevent final physical release.

Seven separately named public C regressions are shared in gc_contract.h by
the real consumer and an isolated oracle consumer: allocation-free controls
and actual byte counts; mode returns/stopped steps; reverse nonyieldable
finalizers; refused activation and later recovery; state-close finalizers;
refused close storage cleanup; fragmented GC/shutdown warnings. Each owning
allocator test checks zero outstanding bytes and blocks. The first-party
consumer allocator moved into a shared header without changing its behavior.
No C-private layout or reference interpreter object enters the Ada library.

Default comparison passes in reports/m3-gc-api-oracle.log; the subsequent
instrumented comparison, including the warning case, passes in
reports/m3-gc-api-instrumented-core.log. check-core-image now performs this
same C/Ada comparison in each selected profile/configuration/link context and
retains both executable hashes and captures. The reference library is built
separately without requiring an interactive oracle CLI or readline gate.
The full default control-refactor run in reports/m3-gc-api-full-default.log
retains 1,304 AUnit cases; final close/header changes require the subsequent
full pipeline evidence recorded below. No scoped record is closed by this
component implementation or by an enclosing successful process.

The final close/header runtime changes pass the complete instrumented static
pipeline in reports/m3-gc-api-full-instrumented.log and the complete default
validation/static pipeline in reports/m3-gc-api-final-default.log, each retaining
1,304 Windows AUnit cases. The shared C contract additionally exercises INT_MAX
parameters and an all-bits-one size_t step through the real variadic export.
Reference library and all shared contract source hashes are retained alongside
the selected Ada library hashes and both process captures.

## Scoped completion, launcher identity and all-file matrix scheduling

The new gc-io-events scope selects the four complete source partitions (762
original anchors) and 77 directly exercised public API entries. Scope selection
and every actual coverage record remain pending review. Structural checking
still regenerates all 4,490 original source anchors and 473 header entries.
check-conformance-scope.ps1 -RequireScopedComplete rejects pending coverage;
the original full-M3 -RequireComplete behavior is preserved. Twenty-five scoped
inventory/process regressions test missing/duplicate files and APIs, corrupted
unrelated inventory, self-review, unresolved runtime records, early returns,
GC closure ordering (including a spoofed embedded OK), final file date/version
output, physical shutdown, leaks and wrong configuration. The existing runner's
38 acceptance/process regressions also pass.

run-conformance.ps1 has a separate -Scope gc-io-events -RequireScopedAcceptance
path for individual file/context operations. It requires a complete reviewed
scoped ledger and execution contract, preserves gate_acceptance=false for full
M3, and reports scoped_operation_acceptance separately. Equivalent executions
retain their explicit disposition, manifest hash and executed-source hash;
unreviewed diagnostic equivalents cannot request acceptance. GC closure and
files final witnesses supplement process success and balanced telemetry. This
per-operation gate does not itself reconcile the complete 104-operation matrix.

Actual scoped execution exposed that conformance_runner lacked the requested
--conformance-config option. The test-only launcher now constructs/configures a
real session and reports selected behavior, installed T, numeric/pointer sizes,
the actual public C extra-space prefix and independent storage ceiling. This
reports Ada's retained public header prefix; it does not pretend to install the
C-private ltests L_EXTRA lock structure. Both the bare lua child and the
arg-selected child reproduce the parent's measured report. The ordinary CLI
remains on the shared execution path. Scoped runs omit only unrelated REPL and
native-module setup gates, which remain required by the full-M3 command.

The default and instrumented pipelines now schedule all four selected files.
The shared GC/events runner executes independent C/Ada processes in disposable
directories, compares exact stdout and empty stderr, and checks parent cleanup.
Default T omissions must match their individual pinned messages and remain
unresolved links to instrumented coverage. The memory-layout GC candidate now
declares both configurations; only its unconditional weak-string span executes
in default mode. Windows file equivalents and POSIX unchanged file runners are
scheduled in both configurations, retaining their existing native contracts.

Local full default validation/static passes in reports/m3-scope-full-default.log
and full instrumented static passes in reports/m3-scope-full-instrumented.log,
retaining 1,304 AUnit cases each. Final default GC/events comparison passes in
reports/m3-scope-final-default-batch.log with explicit context identities. Final
scope-negative evidence is reports/m3-scope-final-tests.log. The instrumented
scoped GC and C/Ada events observations also pass independently. Review records
remain pending; no selected source/API record has been promoted on lexical or
process evidence alone. Published 31bc086's Windows/Linux jobs are green;
macOS jobs remain queued. Independent review-agent authorization was requested
because current session instructions prohibit unrequested delegation.

The subsequent scoped API ledger regressions pass all 30 cases in
reports/m3-scope-api-ledger-tests.log, including missing/duplicate records,
header drift, missing behavioral invariants and self-review. The separate
77-entry API ledger preserves the global 473-entry ABI acceptance boundary.
File report producers now retain explicit configuration/platform/profile/linkage
contexts. POSIX file runs require both setup-child reports, the instrumented
pipe receiver, and all four Ada typed-exit reports; C exit children retain
the documented upstream telemetry-writer limitation. POSIX execution of this
new child accounting remains pending CI; local Windows results are recorded
separately in reports/m3-file-context-default.log.

CI dd44a4e run 42272716242 exposed a Linux shared executable lookup failure
after copying the launcher into its disposable directory: libgnat-16.so was
not found. The default and instrumented harnesses now derive the selected
compiler's actual adalib directory and retain it in LD_LIBRARY_PATH. This
corrects subprocess setup; validation of that fix awaits its CI revision.

Author semantic candidates now cover all source bytes of the four files in
84 contiguous hashed sections under tests/conformance/reviews. They explicitly
retain pending independent review and have no coverage authority. Reading the
complete files source exposed two empty-command subprocesses omitted from the
new POSIX telemetry count: expected Ada child totals are eight/default and
nine/instrumented (C normal-return totals four/five). The count is corrected.
The files candidate also records that upstream's no-buffer write sequence opens
a read-only stream and does not check that write result; its enclosing process
success must not be used as proof of successful unbuffered output.

CI 0159765 run 42273338984 confirms the corrected child cardinalities from
actual Linux default static/shared and instrumented shared executions: C/Ada
reported four/eight default and five/nine instrumented children, respectively.
The prior six/seven Ada expectation caused the harness failure. Linux shared
execution progressed beyond the repaired libgnat lookup into completed file
execution; the next revision must still rerun the corrected gate. The existing
IO: actual libc buffering modes AUnit case checks successful writes in all
three buffering modes separately from the unchanged upstream sequence.

## Shared file acceptance path and measured platform launchers

The scope completion witness now rejects files.lua's temporary-file omission
even if date/version output appears, requires its IO branch markers and the
instrumented failed-write marker, and requires gengc's instrumented tail.
All 35 scope regressions pass in reports/m3-scope-branch-witness-tests.log.
The shared configuration validator now checks both implementation directions:
an Ada binary cannot serve as a C baseline. All 40 runner regressions pass in
reports/m3-file-launcher-runner-tests.log.

Platform file runners now measure parent, bare-lua and arg-child configuration,
including actual adapter and allocation limits. Each probe group has a separate
telemetry prefix: five Ada session disposals, or two C Lua probe-parent records
(the C configuration printer does not construct a state). The default and
instrumented Windows native/file counterparts pass these checks in
reports/m3-file-launcher-default.log and reports/m3-file-launcher-instrumented.log.
Two actual launcher-isolation regressions pass in each configuration, recorded
in reports/m3-launcher-negative-default.log and
reports/m3-launcher-negative-instrumented.log.

files.lua can now use run-conformance.ps1's shared scoped operation/acceptance
path, including the Windows candidate's narrow native module/process fixtures
and complete child telemetry. check-files-scoped.ps1 compares independent C/Ada
output outside final date values, preserving all expected native stderr.
Instrumented Windows shared-path observations pass in
reports/m3-scoped-files-instrumented.log. These diagnostics retain pending
semantic/equivalent reviews and do not set scoped acceptance. Existing native
counterpart tests remain scheduled in addition to this common path.

Full local Windows validation/static pipelines pass after integration in
reports/m3-unified-file-full-default.log and
reports/m3-unified-file-full-instrumented.log, retaining 1,304 AUnit cases each,
all retained consumers, GC/API oracle comparisons and both native and shared
file paths. The default log's only error-status line is the required invalid-CLI
option test; its finalizer-warning fixture is expected. No unexpected diagnostic
appears in the instrumented log. Published 28329f8 run 42274361758 now has all
16 Windows/Linux jobs green, including both embedded Windows static-PIC steps
(18 applicable contexts); all eight macOS jobs remain queued. These are still
observations, not reviewed scoped acceptance.

The next acceptance checkpoint adds ConformanceMatrix.psm1 and
check-conformance-matrix.ps1. The manifest requires all 104 file/context pairs
and 208 C/Ada reports; verification rehashes captured output, telemetry and
equivalent source artifacts and replays the reviewed execution contracts.
Acceptance additionally requires the resolved scoped ledger, independent
reconciliation review and a clean checkout at the exact execution revision.
No real matrix is accepted yet. Seventeen explicitly synthetic regression
cases pass in reports/m3-matrix-selftests.log, including incomplete matrices,
changed artifacts, wrong revision/host/implementation, pending review, and
mislabeled runtime profile, launcher profile or library type. CI retains
generated equivalent sources for later hash verification.

The test-only configuration protocol now reports the runtime's Alire build
profile and the launcher's GPR-derived build profile and library type. The
scoped runner validates these actual measurements before execution and records
the normalized native host. No generated configuration, public header or
production ABI is changed. The default local validation/static pipeline passes
in reports/m3-matrix-full-default.log with 1,304 AUnit cases and all four matching
C/Ada observations. Published 70a22a0 run 42276786486 has all 16 Windows/Linux
jobs green, including both static-PIC steps; its first macOS instrumented job
has started, with the other seven macOS jobs still queued at this observation.
PR #9 has no review comments at this poll. Independent semantic/equivalent
review and final-revision 26-context acceptance remain open.

The instrumented local validation/static pipeline also passes in
reports/m3-matrix-full-instrumented.log: 1,304 AUnit cases (zero failures/errors),
all four C/Ada observations, native file counterparts, real launcher-isolation
negatives, public GC oracle comparisons and Windows unwind checks. The AUnit
stderr contains the expected ordinary-finalizer-failure warning fixture.
Separately rerun scope and runner suites retain 35 and 40 passing cases in
reports/m3-matrix-scope-tests.log and reports/m3-matrix-runner-tests.log.
The final matrix self-test rerun passes all 17 cases after verification-flag
checks were added. Documentation validation passes all 77 Markdown files.

Artifact reconciliation found a CI provenance mismatch: run 42276786486's
instrumented-Linux-relocatable artifact (13532679957, ZIP SHA-256
1c2757e5a8568995a36a2a99669b5f6351ab51243ca22f272015dd707509ae78)
records GitHub's synthetic PR merge commit
087847446bd50dc751be26a1c21df0a5c728cd66 rather than published head 70a22a0.
Those observations remain valid for their recorded revision but cannot satisfy
the final-head matrix. Both CI jobs now explicitly check out the PR head SHA
(or the triggering SHA for push/manual runs). This preserves exact revision
reconciliation without rewriting report identities. Fresh final-head CI is
required; previous green jobs are not promoted to final-head acceptance.

macOS instrumented static job 128095028803 in run 42276786486 completed with
1,299 passing AUnit cases and matching C/Ada events.lua, gengc.lua and gc.lua
equivalent observations. Both native C and Ada then failed unchanged files.lua
at line 474: opening /dev/full returned permission denied. Missing later child
telemetry followed that early failure and is not a separate implementation pass.
The new files-macos-platform candidate replaces that single hashed open with
a real failing native FILE descriptor, preserving subsequent assertions and
the original instrumented POSIX nonblocking-write tests. A separately named
counterpart checks repeated failed flushes, public FILE identity, default-stream
restoration and physical closure. It runs for both C and Ada through the common
scoped runner. The Linux unchanged runner remains scheduled on Linux.

Windows strict validation/static compilation and matching Windows file/native
counterparts pass after this test-only driver extension, in
reports/m3-macos-driver-windows-build.log and
reports/m3-macos-driver-windows-counterparts.log. The Mac driver has not yet run
on macOS; its candidate and review remain pending. The 17 matrix regressions
pass in reports/m3-macos-matrix-selftests.log. Matrix equivalent review status
now uses the existing generator's accepted vocabulary, rather than reviewed.

The matrix review validator now has a positive accepted-vocabulary fixture and
separate negatives for pending/unknown status, self-review and absent review
artifacts. All 22 synthetic regressions pass in
reports/m3-matrix-review-vocabulary.log. They do not authorize a real review.

The three existing public IO/OS C tests were extracted unchanged into
c_api/tests/io_contract.h and remain in the ordinary consumer. A new standalone
io_api_contract.c runs those same cases against both Ada and the isolated
pinned C oracle, also requiring zero allocator bytes/blocks after close.
Default and instrumented Windows validation/static core-image campaigns pass
with identical C/Ada output in reports/m3-io-oracle-default.log and
reports/m3-io-oracle-instrumented.log, including all retained GC, startup and
unwind consumers. Both CI configurations schedule the new comparison and
retain its executable/library/source hashes. Final platform acceptance and
independent semantic/equivalent review remain outstanding.
