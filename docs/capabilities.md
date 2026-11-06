# Capability Matrix

This matrix separates implemented runtime facilities from accepted milestones.
M1, M2a, and [M2b](milestones/m2b.md) are accepted. Exact
[M2b validation](validation-m2b.md) complements [status](status.md); source alone
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
| CLI        | Files, snippets, stdin, arguments, usage, checking/status   | 35 process cases                               |
| Builds     | Static/shared, strict profiles                              | Acceptance matrix; see status                  |

## M2b export inventory

Fresh sessions register the following library surface. This is the declared
M2b implementation scope, verified in its acceptance matrix.
CLI execution additionally supplies `arg`.

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

## M3 mathematics implementation

The implementation extends the historical M2b inventory above with the exports
below. [ADR 0011](decisions/0011-host-mathematics.md) owns the dependency and RNG
decisions. Implementation is distinct from final platform/upstream acceptance;
current [status](status.md) owns verified test counts.

| Configuration / group | Added functions                        |
| --------------------- | -------------------------------------- |
| Default trigonometry  | acos, asin, atan, cos, sin, tan        |
| Default real helpers  | deg, exp, frexp, ldexp, log, rad, sqrt |
| Default owned RNG     | random, randomseed                     |
| Compatibility only    | atan2, cosh, sinh, tanh, pow, log10    |

The default table excludes the compatibility-only names. Seeded RNG output
uses xoshiro256** with native-64 or actual split-32 arithmetic, exact two-word
seeding and unbiased interval rejection. Both paths retain per-universe state;
reopening math through the future public C API still needs independently
captured RNG instances. Host mathematical primitives preserve native IEEE
domains, signed zero and rounding rather than raising Ada domain exceptions.

There are 38 new focused mathematical cases and a first-party byte-encoded
differential campaign. Oracle fixture validation is recorded; it does not by
itself establish Ada parity, unchanged math.lua or complete M3 acceptance.

## Deliberately deferred

M2a adds shared syntax checking and a private canonical opcode definition layer.
Goto/labels/close now execute through the private lifecycle backend.
See the [frontend inventory](frontend.md) for scope and current evidence.

- Syntax accepted: full pinned default grammar/static-semantic target.
- Runtime behavior: M1/M2b plus the implemented lifecycle delivery below;
  verified runtime matrix and final publication checks are recorded separately.
- Opcode format: all 85 canonical definitions and six encodings.
- Canonical code generation: normal text compilation emits real pinned words.
- Canonical code execution: normal sessions/CLI use scalar canonical registers;
  the earlier backend remains only during migration/platform verification.
- Native binary chunks: checked load/dump and selected-function string.dump
  have focused execution/interoperability evidence in [binary chunks](binary-chunks.md).

| Facility                          | Later gate / current response                            |
| --------------------------------- | -------------------------------------------------------- |
| Finalization                      | Deferred; no finalizer execution                         |
| Userdata                          | Stable payload/uservalue APIs; finalization pending      |
| io/os                             | Deferred; unavailable facilities                         |
| table.sort/create                 | Implemented; focused local acceptance, platforms pending |
| Reopened C-created math libraries | C-facade integration; distinct RNG captures required     |
| Binary chunks                     | Implemented; expanded platform acceptance pending        |
| C exports and allocator parity    | Partial real C surface; remaining API/allocator work     |
| Dynamic native modules / LuaRocks | M4; no compatibility claim                               |
| Whole upstream suite              | M3; full coverage ledger remains incomplete              |
| Interactive REPL                  | Future CLI work; no-input usage is intentional           |

The runtime does not specify hash iteration order, ambiguous table borders,
pointer text, or byte-identical diagnostic wording. Differential fixtures avoid
relying on those implementation choices. IEEE formatting follows the matching host oracle.

Decimal/hexadecimal numeric string formatting now uses the calling world's
managed exact limbs and byte buffers, including parser scratch for numeric
strings. It retains nearest-even rounding, signed zero and host-specific
hexadecimal policies. The [formatting guide](number-formatting.md) records the
sixteen focused owner/refusal cases and deterministic 1,435-line local C/Ada
campaign. This allocation-path checkpoint does not establish whole-file string
or math conformance, or complete callback-allocator coverage of the runtime.

## Language lifecycle implementation

Goto/labels, <close>, the fourth generic-for closing value and weak-key/value
tables execute on the canonical backend. Threads have real identity and
reachability-based ownership. Ephemerons use fixed-point stop-the-world tracing.
Lua-facing coroutine exports are create, resume, yield, wrap, status, running,
isyieldable and close. Base collectgarbage supports no argument, collect, stop,
restart and isrunning. Other options explicitly fail; no byte counts or collector
modes are fabricated.

The debug subset is getinfo, getlocal, setlocal, getupvalue, setupvalue, upvalueid,
sethook, gethook and traceback. The full-M3 implementation additionally provides
getregistry, getmetatable, setmetatable, getuservalue, setuservalue and
upvaluejoin, with shared primitive
type metatables. Fifteen focused session cases exercise actual registry roots,
cell identities, mutation and collection. It inspects actual cells and logical Lua/native
activations, including explicit-thread forms, source ranges, call-site names,
tail calls and per-thread call/return/line/count hooks. Native continuation phases
are hidden. Count cadence now follows executed canonical words and explicit native work;
full hook-cadence parity remains an expanded acceptance obligation.
Userdata storage and debug access to its actual traced uservalue slots are
implemented. Existing nil slots return a second true result; absent slots
return one nil. Finalizers remain pending. Canonical source,
local/upvalue inspection, native binary load/dump and the added debug operations are M3
implementation checkpoints with their own evidence and pending platform gates.

[Lifecycle acceptance](milestones/m3-language-lifecycle.md) owns unchanged
goto.lua/coroutine.lua execution, precise T-absent omissions and platform evidence.
Passing those targets does not complete any original M3 gate or establish full
C-API, allocator, canonical execution, binary-chunk or ecosystem compatibility.

Lifecycle runtime acceptance has passed the [18-job matrix](validation-m3-lifecycle.md)
and Windows static-PIC. upvalueid exposes opaque light-userdata identities for
actual cells. [Stable userdata](userdata.md) adds real payload pointers and
selected C creation/uservalue/metatable operations, with local component evidence.

Collector controls return C Lua's integer status where applicable. A disabled
gethook returns one nil; active hooks retain their requested signed count while
only positive intervals enable count events. Option flags honor the pinned
C-string NUL boundary without changing ordinary Lua byte-string semantics.

## M3 table algorithms

The [table algorithm guide](table-algorithms.md) owns iterative resumable
sorting, real capacity hints and 24 focused cases. Runtime exports add table.sort
and table.create. The full upstream sort.lua and final platform gates remain
pending; its collector/OS/test-adapter dependencies are separate work.

## M3 output and environment ownership

Ada sessions provide explicit Captured/Process_Streams delivery policies.
The CLI and C-created states select immediate native stdout; embedding defaults
and Reset retain capture. Seventeen focused AUnit cases and nine raw-byte
consumer processes cover quotas, callbacks, failures, switching, reset and
version/output ordering. The latest local focused suite passes 1,038 cases;
full-pipeline and platform evidence remain owned by status/session records.

Four environment cases cover actual registry replacement, persistent _ENV
cells, default load and host argument publication. Eight separate userdata
inspection cases cover result counts, actual mutation, native integer indices,
validation, raw bypass and collection. Corresponding valid-domain C cases
were independently checked against both pinned configurations. These additions
do not establish complete debug/C-API or whole-suite execution parity.
