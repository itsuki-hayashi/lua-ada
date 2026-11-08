# ADR 0035: Managed immutable diagnostic text

Status: scoped component and engine failure-field migration implemented;
complete allocation audit and final acceptance pending.

Runtime failure state still contains unbounded Ada strings. Replacing them
with ordinary mutable buffers alone would make controlled assignment allocate
while saving or propagating an error, precisely when allocation may be refused.
The representation must also support an allocation-free emergency message.

The private Lua.Diagnostic_Text component stores up to 96 counted bytes inline.
Longer immutable payloads use one typed block in the selected owner's existing
subpool. Controlled copies increment its checked reference count; the final
handle frees that actual block through the same root pool. Replacement builds
and fills a complete new payload before releasing the old one. Refusal leaves
the old diagnostic intact. Replacing it with a short emergency value performs
no growth and releases a former long block.

Query retains an allocation-free immutable snapshot for the whole callback.
That protects both inline and allocated bytes when a callback clears, replaces
or raises through the original handle. The owner must outlive every handle and
borrow; all handles sharing a payload follow its serialization contract. This
component adds no public Ada embedding API, C ABI or external dependency.
Its private spec is listed in the existing SAL interface closure for child
AUnit access without changing Ada privacy.

The 96-byte threshold and block layout are private implementation choices, not
allocation-count or native-layout compatibility promises. Construction/copying
of input-sized bytes must still be charged by the runtime consumer; the small
inline copy and shared-handle bookkeeping are bounded. To_String is a host
materialization convenience; VM algorithms must use Query for borrowed views.
Lua error values that already own their original string should remain rooted
and propagated as values instead of requiring a duplicate diagnostic copy.

Fourteen focused AUnit cases exercise selected ownership, permanent refusal,
atomic replacement, allocation-free shared/self assignment, inline release,
query alias mutation and exceptional cleanup, and binary bytes across 96/97.
A bounded supplied-source Haiku review found no high-confidence defect. Its
pool-identity question is answered by Storage.Pool's existing subpool owner,
and its synchronization caveat is explicit in the spec. Positive reference
count overflow is checked; no billion-handle test or proof claim is made.

Context.Failure_Text now uses this representation. Captured Lua errors keep
their original value and clear duplicate text; pending diagnostics publish
through a borrowed view. Saved compiler error values receive an actual traced
activation capture until restoration. Host reports materialize their public
result explicitly. See the [runtime migration record](../sessions/2026-11-08-runtime-failure-storage.md).
This closes that storage path, while the complete allocation/temporary audit
and final-head matrix evidence remain open.

Auxiliary IO errors and argument errors share the private immediate-public-
caller location formatter. It borrows actual function source/line metadata,
adds no prefix for a C caller or missing stripped line, and builds charged
text in selected-owned storage. The [IO location record](../sessions/2026-11-08-io-error-locations.md)
describes the focused boundary and its remaining whole-CLI acceptance limit.
