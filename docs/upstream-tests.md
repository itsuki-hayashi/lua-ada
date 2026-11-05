# Pinned Upstream Test Inventory

Baseline: Lua v5.5.1, `7579fc9d7ed90240487251dfb69168f8e64e9294`.
All 34 `references/lua/testes/*.lua` files are preserved unchanged.

M1 had no whole-file upstream execution passes. The historical inventory below
records its prerequisites and reviewed first-party subset mappings. M2a added
compile-only evidence; M2b targets the first three unchanged execution files.
These distinct evidence levels must not be conflated. Complete upstream
conformance remains later work.

## M2b execution targets

| File           | Role                                      | Direct Windows result            |
| -------------- | ----------------------------------------- | -------------------------------- |
| tpack.lua      | Packing, alignment, numbers, byte strings | Provisional pass, default budget |
| utf8.lua       | UTF-8, patterns, formatting, text loading | Provisional pass, default budget |
| bitwise.lua    | Bits, string handlers, loading, coercion  | Provisional pass, default budget |
| bwcoercion.lua | Module loaded by bitwise.lua              | Helper, not a fourth suite       |

Windows disposable raw-byte comparisons now also pass at the default budget.
The [M2b protocol](milestones/m2b.md) requires each primary file to run alone
against C Lua and Ada in fresh processes, from disposable verified copies, with
no _soft/_port/_U/_nomsg flags and no T. Require empty stderr, successful exit,
same-host stdout byte equality, and the final success marker within 120 seconds.
Use the default 1,000,000-instruction profile unless measured instruction-only
exhaustion justifies the explicit documented test profile. Linux/macOS and final
revision matrix evidence remain unverified. See [status](status.md) and the
[current session](sessions/2026-11-06-m2b-core-libraries.md).

All other files below remain outside M2b whole-file acceptance. Do not invoke
all.lua or infer their execution coverage from these three targets.

## Historical M1 mappings

