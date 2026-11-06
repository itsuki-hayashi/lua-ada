# Language Lifecycle Validation

Recorded runtime checkpoint: 830e0a1a2bad905ef34da3d553b24f8260ef35ff.
PR: [#7](https://github.com/itsuki-hayashi/lua-ada/pull/7), against master.
Status: runtime acceptance complete; final publication checks are linked from PR #7.
This bounded delivery does not complete the broader M3 milestone.

## Reproducible checks

Run scripts/check.ps1 with each profile and library kind. It builds the strict
Ada 2022 library, CLI and nested AUnit consumers; required flags and runtime
checks remain enabled. The latest reviewed local Windows validation/static run
passed 587 AUnit cases, zero failed assertions and zero unexpected errors,
public Ada syntax/session consumer, 35 process CLI cases and eight differential
fixtures. There are 99 new focused lifecycle cases beyond the 488-case baseline.

scripts/check-lifecycle.ps1 executes unchanged goto.lua and coroutine.lua in
fresh independent C/Ada processes, using hash-verified disposable fixtures,
matching working directories and package paths, zero exit status, empty stderr,
matching raw stdout and final OK markers. It rejects staged/unstaged fixture
changes and compares source hashes to the pinned inventory.

The lifecycle files use compatible CLI policy, 900 seconds and a 2 GiB sampled
resident-process watchdog. WorkingSet64 samples process resident bytes every
50 ms; it is not exact peak allocation or C managed-allocation accounting.
The retained tpack.lua, utf8.lua and bitwise.lua keep bounded 1,000,000 instructions
and 120 seconds; unchanged bwcoercion.lua remains a helper, not a sixth suite.

scripts/compare-lifecycle.ps1 compares 1,024 deterministic cases, seed 872641,
across generated scope exits, close/error replacement, nested coroutines and
weak/ephemeron collection. Raw C/Ada output matches locally. Failure reports
retain stdout/stderr and hex-decoded generated mismatch source. Retained checks
include the 1,120-case library campaign, frontend/lexer/parser/opcode campaigns,
all 34 upstream parse-only files, C99/Ada packing layout and isolated ABI probes.
These C probes are test fixtures, not production exports.

## Platform matrix

The [runtime acceptance run](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42166013145)
passed all 18 jobs at the revision above. Every job log was inspected for 587
successful AUnit cases, zero failures/errors, the real Ada consumer, 35 CLI
cases, the retained M2b primary files, both lifecycle files and the differential
fixtures. The Windows static-validation job additionally repeats the entire
pipeline under static-PIC: 587 cases, 35 CLI and all five selected files again.

| OS      | Profile     | Link   | Job ID       | AUnit | CLI | Files | Result |
| ------- | ----------- | ------ | ------------ | ----- | --- | ----- | ------ |
| Linux   | development | shared | 127722553216 | 587   | 35  | 5     | pass   |
| Linux   | development | static | 127722553331 | 587   | 35  | 5     | pass   |
| Linux   | release     | shared | 127722553384 | 587   | 35  | 5     | pass   |
| Linux   | release     | static | 127722553452 | 587   | 35  | 5     | pass   |
| Linux   | validation  | shared | 127722553556 | 587   | 35  | 5     | pass   |
| Linux   | validation  | static | 127722553356 | 587   | 35  | 5     | pass   |
| macOS   | development | shared | 127722553609 | 587   | 35  | 5     | pass   |
| macOS   | development | static | 127722553362 | 587   | 35  | 5     | pass   |
| macOS   | release     | shared | 127722553562 | 587   | 35  | 5     | pass   |
| macOS   | release     | static | 127722553459 | 587   | 35  | 5     | pass   |
| macOS   | validation  | shared | 127722553364 | 587   | 35  | 5     | pass   |
| macOS   | validation  | static | 127722553376 | 587   | 35  | 5     | pass   |
| Windows | development | shared | 127722553411 | 587   | 35  | 5     | pass   |
| Windows | development | static | 127722553571 | 587   | 35  | 5     | pass   |
| Windows | release     | shared | 127722553307 | 587   | 35  | 5     | pass   |
| Windows | release     | static | 127722553354 | 587   | 35  | 5     | pass   |
| Windows | validation  | shared | 127722553408 | 587   | 35  | 5     | pass   |
| Windows | validation  | static | 127722553506 | 587   | 35  | 5     | pass   |

All three static-validation logs additionally contain passing ABI probes, all
85 opcode definitions/4,096 instruction words, 10,000 arbitrary-byte lexer
cases, 2,000 generated grammar cases plus 2,000 mutations, all 34 unchanged
upstream parse-only files, C99/Ada layout, the 1,120-case library campaign and
the 1,024-case lifecycle campaign. Parse-only evidence remains distinct from
execution. Native aggregate/heavy C baseline observations retain their separate
report-only scope; they do not establish Ada full-suite coverage.

Exact inspected marker counts and job IDs are retained in
[the machine-readable evidence](evidence/m3-lifecycle-jobs.json).
All jobs selected stable GNAT 16.1.0 through Alire 2.1.1; GPRbuild package 26.0.1
reported banner 26.0.0. Hosts included Windows 10.0.26100 X64 (MinGW target
x86_64-w64-mingw32), Ubuntu 24.04.5 LTS X64 (x86_64-pc-linux-gnu), and macOS
26.6.2 Arm64 (aarch64-apple-darwin24.6.0). Numeric settings remain default 64-bit
integers/binary64, ASCII classification and LUA_COMPAT_GLOBAL=1. These probes
and matching host configurations do not establish a production C ABI.

The final handoff commit updates documentation and the inspected evidence only.
PR #7 records its publication-head matrix separately; it must pass before the
PR is marked ready. This avoids substituting an older runtime checkpoint for
final-head checks. All 18 lifecycle artifacts and three conformance artifacts
were uploaded successfully. Lifecycle stdout/stderr, fixture hashes, mismatch
sources and license notices remain available for every configuration, including
Windows static-PIC.

Earlier intermediate revisions and the initial macOS stable-GNAT download
HTTP 500 are recorded in the dated session. No compiler-policy change or hidden
skip was used to turn that infrastructure failure into a pass. The final runtime
matrix above has no failed, skipped or cancelled jobs.

## Scope of the upstream result

coroutine.lua is **default-configuration execution with documented upstream
omissions**. T is absent, no _soft/_port/_U/_nomsg flags are set, and all.lua is
not invoked. The runner requires exactly its two upstream omission messages and
rejects other skip text. Every omitted source block is inventoried in the
[lifecycle acceptance owner](milestones/m3-language-lifecycle.md).

Five selected whole-file passes do not establish full standard-suite, complete
coroutine or C-API conformance. Count-hook cadence and semantic stack charges
still reflect private instructions/register packets. Canonical execution,
allocator-callback/physical-allocation parity, public C ABI, binary chunks,
userdata, finalizers, collector modes, remaining libraries/full CLI and ecosystem
modules remain outside this delivery. No reference/module pins changed. Optional
GNATdoc rendering, fuzzing and formal proof were not run.

## Reviewed compatibility boundaries

Focused regressions cover dead/closed coroutine yieldability, closing-phase
cleanup after hard quota aborts, weak-mode NUL boundaries, collector result
packets/default arguments, disabled-hook arity, empty hook configuration and
signed count reflection. C-string option boundaries are deliberate compatibility
behavior; ordinary Lua strings remain binary-safe. The dated session preserves
intermediate counts; this record describes the final 587-case runtime revision.
