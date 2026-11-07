# Remaining upstream compatibility implementation

Date: 2026-11-07, Asia/Tokyo. Status: implementation in progress.

## Objective and baseline

Complete the approved remaining upstream target, relevant T paths and native
fixtures in one PR, address automatic review, then merge after final acceptance.
Start: clean master d438f1fb2491006c1c248e0888637b4afa5ae0fc, merged PR #10.
Branch: codex/m3-remaining-upstream-compatibility. ADR 0018 records the approved
private-T review/exclusion policy without weakening public behavior.

## Initial implementation and verification

The package Lua searcher had forced text mode. It now accepts text or native
binary chunks, like loadfile. A separately named AUnit case writes a dumped
module, requires it, verifies loader data and verifies cached identity, removing
the fixture before result assertions.

Strict Windows validation/static root and test builds pass using Alire 2.1.1
and GNAT 16.1.0. Commands: alr -n build --validation with
-XLUA_ADA_LIBRARY_TYPE=static and -XLUA_ADA_PREBUILT=false at the root; then
alr -n build --validation --profiles=lua_ada=validation with prebuilt=true in
tests. tests/bin/static/test_runner.exe passes 1,391 cases, zero assertion
failures and zero unexpected errors. Captures are under ignored
reports/remaining-loader-*.log.

The first full default baseline command was scripts/check.ps1 -LibraryType
static -Profile validation. It passes the original 1,390 AUnit cases and
retained component checks but fails scoped acceptance because first-party edits
were made during execution. The report explicitly identifies dirty inputs.
This run is incomplete, not a passing pipeline; preserve
reports/remaining-baseline-default.log and rerun from a clean checkpoint.

The first new test setup used os.tmpname and encountered a Windows permission
failure before reaching require. The test now uses a dedicated local fixture
name in its isolated serial test directory, then removes it. This setup repair
does not establish os.tmpname compatibility; native temporary-path behavior
remains part of the remaining file/CLI validation.

## Outstanding work

Isolated managed worktrees are implementing reviewed-exclusion validation,
reader/writer C APIs and actual debug metadata. No new full-file acceptance,
global API completion, exclusion approval, final matrix, PR or merge is claimed.
Finish the approved checkpoints and fresh exact-revision evidence before PR
readiness; this record is a progress checkpoint, not task completion.
