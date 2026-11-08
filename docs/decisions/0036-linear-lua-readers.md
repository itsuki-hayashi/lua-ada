# ADR 0036: Linear Lua reader loading

Date: 2026-11-08, Asia/Tokyo. Status: scoped implementation.

## Context

Pinned Lua revision `7579fc9d7ed90240487251dfb69168f8e64e9294` invokes
Lua load readers from lbaselib.c:generic_reader inside the actual protected
parser. The lexer determines when another piece is needed. A definitive
syntax or semantic error can therefore prevent later callbacks, while an
unfinished token still requires its real following byte. Binary prototypes
are self-delimiting and need no extra EOF callback. Mode rejection precedes
further parsing. Reader errors inherit the surrounding message handler.

The previous Ada base.load continuation drained every nonempty reader result
before starting the shared parser. A later callback error could replace an
already definitive semantic error. Treating each prefix as a complete source
would manufacture EOF inside names, numbers, strings, comments or delimiters.

An experimental pending-input view correctly distinguished unavailable bytes
from genuine EOF, but reparsing each prefix was quadratic. A one-byte
assignment stream took 22.492 seconds for 8,009 source bytes and 99.375
seconds for 16,009 bytes, versus approximately 8 and 9 milliseconds for
native Lua. That experimental helper and its input API extension were
removed from production; their diagnostic measurements remain local evidence.

## Decision

Have the actual base.load activation request a C-owned reader portal only
after Native_Step returns. Preserve its callee, public name, native charge,
hook state and actual argument cells. A saved builtin called directly from C
keeps its existing hidden phase and original public C caller. The neutral
Publish_Builtin_Window transition moves that phase's current scalar prefix
to its real owner, retires the duplicate window, and borrows the owner's
cells through the existing allocation-free stack-view lease. Its failure-only
Prepare_Argument_Diagnostic wrapper retains its original no-resume contract.

The C portal invokes the existing public lua_load with an ABI reader which
calls the current actual reader argument through lua_call. Ada retains all
name/mode selection, number conversion, result-type checking, status policy,
environment selection and result publication. Existing selected-owned input,
parser, canonical lowerer and binary decoder consume each stream once. The
reference interpreter remains a separate oracle and is never linked.

Every reader callback executes beneath the existing C_Read_Guarded checkpoint
immediately above the waiting Ada frontend. Errors, rejected yields, host
aborts and self-close transfers return typed status before that frontend
releases its partial storage. They never jump through an Ada parser or VM
step. Reentrant Lua work uses the same explicit driver and instruction budget;
there is no recursive executor, worker task, second grammar or saved Ada stack.

The activation's existing managed byte buffer retains NUL-terminated option
bytes through all callbacks. Numeric options also replace the actual argument
cells before reader entry. Successful load completion reads the current
argument-four environment cell. Protected failure publishes nil plus the exact
error object on real C slots. The common callback completion owns results
before restoring a borrowed view, and the common return-hook continuation
preserves subsequent edits to those actual result slots. Cache reuse resets
all three portal scalar fields. Existing error/abort/reset cleanup retires
their actual guard and restores any lease exactly once.

## Alternatives and consequences

Eager draining loses reader demand and error precedence. Prefix reparsing
with honest pending input remains too expensive even without copying its
source. A second grammar for selected early errors would violate shared
frontend ownership. A task or stackful executor would introduce a second
execution/transfer model. Reusing the already guarded public loader keeps
one frontend, codec, allocator, driver and callback boundary.

The canonical runtime probe is an Ada host too. Its manual driver loop now
services the same foreign, warning and external-release requests as production
hosts, after each Step returns. Exceptional exits cancel an unfinished borrow
before physical cleanup. Producer/VM and source/bytecode checks remain intact.

## Verification boundary

The companion [session](../sessions/2026-11-08-linear-lua-readers.md) records
native-paired token boundaries, direct saved-C builtin ownership, mutable
argument/environment cells, weak-root retirement, return hooks, typed host
quotas, selected-storage release and measured large one-byte streams in both
configurations. These are component results. Full unchanged-source/T,
platform and immutable final-head acceptance remain separate obligations.
