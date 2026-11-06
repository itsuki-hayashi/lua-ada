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
