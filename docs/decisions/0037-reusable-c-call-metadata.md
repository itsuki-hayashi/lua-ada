# ADR 0037: Reusable C call metadata

Status: implemented component with focused strict validation; full delivery
acceptance remains separate.

Pinned public T memory tests warm real call depth with deep(4), disable
provider growth and enter T.testC's protected function call. C Lua returns
10 without allocating. The former Ada boundary allocated a scalar Call_Record
before its protected scheduler boundary, so refusal escaped the command.
A freelist populated only by earlier C API calls cannot satisfy that first
entry; a C-stack record cannot survive abandoned callbacks or guard ACK.

Each context now counts its actual allocated Frame capacity, including active,
cached, dedicated reset and base C owners. Returning to a cache preserves the
count; physical deallocation reduces it. Counting never constructs a C surface
for an otherwise Ada-only context. Surface construction reserves one host
entry and the current frame capacity using that world's selected owner.
Dedicated reset owners are allocated through the same frame allocator without
consuming the ordinary cache. Lazy first C exposure must preserve call depth
already warmed immediately before an allocation limit is enabled.
Every subsequent raw frame allocation reserves its corresponding metadata
before publication. Refusal rolls back the unpublished frame and capacity;
normal emergency collection/retry remains in the owning frame allocator.

A foreign Control owns intrusive all/free lists of scalar Call_Record nodes.
Records have no Lua values or hidden allocator. Checked owner identity and
per-owner generation distinguish a live pump from a reused node at the same address, including
reserved reset records. Acquire/return use constant
time links. A genuinely deeper cold API entry may grow through the selected
provider; warm depth consumes an existing record. Node construction is
transactional and charges actual shared work. Driver/context/window fields
are cleared before returning the record, retaining only physical owner links.

A live record may refer to an addressed context while the main control owns
the current scheduler chain. Its explicit pool-owner association survives
cross-context calls, frame retirement, suspension, host abort and self-close.
Only genuine C guard completion/discard returns it. Frame shrink frees unused
nodes above the current capacity; live nodes defer trimming until ACK. Physical
control disposal requires zero outstanding records and releases every unused
node before freeing its owner. All physical frame deletion, including the
test-only resetCI cache command, delegates to the same checked private engine
release so actual capacity and metadata trimming cannot diverge. No waiting
Ada frame permits a foreign jump.

The same public zero-growth witness exposed independent private return copies:
a fresh canonical Unwind_Results packet, three controlled Action copies and
fresh status wrapping. Canonical RETURN now publishes only its rooted actual
scalar range. The scheduler borrows that range through closing/hooks, reuses
retained empty packet capacity when delivery requires a packet, and owns the
result before retiring the source. The migration backend keeps its separate
packet lifetime. Discarded closer results require no delivery packet.

An ordinary C boundary reuses its empty frame argument arena for error
reserve. The shared context result arena stays reserved for nested entries;
result delivery copies into existing capacity when it fits so both owners
retain their buffers. Successful status insertion uses the retained packet. Actual scalar cells
remain the source for debug/hook mutation; stale request/result copies are removed before
callbacks can collect weak operands. These are storage/ownership changes, not
a new interpreter, callback recursion, grammar, C VM or fake success status.

An owned Lua window also prepares physical backing for its actual end plus
public Minimum_C_Stack. Preparation shares Ensure_Stack's capped 1.5 growth
rule and selected allocator, before publishing the window. Semantic bound,
public top, window length and maximum remain unchanged. Refusal can retain
extra buffer capacity, but no parallel length/top is published. A later real
C request still applies normal semantic growth and overflow checks. Actual
frame allocation likewise reserves its owning reference-vector capacity, so
cached depth cannot discover a fresh metadata-vector growth under refusal.

Primitive equality now uses the existing value comparison directly when no
handler can apply, including mixed integer/real kinds and same-object
identity. Distinct table/userdata operands retain the normal __eq continuation.
Bounded string comparisons charge their actual possible byte scan.

A successful assert returns its owned argument span without a controlled
copy, preserving nils, protection prefixes and actual return-hook mutations.
The missing/nil/false branches retain their original diagnostics. Calling its
saved C function pointer publishes into the actual caller's existing argument
span without running close callbacks or moving close markers. Real outer C
return still closes its marked arguments before its return hook. Hook events
build event/line arguments directly in the traced @hook owner's reusable
buffer, then drop duplicate argument roots after callback publication.

The implementation must retain separate evidence for pure Ada capacity,
transactional refusal, nested and repeated M=0 entry, numeric errors, actual
byte ceilings, shrink with outstanding records, self-close, host abort and
healthy recovery. Native source witnesses or this approved design alone do
not establish passing Ada execution. The [component record](../sessions/2026-11-08-c-call-metadata.md) preserves
actual validation and limitations. Full memerr.lua and aggregate upstream
acceptance remain separate gates.
