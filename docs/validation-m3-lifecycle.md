# Language Lifecycle Validation

Runtime/test revision: 80009520a410477319522ecd03652f7f2baee24c.
PR: [#7](https://github.com/itsuki-hayashi/lua-ada/pull/7), against master.
Status: final platform log inspection pending; not a full M3 acceptance claim.

## Reproducible checks

Run scripts/check.ps1 with each profile and library kind. It builds the strict
Ada 2022 library, CLI and nested AUnit consumers; required flags and runtime
checks remain enabled. The latest reviewed local Windows validation/static run
passed 574 AUnit cases, zero failed assertions and zero unexpected errors,
public Ada syntax/session consumer, 35 process CLI cases and eight differential
fixtures. There are 86 new focused lifecycle cases beyond the 488-case baseline.

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

The reviewed runtime requires all Windows/Linux/macOS × development/validation/
release × static/shared jobs, plus Windows validation/static-PIC. Every job must
show the focused tests, API/CLI regressions, retained M2b files and both lifecycle
files. Static-validation jobs additionally run the expanded campaigns, ABI and
layout checks. Final job IDs, inspected markers and conclusions are recorded
below once all jobs finish. A green summary without inspected evidence is not
sufficient.

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
