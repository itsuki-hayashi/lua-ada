# Pending API941 tail, pool and owner binding review

This is a new author proposal at committed snapshot
`c10ba1cf207a0b034642ed16a099bbfd994dbcea`, including canonical-tail checkpoint
`76b8dd99ab27e6dc7a5557074b42e91c33926373`. It preserves the dated pre-pool,
pool-only and fce313c runtime proposals and every existing review. The
[JSON packet](api941-tail-owner-bindings.author-proposal.json) supplies source
identities and proposed review dependencies only. It installs no authority,
constructs no complete adapted program and executes no Lua source.

The snapshot includes the committed pool, generation-plus-pool-owner correction
and checked resetCI physical release. It excludes Root's uncommitted IO work
and the forthcoming locals close/refusal Machine correction. That future drift
requires a separate dated binding/review follow-up; an eventual c10ba1c review
cannot silently extend to it.

The old exact API941 approval still binds Engine body hash 8a462ca9... and
adapter body hash 9e8f1820.... Current bodies are 4830ebe0... and 03b0099c....
The existing guard rejects the stale Engine identity before any source
reconstruction. Changing only those two hashes would omit the committed pool,
cross-context guard, result-arena and direct-tail ownership transitions.

The required counterpart union preserves the original nine paths and adds
Engine's declaration, both Foreign/Machine/Canonical declarations and bodies,
and both Stacks/Stack_Views declarations and bodies: exactly twenty files.
The stack packages define the actual scalar/cell live union and borrowed
public C view which own arguments and pending results. Each addition records
a concrete lifetime dependency. Every source is bound to its committed Git
blob and SHA-256. Fifty named implementation regions locate these ownership
paths; overloads and the Physical_Owner expression are recorded separately.

The tail change affects userdata reachability while leaving finalizer and
weak-table policy unchanged. The direct canonical Lua tail bridge moves its
outgoing argument arena into an independent selected owner before Dispatch
releases the old frame. Dispatch pins the function and arguments before
destructive retirement. Collector.Trace_Roots traces these operation pins;
Collector.Trace_Context/Stacks.Trace trace the real destination frame, scalar
slots and open cells. A local Ada vector alone is not a collector root.
Emergency collection during partial callee publication is a required boundary.

Push_Frame publishes the actual activation/window before parameter and vararg
setup, then returns the successfully created callee explicitly. After Dispatch
returns, the bridge clears duplicate argument edges and may donate only empty
physical capacity to that exact callee. It does not infer a recipient from the
current top frame. Driver.Step ends operation roots on normal and exceptional
exits before a later scheduled hook, callee or C body runs. Return_Frame clears
retired activations before caching them; cached frames are not logical roots.
Forwarded userdata must remain alive through publication, while discarded or
hook-replaced arguments must become collectible without stale request copies.

Native/metamethod/migration tails retain their separate copy/continuation
protocol. Imported canonical TAILCALL with live TBC slots still fails rather
than abandoning close handlers. Protected errors, callee-construction refusal,
typed host abort, yielding callees and actual hook mutation remain required.
Independent review must inspect their real owners and cleanup. This author
assessment is neither a proof nor a runtime pass for those paths.

Tail_Weak_Argument uses a table: it checks weak identity retirement, not
userdata finalizer ordering. The actual API941 counterpart must still create
the original thousand zero-sized userdata, call a thousand unique finalizers,
clear weak values before callbacks, retain finalizing weak keys/objects through
the first cycle, reclaim them in the second and avoid repeated callbacks.
Both original positive-growth assertions, truthful memory count, stopped
collector, two collections and restart remain. Selected-owner zero bytes and
blocks at shutdown remain mandatory. No private capacity observation waives a
public lifetime check.

All three original-coordinate API941 spans and replacement bytes remain
unchanged. The lifecycle output stays
`2838c5b9183c835b3581f829657d30451c16be1bfca952e5b8638d67e5966897`.
Original parent LUA-API-ASSERT-CALL-0195 remains required and pending, with no
lifecycle source exclusion. Incremental hashing reads original slices and
replacement snippets without constructing or writing a complete adapted source.

The composite has two additional stale edges: it still binds private18
manifest f3e8a7e0... and policy c197e57c..., while current identities are
24382604... and 4917d6bb.... Existing parser-status private18 approvals are
inputs to revalidate against current schema-v3 policy; they grant no new waiver
or changed-lifecycle approval. Renewal needs concrete current inner identities.

The proposed graph is ordered:

1. Root independently reviews all twenty counterparts and each unchanged
   API941 operation, writing a new dated tail-owner exact narrative.
2. Three new span decisions bind that narrative, exact original/replacement
   hashes and identical twenty-file counterpart sets. The reviewer is outside
   both authors. Actual nonsynthetic source-only labels carry no execution,
   runtime or coverage authority.
3. Only after Root's decision, bind the approved review and current snapshot
   in the live lifecycle mapping. Preserve all source coordinates, replacement
   bytes, invariants, output hash and required original parent.
4. Revalidate the current private18 feature/exclusion/transform graph. Bind
   its manifest, the new lifecycle manifest and current policy in the composite.
   Recompute the exact claims digest with the existing claims/hash helpers
   after those identities exist; no future digest is invented here.
5. Obtain a distinct independent composition narrative and approval. Preserve
   two components, four disjoint original-coordinate operations, sole private
   child LUA-API-REVIEWED-BLOCK-9001 and required parents 0125/0195. An outer
   approval cannot bypass stale inner source or counterpart checks.
6. After those decisions, obtain fresh reviewed-source counterpart, whole-file,
   completion, warning, allocator and final-context evidence. Rebind again if
   a required implementation source drifts first.

The union output remains
`c360ae605ad7d2e7935a38ad684a5bb0fd081e59d6d3cc397527864f75cc77d3`:
only the existing eighteen-byte private-bound empty replacement and the three
lifecycle operations. No new exclusion, eligibility rule, parent downgrade,
source execution or acceptance is proposed. Current metadata/tail Lua fixtures,
named AUnit sources, actual C hook controls and selector/review helpers are
bound as review inputs. Historical passes supply no current runtime authority.
