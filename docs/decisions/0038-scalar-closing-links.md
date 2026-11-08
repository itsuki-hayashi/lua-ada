# ADR 0038: Scalar closing links

Status: implemented component with focused strict validation; full delivery
acceptance and renewed whole-source bindings remain separate.

The mandatory T memory test declares a closing local from enter(0), which
warms genuine call depth and disables provider growth before returning its
already constructed closing object. A later table allocation must fail, and
the actual closer must run and lift that limit. Canonical TBC formerly called
Capture_Cell and appended a private Close_Entry. Its artificial cell allocation
failed before the declaration became marked, so the closer never ran. The
pinned native lfunc.c instead links the actual scalar slot without creating an
upvalue or an independently allocated closing record.

Canonical TBC now uses the existing context-owned Closing_Links rows reserved
transactionally with the scalar/cell arenas. The frame's historical private
C_Closing_Level field is the head for canonical and C scalar slots. It borrows
absolute indices and owns no duplicate value. Nil/false declarations return
before marking. A real closing slot must lie in its canonical window and above
the previous head. No frame/prototype vector reservation, function scan, new
binary field or eager allocation is added. Actual lexical captures still use
the existing cell allocator when a closure genuinely needs them.

The shared unwind driver interprets canonical scope depths and symbols relative
to the frame base. Explicit C_Slot_Exit retains absolute API stack levels,
including a C view borrowing a Lua frame. Before following any link, the private
Stacks.Closing_Predecessor checks its initialized owner interval and strictly
descending predecessor. An integration correction also bounds the head by
Stack_Window_Length, not merely whole-context initialized storage. Actual
C views grow their physical owner before exposing extra slots; retired owners
retain that descriptor. A child window or a changing Foreign_Top therefore
cannot substitute for this owner interval. Strict descent keeps predecessors
inside the same upper bound. Each selected head is removed before calling its
handler, matching native closing order and existing continuation/error policy.
The unwind iteration remembers that it selected a linked slot before popping
its head. A later debug/C write of nil/false cannot cancel that original mark:
the current type closer is dispatched, or the normal closing call error is
raised. This does not mark initially nil/false declarations or change the
migration packet filter. Native ordinary mutation controls verify the rule.
Return and contradictory-tail guards consider both scalar heads and migration
Close_Lists. The migration backend retains its separate list/cell semantics.

Departing canonical scopes detach their actual open upvalue cells first.
Stacks.Detach copies the latest cell value into its scalar slot and removes
only the open association. A later debug.setupvalue changes the closed cell,
while debug.setlocal still changes the actual pending scalar. Native paired
controls prove the distinction: the former leaves the pending closer object
unchanged; the latter replaces it. Existing return-window and close-result
mutation paths keep their actual scalar ownership and ordering.

Stack tracing includes every pending highest closing slot independently of
compiler/debug live extents, before clearing dead gaps. The collector also
marks each unfrozen linked scalar explicitly, validating strict descent;
ordinary Shade_Value accounting charges the traversal to the shared GC budget.
Genuine abandoned execution retains its existing Closing_Stack_Prefix floor
until the selected handlers finish. It does not create a second frozen packet,
upvalue capture or callback recursion. Detached error scopes and suspended
contexts retain their actual stack owners through their existing protocols.

Three internal fixture assumptions were updated to inspect actual links and
prefix ownership rather than removed synthetic Close_Entry records. Their
root/release assertions remain. The read-only conformance memory checker follows
the same initialized chain and live interval; it never repairs heap state.
Fifteen new AUnit cases cover real refusal/recovery, cold true/nil/false entry,
independent cells and debugger mutation, suspension, iterator/jump scopes,
absence of artificial capture, dead-debug-extent roots and rejected cycles.

Both configurations pass 2,536 AUnit cases, all six strict component builds,
and the 26 ordinary default / 27 instrumented C consumers. Twelve public cases
match all four native/Ada T binary producer/VM roles. Unchanged errors.lua and
coroutine.lua complete in all eight roles under the actual 2-GiB ceiling with
balanced ownership; errors retains its separately documented printed depth
counts. See the dated component session for exact evidence and limits. These
checks do not renew a source-equivalence manifest or establish full upstream,
platform, native-module or final PR acceptance.
