# M2a Frontend Implementation

Date: 2026-11-06, Asia/Tokyo. Branch: codex/m2a-frontend-parity.
Baseline: master dd76522. M2a is complete; see
[immutable validation](../validation-m2a.md).

## Baseline

Windows x86_64-w64-mingw32; Alire 2.1.1, native GNAT 16.1.0,
GPRbuild banner 26.0.0. Initial static-validation check passed 171 AUnit
cases, 19 CLI cases, and six differential fixtures. Pinned references and
consumer fixtures remain unchanged.

## Work and evidence

Added a private canonical opcode layer, independent of the M1 VM, and
test-only C/Ada inspection executables. All 85 metadata entries and 4,096
arbitrary instruction words match pinned C Lua. The 89 new focused AUnit
cases cover every opcode separately, operand endpoints/overflow, unused
IDs, top predicates, and 4,096 bit-preserving round trips.

Refactored scanning into an owned incremental scanner with a batch adapter.
Numerals are validated lexically and classified as integer/float; tokens
retain decoded numbers and post-token locations. Default contextual global,
hex exponent scanning, and unmatched byte tokens match C Lua.
The compiler now lowers owned resolved syntax nodes; its previous grammar and
name resolver have been removed. Nodes retain bindings, captures, declaration
attributes, and jump targets. Checking allocates no runtime heap or globals.

A protected isolated C frontend adapter provides lexical inspection and
compile-only parsing. Neither adapter executes source or links into Lua Ada.
10,000 arbitrary-byte C/Ada token comparisons passed (seed 551, lengths
0 through 64); all 34 unchanged upstream files have matching lexical token
streams, payloads, and scanner lines. This is not parser or execution evidence.
Subsequent local validation passed 347 focused AUnit cases and 30 CLI cases,
plus a standalone Ada syntax/session consumer. Existing six raw-byte execution
fixtures and the arithmetic matrix still pass against the pinned interpreter.
The generated 2,000 valid grammar cases and 2,000 mutations match C acceptance
and reported lines. Raw-source parse comparisons match all 34 unchanged files;
all.lua/main.lua reject their leading # preamble in both raw interfaces.
CLI file loading handles those preambles separately. No suite was executed.

Lua.Syntax.Check returns owned diagnostics and controlled resource failures.
CLI --check supports all batch inputs without creating a session. Execution
validates a whole chunk before Unsupported_Feature for goto/labels/close.
Syntax failures take precedence. Numeric and first generic-for controls now
follow Lua 5.5 const rules, correcting the previous M1 assignment test.

## Final acceptance and handoff

All 18 OS/profile/link jobs passed at implementation commit d8770ef; every job
log was inspected. Each OS passed the frontend/opcode campaign and ABI probe;
Windows additionally passed static-PIC. All seven bounded backlog gates close
with this evidence. PR #3 is open and unmerged. Final handoff changes record
evidence and strengthen the existing multiline error-priority regression.

The Linux C oracle initially needed explicit Unix math linking; that was fixed.
The adapter now roots its source label across allocation/collection, protected
by the allocation-pressure regression. Required compiler commands were inspected.
No full Lua execution, canonical code generation, C ABI, binary chunk, or module
parity is claimed. Continue with deferred M2 runtime/library work or a separately
scoped canonical-code generation milestone; do not treat opcode definitions as
an executable VM migration.
