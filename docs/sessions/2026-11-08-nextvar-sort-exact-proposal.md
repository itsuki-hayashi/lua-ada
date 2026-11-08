# Exact table-source proposal

Date: 2026-11-08, Asia/Tokyo. Source-only author checkpoint on 5496d0e; pending
independent review. No runtime, reference, source selector or policy changes.

The [proposal and review limits](../../tests/conformance/targets/remaining-upstream-compatibility/nextvar-sort-exact-source.author-proposal.md)
describe six exact changes. The [data packet](../../tests/conformance/targets/remaining-upstream-compatibility/nextvar-sort-exact-source.author-proposal.json)
binds original bytes, affected anchors, current counterparts and proposed
replacements. It distinguishes useful actual Ada storage equivalents from a
separately pending private positive constructor-allowance exclusion. The mixed
T block is not excluded; constructor generation/warming/GC/length/values,
29 original check calls and argument evaluations, both actual churn callers,
the original 100,000-cycle workload, unused printer and Sort memory thresholds
are retained.

Both proposed source hashes and unchanged-segment proofs were calculated
in memory only. No adapted Lua source was emitted or executed, no approval or
applicability was authored, and no exclusion/registry/schema was installed.
The current closed V4 resource registry and target reviewed-source selector
do not admit these cases. Their bounded review/implementation requirements are
recorded as gaps rather than silently expanded.

Exact source inspection corrected one dated feature-packet inventory error:
the second forcerehash caller is line 299, not the following line-300 comment.
The earlier proposal remains unchanged; the new packet explicitly records the
correction and binds both true caller spans.

No Alire/GPR build or Lua execution was performed for this proposal. Validation
checks original span hashes, disjoint replacements, 29 identical mapped calls,
unchanged byte segments, source counterpart hashes and retained source
contexts. UTF-8/LF/final-newline and changed Markdown links are checked. The
full documentation checker retains the known uninitialized future Busted
rockspec link blocker; no passing full-check claim is made.
