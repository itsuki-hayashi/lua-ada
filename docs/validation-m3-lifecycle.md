# Language Lifecycle Validation

Recorded runtime checkpoint: 4b71475e8a84eaf9a34787695e9ac82f1b2a9b84.
PR: [#7](https://github.com/itsuki-hayashi/lua-ada/pull/7), against master.
Status: runtime acceptance verified; publication-head checks remain mandatory.
This bounded delivery does not complete the broader M3 milestone.

## Reproducible checks

Run scripts/check.ps1 with each profile and library kind. It builds the strict
Ada 2022 library, CLI and nested AUnit consumers; required flags and runtime
checks remain enabled. The latest reviewed local Windows validation/static run
passed 575 AUnit cases, zero failed assertions and zero unexpected errors,
public Ada syntax/session consumer, 35 process CLI cases and eight differential
fixtures. There are 87 new focused lifecycle cases beyond the 488-case baseline.

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

The [runtime acceptance run](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42158285078)
passed all 18 jobs at the revision above. Every job log was inspected for 575
successful AUnit cases, zero failures/errors, the real Ada consumer, 35 CLI
cases, the retained M2b primary files, both lifecycle files and the differential
fixtures. The Windows static-validation job additionally repeats the entire
pipeline under static-PIC: 575 cases, 35 CLI and all five selected files again.

| OS      | Profile     | Link   | Job ID       | AUnit | CLI | Files | Result |
| ------- | ----------- | ------ | ------------ | ----- | --- | ----- | ------ |
| Linux   | development | shared | 127697563624 | 575   | 35  | 5     | pass   |
| Linux   | development | static | 127697563921 | 575   | 35  | 5     | pass   |
| Linux   | release     | shared | 127697563991 | 575   | 35  | 5     | pass   |
| Linux   | release     | static | 127697563899 | 575   | 35  | 5     | pass   |
| Linux   | validation  | shared | 127697563837 | 575   | 35  | 5     | pass   |
| Linux   | validation  | static | 127697563892 | 575   | 35  | 5     | pass   |
| macOS   | development | shared | 127697563993 | 575   | 35  | 5     | pass   |
| macOS   | development | static | 127697563917 | 575   | 35  | 5     | pass   |
| macOS   | release     | shared | 127697563944 | 575   | 35  | 5     | pass   |
| macOS   | release     | static | 127697564079 | 575   | 35  | 5     | pass   |
| macOS   | validation  | shared | 127697564046 | 575   | 35  | 5     | pass   |
| macOS   | validation  | static | 127697564047 | 575   | 35  | 5     | pass   |
| Windows | development | shared | 127697563913 | 575   | 35  | 5     | pass   |
| Windows | development | static | 127697563953 | 575   | 35  | 5     | pass   |
| Windows | release     | shared | 127697563927 | 575   | 35  | 5     | pass   |
| Windows | release     | static | 127697563898 | 575   | 35  | 5     | pass   |
| Windows | validation  | shared | 127697564036 | 575   | 35  | 5     | pass   |
| Windows | validation  | static | 127697564009 | 575   | 35  | 5     | pass   |

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

The subsequent handoff commit changes documentation/evidence retention only;
its complete matrix must also pass before PR #7 is marked ready. Current
publication-head checks are linked from the PR. Lifecycle stdout/stderr,
fixture hashes and generated mismatch sources are preserved as per-configuration
CI artifacts, including the Windows static-PIC observations.

Initial implementation 16cc35491384c345a3a2e328555eaf30ca13f5ca had a successful
18-job push run 42156106894. Its duplicate PR run had 17 successful jobs and one
macOS stable-GNAT archive HTTP 500 before compilation. No code/compiler-policy
change was made to hide that infrastructure failure. The reviewed revision adds
ten focused metadata/boundary cases and requires a fresh complete matrix.

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

## Final yieldability correction

A later direct C-oracle comparison added one focused regression: dead/closed
coroutines remain yieldable according to C Lua's boundary query. Execution now
ends the closing phase on completion and keeps that query independent of dead
status/abandoned error frames. Local AUnit passes 576 cases (88 new), with zero
failed assertions/errors. The 575-case table above remains the exact recorded
checkpoint. The current publication-head matrix must validate this correction
and is linked from PR #7; it cannot inherit the checkpoint's result.
