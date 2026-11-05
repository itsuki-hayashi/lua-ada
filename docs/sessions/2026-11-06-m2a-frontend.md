# M2a Frontend Implementation

Date: 2026-11-06, Asia/Tokyo. Branch: codex/m2a-frontend-parity.
Baseline: master dd76522. M2a remains in progress.

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
The existing compiler consumes the updated batch interface pending its
replacement by shared parsing/lowering.

A protected isolated C frontend adapter provides lexical inspection and
compile-only parsing. Neither adapter executes source or links into Lua Ada.
10,000 arbitrary-byte C/Ada token comparisons passed (seed 551, lengths
0 through 64); all 34 unchanged upstream files have matching lexical token
streams, payloads, and scanner lines. This is not parser or execution evidence.
The current 260-case AUnit runner passed with no failures/unexpected errors.

## Remaining acceptance

Shared resolved syntax storage, complete grammar/static semantics, VM lowering
refactor, public checking API, --check, and unsupported-feature status remain
pending. Grammar generation/mutation campaigns and upstream parse comparison
remain pending. Cross-platform/profile/link acceptance must run on the final
revision. No milestone completion or full Lua compatibility is claimed.

