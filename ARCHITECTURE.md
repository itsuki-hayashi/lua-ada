# Architecture

The M1 runtime and M2a frontend are accepted. M2b extends the runtime with core
metamethods, resumable native calls, libraries, and text loading; its platform
acceptance remains in progress. Complete Lua and C compatibility remain later
gates. [Decisions](docs/decisions/README.md) record compatibility tradeoffs.

## Components and dependencies

```text
Batch CLI / Ada host
        |
  Lua.Sessions / Lua.Syntax       Future C facade
        |                               |
  Lua.Engine (private) <----------------+
     |          |
  Compiler    Machine / native continuation drivers
     |          |                   |
  Parser     values / heap      library helpers / source files
     |          |
  Lexers     roots / collector
                |
         integers / numbers / narrow platform numerics
```

The root library never depends on AUnit, CLI, or reference C sources. The C
oracle and ABI experiments are separate test artifacts. `Lua.Engine` and its
descendants are implementation units beneath a private ancestor; public clients
cannot depend on register layout or heap addresses. No serialized bytecode
compatibility is implied.

The [real-world module fixtures](tests/modules/README.md) are future consumer
compatibility inputs. They are separate from implementation/API references,
excluded from GPR source paths, and introduce no runtime dependency.

| Component                 | Responsibility                                              |
| ------------------------- | ----------------------------------------------------------- |
| Lexers / Parser           | Incremental scanning, owned resolved syntax, limits         |
| Numbers / Integers        | Exact conversion, wrapping arithmetic, comparisons          |
| Engine.Compiler           | Lower resolved syntax to private register instructions      |
| Engine.Machine            | Lua/native frames, dispatch, packets, protected errors      |
| Engine                    | Values, metatables, heap, roots, tracing, lifecycle         |
| Engine library helpers    | Strings, patterns, packing, UTF-8, bounded table/math work  |
| Engine native drivers     | Stateful iterators, Lua callbacks, text and package loading |
| Sessions / Syntax         | Small owned execution and independent checking interfaces   |
| CLI / source file helpers | Batch streams, preambles, diagnostics, process status       |

## Compilation and execution

One incremental scanner feeds an owned parser/resolver. Indexed discriminated
syntax nodes retain source order, lexical symbols, captures, and label targets.
Lua.Syntax.Check validates this representation without VM/runtime allocation.
The compiler lowers it into existing typed private instructions. Declaration
lookup happens at the source point; later shadowing cannot retarget a capture.
Nested runtime functions retain lexical environment objects. See
[ADR 0006](docs/decisions/0006-shared-frontend.md) and
[frontend compatibility](docs/frontend.md).

The independent private Lua.Opcodes package defines the pinned 32-bit canonical
format. It neither replaces the current VM operations nor promises canonical
instruction streams or serialized chunks. Execution validates a complete chunk
before returning Unsupported_Feature for valid goto/label/close constructs.

Registers contain packets, allowing calls/varargs to produce zero or many
results. Scalar consumers take the first result or nil; only final list
expressions expand, and parentheses collapse. Assignment retains evaluated
table/key operands until stores. Branch instructions implement short circuit
logic. Loop instructions separate private controls from assignable visible
variables; each iteration creates fresh capture cells.

An explicit activation stack bounds calls without mapping Lua recursion onto
Ada recursion. Tail calls replace activations. Protected calls establish VM
boundaries; errors unwind VM frames to the nearest boundary. Resource failures
leave the VM altogether so Lua cannot restart an exhausted budget.

Native activations use that same stack. A native step completes, requests a
Lua/native call, or requests another bounded step. It stores continuation phase,
arguments, captures, and pending results in its owned activation before control
returns to the VM. A library callback never recursively starts an executor.
The instruction counter covers both frame kinds and helper loops/backtracking.
Language errors unwind abandoned native phases as well as Lua frames; a new
chunk receives a fresh budget. See [ADR 0007](docs/decisions/0007-native-libraries.md).

Metamethod lookup is raw. Ordinary indexing, assignment, calls, primitive
fallbacks, and applicable library functions request handlers through the VM.
Raw library operations remain genuine bypasses. Each session owns its string
metatable; numeric-string arithmetic lives in its initial arithmetic handlers,
so user overrides remain observable. Callable chains have a separate bound
from index/newindex chains. Lua 5.5 equality selection and the absence of an
obsolete less-than fallback for less-or-equal are explicit compatibility rules.

See [runtime ownership](docs/decisions/0004-runtime-ownership.md) and
[embedding](docs/embedding.md).

## Ownership and collection

One limited controlled session owns globals, heap objects, prototype graphs,
execution stack, arguments, error value, and roots. Private discriminated
values distinguish scalars from string/table/environment/closure references.
Objects do not move. Ada finalization releases a universe but does not
substitute for tracing cycles.

An iterative stop-the-world mark/sweep collector traces globals, live frames,
register packets, environments/captures, arguments, named vararg tables, error
objects, table/type metatables, native-closure captures, native activation
arguments/results, module registries, and reachable compiled prototypes. It runs
at instruction safe points,
after temporaries have entered traced storage. Allocation itself does not
collect unrooted instruction temporaries. Dead table-key tombstones are cleared
before object reclamation. Repeated chunks can reclaim compiled code.

Tables currently use linear entries and insertion traversal. Sequence length
uses a valid contiguous-prefix border. Neither order nor C hash layout is a
compatibility promise. GC modes, barriers, finalization, weak tables, and
coroutines are later work. Coroutines will be interpreter contexts sharing a
universe, rather than Ada tasks.

## Safety and platform constraints

Strong types, bounded indexes, contracts, private representations, generics,
and a tagged output interface express actual invariants. Scalars are not forced
into an inheritance hierarchy. Required warning/style flags and ordinary Ada
runtime checks remain enabled in every profile. Explicit modular operations
implement integer wrapping. Strings remain bytes.

Numeric text conversion uses standard Ada big integers for exact binary64
rounding; formatting implements Lua's 15/17-digit general format. One isolated
host `pow` import is justified by measured rounding/domain incompatibilities
in standard Ada exponentiation (ADR 0005). No downloaded production dependency
is introduced. Packing and UTF-8 helpers use standard Ada types and explicit
byte/bit operations. Native pack widths and maximum alignment come from C
interface types, including long double; an isolated C99 probe verifies the host
layout. Virtual packsize arithmetic does not allocate. Semantic size overflow
is a Lua error; valid allocation/work quotas remain resource failures.

Text loading reuses the shared frontend and file preamble handling. A loaded
closure retains its initial environment rather than acquiring session globals
when called. Omitted and explicitly nil environments remain distinct. Module
loading uses owned loaded/preload registries and callable Lua searchers. The
public package fields initially expose those tables, but replacing a field does
not replace the registry root. The default search path is local and portable;
native loading and environment-driven initialization remain deferred.

Selective SPARK may protect suitable bounded algorithms; no whole-runtime
proof is claimed. Fuzz/proof tools are optional. AUnit and differential tests
provide current behavioral evidence.

## Future interoperability

The C facade must share the core without contaminating it with ABI layouts.
Early experiments investigate C allocation, varargs, callbacks, extra space,
startup/shutdown, and nonlocal transfer. No foreign longjmp may cross active
Ada frames. Status returns and C-only guarded checkpoints are feasibility
mechanisms, not a public Lua API.

Ada containers currently allocate outside a `lua_Alloc` callback. Full C
allocator parity needs replaceable storage and an allocation audit. Private
representations and absence of exposed handles preserve room for that work.
Binary chunks, C layouts/addresses, native modules, and LuaRocks have independent
future acceptance gates.
