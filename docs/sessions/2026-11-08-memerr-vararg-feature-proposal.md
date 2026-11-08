# Memory vararg allocation-count feature proposal

Date: 2026-11-08, Asia/Tokyo. Source-only author proposal; review pending.

The [author packet](../../tests/conformance/targets/remaining-upstream-compatibility/memerr-vararg-allocation.author-proposal.json)
binds the original memerr.lua, exact original 133 comparison, complete mixed
vararg block, pinned native/manual code and current Ada creation/indexing
implementation. Twenty-two source/diagnostic file hashes and eight exact byte
spans were recomputed and checked. No adapted file, source decision, output
normalization, ledger change or execution acceptance is authored here.

Only `assert(b.aloc == 3)`, nineteen bytes at original byte 3544/line 133, is a
candidate private allocation-geometry comparison. Native createvarargtab
constructs a table and resized array/hash parts. Ada owns actual member,
dense-index and hash-index buffers separately. A custom allocator can observe
calls, so the packet does not call this unobservable; the exact positive count
for one storage representation is not a public geometry promise. No public
API behavior or actual allocation failure is proposed for exclusion.

Keep the original materialized pack(...t) return, exact five arguments,
testalloc/testbytes sweeps, both GC calls, deep(4), real controls, all typed
status/message checks, increments, minimum-count output and result lifetimes.
Any source-linked counterpart must verify the actual returned table's type,
n=5 and five payloads, absent sixth element, distinct new identity, partial
construction safety, successful retry and zero selected bytes/blocks at final
shutdown. Existing public vararg tests are narrower context, not acceptance
for this full block or its failure campaign.

The adjacent original optimized sel block is mixed required behavior. Preserve
its integral-real index 2.0, result 32 and exact aloc 0 comparison byte-identical,
plus the exact zero-extra-byte behavior of testbytes. The pinned manual
explicitly describes hidden-vararg indexing conditions; this cannot become
an optimizer-stream exclusion. Initial component diagnosis found a real fresh
tail-argument copy before GETVARG. The separate owned-tail checkpoint 8950f41
repairs it and executes actual count/byte controls successfully; this imports
no passing original whole-file obligation into the proposal.

Fresh post-tail diagnostics use separate original native and exact-approved
17-byte-verifier Ada suite copies, no soft flags, 900-second timeout and 2 GiB.
Ada now observes 5 materialized allocations and still fails adapted 134/original 133
against native 3. The later optimized block is not reached by that whole-file
run. Ada finishes with zero outstanding bytes/blocks, peak 1,065,397 bytes,
10,325 managed and 18,085 provider refusals, shutdown_complete=true and no
accounting fault. Native passes its materialized 3/optimized 0/result 32 checks,
then fails original 205's temporary-name fixture with Windows Permission denied.
Both remain failing whole-file observations. Source-linked raw diagnostics
are retained in reports/hook-top/memerr-tail-13123c3a3a284eac8eec3f0debb95cd5.

Root must independently review candidate relevance and retained counterparts,
then separately review any exact derived spans/replacement bytes and source
bindings before adaptation. This packet permits neither deleting the whole
block nor waiving another count by analogy. Original parent, actual execution,
reviewed source resolution and final matrix acceptance remain distinct.
