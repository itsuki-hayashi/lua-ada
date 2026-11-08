# ADR 0019: Demand-driven shared frontend input

- Date: 2026-11-07, Asia/Tokyo.
- Status: scoped implementation; local default validation completed.
- Scope: source acquisition and guarded public C reader callbacks.

## Context

The first public reader/writer checkpoint buffers text through EOF and retries
binary decoding on successively longer prefixes. Buffering can invoke a reader
after native Lua has already found an error, changing side effects and which
error wins. Repeated prefix decoding can do quadratic work. An EOF-observation
flag cannot reliably repair that boundary: lexical lookahead itself can demand
another byte before delivering an otherwise invalid token.

The existing lexer, resolving parser and checked binary decoder remain the
single production frontend. Their partial arenas and canonical model use the
universe's selected allocator. Public C readers can invoke the API, execute
nested Lua calls, collect, refuse allocations or raise arbitrary errors. A
foreign nonlocal jump must never cross their waiting Ada activations.

## Decision

`Lua.Inputs` supplies a private borrowed whole-buffer view or an owned growing
input. A missing requested byte calls an optional refill. Each returned piece
is copied through the selected managed allocator before another refill can
invalidate it. Whole-buffer entrypoints continue to borrow their original
storage synchronously. The scanner, parser and decoder each consume one input
through the same existing algorithms; there is no grammar copy or prefix
reparse. Binary completion does not request a redundant EOF read.

The public `Lua.Syntax.Check_Result` adds an `Incomplete_Input` boolean for
interactive hosts. Only explicit grammar expectations at the actual EOF token
and unfinished quoted/long lexical tokens at actual EOF set it. Malformed
numerals/escapes, static-semantic/resolver errors, resource failures and success
leave it false. This is a parser/scanner fact, not a diagnostic-text heuristic
or exposure of internal syntax/runtime handles.

The lexer preserves pinned `llex`'s current-byte lookahead: consuming a token's
last punctuation or closing quote can request the next current byte before the
parser receives that token. Escape diagnostics preserve their corresponding
save/advance demand. Fixed-buffer binary mode preserves the pinned decoder's
contiguous code, long-string and debug-array piece requirements, while Ada
continues to own decoded code and strings.

The refill adapter invokes a small C shim with a live C-owned checkpoint above
the suspended Ada frontend. Reader errors, attempted yields and private host
aborts jump only to that shim and return typed status/handled metadata to Ada.
The frontend can then finalize its partial storage before the outer C API
boundary returns a Lua error or forwards a host abort. This narrow guarded
foreign-reader call extends ADR 0013's borrowed-boundary rule; it does not
restore an abandoned C stack or recursively call an Ada executor/parser.

Nested public API execution uses the actual existing universe, context,
allocator, registry and driver. Refill calls and copied input bytes are charged
to its existing bounded work budget. Protected Lua calls cannot catch a
configured host quota. At refill time the frontend owns raw managed syntax/model
storage and has not adopted runtime wrappers or retained unrooted Lua values.
After a reentrant callback, its empty transient operation lease is renewed
without restarting execution or counters; callback-discarded weak temporaries
are not retained by an old allocation epoch.

## Alternatives and consequences

Gathering text to EOF changes observable reader behavior. Repeated parsing or
decoding of prefixes wastes work and allocations. Calling a reader without a C
checkpoint would expose active Ada frames to `longjmp`. A second parser or an
independent execution session would split grammar, ownership and budget rules.
These alternatives are rejected.

Owned input retains bytes already supplied, so source storage remains linear in
the supplied extent rather than a constant-space stream. Geometric growth and
one frontend pass avoid quadratic reconstruction. Refusal retries reuse the
same still-valid foreign piece after emergency collection. Input ceilings and
checked representation limits stay explicit host policy rather than hidden
product defaults. Native fixed-buffer loading may use less memory than copied
Ada ownership; this decision makes no C-private allocation-layout claim.

## Verification

The implementation adds public contract cases for early syntax versus reader
side effects, native punctuation prefetch, split keywords/numerals/escapes/long
delimiters, recursive API loading/execution/collection, every binary split,
fixed piece constraints and retained refusal/recovery behavior. Separate Ada
host cases exercise acquisition work quotas, nested execution quotas and
catchable arbitrary reader errors. Seventeen separately named checking cases
exercise the structured incomplete-input boundary, including malformed tokens,
unresolved labels and completed input.

The local Windows/default/validation/static strict runtime, C consumer and
nested test builds pass. All 1,412 AUnit cases pass with zero assertion failures
or unexpected errors, including the twenty new cases described above. All
twenty-eight standalone public reader/writer cases and the complete retained
C consumer pass. Identical standalone source passes the pinned native default
and instrumented C builds, with byte-identical contract output.

An execution-only replay against the existing pinned C frontend/opcode oracles
passes the 10,000 seeded lexer inputs, 2,000 grammar programs, 2,000 mutations,
allocation-pressure diagnostic and all thirty-four source lex/parse pairs,
plus opcode records. Those source checks are syntax evidence, not Lua-file
runtime acceptance. The unchanged canonical campaign passes thirty-six
four-way compiler/runtime interoperability cases. Initial strict compilation
rejected a missing prior local Peek specification; that cause was repaired
without weakening the warning/style policy before these passing runs.

Full static/shared/platform/configuration acceptance remains a separate final
delivery gate. This ADR does not establish complete upstream conformance,
public auxiliary APIs, native-module loading or CLI acceptance.
The dated [component session](../sessions/2026-11-07-demand-driven-input.md)
records commands, tool versions, repaired validation causes and integration
limits.
