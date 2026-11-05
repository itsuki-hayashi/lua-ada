# Capability Matrix

This matrix describes the scoped M1 implementation. Platform evidence lives in
[status](status.md); a feature entry alone is not full conformance evidence.

| Area       | M1 implementation                                           | Evidence                                       |
| ---------- | ----------------------------------------------------------- | ---------------------------------------------- |
| Values     | nil, bool, int64, binary64, byte strings                    | Integer/number/session AUnit                   |
| Operators  | Arithmetic, bits, comparisons, concat, length, logic        | Numeric matrix, precedence/short-circuit cases |
| Variables  | Lexical cells, globals, _ENV, 5.5 global/const              | Scope/global/constant cases                    |
| Statements | Assignments, blocks, conditionals, all loops, break/return  | Session cases, tables_and_loops.lua            |
| Functions  | Functions/methods, recursion, captures, varargs, tail calls | Session/lifecycle cases, core.lua              |
| Results    | Scalar/list adjustment, nil padding, final expansion        | Packet/assignment/named-vararg cases           |
| Tables     | Construction, mutation, identity, raw access, iteration     | Key/iteration cases and fixtures               |
| Errors     | Located diagnostics, pcall, bounded resources, recovery     | Lifecycle cases, errors_and_bytes.lua          |
| Lifetime   | Nonmoving iterative tracing; cycles and prototypes          | Cycle/capture/repeated-chunk cases             |
| Ada host   | Unique sessions, persistent globals, output sink            | Lifecycle Ada consumer                         |
| CLI        | Files, snippets, stdin, arguments, usage, stderr/status     | 19 process cases                               |
| Builds     | Static/shared, strict profiles                              | Acceptance matrix; see status                  |

The base subset is exactly `print`, `assert`, `error`, `pcall`, `type`,
`tonumber`, `tostring`, `select`, `next`, `pairs`, `ipairs`, `rawequal`,
`rawget`, `rawset`, `rawlen`, `_G`, and `_VERSION`; CLI adds `arg`.

## Deliberately deferred

M2a adds shared syntax checking and a private canonical opcode definition layer.
Syntax accepts goto/labels/close while execution returns Unsupported_Feature.
See the [frontend inventory](frontend.md) for scope and current evidence.

- Syntax accepted: full pinned default grammar/static-semantic target.
- Runtime behavior: M1 execution plus corrected Lua 5.5 const loop controls.
- Opcode format: all 85 canonical definitions and six encodings.
- Canonical code generation: deferred; compiler lowers to private operations.
- Canonical code execution: deferred; no binary chunk compatibility claim.

| Facility                              | Later gate / current response                    |
| ------------------------------------- | ------------------------------------------------ |
| goto / labels / close attributes      | Checks accept; execution Unsupported_Feature     |
| Metatables, weak tables, finalization | M2; no metamethod dispatch                       |
| Coroutines, userdata, full libraries  | M2; unavailable facilities                       |
| Runtime load/loadfile/require         | M2/M4; unavailable facilities                    |
| Binary chunks                         | M3; text-source interface only                   |
| C exports and allocator parity        | M3; isolated feasibility probes only             |
| Dynamic native modules / LuaRocks     | M4; no compatibility claim                       |
| Whole upstream suite                  | M5; inventory records all deferred prerequisites |
| Interactive REPL                      | Future CLI work; no-input usage is intentional   |

M1 does not specify hash iteration order, ambiguous table borders, pointer text,
or byte-identical diagnostic wording. Differential fixtures avoid relying on
those implementation choices. IEEE formatting follows the matching host oracle.
