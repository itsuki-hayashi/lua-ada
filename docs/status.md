# Project Status

Updated: 2026-11-05 (Asia/Tokyo). M0 complete; **M1 active and incomplete**.
See the accepted [M1 target](milestones/m1.md).

## Implemented and verified

- Reusable static/shared library, separate development CLI, nested AUnit crate.
- Byte-oriented lexer with keywords, operators, source positions, decoded string
  escapes, long strings/comments, syntax diagnostics, and a token budget.
- Six AUnit cases covering lexical/integer boundaries and 1,000 deterministic
  arbitrary-byte source scans.
- Checked integer wrapping, floor division/modulo, and logical shifts.
- CLI help/version and explicit failure for unsupported execution requests.
- Isolated C reference CLI and ABI probes; three oracle-only Lua fixtures.

Windows x86-64 passed all six development/validation/release x static/shared
build/test combinations. AUnit has 6 successes, 0 failed assertions, 0 unexpected
errors per run. CLI contracts pass in each combination. The parent library is
validation-profile under AUnit; the matrix also builds each requested root
profile explicitly.

The additional static-PIC validation build/test also passed on Windows.

Tools: Alire 2.1.1, GNAT 16.1.0, AUnit 26.0.0, GPRbuild package 26.0.1
(binary banner 26.0.0). Shared tests load the real library; production has no
C reference dependency. Local logs are ignored under reports/.

ABI probe on Windows: integer=8, number=8, lua_Debug=144, extraspace=8 bytes;
currentline offset=48. These are host observations, not portable constants.
Callback/jump prototypes are limited; full error/yield integration is unresolved.

## Not yet verified or implemented

Linux/macOS CI has been authored but not run remotely. Neither platform has
local evidence. No resolving parser, bytecode VM, runtime values/tables/GC,
session embedding API, base functions, script execution, or C drop-in API exists.

The Lua fixtures pass on C Lua 5.5.1 only; **Ada parity is not tested**.
Full upstream inventory/conformance, native modules, LuaRocks, binary chunks,
GNATdoc output, fuzz campaigns, and formal proof are not complete.

See [session evidence](sessions/2026-11-05-m1-gates.md) and [backlog](backlog.md).
