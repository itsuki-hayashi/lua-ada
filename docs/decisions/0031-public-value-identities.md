# ADR 0031: Stable public value identities and default rendering

- Date: 2026-11-08, Asia/Tokyo.
- Status: implemented component; full target acceptance remains pending.
- Scope: lua_topointer, Lua default tostring and string.format pointer output.

## Context

Default object text used collector serials while the C API exposed actual
addresses. Native modules can compare pointer text with lua_topointer, and
ordinary Lua can compare tostring with string.format. Copying a returned long
string also changes observable identity, even when its bytes are unchanged.
An Ada-only session can render a coroutine before its first C callback.

## Decision

Use one private Pointer_Of implementation for public C queries and Lua
rendering. Tables, strings and closures use their stable object identity;
userdata uses its public payload; light values and C functions use their
actual ABI identity. Threads use their actual stable C surface. Materialize
the main/selected surfaces lazily before first publishing an Ada-only thread
identity, borrowing that world's lifetime with Owns_Universe=False. Normal
context teardown owns the reserved metadata and C blocks. No second universe
or execution driver is created for a pointer conversion.

Default descriptions append to selected-owner storage. Raw string __name
uses only its prefix before NUL; scan/copy work charges the shared budget.
Primitive default text ignores __name. Existing strings and string results
from __tostring remain the actual returned value. Only numeric handler
results require conversion. Missing arguments use shared call-origin errors,
and invalid handler results retain the pinned quoted diagnostic.

Use bounded C formatting glue for actual host pointer spelling. A measured
MinGW distinction makes dynamic-star %*p differ from literal-width %20p.
The glue constructs a validated bounded literal specification (width 0..99)
and formats only a pointer. Lua's explicit null pointer format remains the
string `(null)`; raw C/default-description null spelling remains native.
This contains no interpreter logic and changes no public Ada interface.

## Verification and limitations

Native-paired Lua cases verify identity relationships inside each image,
never literal cross-process addresses. C cases compare the actual public
pointer with native snprintf for all exposed kinds and both alignments at
widths 20/99, including NULL light userdata. Do not require any private
relationship between string object identity and its byte pointer.

Separately check Ada-only rendering before a later C borrow, weak-thread
collection, bounded long-name work, short prefixes with huge NUL suffixes,
and actual refusal during the first surface allocation. Compile/schedule
before that refusal so parser setup cannot masquerade as the target failure.
Require the inner Lua pcall's memory error, healthy same-state retry and
balanced teardown. A bounded independent source review raised allocation
and active-stack concerns; focused tests cover those actual paths. The
review ran no tests and grants no source/global acceptance authority.
