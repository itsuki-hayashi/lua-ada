# ADR 0040: Observable private resource eligibility

Status: implemented source-verifier capability; no resource exclusion, actual
review approval, source transformation or runtime acceptance is installed.

[ADR 0018](0018-relevant-t-compatibility.md) permits independently reviewed
private implementation checks while preserving public behavior. Original
memerr.lua133 compares one materialized table's exact positive allocation
count with three. The selected allocator observes that count, so labelling it
module-invisible under eligibility V1 would be false. V2 permits only a pure
comparison conjunct strictly inside a retained assertion; this entire 19-byte
assertion also cannot fit its six-byte original inventory anchor. V3 remains
specific to eight private compiler structures and cannot lend resource scope.

Version 4 is therefore a separate closed registry. It contains exactly one
row: pinned memerr.lua SHA256
02CC2A754E688BDFCBF507E009D899C4D367F27CED45094B68FDF208A6912491,
offset3544/length19, original assert(b.aloc == 3). Source authors cannot append
rows through policy data. The row explicitly declares observable=true and no
public/mixed/module compatibility obligation. Its independent feature review
must explain why no positive allocation geometry is promised; public selected
provider refusal, payload, identity, collection and recovery remain mandatory.

The source rule preserves original ASSERT-CALL-0004's exact six-byte identity
as a distinct required parent. A separate unexcluded reviewed-block child binds
the actual five-argument materialization bytes at3403/length141. A reviewed
original reference must link both that public runtime child and the exact
private child. Previously passing originals cannot be reclassified. The exact
254-byte optimized named-vararg span at3604 remains protected, including its
result32/count0 assertion and call through the original byte sweep. An attempt
to exclude either retained public interval is rejected even with an older
false-visibility label. The registry pins the full source and top-level T
absence guard; it introduces no general statement/expression grammar.

A small private helper is dot-sourced into Inventory so existing byte scanning,
reviewed-file resolution, semantic-field approvals and protected-scope checks
remain authoritative. The helper requires independent current feature and
semantic-retention reviews. Feature bindings cover 26 exact primary native,
implementation/provider/checker and verifier paths. Semantic bindings cover
the four current ordinary/T Lua/Ada counterpart sources and all eight semantic
and real-refusal contracts. The original optimized workload and actual fault
controls cannot be replaced by fake counters or a T-absent pass. Source reviews
must have real integer version/offset fields, false runtime/coverage/adaptation
authorities and empty execution/extra-waiver arrays. Only direct disposable
self-tests can enable labelled synthetic input; actual target callers cannot.

V1/V2 interpretation and historical protected descriptors retain their meaning.
The V3 eight-candidate semantics are unchanged. Its source-dependency graph
must now include the imported helper, making ten required bindings. Its older
nine-source review is intentionally stale and needs a new independent review;
no actual review is rehashed automatically. Data installation remains a
separate author/reviewer operation after this verifier checkpoint.

All source decisions require an explicit actual/synthetic boolean label.
The direct public command driver and its count/owner registry-key header are
included in the source graph; changing them invalidates the feature decision.

Sixty-eight source-binding/rejection cases, 42 V3 cases (including the new helper
staleness control), 62 inventory cases, 45 legacy exclusion cases and the 35
transform/53 verifier-equivalent cases validate the bounded rules. Tests create
only labelled disposable metadata under ignored reports. No Lua execution or
whole-file pass is supplied by these checks. See the dated delivery session.
