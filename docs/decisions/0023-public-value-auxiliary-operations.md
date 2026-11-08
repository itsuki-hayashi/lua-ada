# ADR 0023: Public value and auxiliary operations

- Date: 2026-11-08, Asia/Tokyo.
- Status: scoped implementation; final target acceptance pending.
- Scope: length, concatenation, scalar output and 28 auxiliary exports.

## Context

The pinned public surface includes operations that can invoke arbitrary
metamethods, utility routines composed from that surface, and number conversion
that must work under allocator refusal. A second executor, borrowed unrooted
operands or copied interpreter implementation would violate the runtime's
ownership and continuation design. The source evidence is pinned lapi.c,
lauxlib.c and lobject.c; the reference image remains a separate test oracle.

## Decision

lua_len handles primitive strings and handler-free tables directly in Ada.
Other operands use the existing hidden length/unary continuation after the
dispatcher returns to its C-owned portal. lua_concat preserves zero/one-value
behavior and folds larger argument tails from the right through the existing
binary primitive and metamethod continuation. Operands enter explicit roots
before their original stack edges retire. A scalar copied from a departing
frame cannot retain a vector indexing borrow across completion. Both public
operations retain nonyieldable C-call semantics while allowing nested Lua/C
callbacks, protected errors and collection.

lua_numbertocstring writes a caller-owned fixed C buffer without changing the
stack or numeric type. The old Float_IO renderer had away-from-zero decimal
ties and an inaccurate subnormal readback. The implementation now reuses
string.format's exact quotient/remainder formatter and the existing exact
number parser, with the pinned fifteen/seventeen-digit roundtrip selection.
It restores the sign, native radix byte and real-looking suffix in Ada.
The [fixed scratch provider](0024-fixed-numeric-scratch.md) owns all temporary
limbs and bytes in a bounded local arena, independent of the Lua allocator.
There is one numeric grammar and one exact decimal rounding implementation.

The 28 auxiliary exports form a C ABI composition layer over real public Ada
operations. They provide checked arguments/options, metatable helpers,
userdata checks, error positions and names, system results, references,
metamethod-aware length and function registration. They own no interpreter
state, grammar, executor, collector or unmanaged input-sized allocation.
This follows the already implemented getsubtable/requiref composition boundary;
each value, table, callback, error and registry mutation executes in Ada.
Variadic error forwarding remains native C ABI work. Reference helpers use
real registry/table entries; no shadow reference registry is introduced.

Foreign option-list traversal and long byte comparisons/default-length scans
charge the original host work policy. Native POSIX configuration defines are
shared by the runtime and its C consumers so process-result decoding matches
the separately built native baseline; DLL export defines stay runtime-only.

## Alternatives and verification

A C reference library cannot supply missing exports. Temporary Lua execution
by recursive interpreter calls would split roots and permit nonlocal transfer
across Ada. Default-heap big integers would evade ownership, and approximate
floating I/O changes observable decimal text. These alternatives are rejected.

Seven public C value cases exercise primitives, handler operand/order/error
behavior, actual C caller inspection, yield barriers, unchanged output for
nonnumeric slots, provider refusal and 20,000 deterministic binary64 spellings.
Six separately named AUnit cases protect the observed tie, subnormal, maximum
finite and negative-zero regressions without a selected-provider request.
The auxiliary consumer has 76 separately named cases over all 28 exports,
including method/self errors, source positions, captured upvalues, references,
userdata names, errno and platform process statuses. Separate bounded-session
cases check foreign option/default scanning and recovery.

The [session](../sessions/2026-11-08-public-value-auxiliary.md) records the actual
local observations and unfinished gates. No private T exclusion follows from
these implementations or component comparisons. Public buffers, file loading,
traceback, further core operations and full public-surface acceptance remain
separate obligations in the same authorized delivery.
