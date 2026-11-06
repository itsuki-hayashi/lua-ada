# Stable userdata storage

The current M3 checkpoint implements real full userdata in the shared Ada/C
runtime. This advances object ownership and selected public C exports; finalizer
scheduling, file libraries, complete allocator parity and final platform
acceptance remain separate requirements.

## Payload and identity

One managed discriminated Ada heap object contains its metadata and inline
payload. A C-convention unchecked union of native long double, long long and
address types supplies alignment. The payload is an array of those aligned
blocks; its final padding does not contribute to the logical byte size. No C
private GC header or object layout is reproduced.

C sees only the payload address. It remains stable while its userdata value is
reachable, including across managed-vector growth and collection. A zero-byte
object still owns one physical block, giving it a unique nonnull address.
Payload bytes are unspecified on construction. Generic userdata receives no
invented native destructor and no reference-interpreter storage.

Full userdata has its own Lua type category, identity equality, table-key
behavior and object metatable. Ordinary metamethod dispatch includes userdata;
raw equality remains identity-based. Distinct equality handlers follow the
pinned left/right selection rule, without requiring a shared handler.

## Lua-owned edges

Each object owns an allocator-bound vector of Lua uservalues, initially nil.
The collector traces those values and its real per-object metatable. Removing
an edge permits collection; unreachable userdata/table cycles are reclaimed.
Weak keys, weak values and dead-key cleanup recognize userdata references.

The implemented public C operations are lua_newuserdatauv, lua_touserdata,
lua_topointer, lua_rawlen, lua_getiuservalue, lua_setiuservalue, lua_getmetatable
and lua_setmetatable, in addition to ordinary type/stack operations. A valid
nil uservalue returns LUA_TNIL; an out-of-range get pushes nil but returns
LUA_TNONE. Out-of-range sets still consume the supplied value. C metatable
operations bypass the base library's __metatable protection.

Pinned lapi.c:1363 requires a uservalue count strictly below SHRT_MAX, rather
than USHRT_MAX. The default 16-bit C short therefore permits 32,766 values.
The constructor validates the count and object-size arithmetic before
requesting storage. Managed allocation refusal remains a Lua memory failure;
an arbitrary physical Ada failure is not reclassified as callback refusal.

## First-party host resources

An internal attachment may retain a metadata address and a library-level
cleanup procedure. It receives the actual allocator owner, payload address,
metadata address and a typed release reason: Collected, Lua_State_Close or
Host_Disposal. It must be idempotent, nonraising, allocation-free and unable
to call Lua. Attachments cannot be silently replaced.

Actual object reclamation calls this procedure once before freeing payload
storage. Marking a live object does not call it. The separate finalizer/lifecycle
checkpoint must select the release reason at explicit Lua close and automatic
host disposal, schedule real __gc handlers, and preserve resurrected objects.
Those paths are not established by the storage tests here.

An IO attachment may always release its own private metadata, but it must not
override ordinary Lua semantics by closing a file whose __gc handler was removed
or replaced. Additional non-Lua file cleanup is allowed only during forced host
disposal or failed construction, when callbacks are forbidden. It must inspect
the real closef state and must never close borrowed standard streams. A host
quota abort does not dispose reachable global files. IO integration is pending.

## Verification boundary

Thirteen separately named AUnit cases cover aligned/zero-size/stable payloads,
owned nil uservalues, uservalue/metatable tracing, cycles, key identity, equality
handlers, actual cleanup timing, invalid counts, size overflow and duplicate
attachments. Windows validation/static passes 964 total cases with zero failed
assertions or unexpected errors in reports/m3-userdata-aunit2.log.

Four valid public-C-API cases pass independently against pinned C Lua and the
actual Ada library: native alignment and mutable bytes, uservalue result/pop
rules, raw metatable identity/protection bypass and the last valid uservalue
slot. The Ada-linked consumer passes all 30 named cases and exits zero in
reports/m3-userdata-c-consumer1.log. Strict build evidence is
reports/m3-userdata-build6.log and m3-userdata-c-build1.log.

reports/m3-userdata-check1.log passes the retained validation/static pipeline:
964 AUnit cases, the real C/mixed/startup image checks, Ada consumer, 35 CLI
cases, ten binary CLI comparisons, eleven differential fixtures and the five
previous unchanged upstream targets. Its invalid-option subprocess deliberately
returns failure as part of the CLI contract. It adds no new whole-file pass.

The preceding cache checkpoint also reran all 26 earlier C cases successfully
before userdata promotion. Its constructor-refusal sweep and the new consumer
both measure 25 managed initialization growth points with balanced cleanup.
These are local component results, not full upstream, finalization, public C
API, allocation-category or cross-platform acceptance claims.
