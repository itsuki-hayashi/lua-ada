# ADR 0030: C entry ownership across contexts

Date: 2026-11-08, Asia/Tokyo. Status: scoped implementation.

## Context

A C callback can create another same-world thread and use `lua_pcall` on that
thread without resuming it. The pinned public `doonnewstack` test helper uses
exactly this sequence. The existing facade selected a nested foreign boundary
whenever the world's main control already held a driver, even if the addressed
context had no C caller. The machine correctly rejected that invented caller,
causing an unprotected host abort instead of executing the real protected call.

A host quota on such an addressed context also has to reach the actual C body
that called it. Its local state surface can have no guard. Looking only at the
main thread would fail when that body runs on a coroutine; jumping over waiting
Ada or restarting an execution budget would violate the runtime boundary.

## Decision

A cross-context C call owns an ordinary C entry driver. Its scalar transport
record saves the outer driver, owned/borrowed flag, call-record head, current
context and native depth before publishing the switch. Both new metadata owners
are allocated first. The entry holder retains its genuine protected-call and
message-handler semantics; it is not a Lua resume and changes no coroutine
lifecycle. Finish/cancel restore the exact outer ownership before publishing
results. Failed result publication still belongs to the addressed API stack.

The machine's in-out-world entry overload shares its existing entry algorithm
with owned-access callers. It retains that world only until Finish/Cancel,
uses the same allocator/roots and never resets the host budget. Each machine
step returns before C executes a callback; there is no recursively active VM
step or second interpreter.

The private response adds a typed `Abort_State` field naming the actual saved
C caller surface. It is resolved from the nearest genuine scalar switch without
allocation and retained before that switch's record is released. C uses it only
for a host abort when the addressed surface has no guard, and only after Ada
dispatch has returned. A nearer live local guard keeps priority. Ordinary Lua
errors remain on their addressed state. The borrowed portal preserves the
original host failure before releasing switched ownership. New release callbacks
are not drained while an abort action is being propagated.

## Alternatives and consequences

Borrowing a nonexistent target C callback invents execution ownership. Always
using the main surface skips coroutine callers. Treating a quota as a protected
Lua error lets pcall hide the host's stop. A new budget or recursive executor
would bypass existing policy and roots. The selected design changes only scalar
driver ownership and a private checked ABI response; it creates no value copy
store or foreign continuation outside actual live C guards.

Cross-entry metadata remains an ordinary allocation and can refuse before the
switch. This decision does not claim zero-allocation arbitrary C call setup,
complete allocator parity or full public API acceptance.

## Verification

The [component record](../sessions/2026-11-08-public-api-driver.md) records
default and upstream-test strict builds and 1,896 passing AUnit cases. The new
public helper initially caused process abort; the real shared-budget regression
also reproduced an unprotected exit before typed routing was added. Three
named budget cases now preserve the instruction-limit diagnostic, escape Lua
protection, recover in the same world and free all owned blocks. Their callers
are respectively the main context, a coroutine with no main guard, and two
nested cross-entry switches. Nineteen public Lua witnesses match native T using
both its original T driver and the identical first-party C driver module.
Full reset/continuation/refusal/image/platform acceptance remains separately
tracked; this component does not exclude any public or private-T obligation.
