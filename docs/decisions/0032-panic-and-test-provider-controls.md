# ADR 0032: Panic preparation and shared test-provider controls

Date: 2026-11-08, Asia/Tokyo. Status: scoped implementation.

## Context

The pinned T.checkpanic helper creates an independent Lua state using the
caller's actual allocator and catches its selected panic function with a
C-owned setjmp. Its commands may refuse allocation or install real host C
to-be-closed slots. Pinned luaD_throw resets that state before panic runs and
retains the final error status. Merely invoking the selected C pointer skipped
the close handlers and exposed the wrong observable stack and status.

The configured test launcher's allocation controls also have to affect states
which inherit its allocator. Applying T.totalmem and T.alloccount only to the
original Ada Storage.Owner let independently created states bypass refusal.
The interpreter's separate owners and public provider contracts remain useful;
the test driver needs control at their actual common provider boundary.

## Decision

A private typed Prepare_Panic operation reuses the real thread-reset driver,
reserved continuation frames, C closing links and scalar stack. Its incoming
error is the actual API top value. Unlike public thread reset, this operation
retains the final error value/class and dead-thread status for the selected
panic callback. C pumps each close callback only after Ada dispatch returns.
Panic and its test-only longjmp execute after that pump finishes; neither jump
passes over an active Ada dispatcher or executor step. A genuine main-surface
C guard receives an unhandled child error through the existing typed C route.
This implementation does not claim every VM-only main-handler transfer without
a corresponding native witness.

The test-only Conformance_Allocator wrapper owns a shared byte ceiling and
successful-growth countdown. It measures the real provider blocks inherited
by independent states, refuses before changing ownership, and still allows
shrinks and frees. Clearing the test ceiling preserves the configured host
ceiling. Ordinary production owners and unconfigured AUnit worlds retain their
existing local controls. The wrapper cannot call Lua or propagate an Ada
exception across its C-convention allocator entry.

A registry-bound genuine zero-upvalue C leaf transports a scalar count to the
test owner. The runC alloccount command temporarily roots and restores its
caller's slot 1 before directly invoking that leaf. It does not allocate a Lua
call activation while refusal is armed. Remote test modules receive only the
actual control function and scalar owner binding through public API calls;
values are not moved between independent universes.

The checkpanic C helper registers its jump context under an ordinary protected
call before installing panic. Result publication is also protected while the
child string remains alive; the child is closed before propagating a failed
parent publication. These cleanup extensions strengthen the source helper's
unguarded setup/publication without imitating private Lua state layouts.

Canonical calls and returns copy their real scalar register range directly
into the existing activation-owned packet. Reserve precedes replacement and
the window remains the source root. The former temporary register-list vector
allocated on every instruction even when the destination packet had capacity,
preventing a warmed control callback from clearing a zero-growth countdown.
Invoke actions carry scalar metadata and borrow that published packet through
synchronous callee publication; helper/return actions retain independent owned
packets where retiring the source requires them.

Public pcall removes its function from its existing argument packet instead of
making a controlled temporary before protection. Its abandoned argument/result
capacity can become the recovery packet after failure. Recovery still requires
the actual holder to own at least two slots before publishing false/error;
foreign/reset holders keep their existing pre-reserved packets. No recovery
buffer is allocated under permanent provider refusal.

An unrepresentable userdata object is rejected as the ordinary runtime error
"block too big" before a provider call. The bound uses the actual Ada object
type's fixed and payload storage. A valid request refused by the provider still
reports a memory error; no private C object layout is copied.

## Alternatives and consequences

An owner-only test limit was insufficient because a child uses another owner.
A global production allocator or an owner shared between independent states
would instead change runtime ownership and host semantics. This decision keeps
the shared controls inside the single-launcher test observer.

A direct panic jump from Ada or a recursively running close interpreter would
abandon live Ada ownership. Reusing the continuation driver preserves the
single executor, allocator, scalar roots and host budget. Public reset and
panic preparation retain their distinct status behavior.

The source manifest records the public command additions and helper changes.
The component session records actual native/Ada executions and remaining
limits. This scoped implementation neither establishes full api.lua/memerr.lua
acceptance nor excludes missing public or private-T obligations.
