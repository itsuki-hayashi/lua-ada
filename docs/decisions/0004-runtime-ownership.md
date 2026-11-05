# ADR 0004: M1 Runtime Ownership and Execution

Date: 2026-11-05. Status: accepted for the scoped M1 runtime.

## Constraints and evidence

ABI probes establish reference allocator failure/free behavior, C varargs,
extra-space layout, explicit Ada lifecycle, callback reentry, and C-only jump
checkpoints. A reference yield probe returns through Ada before suspending C.
These are feasibility observations, not a drop-in C API implementation.

## Runtime decision

- One limited controlled Ada session owns a world and all its allocations.
  Closing/finalization releases the whole universe; copying is unavailable.
- Lua scalars are private discriminated values. Strings, tables, environments,
  and closures refer to nonmoving owned objects with explicit tracing edges.
- Lexical declarations get unique cell symbols during compilation. Captures
  retain environments, so later shadowing cannot change an earlier binding.
- Private typed register instructions carry result packets. Only final list
  expressions expand; scalar consumers and parentheses collapse packets.
- Explicit VM frames support bounded calls, tail-frame replacement, and pcall
  boundaries without consuming the Ada call stack for Lua recursion.
- A stop-the-world iterative mark/sweep collector runs at instruction safe
  points. Globals, frames, packets, captures, vararg tables, and error objects
  are roots. Allocation itself never collects unrooted instruction temporaries.
- Compiler prototypes are traced alongside closures and collected when dead,
  preventing repeated execution from retaining every compiled source forever.

## C boundary and future work

Interpreter errors currently use an internal Ada exception caught by VM/session
boundaries. A future C facade must return statuses from Ada before invoking C
nonlocal transfer, and guard each foreign callback above its Ada caller.
No C longjmp across active Ada frames is approved. Yield continuations and
complete API integration remain later C-compatibility tasks.

The current standard Ada containers/strings allocate outside a Lua allocator
callback. Full C allocator parity therefore needs an audit and replaceable
allocation/storage abstractions, not merely replacing the central object new.
No internal pointer is exposed publicly, and the private instruction format is
not serialized, leaving those adaptations possible without an embedding ABI.

## Consequences and verification

Independent sessions, cyclic tables/closures, live captures, bounded allocation,
tail recursion with a low frame limit, and recovery have focused AUnit cases.
Object counts describe owned allocations, not process memory. Insertion-order
table traversal and a contiguous-prefix length border are implementation choices
within Lua's unspecified order/border behavior; they are not promises to reproduce
C hash layout. GC modes, finalizers, weak tables, and C allocator parity remain
outside M1 rather than being inferred from the basic tracer.
