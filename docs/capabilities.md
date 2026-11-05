# Capability Matrix

This matrix separates implemented runtime facilities from accepted milestones.
M1 and M2a are accepted; [M2b](milestones/m2b.md) implementation and validation
are in progress. Evidence lives in [status](status.md); source existence alone
does not establish platform acceptance or full conformance.

| Area       | Runtime implementation                                      | Evidence                                       |
| ---------- | ----------------------------------------------------------- | ---------------------------------------------- |
| Values     | nil, bool, int64, binary64, byte strings                    | Integer/number/session AUnit                   |
| Operators  | Arithmetic, bits, comparisons, concat, length, logic        | Numeric matrix, precedence/short-circuit cases |
| Variables  | Lexical cells, globals, _ENV, 5.5 global/const              | Scope/global/constant cases                    |
| Statements | Assignments, blocks, conditionals, all loops, break/return  | Session cases, tables_and_loops.lua            |
| Functions  | Functions/methods, recursion, captures, varargs, tail calls | Session/lifecycle cases, core.lua              |
| Results    | Scalar/list adjustment, nil padding, final expansion        | Packet/assignment/named-vararg cases           |
| Tables     | Construction, mutation, identity, raw access, metatables    | Key/iteration and native-dispatch cases        |
| Errors     | Diagnostics, pcall/xpcall, resources, callback recovery     | Lifecycle and native continuation cases        |
| Lifetime   | Nonmoving iterative tracing; cycles and prototypes          | Cycle/capture/repeated-chunk cases             |
| Ada host   | Unique sessions, persistent globals, output sink            | Lifecycle Ada consumer                         |
| CLI        | Files, snippets, stdin, arguments, usage, checking/status   | 30 process cases                               |
| Builds     | Static/shared, strict profiles                              | Acceptance matrix; see status                  |

## M2b export inventory

Fresh sessions register the following library surface. This is the declared
M2b implementation scope; the milestone remains open until its full acceptance
matrix passes. CLI execution additionally supplies `arg`.

| Library / group        | Functions and fields                                                  |
| ---------------------- | --------------------------------------------------------------------- |
| Base calls/errors      | print, assert, error, pcall, xpcall, type, tonumber, tostring, select |
| Base tables            | next, pairs, ipairs, rawequal, rawget, rawset, rawlen                 |
| Base metatables        | getmetatable, setmetatable                                            |
| Base loading/state     | load, loadfile, dofile, require, _G, _VERSION                         |
| string bytes           | byte, char, len, lower, rep, reverse, sub, upper                      |
| string patterns/format | find, format, gmatch, gsub, match                                     |
| string packing         | pack, packsize, unpack                                                |
| utf8                   | char, codes, codepoint, len, offset, charpattern                      |
| table                  | concat, insert, remove, move, pack, unpack                            |
| math functions         | abs, ceil, floor, fmod, max, min, modf, tointeger, type, ult          |
| math constants         | huge, pi, maxinteger, mininteger                                      |
| package                | loaded, preload, searchers, path, searchpath, config                  |

Patterns include captures, position captures, backreferences, balanced/frontier
patterns, and empty-match progression. gsub supports string/table/Lua-function
replacements; gmatch retains iterator state. Strings remain byte sequences,
including embedded NUL. Packing supports widths 1–16, byte orders, alignment,
binary32/binary64, fixed/prefixed/zero-terminated strings, and virtual packsize.
UTF-8 supports strict/lax decoding, extended 31-bit encodings, and Lua 5.5's two
offset results.

Core dispatch covers __index, __newindex, __call, arithmetic/bitwise/unary
handlers, __len, __concat, __eq, __lt, __le, __tostring, __pairs, __metatable,
and applicable __name diagnostics. Lookup itself and raw operations bypass
handlers. Lua and native handlers share result adjustment and protected errors.
Each session has its own string metatable and initial string arithmetic
handlers. Primitive bitwise operations reject numeric strings; installed Lua
handlers may supply coercion.

Text load accepts strings/readers, names, modes, and explicit environments.
loadfile/dofile reuse file preambles. Lua-only require has preload/file searchers,
loader data, caching, and mutable searchers. Its internal registries survive
replacement of public package.loaded/preload fields. The default package.path
is `./?.lua;./?/init.lua`; native loading is deferred.

## Deliberately deferred

M2a adds shared syntax checking and a private canonical opcode definition layer.
Syntax accepts goto/labels/close while execution returns Unsupported_Feature.
See the [frontend inventory](frontend.md) for scope and current evidence.

- Syntax accepted: full pinned default grammar/static-semantic target.
- Runtime behavior: M1 execution plus the M2b surface above; acceptance open.
- Opcode format: all 85 canonical definitions and six encodings.
- Canonical code generation: deferred; compiler lowers to private operations.
- Canonical code execution: deferred; no binary chunk compatibility claim.

| Facility                               | Later gate / current response                    |
| -------------------------------------- | ------------------------------------------------ |
| goto / labels / close attributes       | Checks accept; execution Unsupported_Feature     |
| Weak tables and finalization           | Remaining M2; unsupported                        |
| Coroutines, userdata, debug, io/os     | Remaining M2; unavailable facilities             |
| string.dump, table.sort/create         | Remaining library work; unavailable              |
| Math RNG and remaining transcendentals | Remaining library work; unavailable              |
| Binary chunks                          | M3; text-source interface only                   |
| C exports and allocator parity         | M3; isolated feasibility probes only             |
| Dynamic native modules / LuaRocks      | M4; no compatibility claim                       |
| Whole upstream suite                   | M5; inventory records all deferred prerequisites |
| Interactive REPL                       | Future CLI work; no-input usage is intentional   |

The runtime does not specify hash iteration order, ambiguous table borders,
pointer text, or byte-identical diagnostic wording. Differential fixtures avoid relying on
those implementation choices. IEEE formatting follows the matching host oracle.
