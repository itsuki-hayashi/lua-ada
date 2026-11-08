# ADR 0046: CLI message handling above intact failed frames

Date: 2026-11-08

Status: implementation checkpoint in progress; runtime validation pending.

## Context and native evidence

Pinned `references/lua/lua.c` separates loading, script argument preparation,
`docall`, `msghandler`, `report` and REPL `l_print`. A CLI message handler must
execute inside the protected error path while the original frames still exist.
Formatting a stored failure after the driver has discarded those frames cannot
preserve traceback, callback ancestry, error identity or mutable C temporaries.

Fresh same-host original C observations used separately copied default and
instrumented executables and their matching DLLs. The initial 40 processes
cover primitive error objects, custom/callable/raw `__tostring`, actual frames,
mutation of handler argument one, compile/pushargs ordering, memory errors and
typed exits. A separate instrumented observation prints `HANDLER_ARMED` before
enabling permanent allocation refusal inside the actual metamethod. It then
reports canonical `not enough memory`, without traceback, with eight measured
provider refusals and zero outstanding selected bytes/blocks. The cold numeric
refusal observation alone does not prove where handler entry occurred.

The authored named fixture subsequently runs 19 ordinary and 21 instrumented
native processes. It adds real callback collection/weak ownership, yielding,
and closing after transformation. Separate REPL controls establish that a
nonstring error from `print` does not invoke `__tostring`: `l_print` publishes
`error calling 'print' ((null))`, while raw `report` uses
`(error message not a string)`.

Additional native controls establish one persistent main function across
initialization, snippets, script argument callbacks, script and REPL/prompt
callbacks. It initially owns actual integer argc and light userdata argv.
Mutating those Lua stack cells does not replace pmain's separately captured C
scalars. REPL loadline clears the actual stack before the first prompt, which
releases a weakly watched value previously stored in that prefix.

The first per-docall C transport prototype matched nineteen default native
handler/error/status cases after removing only each executable's real report
prefix. It nevertheless fails a mandatory hook control: native retains one
main across three snippets, while the prototype adds C call/return events for
each new transport. That prototype is rejected as the complete implementation.
Its failed actual captures and retained M0 argument-entry observation remain
diagnostic evidence; they are not passing CLI or target results.

These are native observations, not Ada acceptance. The instrumented native
`os.exit(37,false)` process exits 37 but reports its debug allocator's atexit
assertion; it is not a successful cleanup observation. Neither exit form emits
the launcher's finish sidecar, so no native exit balance is inferred. All
other native observations have actual PID/run/configuration-bound 2 GiB
sidecars. The ordinary primary timeout is 900 seconds; the no-close exit probe
has a separately labeled five-second secondary watchdog.

## Decision

Keep this policy in `Lua.Sessions.CLI`, a child built by CLI and test projects
only. Generic session execution and the runtime SAL do not acquire a CLI
message-handler ABI or behavior.

One actual native main continuation spans CLI initialization, actions, selected
script and REPL. It has an implemented catalogued C trampoline, rather than a
dummy function address or an inspection marker. Its driver requests typed host
work without completing the native activation or yielding a Lua coroutine.
The Ada CLI performs host policy/compilation at those requests; child calls use
that same retained driver, actual caller window and explicit protection. A
new executor is never started inside an active C or Ada interpreter body.

The caller window owns actual argc/argv slots, handler/function/argument
temporaries and pending results. Callback mutation and collection observe
those real cells. Script results and loadline's stack reset affect the actual
prefix; final return placement follows its real current top. The host control
borrow is cleared before typed physical state disposal. Only actual main entry
and completion generate its call/return hooks; cancellation does not fabricate
a successful return. Reentry and expired calls reject before reading any host
controller. Generic embedding execution retains its existing boundary.

The private Ada `Docall` phase installs the actual message handler only after
successful compilation and argument preparation. Ada owns status
classification, result retention/discard, display, cleanup and typed exit.
Prompt/global/length primitives borrow the same real native main owner and
window, preserving ancestry without adding independent query callers.

The handler's allocation-free Ada selector chooses each public API primitive.
The small C loop performs a chosen fallible operation only after that Ada
selector has returned. A user error or callback therefore cannot jump across
a live Ada policy frame. Existing guarded foreign pumps and protected recovery
retain ownership and perform all actual Lua execution; there is no recursive
executor, source shim, C interpreter or reconstructed traceback.

The policy preserves these independently observed distinctions:

- Initial string/number conversion bypasses `__tostring`.
- Raw `__tostring` lookup accepts callable values. Only an actual string result
  returns immediately, without adding traceback. Other results use primitive
  type fallback; `__name` and metatable `__index` do not replace that policy.
- Fallback reads the current real argument slot after the callback, including
  changes made through `debug.setlocal`. Its original error stays rooted while
  the callback inspects or collects it.
- Recursive handler errors use the same existing protected recovery before
  failed handler/original frames retire. Memory failure skips the handler;
  host resource stops retain their separate uncatchable classification.
- Loading and script argument lookup/length errors occur before `Docall` and
  use raw reporting. REPL `print` runs afterward, with its separate framing.
- Only the displayed C-string prefix is published. The original engine string
  and error identity are not rewritten to truncate embedded NUL bytes.

The explicit CLI interrupt lease belongs solely to the nested protected drive
in this helper. It starts after load/pushargs and finalizes before an outer
`Apply_Exit` can free the world. Prompt lookup, compilation, argument queries,
display `print`, and generic driver starts do not implicitly arm it. Signal
implementation and platform evidence are tracked separately in ADR 0045.

## Validation and boundaries

Focused AUnit cases and native-paired CLI processes must verify the policies
above, actual frame/local mutation, selected-owner cleanup, refusal/retry,
typed exit, REPL nil result tuples and ordinary embedding behavior. Builds
retain the repository's strict flags and checks. Initial/failing observations
remain dated evidence; source review and runtime execution are separate gates.

This decision does not claim complete `main.lua`, a true terminal observation,
private C temporary layout equivalence, Unix signal acceptance, private memory
allocation-count identity, or final immutable target/PR acceptance. The existing
`-l` source thunk's extra Lua frame is a separately documented CLI obligation.
