# Library argument diagnostic checkpoint

Date: 2026-11-08, Asia/Tokyo. Scope: shared argument type spelling, actual
call origins and Lua debug/IO/numeric argument failures. This is a component
of the approved remaining-suite delivery, not full acceptance.

## Implemented behavior

Engine.Diagnostic_Type shares the VM policy from `ltm.c:luaT_objtypename`:
only table/userdata raw string `__name` fields override the primitive type.
Engine.Argument_Type follows `lauxlib.c:luaL_typeerror`: any raw string
`__name` takes priority, then light userdata gets its special spelling.
Absence is explicit and remains distinct from nil. Both render the C prefix
without first copying all bytes after an embedded NUL. Neither invokes Lua
or allocates a Lua object; the underlying counted values stay unchanged.

The private Diagnostics package formats argument errors using the actual
public activation. A hidden builtin phase borrows its real C owner, including
its explicit call origin and extra-argument count. A borrowed inspection
query preserves hook/finalizer priority, tail-call name loss, field names and
their C prefix. Unknown names search the actual table-valued registry
`_LOADED` to depth two, with charged traversal and no value/name cache.
Colon self is subtracted after extra `__call` values. Only the immediate Lua
caller adds a source prefix; stripped/unknown auxiliary locations omit it.

Numeric conversion preserves the shared parser and strict binary64/int64
boundary. A wrong type and a valid number without integer representation
receive distinct indexed diagnostics. Lua inspection uses this converter for
optional indices, retaining its existing validation order and C-int wrap.
IO handle and numeric-library checks now use the shared formatter. No
interpreter recursion, foreign transfer protocol or actual call frame was
introduced by these queries.

## Verification

Strict Windows/default/static root, nested tests and C consumers build with
GNAT 16.1.0 and all retained warning/style/runtime-check flags. Initial
redundant-with and unused-use warnings were corrected. All 1,856 local AUnit
cases pass, including thirty individually named argument cases. Native
default and instrumented C pass both new thirty-case Lua fixtures; all four
default compiler/runtime paths pass those and both retained eighty-case
operation fixtures. The direct companions compile the actual operation in
each producer rather than deferring it to a nested load.

The real public builtin C consumer retains its fifteen earlier cases and
adds four independently native-proven cases. All nineteen pass unchanged on
Ada default, native default and native T, with balanced counted storage.
Direct saved library pointers preserve the original C caller's identity,
method self, prepended callable arguments and captured C closure identity.
All seventeen retained C consumers and thirty-six retained four-way cases
pass. The separately owned native-module image fixtures were not run bare.

Unchanged db.lua again matches stdout SHA256
`61D58565C89CD99626C0A10641E6E8A14303A560258EF302FC6B9915E7724897`
with empty stderr. Full unchanged errors.lua advances past light-userdata and
FILE* checks and next fails its named tostring prefix at line 274; that
separate component remains required.

A tool-free one-turn Claude Haiku supplied-text review found no
high-confidence new regression (reported cost USD 0.01303). Its medium
source-index question was resolved against Canonical.Source_Line's zero-based
offset and the packet backend's one-based instruction index. Two multiline
native/Ada observations match exact source lines three and two. Frame.PC is
Positive, and all File_Argument calls use the first file/self operand. The
review did not execute tests and is not GitHub/final approval.

## Remaining boundaries

The fallback currently reads registry `_LOADED` raw. A separate measured
case removes that key and supplies it through registry `__index`: native
executes that callback once and names math.sin; Ada executes none and reports
`?`. This older missing callback behavior is not called passing here. Its
repair needs an actual deferred lookup/error continuation, not a recursive
executor call inside the synchronous formatter.

That retained obligation has subsequent
[registry continuation component evidence](2026-11-08-argument-registry-continuations.md).
The observations above remain the original evidence for this dated checkpoint.

Named tostring, remaining error-file behavior, actual public C concat
windows, the explicit locals.lua progress-output policy, integrated Ada T,
shared/platform matrices and immutable final acceptance remain open.
Reference sources and pins are unchanged; git diff --check is clean.
