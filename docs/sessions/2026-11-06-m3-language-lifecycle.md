# Major M3 Language Lifecycle Implementation

Date: 2026-11-06, Asia/Tokyo. Branch: codex/m3-language-lifecycle.
Baseline: merged PR #6, master bbc6e230cc1fcf4d20eb3caf02077b6bb0c0f46a.
Status: runtime acceptance verified. Final documentation/evidence-retention
head checks remain mandatory before marking the single PR ready.

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

## Reviewed implementation refinement

The initial implementation tree 697eb42c0b351fa9d7b26d599dac5a31e9302749
was published through the GitHub connector as commit
16cc35491384c345a3a2e328555eaf30ca13f5ca. Native SSH push stalled; its identified
processes were stopped. The connector tree was compared byte-for-byte by Git
tree SHA before synchronizing the local branch. PR #7 is open as draft and
remains the single delivery PR.

Source review added Lua-compatible short-source formatting, correct function
keyword/implicit-return line metadata, controlled extreme debug-index/count
checks, explicit typed language/host states, and pinned-inventory fixture hashes
including staged-edit rejection. Ten further focused cases bring the suite to
574 passing tests (86 new cases versus the merged baseline), zero failed
assertions or unexpected errors. scripts/check.ps1 -Profile validation
-LibraryType static passed again in reports/m3-reviewed-full-validation.log,
including all five selected upstream files, 35 CLI cases and eight differential
fixtures. The added lifecycle campaign is one of those fixtures.

Intermediate local Windows validation/shared and validation/static-PIC pipelines
also passed their complete 564-case checkpoint. Retained local ABI, frontend/
opcode, C99 layout and 1,120-case library campaigns passed. The separate lifecycle
campaign passed 1,024 cases, seed 872641.

The initial remote PR run 42156155188 passed 17 of 18 jobs; macOS static-validation
failed before compilation because the stable GNAT archive download returned
HTTP 500 on all three existing retries. This is missing platform evidence, not
a runtime/test pass or a reason to change compiler versions. The reviewed
revision requires a fresh full matrix and inspection of every final job log.

A final logical-frame review found that the exported ipairs iterator still used
an internal-helper name. It now has a genuine native activation name, so debug
inspection, hooks, native-depth accounting and non-yieldable callback rules see
it consistently. A focused callback regression raises the local suite to 575
passing cases (87 new), zero failed assertions/unexpected errors. The validation
owner is docs/validation-m3-lifecycle.md; final platform evidence remains pending.

## Completed runtime acceptance and handoff checks

Runtime/test revision 4b71475e8a84eaf9a34787695e9ac82f1b2a9b84 passed all 18
jobs in PR run 42158285078. Every log was inspected: 575 successful AUnit cases,
zero failed assertions/errors, Ada consumer, 35 CLI cases, eight differential
fixtures and all five selected unchanged upstream files. Windows static-validation
also repeated the complete pipeline with static-PIC. All three static-validation
logs show ABI, 85-opcode/4,096-word, 10,000-byte-input, 2,000 grammar plus 2,000
mutation, 34-file parse-only, C99 layout, 1,120-library and 1,024-lifecycle checks.

The validation record and machine-readable evidence own exact job IDs, tool/host
versions and marker counts. The final handoff commit updates documentation and
adds per-configuration lifecycle artifact retention; runtime/test source is
unchanged. Its full matrix must pass before PR #7 is marked ready. Do not merge.
This completes the approved bounded runtime features, not the broader original
M3 gates, canonical execution, C ABI/allocator parity or the complete suite.
