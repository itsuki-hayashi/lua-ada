# Exact locals source proposal (2026-11-08)

Source-only checkpoint. Root's existing draft, SHA-256
`332c372e6c1e0a6b1660bf678141972e6c12164b0d5db46b8835469711598d85`,
is retained and revised as
[locals-dead-table-storage.equivalent.author-proposal.json](../../tests/conformance/targets/remaining-upstream-compatibility/locals-dead-table-storage.equivalent.author-proposal.json).
Root remains its original author; remaining_suite is recorded as revision
author. Exact review must be independent of both. The accepted feature-only
decision is bound separately and supplies no exact transformation authority.

Only the original 26-byte T.querytab size statement and 110-byte private query
loop are replaced. The first replacement adds a weak-value watch of the
original anonymous table key and calls the actual Ada table-storage inspector.
Both returned counts must be nonnegative integers; logical live entries must
be four. After the unchanged public deletion and full collection, another
actual inspection requires zero live entries, a cleared weak watch and
next(a)==nil. The proposal constrains no particular retained row or bucket
capacity. Existing separate live-key and same-table reuse counterparts remain
bound rather than expanding these two source patches.

The original T guard, stopped collector, exact four-entry construction,
pairs deletion, full collectgarbage call and all following insertion-refusal
sweep bytes remain untouched. Both original source anchors stay required and
pending; source_exclusions is empty. The planned complete-output SHA-256 is
`54481f4b2c760ef1f8efd747706a3e6eb02553f582e15210aaaab6ec72c448d8`.
It is computed incrementally from original slices and replacement snippets;
no reconstructed Lua program is emitted or executed for this checkpoint.

The new bounded ConformanceLocalsEquivalent module recognizes only this pinned
source, two exact original offsets/lengths/hashes, replacement hashes, output
hash and counterpart set. Its definition validator returns metadata and the
planned hash, never source bytes or approval. The existing reviewed-source
selector dispatches this single identity through a separately gated replay
path. That path requires actual nonsynthetic source-only approval and exact
narratives, then the existing full equivalent identity/span/counterpart guard.
Original and revision authors cannot approve it. Pending mappings, native or
default selections, synthetic metadata and source/runtime authority claims
fail closed. The existing disposable-output destination restrictions remain.

Twenty-two current counterpart files are bound at committed runtime base
fce313c, including actual checker/probe/tests, table/collector/owner code,
compiler/canonical/stack/frame lifetimes, manual and selector implementations.
Owner/resetCI changes are included. Their changes require new independent
exact review; earlier API or feature approvals cannot renew these bindings.

All **38** definition/rejection tests pass. They cover widened/moved/extra
patches, weakened counts/types/weakness, missing parents/counterparts, stale
source/feature/output/implementation hashes, both self-review actors, synthetic
specifications/approvals/narratives, wrong implementation/configuration and
invented evidence or authority. The pending CLI generator fails without
creating its requested output. Negative fixtures contain review metadata,
unchanged source copies and deliberately stale Ada counterparts; they never
contain an approved or generated adapted locals program. Original reference
bytes remain unchanged.

An initial check exposed a call to a private, unexported review helper. The
module now performs a small local approval-label preflight before using the
exported full equivalent guard. Its failed log is retained; final checks pass.
No Alire/GPR build or Lua conformance execution was needed for this source-only
work. Exact review, source emission, actual equivalent execution and final
source/platform acceptance remain pending.
