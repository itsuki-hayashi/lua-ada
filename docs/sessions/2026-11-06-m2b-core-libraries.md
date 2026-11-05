# M2b Core Libraries Session

Date: 2026-11-06, Asia/Tokyo. Branch: codex/m2b-core-libraries.
Baseline: master 8c001ad after the maintainer merged PR #3.
Status: **implementation and validation in progress**.

## Accepted work

The [M2b target](../milestones/m2b.md) owns scope and stable work identifiers.
The acceptance goal is unchanged tpack.lua, utf8.lua, and bitwise.lua, with
bwcoercion.lua as a helper. No complete upstream-suite pass is implied.

## Harness foundation

Added a public-API upstream runner, disposable raw-byte comparison driver, and
an isolated C99 native-layout probe. The driver verifies fixture-copy hashes,
uses independent processes, removes ambient Lua initialization from child
environments, enforces successful exit/empty stderr/final markers, and retains
evidence under ignored reports/upstream. The instruction budget is explicit;
the larger allowed profile is never selected silently.

The host-layout probe measures native widths/alignment and maximum alignment
using the pinned LUAI_MAXALIGN union. Its output must be compared with the Ada
packing layout before platform acceptance. It is never production glue.

## Evidence and handoff

The integration owner built the initial integrated sources with GNAT 16.1.0
under strict flags and recorded 439/439 AUnit cases passing in
reports/m2b-aunit.log. The disposable driver recorded three whole-file passes
in reports/m2b-upstream.log: tpack.lua, utf8.lua, and bitwise.lua, each using
the normal 1,000,000-instruction budget and 120-second timeout. bwcoercion.lua
remains an unchanged helper. This is provisional Windows development/static
evidence; later edits require rerunning it, and platform acceptance remains
open until all required jobs pass on the final PR revision.

The loading work area added resumable readers, independently captured load
environments, file loading, registry-owned module state, mutable searchers,
and custom loader-data propagation. Table helpers use native continuations for
metamethod-aware length/read/write/equality operations, keeping pending values
rooted. Core math helpers include exact dyadic fmod reduction with charged
native loops. Forty-one focused public-session library tests cover these
contracts, including six additional table-event cases awaiting the next run.

Harness checks also exercised the subprocess capture helper against the C
oracle with empty output: stdout/stderr both remained zero-length byte arrays,
exit status zero. This protects raw-byte reporting from PowerShell's empty-array
unwrapping. The script parser and repository Markdown links passed at harness
creation; the integration owner coordinates final lint and build checks.

Reference and consumer fixture pins remain unchanged. Generated configuration
must not be edited, and Alire builds remain serialized across work areas.

## Final local integration before publication

The complete Windows validation/static command passed after review fixes:
`pwsh -NoProfile -File scripts/check.ps1 -Profile validation -LibraryType static`.
It passed 472 individually named AUnit cases, 30 CLI cases, the syntax consumer,
seven differential fixtures, and all three unchanged upstream primary files.
Each upstream file used the default 1,000,000-instruction budget and 120-second
wall timeout. The separate 1,120-case campaign uses seed 0x25a51.
The C99/Ada layout comparison passed, including long-double alignment.

Review regressions cover zero-result xpcall handlers, protected reader errors
returned by load, outermost protected tail-call unwinding, quoted-string work,
backreference comparisons, repeated subject copies, and dynamic compilation
work. Resource exhaustion remains an execution abort through protected calls.
The expanded environment is collected after bootstrap so heap statistics have
a stable live baseline; the automatic-collection test reserves 128 transient
objects above that baseline instead of relying on the old builtin count.

Cross-platform CI, ABI probes, Windows static-PIC, and final PR acceptance remain
pending. Local logs are ignored reports, not immutable cross-platform evidence.

## First CI feedback

Published implementation 7d329ae and opened
[PR #4](https://github.com/itsuki-hayashi/lua-ada/pull/4).
Linux configurations passed; macOS passed 472 AUnit cases and all three primary
files but failed the added library differential campaign. Darwin libc normalizes
hexadecimal subnormals (0x1p-1074), while Linux retains a minimum-normal exponent
(0x0.0000000000001p-1022). The Ada formatter now selects the matching host policy.
Three portable focused cases exercise macOS subnormal/precision behavior and
protect the Linux representation on every host. No fixture or comparison was
weakened. The repaired revision still requires all platform jobs to pass.