| File                                                      | Purpose                       | Deferred prerequisites                         | M1 mapping                          |
| --------------------------------------------------------- | ----------------------------- | ---------------------------------------------- | ----------------------------------- |
| [all.lua](../references/lua/testes/all.lua)               | Suite orchestration           | load/require, libraries, T, coroutine/GC modes | No whole-file run                   |
| [api.lua](../references/lua/testes/api.lua)               | C API and stack operations    | T, C exports, userdata/metatables              | ABI probe is feasibility only       |
| [attrib.lua](../references/lua/testes/attrib.lua)         | Assignments and global state  | load/require, libraries, coroutine/T           | Session assignment/global cases     |
| [big.lua](../references/lua/testes/big.lua)               | Large expressions and stress  | load, libraries, T, metatables                 | Register/source budgets             |
| [bitwise.lua](../references/lua/testes/bitwise.lua)       | Bit operations                | load, math/string, T                           | Integer cases; numeric matrix       |
| [bwcoercion.lua](../references/lua/testes/bwcoercion.lua) | Bit coercion/metamethods      | string/math, metatables                        | Primitive coercion only             |
| [calls.lua](../references/lua/testes/calls.lua)           | Calls and recursion           | load/require, libraries, metatables/T          | Calls, tail frames, core.lua        |
| [closure.lua](../references/lua/testes/closure.lua)       | Captures and lifetime         | load, debug/GC, metatables/T                   | Capture/cycle AUnit cases           |
| [code.lua](../references/lua/testes/code.lua)             | Exact VM/code generation      | T opcode inspection, load, libraries           | Reviewed mapping below              |
| [constructs.lua](../references/lua/testes/constructs.lua) | Grammar/control flow          | load/require, debug/libraries/T                | Lexer/control-flow cases            |
| [coroutine.lua](../references/lua/testes/coroutine.lua)   | Coroutine semantics           | Coroutine library, yields, T                   | Deferred; ABI yield experiment only |
| [cstack.lua](../references/lua/testes/cstack.lua)         | C-stack overflow boundaries   | Coroutine/metatables, string, T                | Explicit-frame depth/tail cases     |
| [db.lua](../references/lua/testes/db.lua)                 | Debug hooks and traceback     | Debug library and other full libraries         | Located diagnostics only            |
| [errors.lua](../references/lua/testes/errors.lua)         | Error semantics/messages      | load, debug, libraries, metatables/T           | Protected/error/recovery cases      |
| [events.lua](../references/lua/testes/events.lua)         | Metamethod dispatch           | Metatables, libraries, T                       | Deferred                            |
| [files.lua](../references/lua/testes/files.lua)           | Filesystem/process I/O        | io/os, load/require, full libraries            | CLI file-input cases only           |
| [gc.lua](../references/lua/testes/gc.lua)                 | Collector modes/finalization  | collectgarbage, weak/finalized objects, T      | Cycle/live-root AUnit cases         |
| [gengc.lua](../references/lua/testes/gengc.lua)           | Generational collection       | Collector modes, metatables/T                  | Basic tracing only                  |
| [goto.lua](../references/lua/testes/goto.lua)             | Labels and goto               | goto, load, libraries, T                       | Explicit unsupported diagnostic     |
| [heavy.lua](../references/lua/testes/heavy.lua)           | Large stress helpers          | load, collectgarbage, libraries/I/O            | Bounded resource cases only         |
| [literals.lua](../references/lua/testes/literals.lua)     | Literal syntax                | load, libraries, coroutine/debug/T             | Lexer and numeric boundary cases    |
| [locals.lua](../references/lua/testes/locals.lua)         | Locals/constants/closing      | close, load, debug, libraries/T                | Scope/global/const cases            |
| [main.lua](../references/lua/testes/main.lua)             | Full interpreter CLI          | Full flags, io/os, load/require, T             | 19 scoped CLI process cases         |
| [math.lua](../references/lua/testes/math.lua)             | Math library and numbers      | math/string, load, T                           | Numbers and numeric matrix          |
| [memerr.lua](../references/lua/testes/memerr.lua)         | Allocator failure injection   | T, complete API/libraries/GC                   | Reference allocator probe only      |
| [nextvar.lua](../references/lua/testes/nextvar.lua)       | Iteration/table behavior      | load, libraries, metatables/GC/T               | Table/iteration fixtures            |
| [pm.lua](../references/lua/testes/pm.lua)                 | Pattern matching              | String patterns, load, metatables/T            | Deferred                            |
| [sort.lua](../references/lua/testes/sort.lua)             | Sorting                       | table.sort, full libraries/metatables/T        | Deferred                            |
| [strings.lua](../references/lua/testes/strings.lua)       | String library                | string library, pack, libraries/T              | Byte literals/output cases only     |
| [tpack.lua](../references/lua/testes/tpack.lua)           | Binary pack/unpack            | string.pack/unpack, math, T                    | Deferred                            |
| [tracegc.lua](../references/lua/testes/tracegc.lua)       | GC tracing helper             | debug/collectgarbage, libraries/T              | Deferred helper                     |
| [utf8.lua](../references/lua/testes/utf8.lua)             | UTF-8 library                 | utf8/string, load/require, math/T              | Byte semantics only                 |
| [vararg.lua](../references/lua/testes/vararg.lua)         | Varargs and result adjustment | load, libraries, GC/T                          | Packets/named-vararg cases          |
| [verybig.lua](../references/lua/testes/verybig.lua)       | Very large table stress       | Full libraries and I/O/T                       | Bounded heap/table cases            |

## Internal-code mapping

M2a adds token and raw-source compile-only comparisons for every file above;
see the [frontend guide](frontend.md). Those checks are parse-only evidence;
M2b's three execution targets above are separate. Opcode definitions are
independently tested against C; code.lua instruction-stream/optimization
assertions remain deferred.

`code.lua` inspects C register opcodes, constants, and optimization choices
through the upstream `T` instrumentation. Those layouts do not define the
public language contract. M1 uses private typed Ada instructions and packets.

The precedence/associativity and short-circuit AUnit cases protect observable
evaluation; result-adjustment and assignment cases protect packet/scalar
boundaries; tail-frame and call-depth cases protect call behavior. These are
reviewed Ada behavioral equivalents for those respective invariants, not a
replacement for every exact opcode assertion in `code.lua`. Full optimization/
instruction-verification mappings remain open for the later conformance gate.

`ltests.c`, T-based memory failure injection, and public C API assertions
require later C facade work. The isolated C/Ada probe establishes boundary
feasibility only. Do not count it as the Ada implementation passing api.lua.

## Execution policy

Unchanged-suite runs must use a disposable working copy because tests
write files. Record mode flags (`_U`, `_soft`, `_port`, `_nomsg`), T availability,
OS, numeric ABI, and exclusions. A reduced suite or omitted T is not a full
upstream pass. Add actual per-file evidence when its prerequisites are delivered.
