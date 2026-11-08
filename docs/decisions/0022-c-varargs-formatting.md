# ADR 0022: Owned C varargs formatting

- Date: 2026-11-08, Asia/Tokyo.
- Status: scoped implementation; complete target acceptance pending.
- Scope: public lua_pushfstring and lua_pushvfstring exports.

## Context

C consumers pass promoted variadic arguments through their native ABI. Ada
cannot portably decode a C va_list, but formatting through temporary Lua stack
values would change the required free stack extent and expose intermediate
objects. Unmanaged input-sized buffers would bypass the selected allocator.
The pinned source is references/lua/lobject.c, lapi.c and lobject.h at the
repository's unchanged Lua revision. No reference implementation is linked.

## Decision

A C ABI adapter consumes the native va_list and dispatches borrowed counted
spans and typed scalars. One Ada-owned record contains the selected provider's
managed byte buffer. Shared numeric rendering and the existing extended UTF-8
encoder produce scalar bytes; only completion creates one actual Lua string.
No intermediate Lua value, extra execution frame or input-sized C allocation
is introduced. Pointer text uses the host's native fixed-size conversion.

A raw C checkpoint catches typed statuses after each Ada operation returns.
Every exit frees the temporary, including refusal during record construction
and configured host aborts. Both copied and caller-owned variadic lists end
before forwarding a nonlocal transfer. Scanning foreign C strings, appending
spans and processing conversions consume the original bounded work counter.
The existing bounded string limit remains enforced; neither configured limit
becomes a catchable Lua allocation error.

Scanning and copying are separate linear work: complete 4,096-byte scan blocks
are charged before continuing, and each copied span charges its full length.
This is a conservative host cost model, not a C instruction-count equivalence.

The variadic lua_pushfstring raises memory failure. Its va_list counterpart
returns NULL. Native observations of the pinned default and instrumented C
builds show that this NULL return leaves the entry stack unchanged: clearbuff
catches luaD_rawrunprotected without installing an error slot. The manual's
statement that it pushes an error message disagrees with that implementation.
The adapter follows the measured pinned implementation, records this explicit
discrepancy and retains source-linked regressions. No public assertion is
excluded. Unknown conversions are copied literally as pinned lobject.c does;
the manual still requires valid conversion specifiers from consumers.

The shared encoder accepts the pinned checked code-point range through
0x7FFFFFFF. Pinned instrumented C asserts that precondition; values beyond it
and a terminal bare percent are invalid caller input, with no portable result
claimed. The adapter stops safely at a terminal percent. Caller va_list reuse
after formatting likewise has no portable C contract; the adapter consumes a
va_copy. Managed byte extents retain the engine's existing Natural limit.
Above that representation an actual allocation refusal is reported; C's
MAX_SIZE overflow truncation at its much larger host-size boundary is not
implemented. The accepted campaign's 2 GiB provider ceiling still applies to
every complete runtime allocation. No executed witness covers that extreme
size boundary, and this is not a passing equivalence or an approved exclusion.

The actual preallocated memory error string retains LUA_ERRMEM when passed to
lua_error, including after a protected call hands that object back to C.
Ordinary equal-text strings are not classified by textual comparison.

## Alternatives and verification

An input-sized C buffer would evade provider refusal. Per-piece Lua strings
would increase stack requirements and change intermediate ownership. A second
numeric or UTF-8 formatter would risk divergence. These alternatives were
rejected in favor of the existing owned implementations and C-only ABI glue.

The public C contract runs identical source against separate Ada and pinned C
images. It compares counted binary output, integers, floats, pointers, unknown
conversions and extended UTF-8, sweeps each implementation's actual growth
sequence under persistent refusal, retries, and checks balanced closure.
It also verifies protected variadic failure and rethrowing the real memory
error object. Two separately named AUnit cases exercise real C exports from
bounded Ada sessions and verify abort recovery and complete storage release.
The dated [session](../sessions/2026-11-08-c-varargs-formatting.md) records local
results. Final-head, all-platform and full upstream evidence remain required.
