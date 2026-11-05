# Compatibility Contract

Baseline: Lua **5.5.1**, pinned at
`7579fc9d7ed90240487251dfb69168f8e64e9294`. The
[Lua 5.5 manual](https://www.lua.org/manual/5.5/) defines the language; use
the pinned implementation/tests for release-specific behavior. Later upstream
releases require deliberate baseline updates and fresh evidence.

## Required behavior

Long-term compatibility includes language and standard libraries, CLI behavior,
public C API/ABI, compatible binary-chunk loading/dumping, native module loading,
and compatible LuaRocks packages. M1 and M2b execute their documented subset
through Ada sessions and the batch CLI; the
[M2b record](validation-m2b.md) establishes three whole-file execution passes.
Full libraries, C exports, chunks, native modules, and
LuaRocks remain future gates. See [capabilities](capabilities.md).

Claims must name OS, architecture, compiler/linker/C runtime, numeric settings,
endianness, and relevant Lua configuration. Begin with upstream's default
64-bit integer/double configuration on supported 64-bit hosts; do not imply
compatibility across different chunk formats or incompatible C runtimes.
Nondefault configurations need separate evidence.

Ada clients use the small [ownership-aware session interface](embedding.md). The ada-lua reference
is an API design input, not a dependency or a promise to clone its interface.

## Upstream tests

Preserve `references/lua/testes` unchanged. Applicable language and public API
tests must pass without changing assertions. The suite also contains C-internal
tests: [code.lua](https://github.com/lua/lua/blob/v5.5.1/testes/code.lua)
asserts exact opcodes/constant lists through `T`, and `ltests.c` uses internal
C headers. The Ada implementation may use different representations.

The [34-file inventory](upstream-tests.md) records deferred prerequisites and
subset mappings. Provide reviewed Ada equivalents with explicit
upstream-to-Ada mappings and rationale. Do not silently skip tests or equate
internal test adaptation with public API coverage. Distinguish C oracle results,
Ada equivalents, platform exclusions, failures, and unimplemented tests.

The upstream driver supports `_U`, `_soft`, `_port`, and `_nomsg`; reduced or
portable modes change coverage. Record those settings and unmet prerequisites.
Do not call a reduced run a full suite pass or treat missing `T` as evidence
that C API and internals were tested.

## ABI feasibility risks

| Concern                 | Evidence required before claiming compatibility        |
| ----------------------- | ------------------------------------------------------ |
| Variadic exports        | C varargs and `va_list` exercised from C callers       |
| Errors and yields       | Safe unwinding, reentry, cleanup, callback nesting     |
| Allocation              | `lua_Alloc`, resize/free, failures, userdata lifetime  |
| Addresses and layouts   | Opaque state, `lua_Debug`, stable pointers/extra space |
| Symbols and lifecycle   | Names, exports, static/shared linkage, Ada startup     |
| Native loading          | OS loader, search paths, ABI-compatible modules        |
| Chunks and numerics     | Matching version/configuration, cross-engine tests     |

Permit narrow essential C/OS glue where Ada cannot portably express the ABI.
Interpreter logic and portable behavior remain Ada. Never permit foreign
nonlocal jumps over Ada frames without an explicitly validated safe mechanism.

LuaRocks compatibility is demonstrated using selected pure-Lua and native rocks
on matching configurations, then expanded. Installation metadata alone is not
proof that modules load and behave correctly.

Eight [consumer module fixtures](../tests/modules/README.md) are pinned for
future C Lua/Lua Ada parity checks. The catalog owns revision, dependency, and
update notes. All module execution/platform evidence is currently unrun; the
checkouts do not expand M1 or establish LuaRocks/native-module compatibility.
