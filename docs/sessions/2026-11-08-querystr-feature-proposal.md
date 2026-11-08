# API string-table feature proposal (2026-11-08)

Source review only. The author packet is
[api-string-table-geometry.author-proposal.json](../../tests/conformance/targets/remaining-upstream-compatibility/api-string-table-geometry.author-proposal.json).
It binds the original API source, generated-template parent, three candidate
private spans, pinned native/manual implementations and actual Ada weak-index
code. All fifty-two file/span hashes were checked against their current bytes.
No production, scope, ledger, adapted source or installed exclusion changed.
The independent feature review remains pending.

Original lines1328,1329 and1343 inspect the C string table's bucket capacity
and use count. Native querystr directly reads G(L)->strt. Native collection
can rehash/shrink that table; a refused shrink restores its former geometry.
Ada's weak index allocates replacement storage before relinking and currently
does not shrink during collection. Copying native size statistics would impose
an unneeded representation contract, while merely observing unchanged Ada
capacity would establish little safety.

The mixed parent remains required. Preserve the minimal selected libraries,
string==nil, the thousand actual dynamic short strings and table roots,
foo(180), both stack observations, a=nil, the actual allocator-disabled full
collection, remote 'ok' and explicit child closure. Stack-capacity relevance
is outside this string-only proposal. Existing querystr omission or invented
statistics cannot become passing execution evidence.

The proposed Ada counterparts retain reachable string/key payloads and actual
identities, detach unreachable intern headers, revive unswept strings safely,
protect reused headers during a live operation, and survive a real refused
index replacement followed by retry. Selected-owner shutdown must leave zero
bytes and blocks. Existing named string tests cover narrower invariants; they
do not certify this complete source block or its allocation-disabled phase.
The manual says strings are not removed from Lua weak tables, so a weak table
holding strings cannot supply the required intern-index reclamation oracle.

Native debug_realloc refuses any unequal nonzero resize under alloccount(0),
including shrink. Ada's current test provider refuses growth. This packet
preserves that difference and does not approve it as a general allocator
equivalent. Actual attempted growth/refusal and old-chain/root preservation
need separate focused evidence; zero-count GC alone does not prove that the
native shrink-failure path ran in Ada.

The author inspected Root's existing unchanged native T API observation:
exit0, empty stderr, 203 stdout bytes and zero outstanding provider bytes and
blocks. That baseline is source-bound diagnostic context, not a fresh author
execution, Ada counterpart approval or coverage certificate. The later c360
Ada file replay remains diagnostic only while API941 implementation bindings
are stale; nothing in this proposal refreshes those approvals.

Root must independently review feature relevance and the exact retained
requirements. Any later counterpart, exact replacement bytes, private child
classification, transformation/schema change and final whole-source evidence
requires its own review. No Alire/GPR build was requested or run for this
source-only packet; no new runtime behavior or conformance pass is claimed.
