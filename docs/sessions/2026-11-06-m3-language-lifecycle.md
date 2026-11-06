# Major M3 Language Lifecycle Implementation

Date: 2026-11-06, Asia/Tokyo. Branch: codex/m3-language-lifecycle.
Baseline: merged PR #6, master bbc6e230cc1fcf4d20eb3caf02077b6bb0c0f46a.
Status: implementation in progress. Do not present this checkpoint as a ready PR.

## Approved target

One major PR combines typed transfers, stable cells, goto/labels, closing,
coroutines, weak collection, debug inspection/hooks and compatible CLI policy.
Required acceptance: unchanged goto.lua and default-T-absent coroutine.lua,
retained M2b files, focused tests, deterministic campaigns and full platform CI.
The coroutine file's upstream C-API omissions must remain explicitly recorded.
Canonical execution, allocator-callback parity, C ABI, binary chunks, userdata,
finalizers and ecosystem tests remain deferred. The user explicitly superseded
the prior one-small-gate-per-PR order for this delivery.

## Implemented checkpoint

Typed contexts/failures/transfers, iterative coroutine scheduling, real protected
and primitive native frames, stable captured cells, goto/labels, all close paths,
weak/ephemeron tracing, debug inspection/hooks, collection controls and execution
policies are implemented. Native closures use actual stable upvalue cells too.
Generic-for has a whole-loop closing scope, and backward declarations retain
fresh capture identities. Host aborts unwind active scheduler chains without
cleanup callbacks; semantic stack/native-depth failures remain catchable.

## Local verification

Toolchain: Alire 2.1.1, native GNAT 16.1.0, AUnit 26.0.0. Required strict flags,
checks and the existing floating-validity exception remain unchanged. Serialized
Alire builds use validation profile for root/dependencies/consumers.

- alr -C tests build --validation --profiles=lua_ada=validation and
  tests/bin/static/test_runner.exe: 564 successful, zero failed assertions,
  zero unexpected errors. This includes 76 new separately named/commented cases;
  obsolete unsupported goto/close expectations became positive regressions.
- scripts/check.ps1 -Profile validation -LibraryType static: complete local
  pipeline passed, including 564 AUnit, public Ada consumer, 35 CLI cases,
  retained M2b unchanged files at bounded 1,000,000 instructions/120 seconds,
  and both lifecycle files under compatible CLI policy/900 seconds/2 GiB
  sampled resident-process watchdog. C/Ada stdout bytes matched and stderr
  was empty. Coroutine's two expected T-absent messages remain visible.
- scripts/compare-lifecycle.ps1 -Interpreter cli/bin/static/lua_ada.exe:
  1,024 cases across scope exits, close/error replacement, nested coroutines,
  collection and ephemerons, seed 872641; raw C/Ada output matched.
- scripts/check-documentation.ps1: 55 Markdown files passed UTF-8/LF, local
  links and aligned-table checks at that checkpoint; later edits require rerun.

Raw evidence is retained in ignored reports/m3-*.log, reports/lifecycle/ and
reports/m3-lifecycle-campaign.json. The manually instrumented goto diagnostic
copy in reports is development-only; acceptance copies stay hash-identical.
No altered upstream source is used to claim a pass.

## Remaining acceptance

Final source review, final focused tests/campaigns, retained ABI/frontend/opcode/
layout/library checks and all final Windows/Linux/macOS profile/linking jobs,
including Windows static-PIC, remain required before one PR is ready. Original
M3 gates stay open for their broader canonical/ABI/allocator/finalizer/binary/full
CLI requirements. See the lifecycle acceptance owner for exact scope and omitted
upstream source anchors. Do not call the current local checkpoint a ready PR.

Reference/module pins remain unchanged and ecosystem fixtures remain unread,
unbuilt and unexecuted. Optional GNATdoc rendering, fuzzing and proof were not run.
Python is unavailable; local editing helpers use installed Node, not a project
dependency. No new runtime dependency was introduced.
