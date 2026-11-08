# ADR 0042: Typed arguments for selected CLI scripts

Status: implemented component; independent integration review and full main.lua
acceptance remain pending. The [session](../sessions/2026-11-08-cli-typed-arguments.md)
records the actual validation and retained earlier failures.

Pinned lua.c loads the selected file before pushargs reads the current global
arg. It obtains length through luaL_len, copies integer slots raw and calls the
already loaded closure. Host argv strings are only the initial table contents.
Reusing them after -e loses numbers, booleans, object identity, holes, length
callbacks and replacement tables. A Lua shim changes public call ancestry;
implementing the argument loop in C would move interpreter policy into glue.

The existing CLI/test-only Lua.Sessions.CLI child therefore owns
Execute_Selected_Script. It is absent from the runtime SAL and public embedding
value API. The ordinary Sessions.Execute string-argument contract is unchanged.
Only explicit selected scripts, including explicit stdin, call this operation.
Initialization, snippets, implicit stdin, REPL and --check retain their rules.

Compile through the one shared Compiler and create the actual closure before
callbacks. Its initial environment must survive registry-global replacement in
__len. Current.Arguments owns that closure before the first helper drive.
Two real anonymous C callbacks call only public primitives: getglobal returns
closure/table, then luaL_len returns closure/table/integer. They contain no
argument iteration, fallback or argument policy. The original table and
callable are actual C parameters available to inspection and collector roots.
The native observations require their public identities; fixed C backing
positions are not copied or fabricated.

Ada validates table/count and raw-reads the integer entries of that same table.
Numeric/integral-real length conversion and its errors come from luaL_len.
Raw integer reads bypass table __index and retain holes/trailing nil. arg[0]
does not select a different file. Negative/overflowing C-int counts are not
mechanically translated into unsafe Ada arithmetic; bounded positive count
and stack admission precede allocation.

Two selected-owner arenas preserve the handoff invariant. Before callbacks,
reserve actual Minimum_C_Stack headroom in the context packet and a local
argument-only vector. After length, transactionally reserve final capacities
while closure/table/count remain rooted. Append every copied value to the
actual traced context packet, then fill the local vector. A weak or mutated
table is insufficient to root values already copied from it.

Keep the complete context packet through Function_Value Machine.Start. Start
ends prior temporary-root epochs, then Dispatch pins callee/arguments before
allocating/publishing the real call. The context packet remains a strong root
through each of those operations. Clear it only after successful Start, before
call hooks or script instructions execute, so stale private argument/table
roots do not persist. Do not rely on a local Value, untraced vector or expired
Operation_Roots pins. On failure cancel the driver before dropping its roots.
No new Machine entry, root field, context, executor or grammar is required.

Initialize the instruction budget once for compilation, lookup, length, copies
and execution. Meter copy/clear passes before destructive publication; the
existing result transfer retains prepared capacity when it fits. All metadata
uses the same selected allocator and normal refusal/recovery path.

The local owned arena belongs to Execute_Body. It finalizes before outer
Apply_Exit can release the world for close=true. Early typed exits from either
callback follow this same scope order; no local allocator owner survives its
world. Actual warnings and external releases use the established iterative
borrowed pump and typed C guards, with no nonlocal jump over an Ada step.

An actual M0 test exposed a pre-existing length continuation's cold single-value
copy. The [separate correction](../sessions/2026-11-08-length-result-arena.md)
normalizes/forwards its already owned packet; generic scalar-return behavior is
unchanged. This feature does not waive allocation controls or adapt upstream
assertions. Remaining CLI facilities keep their own acceptance requirements.
