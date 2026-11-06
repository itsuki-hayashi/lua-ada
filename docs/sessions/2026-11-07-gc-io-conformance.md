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
