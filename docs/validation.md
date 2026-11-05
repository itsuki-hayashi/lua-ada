# M1 Validation Evidence

Date: 2026-11-05, Asia/Tokyo. **All five M1 gates passed.**

Runtime evidence: [18-job acceptance run](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42045878008)
at commit `ec93d6dcea9322896981b3ead4b2077d6c50b68c`.
Every job log was inspected for test totals, CLI/differential results, stable
compiler selection, and documentation checks.

## Platform and configuration matrix

| Host                            | Architecture / compiler target | Development        | Validation               | Release            |
| ------------------------------- | ------------------------------ | ------------------ | ------------------------ | ------------------ |
| Windows Server 2025, 10.0.26100 | x86_64-w64-mingw32             | static/shared pass | static/shared pass + ABI | static/shared pass |
| Ubuntu 24.04.5 LTS              | x86_64-pc-linux-gnu            | static/shared pass | static/shared pass + ABI | static/shared pass |
| macOS 26.6.2                    | aarch64-apple-darwin24.6.0     | static/shared pass | static/shared pass + ABI | static/shared pass |

All configurations use Alire 2.1.1, latest available stable native GNAT 16.1.0,
GPRbuild package 26.0.1 (banner 26.0.0), and test-only AUnit 26.0.0. The native
C oracle is compiled with the same GCC toolchain and host C/math runtime.
The baseline uses 64-bit Lua integers and IEEE binary64 numbers. No other
OS/architecture, C runtime, or nondefault numeric configuration is certified.

## Evidence per job

Each of the 18 jobs passed:

- 171 separately named AUnit cases: 21 integer, 33 lexer, 30 number,
  50 language/session, and 37 lifecycle/resource/GC cases.
- Zero failed assertions and zero unexpected errors.
- 19 CLI process cases for usage/version, snippets, files, stdin, preambles,
  arguments, diagnostics, output preservation, and status.
- Six raw-byte differential fixtures against pinned C Lua 5.5.1, including
  a 2,366-operation arithmetic matrix and NUL/invalid-UTF-8 output.
- Documentation UTF-8/LF, local-link, and aligned-table checks.

The three static/validation jobs also passed allocation/failure, varargs,
callbacks/reentry, C-only protected jumps, extra space, reference coroutine
yield/resume after Ada returns, and explicit C-host Ada initialization/finalization.
Each observed integer=8, number=8, lua_Debug=144, extra space=8, and currentline
offset=48 bytes. Those observations are not portable representation constants.

Windows additionally passed static-PIC validation with the final 171-case
runtime. Local ignored logs live under reports. Compiler argument records
were inspected in all three profiles: required `-gnat2022 -gnatwa -gnatwe
-gnatv -gnaty` are present, runtime checks remain enabled, and no `-gnatp`
appears. ADR 0003 records the narrow floating-validity exception.

## Gate closure

| Gate                         | Acceptance evidence                                                                           |
| ---------------------------- | --------------------------------------------------------------------------------------------- |
| 1: Build/test foundation     | 18 static/shared strict-profile jobs; real CLI/Ada consumers and focused AUnit                |
| 2: Compatibility constraints | Three-host ABI probes, all 34 upstream files inventoried, ownership ADRs, byte oracle runner  |
| 3: Values/substrate          | Numeric boundaries, key rules, roots, explicit frames, cyclic/prototype reclamation           |
| 4: Language execution        | Resolving frontend, private registers, all scoped control flow, closures, packets, tail calls |
| 5: Usable interpreter        | Base subset, owned sessions, recovery/limits, batch CLI and acceptance fixtures               |

## Limits of this evidence

M1 is the [accepted subset](milestones/m1.md), not full Lua conformance.
No whole unchanged upstream file is claimed passing on Ada; the
[inventory](upstream-tests.md) records each prerequisite and subset mapping.
The C reference remains separate from production. ABI feasibility is not a
public exported C API, allocator parity, or permission for longjmp across Ada.
Complete libraries, C ABI, chunks, native loading, LuaRocks, and other target
configurations remain later gates. No generated GNATdoc, generated GNATtest
coverage, fuzz campaign, proof result, or performance benchmark is claimed.
