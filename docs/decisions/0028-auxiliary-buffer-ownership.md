# ADR 0028: Owned auxiliary buffers across the C boundary

- Date: 2026-11-08, Asia/Tokyo.
- Status: scoped implementation; complete target acceptance remains pending.
- Scope: the eight pinned public auxiliary buffer functions and their macros.

## Context

`luaL_Buffer` is a public caller-owned C structure, including fixed scratch
and macros that write it directly. A native consumer needs its actual layout
and normal stack effects. Growing bytes through raw C allocation would bypass
the Ada owner's accounting. A temporary whose only cleanup is a Lua callback
would also survive an Ada host abort that forbids running additional Lua.

Pinned lauxlib.c uses a to-be-closed userdata and transfers heap buffers to
external strings. Public buffer results, protected errors, allocation refusal
and release lifetimes remain required. Exact private userdata layout and
capacity heuristics are not a new compatibility obligation.

## Decision

Keep the public structure, fixed scratch, pointer arithmetic and ABI copies
in a narrow C facade. Ada owns each dynamic descriptor and allocation through
the selected storage owner. A real userdata holds the descriptor handle and
is registered on its actual C closing slot before dynamic allocation can
fail. Its native `__close` and `__gc` functions share an idempotent release.
The facade uses the existing C portal; no nonlocal transfer crosses an active
Ada interpreter frame.

Attach an allocation-free first-party resource cleanup to that same userdata.
Physical disposal can release any remaining handle after a host abort without
executing Lua. Normal close and successful transfer clear that handle first.
This uses the existing userdata resource mechanism, not a parallel guard list.

On publication, shrink and terminate the allocation, retain its allocator/data
pair, and clear the userdata handle before creating the external header.
Header refusal releases the transferred allocation immediately. Successful
adoption gives the descriptor and bytes to the external string; a subsequent
stack-publication failure cannot give them back to the emptied box. Its
release callback is a package-level C-convention function with a stable code
address, not a pointer into a departing Ada activation.

`Storage.Release_Using` applies ordinary owner unlinking and accounting before
calling a captured compatible provider. Payload deallocation retains the
pair captured by buffer publication even after `lua_setallocf`; ordinary
runtime storage continues using the current provider. Module handles and the
[allocator code lease](0025-native-module-lifetimes.md) retain code through
the relevant release phases.

Bounded work includes foreign scanning, copying and resizing. String policy
checks required content rather than optional growth slack; capacity is capped
when needed so an otherwise valid near-limit string can still be built.
C-compatible states retain the normal native growth behavior.

The instrumented facade compiles its buffer type with the pinned 23-byte
scratch extent through a first-party configuration header. Ordinary public
SDK headers remain unchanged. An allocation-free Ada C leaf returns the
selected initial capacity, checked against that C type's configured extent.
This prevents a private T caller's smaller stack object from being treated
as a 1,024-byte scratch array. No private C state or lock header is imported
into the runtime. SDK, private-T caller and implementation-facade header
roles remain distinct; matching a header probe alone is not runtime evidence.

## Alternatives and consequences

An unmanaged C buffer would hide input-sized bytes from the selected owner.
Copying the final buffer into a second full string would increase peak memory
and abandon the native transfer behavior. Requiring user callbacks during
forced host disposal would defeat the existing bounded-session policy.

Allocation ownership tests therefore observe the provider allocation covering
the public buffer bytes, following its identity through resize. A net drop
in all live bytes cannot prove release: caching a legitimate C activation can
cost more than the released buffer. Neither the observer nor the runtime
requires private C string or box headers.

## Verification implications

Use identical public C cases against actual Ada/default-C/instrumented-C
images. Include nested buffers, callbacks, exact error classes, every measured
growth refusal, healthy retry, immediate failure cleanup, captured providers
and final balance. Keep separately named AUnit cases for bounded scanning,
extent, physical host-abort cleanup, near-limit growth and provider ownership.
The [session](../sessions/2026-11-08-auxiliary-buffer-ownership.md) owns observed
results and outstanding matrix/review obligations. No T exclusion or global
acceptance follows from this component decision.
