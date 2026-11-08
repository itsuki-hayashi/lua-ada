# ADR 0034: Borrowed C stack views

Date: 2026-11-08, Asia/Tokyo. Status: scoped implementation.

## Context

Pinned ldo.c luaD_hook invokes a C hook while borrowing the interrupted
CallInfo. It saves the prior top, exposes the full Lua reservation, ensures
LUA_MINSTACK headroom, and restores that reservation after the callback.
ldebug.c luaG_findlocal observes those same actual cells. A direct line/count
hook yield returns normally to luaD_hook before the executor suspends.

The Ada scheduler already owns a real C hook transport and a C-only guard.
Its event/line packet occupied a different scalar window. Removing that
packet exposed an empty stack to the user hook. Warning and external
payload-release callbacks also borrowed Canonical_Top, which describes open
instruction results rather than the current live Lua range. Public raw stack
access and debug local access consequently disagreed.

## Decision

Keep the actual guard owner separate from the physical scalar owner. The
existing Foreign_Activation retains callback identity, continuation fields,
and its real typed error/yield acknowledgement. An optional Foreign_View names
the actual borrowed stack window. Ordinary C entries clear that override and
restore it after their own guard returns.

Use one embedded Stack_View_Lease for hooks, warnings, and external releases.
It records scalar indices and real frame pointers, never a copied stack or a
second execution state. A custom C hook retires only its consumed transport
reservation before borrowing interrupted cells. Lua hook views expose the
original reservation; warning/release views expose the actual live range.
Writes use the existing scalar/cell arena, collector roots, allocator, and
execution budget. Nested calls open above the current borrowed top.

Reserve minimum C headroom and charge native packet transitions before the
transport retires. Clearing copied native argument/capture packets before
callback collection prevents stale weak roots. On a normal hook return,
retained capacities reconstruct only execution packets which the interrupted
Ada native body still needs, using edited scalar/capture cells. Failure
acknowledgement abandons those packets. Restoration performs no allocation,
restores only its own lease, and leaves real child error or closing scopes
to their existing owner and iterative driver.

The C shim only selects enter/leave operations and supplies its actual guard
token. All nonlocal transfer occurs after Ada dispatch returns. This adds no
recursive executor calls, reference-interpreter linkage, fake callback
pointers, or parallel closing implementation.

## Evidence boundary

Return hooks follow the same real-cell ownership rule. Keep the completed
callee's physical source window until the hook returns, reserve delivery
packet capacity beforehand, and remove copied input/result roots before
callback collection. The explicit @return.hook continuation reconstructs the
packet from Transfer_First/Transfer_Count after actual local writes. Internal
protection contributes its status prefix once; public pcall/xpcall already
expose that prefix in their editable real return range. External-release
continuations retain whether their range is already a complete packet.
The migration packet backend retains its previous separate packet lifetime;
it has no canonical scalar return window to borrow.

A retained Lua frame waiting for a native tail callee must publish the
callee's raw results back into its original canonical CALL A range before
return-hook inspection. Its delivery packet stays rooted until reservation
succeeds; then real scalar writes and transfer metadata describe that same
range. Reading a stale pre-call window is not a valid substitute for this
publication, even if a later hook happens to replace the result.

The same source ownership extends through Return_Exit closing. Publish the
exact scalar range/count before scheduling closers; retain reconstruction
capacity without another value snapshot. Close handlers may then edit those
cells, collect discarded weak values, or suspend in a yieldable context.
Only successful completion rereads the actual range. A close error follows
the existing error-unwind path and abandons outgoing values. Generalize the
existing native publication bit to Return_Window_Published so callback,
canonical and native-tail returns preserve actual counts across closing,
return hooks and external-release deferral.

Coroutine handoff reserves the actual resumer's result area before copying
successful/yielded values. Follow pinned lcorolib.c auxresume: a missing
result area returns false and "too many results to resume", rather than
escaping coroutine.resume as stack overflow. Keep a yielded child suspended
and resumable after discarding that delivery. A wrapper raises the portal
message without closing a healthy child; actual child failure metadata still
selects its existing close/error path. Write directly to the recipient's
owned packet and charge actual pin/barrier/copy or discard passes. Host
instruction/physical failures retain their typed abort behavior.

Nine separately named public C regressions cover real scalar edits, hook
removal/nested calls, protected and unprotected errors, blocked nested yield,
direct hook yield, weak argument/upvalue release, and allocator reentry into
a Lua CI while concatenation handlers inspect and edit pending operands.
The first eight pass both pinned native configurations. The release-reentry
case passes native default; native USER_H aborts its private plock assertion
in ldebug.c before that callback can complete. Its narrower oracle invocation
uses an explicit --without-release-reentry option and is not evidence that
the omitted case passed. Both Ada configurations retain the release case.

Strict Ada build/runtime results belong in the component session after
execution. The initial view component and subsequent return-window component
retain separate evidence. Exact optimizer temporary counts/content, remaining
T commands, and full upstream acceptance remain separate obligations. This
decision grants no source exclusion.
