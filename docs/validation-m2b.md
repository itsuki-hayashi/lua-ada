# M2b Validation Evidence

Date: 2026-11-06, Asia/Tokyo. **All M2b implementation gates passed.**

Implementation: commit `5057fa151cfb608c52cc32308d8ede045fd71ddf` in
[PR #4](https://github.com/itsuki-hayashi/lua-ada/pull/4).
The [18-job acceptance run](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42085233906)
passed every configuration. Every job log was inspected for actual test totals,
upstream results, and applicable probe/campaign results. The handoff commit
updates documentation only; its PR checks must also pass before handoff.

## Configurations and tools

- Windows Server 2025 / Windows 10.0.26100, x86_64-w64-mingw32.
- Ubuntu 24.04.5 LTS, x86_64-pc-linux-gnu.
- macOS ARM64, aarch64-apple-darwin24.6.0. Static-validation and shared-release
  reported macOS 26.7.2; the other four jobs reported 26.6.2.

Each OS passed development, validation, and release with static and shared
linking. The Windows static-validation job additionally passed static-PIC.
All selected stable native GNAT 16.1.0 through Alire 2.1.1, GPRbuild package
26.0.1 (banner 26.0.0), and test-only AUnit 26.0.0. No compiler pin or runtime
dependency was added. Strict compiler/style switches and runtime checks remain
enabled; the existing ADR 0003 floating-validity exception is unchanged.

## Per-configuration acceptance

Every one of the 18 jobs passed:

- 475 individually named AUnit cases, zero failed assertions/unexpected errors.
- The public Ada syntax/session consumer and 30 CLI process cases.
- Seven raw-byte differential fixtures, including the existing 2,366-operation
  numeric matrix and the new 1,120-case library campaign.
- Three unchanged whole-file upstream execution comparisons: tpack.lua,
  utf8.lua, and bitwise.lua. bwcoercion.lua is an unchanged dependency/helper,
  not a fourth suite.

The same acceptance passed again under Windows validation/static-PIC. New
focused cases cover native/Lua nesting, pending GC roots, protected and resource
unwinding, recovery, metamethod rules/isolation, patterns, packing/UTF-8 limits,
formatting, text readers/environments, module registries/searchers, and table/math
boundaries. Each test explains its setup and protected regression.

The upstream runner verified disposable copies against pinned source bytes,
used independent C/Ada processes for each primary file, and required equal
same-host stdout, empty stderr, successful exits, and final success markers.
Both processes used the same directory/local package path. No _soft, _port, _U,
or _nomsg flags were set; T was absent, and all.lua was never executed.
Every pass used the normal 1,000,000-instruction profile and 120-second wall
timeout. The optional 20,000,000 profile was not required or used.

## Additional static-validation evidence

Each OS static-validation job passed:

- The existing isolated ABI feasibility probe: allocator, varargs, extra space,
  Ada callbacks, and protected errors. Layout observations remain integer=8,
  number=8, debug=144, extraspace=8, currentline offset=48.
- The retained frontend/opcode campaigns: all 85 definitions, 4,096 words,
  10,000 arbitrary-byte lexer inputs, allocation-pressure diagnostics, 2,000
  generated grammar cases plus 2,000 mutations, and all 34 unchanged upstream
  files checked lexically and parse-only. This does not execute those 34 files.
- The independent C99/Ada native-layout comparison, including long double.
- The explicit 1,120-case/eight-family library campaign, seed 0x25a51, with
  identical raw stdout, empty stderr, successful exits, and default limits.

All measured hosts use 8-bit bytes, little endian, short=2, int=4, size_t=8,
float=4, double=8, Lua integer=8, and Lua number=8 bytes. Native long is 4 bytes
on Windows and 8 on Linux/macOS. C long double and maximum alignment are
16 bytes on Windows/Linux and 8 on macOS. The probe compares each individual
type alignment too; these are measured layouts, not portable constants.

## Repairs and scope

The first CI attempt exposed Darwin's normalized hexadecimal subnormal spelling.
The repaired formatter preserves Windows C89 modifier restrictions, Darwin's
normalized subnormal representation, and Linux's minimum-normal exponent
representation. Portable host-policy cases and unchanged differential output
protect the repair; no comparison or fixture was weakened.

Other review regressions protect empty xpcall handler results, load reader error
objects, outermost protected tail unwinding, and accounting for native quoting,
subject copies, backreference comparisons, and dynamic compilation.

The [M2b scope](milestones/m2b.md) remains bounded. These are **three whole-file
execution passes**, not complete upstream-suite conformance. Other upstream
suites remain outside this gate; bwcoercion is exercised as the helper of
bitwise. Canonical code generation/execution, binary chunks, remaining
runtime/libraries, full C API/ABI, native modules, and LuaRocks remain deferred.
Reference and ecosystem-fixture pins are unchanged; ecosystem tests were not
run. GNATdoc rendering, GNATtest generation, GNATfuzz, and proof were not run.
The PR is open for review and has not been merged.
