# ADR 0027: Protected error closing and actual C guard ownership

Date: 2026-11-08, Asia/Tokyo. Status: scoped implementation.

## Context

Error closing inside a continuation-capable Lua `pcall` can yield. A blanket
error-unwind barrier incorrectly rejects it, and keeping an already abandoned
native `tostring` activation retains another false barrier. Merely hiding those
records from debug inspection would leave their actual depth, arguments,
return values and physical stack windows alive.

A regular C callback calling unprotected `lua_call` has a further ownership
boundary. Its C body must leave its own live C guard before outer protected
Lua cleanup runs. `lua_pcall` without K instead retains the calling body and
blocks suspension. A suspended unprotected `lua_callk` transport supplies no
error protection: its original guard has already returned, and an escaping
error must bypass K. A caught inner Lua error must preserve an unrelated outer
continuation. An unhandled coroutine error retains its failed call/local graph
and pending closers until explicit reset, rather than closing them as if a Lua
pcall had caught it.

These distinctions follow the pinned `ldo.c` routines `finishpcallk`,
`luaD_pcall`, `luaD_closeprotected` and `lua_resume`, `lfunc.c` close preparation,
and `lstate.c` thread reset. Reference trees remain unchanged.

## Decision

Recovery identifies the genuine protected floor. Abandoned private close
controllers and suspended unprotected C transports do not add protection. An
explicit coroutine-close controller retains its nonyieldable protection.
Message handlers continue to inspect the intact failing graph before retirement.

Above a protected floor, retire genuinely abandoned execution from top to
bottom. Close upvalues and freeze departing close values before reusing scalar
storage. Relinquish each native, handler, cleanup and yield-barrier charge once;
discard obsolete argument, return and temporary packets. Retain code, cells and
frozen closers until physical release. The immutable retirement marker also
removes those owners from shared Lua/C public-frame inspection. Reused records
reset the marker. Error cleanup inherits surviving real C barriers; it does not
invent an unconditional error-path barrier.

The actual scalar prefix below pending TBC slots remains rooted, as specified
by the shared closing-prefix machinery. Each error closer uses its genuine
selected slot and saved outer floor. Error preparation writes the real error
object at level+1 and places the handler call at level+2. Nested cleanup retains
an active outer closer's floor. A failed return closer abandons the old return
packet before remaining error closers collect.

Close controllers build handler/self/error in retained, frame-owned argument
storage. Invocation holders borrow the remaining self/error packet after
removing the handler. Ordinary non-tail dispatch of an already callable value
borrows its rooted input until the new activation publishes ownership. Tail
replacement and receiver-chain expansion retain their explicit owned copies,
because they can release the source or must mutate its argument sequence.
Only explicit coroutine reset needs a per-closer protected false/error packet;
other failures already recover through the genuine outer protected floor.
This avoids fresh temporary vectors and redundant protection during a
permanently refusing error path without preallocating unused packets globally.

For unprotected calls through a live regular C callback guard, copy the actual
guard's frame/serial token across the ABI request. Ownerless parser, reader and
probe guards carry zero tokens; warning/release identities cannot impersonate a
regular callback. A nearby frame alone never proves guard ownership.

The boundary owns an intrusive chain of departing scopes until that exact C
guard acknowledges the error. Protected cleanup retires execution before
detachment; an unhandled coroutine error instead keeps its actual failed
traceback windows. Collector traversal traces each retained scope's cells,
closers and code. Metadata capacity includes detached records, so restoring
their existing pointers cannot allocate. Host abort and physical teardown drain
the chain in the required lifetime order without executing Lua cleanup.

Before returning the error to C, publish a real one-value temporary C stack
view above the preserved prefix using initialized spare storage. Reusing the
old outgoing-call slot would overwrite pending locals before acknowledgement.
The pump leaves this view intact through C release portals. After exact token
validation, remove the view and adopt retained scopes without executing their
old PCs. The same narrow adoption operation is available to coordinated thread
reset after real C transfer. Normal error completion schedules recovery on the
existing driver before hooks, collection or an abandoned instruction; this
preserves the driver's root `lua_resume` failure-finalization protocol.

## Alternatives and consequences

Keeping all old activations active preserves false barriers and dead return
roots. Filtering only debug frames changes appearance without transferring
execution ownership. Running closers before C acknowledgement can yield across
a live C body. Copying retained values into a shadow vector adds allocation on
the failure path and loses their actual scalar lifetime. Resuming an old PC or
recursing into the executor violates the explicit continuation architecture.

The intrusive chain adds private ownership state that collector traversal,
frame-cache reset, host abort and physical destruction must all understand.
The error view is physical C stack storage, not a new Lua call or a fabricated
public frame. Its lifetime ends at typed acknowledgement. Unhandled coroutine
records retain inspection and ordinary-local roots until reset.

## Verification implications and limits

Use native witnesses for ordinary/protected/K-aware calls, errors before and
after suspension, caller identity, failed traceback locals and weak collection.
Retain public C error identity and stack-space preconditions in both native
configurations. Exercise allocation refusal only after the original error
object and required scope exist, so setup failure cannot be confused with
failure-transport allocation. Preserve separately named Lua/AUnit regressions
and both-producer/both-runtime campaigns.

The first implementation covers regular callback guards. Ownerless warning,
reader, writer and external-release guards remain genuine barriers. Their
broader deferred-abandonment policy requires independent native observations
and actual typed ownership tokens; regular callback tests do not certify it.
Full T-enabled upstream acceptance and the final platform/image matrix remain
the major delivery's separate evidence.
