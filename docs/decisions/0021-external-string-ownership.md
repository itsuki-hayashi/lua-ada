# ADR 0021: External strings and weak short-string identities

- Date: 2026-11-08, Asia/Tokyo.
- Status: implemented scoped checkpoint; local Windows/default/static verified.
- Scope: public external payloads, deallocator reentry and ordinary short strings.

## Context

Lua 5.5's `lua_pushexternalstring` always creates an external long-string
header, including lengths zero through forty. Its returned byte pointer is
the original external buffer. A nonnull `lua_Alloc` deallocator receives that
same pointer, original userdata, length plus one, and a zero new size when
the payload is released. Header-allocation failure also invokes it before
raising the memory error. A null deallocator leaves the buffer borrowed.

Ordinary short strings have universe-wide identity. External short strings
remain independent until normalization as a new table key. Replacing an
existing key does not retain the new external key. `lua_topointer` identifies
the actual string header; `lua_tolstring` borrows its payload instead.

Pinned evidence is `lapi.c` (`lua_pushexternalstring`, `lua_topointer`),
`lstring.c` (`internshrstr`, `luaS_newextlstr`, `luaS_normstr`), `ltable.c`
(`luaH_finishset`), `lgc.c` (`freeobj`, `luaC_freeallobjects`), and the public
manual's `lua_Alloc`/`lua_pushexternalstring` entries. `testes/libs/lib22.c`
retains an external string whose deallocator lives in a native module.

The public allocator contract requires freeing and returning null. Its text
does not ban Lua API reentry. An actual default C probe calls a Lua closure
from an external deallocator successfully, including during state close.
Calling that function directly from an Ada sweep would allow a foreign
nonlocal transfer across active Ada frames and a recursive executor entry.

## Decision

Each string header distinguishes selected-owner bytes from an external
payload. The original deallocator and userdata remain attached to that
header; the runtime never feeds an external pointer to its selected-owner
release operation. External payload bytes are neither copied nor charged
as managed provider storage. The actual header remains provider-owned.

Collection unregisters a dead external header and transfers that same
allocation into an intrusive pending FIFO. It performs no callback and
allocates no release record. A guarded C portal invokes the deallocator
only after an Ada scheduler step or API dispatcher has returned. An active
LIFO chain and physical-header/serial token acknowledge nested releases.
The acknowledgment restores the actual borrowed stack window and frees a
detached header exactly once. Ordinary callback Lua calls schedule explicit
boundaries on the original driver with its allocator, roots and work budget.

A returning activation retains its actual raw result packet until queued
external callbacks finish. It remains the real interrupted frame for debug
inspection; no synthetic public deallocator frame is introduced. Completed
API output records remain separate from release transport records, and
their Lua values remain on the real stack during callback collection.

Before header adoption, the live C `lua_pushexternalstring` boundary owns
failure cleanup. It invokes the original deallocator above a C checkpoint,
with the original pre-error stack extent, then raises the typed refusal.
This requires neither a new header nor a new release packet under refusal.

Physical world teardown first queues remaining external payloads while
globals, contexts and code are still live. An idle borrowed driver drains
them through the same C guard before ordinary physical release. A stopped
Lua callback cannot restart the host work quota or abandon remaining
physical cleanup. Native module handles must outlive this entire phase;
the platform loader checkpoint owns their later OS unload ordering.

Ordinary strings of at most forty bytes use a per-world weak bucket index.
Intrusive header chains avoid a second owner or immortal cache. Growth
allocates a complete replacement index before relinking any header;
refusal leaves the old chains valid for emergency collection. Actual
release unlinks the header before deallocation. Looking up an unswept
old-white string revives that same header. Existing intern hits become
temporary roots through an intrusive per-operation list, requiring no
allocation or permanent pin on a successful lookup. Index work and external
hashing consume the existing bounded work counter.

## Alternatives and consequences

Copying every external string would break buffer identity, callback timing,
module-owned allocation, and allocation-refusal behavior. A strong global
intern cache would retain unreachable payloads indefinitely. Calling C from
the sweep or recursively invoking the executor would violate the existing
typed-boundary architecture. A fabricated header pointer would not provide
actual object identity or stable C/Lua inspection.

The weak index and release queues have explicit lifetimes. They are not
roots except for in-flight operations and registered close packets. Owner
allocator callbacks retain their existing nonreentrant contract; external
deallocator pointers share the C ABI but execute through a distinct guarded
portal. A deallocator must still free its payload and return null. A callback
that raises or yields instead has not fulfilled that allocator contract;
the guard nevertheless prevents a nonlocal transfer across Ada.

The native instrumented configuration has an additional observed limit:
its `ltests.h` lock assertion rejects API reentry from a deallocator while
the native collector holds the lock. Its first thirteen ownership cases
pass; the five reentry cases are explicitly skipped in that comparison.
The default native configuration passes all eighteen cases. This is a
focused oracle limitation, not a private-T exclusion or passing reentry
evidence for the instrumented C executable. No upstream source changes.

## Verification and remaining gates

The dated [session](../sessions/2026-11-08-external-string-ownership.md)
records exact builds and output hashes. Eighteen default C/Ada consumer
cases and thirteen ownership cases paired with native T pass locally.
Eight new named AUnit cases cover weak identity/collection/revival, growth,
real C reentry work limits and physical disposal. All 1,557 local cases pass.
The complete core-image script is registered and syntax-checked; it was not
run for this component checkpoint. Integrated Ada instrumented builds,
native-module unload witnesses, full upstream execution, all platforms and
final acceptance remain pending.
