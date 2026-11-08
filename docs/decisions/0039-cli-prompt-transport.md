# ADR 0039: CLI prompt callback transport

Status: implemented component; final component validation is recorded in the
[session handoff](../sessions/2026-11-08-cli-dynamic-prompts.md). Whole main.lua
and full-upstream acceptance remain separate.

The pinned lua.c:554-563 reads the current _PROMPT or _PROMPT2 through
lua_getglobal, uses the default only for nil, and converts a nonnil value with
luaL_tolstring. The CLI formerly emitted fixed strings. Calling a saved Lua
tostring or a generated Lua expression would also change the observable call
stack inside __index or __tostring. Native probes establish one anonymous C
caller, including the actual prompt argument during conversion and no extra
Lua activation. main.lua:371-421 exercises dynamic prompt values.

The CLI/test-only Lua.Sessions.CLI child now drives three minimal real C
callbacks: primary lookup, secondary lookup and auxiliary string conversion.
They invoke only public lua_getglobal or luaL_tolstring. They contain no
interpreter, grammar, scheduling loop, default/error policy or reference Lua
implementation. The shared CLI and nested tests compile this child and C glue;
the runtime SAL and its public embedding interface do not acquire them. Existing
session Failure and Apply_Exit declarations move to the private spec so the
child can reuse their exact result publication.

The Ada child owns one iterative Driver per lookup/conversion and the ordinary
borrowed foreign, warning and external-release pump. No VM Step spans a C
callback and no executor recurses. One budget epoch covers lookup, conversion,
the counted C-string-prefix scan and output. Current.Arguments roots the lookup
value through conversion and its returned string through output and flush.
Scalar copies avoid a vector element borrow across a fallible operation. Nil
selects the native default, empty strings remain empty, and embedded NUL stops
only emitted bytes. Handler failures are fatal raw CLI diagnostics. Typed exit
requests retain their close flag and exit code; they never execute later input.

A completed process exit through an actual C prompt caller reaches the C guard
using its existing abort transport. GDB established Exit_Complete, code 37,
No_Failure, Process_Stopped and a completed Driver immediately before the
borrowed pump overwrote it as generic host abort. The narrow Foreign correction
requires all three typed predicates: completed Driver, Exit_Complete and
Process_Stopped outcome. It restores the portal and returns without resuming or
acknowledging the invalidated C activation. Ordinary host abort keeps its old
path. The CLI then reuses Apply_Exit before any requested physical release.

Two author-created expectations required independent feature review. They do
not adapt an upstream source or exclude an original assertion:

* manual.of:9217 exposes actual parameters and temporary values through
  debug.getlocal, but does not prescribe an intermediate global-lookup layout.
  Native lapi.c:699 keeps the global table in a C TValue and the key in its Lua
  stack. The Ada public composition keeps the global table in the actual C
  stack while its helper owns the key. Both measured callbacks expose one
  anonymous C frame and one actual temporary. The focused fixture accepts the
  observed key or global table, keeps explicit _G/key and __tostring self
  identity checks, and never hides or fabricates a slot. The original exact
  key-equality failure remains dated diagnostic evidence.
* manual.of:3572 specifies lua_getglobal as 0-to-1 with error classification e;
  its allocation/error rules at 2828 permit allocation failure. Warming a
  metamethod does not promise identical private allocation counts. Actual GDB
  traces show Ada's New_Native("@get") allocates an internal native closure,
  so a new strict zero-growth metamethod expectation passed native and failed
  Ada. No scheduler cache, false builtin identity or allocator bypass was added
  to satisfy it. Reviewed public controls instead require correct result or
  actual-refused-growth ERRMEM, canonical memory text, intact prefix/marker,
  strict success and original error identity after refusal is lifted, and
  balanced physical close. The ordinary cached lookup without a metamethod
  retains its strict successful zero-growth control. Last-guaranteed-slot,
  explicit-argument and honest temporary-access assertions remain mandatory.

The first attempt to impose refusal outside the C wrapper also found an
unrelated root protected-entry packet allocation. Its failed trace is retained.
Final controls inject refusal immediately before the actual lua_getglobal in
the C body and assert it remains enabled through the protected return. This
isolates the operation rather than claiming the enclosing entry was allocation
free. ERRMEM is accepted only after an actual provider rejection, never as a
generic substitute for a language error or successful lookup.

Native instrumented os.exit(37,false) reports a failed ltests.c:2226 atexit
zero-block assertion. The fresh final raw process exits 37 with 122 stderr bytes;
it fails the expected clean exit protocol. Default native and instrumented
close=true processes exit 37 with empty stderr. Keep the failed native T
no-close cleanup diagnostic
explicit. Ada managed witnesses require zero selected blocks/bytes for both
flags. No balance result is invented for a native process that bypasses its
main-return telemetry writer. Readline, interrupts, and main.lua's native Windows
temporary-output redirection remain separate obligations.
