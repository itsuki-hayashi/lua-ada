# Fixed-buffer source binding refresh

Date: 2026-11-08, Asia/Tokyo. Source-only review; delivery continues.

The parser-status regression additions changed load_dump_contract.h, correctly
invalidating the earlier fixed-buffer feature binding. The author's two graph
proposals identify the predecessor hashes and every affected review edge.
Root independently verified all 28 original named test bodies and reconstructed
the complete old header by removing only the new helper and two dispatch calls.
Pinned fixed-buffer ownership contracts and the relevant reader tests were
reread before issuing the new feature decision.

New, separately recorded exclusion and exact-transformation decisions now bind
that committed header. The live policy still excludes only the same eighteen
private bytes from api.lua; its source/output hashes, original parent and
protected scopes remain unchanged. Original evidence remains empty. The
refreshed exact replay reconstructs output
51389bf3404ab2f13ae88a8cc3f88e7188ac0639f77b7871f4c9baf1830492bc.
All 45 focused exclusion regressions pass. No derived source was written or
executed by this review, and no original parent or runtime pass is approved.

The complete transform campaign is blocked by the separately stale memory
verifier binding to the test adapter, which now includes table inspection.
API941 and its composition also require independent implementation-binding
refresh after the hook/pool/adapter changes. The composition has not inherited
the new policy or any approval automatically. Historical review files, dated
observations and accepted scope descriptors remain intact.

The current policy SHA-256 is
4917d6bbd7a3048f60a262f2e744a596af5e870039085ce9f2aa6d6945307224.
Source selection, new actual file observations and final reconciliation remain
required after all affected source authorities are reviewed coherently.
