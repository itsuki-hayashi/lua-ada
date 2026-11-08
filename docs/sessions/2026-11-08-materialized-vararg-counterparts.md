# Materialized vararg counterparts (2026-11-08)

The independently reviewed feature candidate concerns only original memerr.lua
133's exact positive allocation comparison assert(b.aloc == 3). It preserves
the actual five-argument materialization, public table semantics, genuine fault
sweeps/recovery and documented optimized-vararg zero-allocation behavior. This
checkpoint adds focused counterparts; it authors no eligibility, inventory,
source exclusion, transformation, output normalization or whole-file pass.

The [author packet](../../tests/conformance/targets/remaining-upstream-compatibility/memerr-vararg-counterparts.author-packet.json)
binds the unchanged original source/span, existing independent feature review,
16 current runtime/checker/provider sources and the actual counterpart sources.
Its review, coverage, adaptation and whole-runtime acceptance authorities remain
false/pending. Runtime provenance is Root87daf6c plus verified eaf451e; the new
component changes only tests, source evidence and guides.

The ordinary materialized_vararg.lua contains four T-free public bodies: exact
10/20/30/40/hello values/types and n5/absent sixth entry, leading/interior/trailing
nil counts, fresh tables with preserved argument-object aliases, and a real
escaped capture keeping then releasing its materialized table. The separate
materialized_vararg_refusal.lua explicitly requires real T and has four fault
bodies: allowance increments by one, byte increments by seven, weak partial
construction cleanup and retained-result refusal/recovery. Both collections and
deep4 run before attempts; only genuine memory errors may precede first success.
Finite loop bounds prevent a hung fixture without asserting positive geometry.
All fault AUnit cases require actual selected-owner refusal and balanced cleanup.

Two nested strict default/T test builds pass against the unchanged verified eaf
runtime using LUA_ADA_PREBUILT=true. Alire 2.1.1, GNAT 16.1.0, Ada 2022,
warning/style checks and runtime checks remain enabled. Both complete AUnit
suites pass 2,557/2,557. The ordinary one-million-step bounded fixture limit is
unchanged; no failure assertion, original limit or host policy was relaxed.
No new runtime/C compile or native-module campaign was necessary for these
test-only additions; eaf's independent six-build/C/large-source evidence remains
separately dated.

Ordinary native/Ada binary producer/VM roles pass in both default and T: eight
raw outputs match SHA256
3587FB806A2310D3AAF7D3FA29AB7D8DEE42588646B6BADCDE8E46C66ACE705C.
The mandatory T fault companion passes all four binary roles, raw stdout hash
0C62F6FA1C800188A24DDDBB627D00ECBBA6966CB302103177EB5753659FADFF.
Successful-role stderr is empty; every successful Ada role finishes with zero
outstanding bytes/blocks,
completed shutdown and no accounting fault. Each Ada fault-role run observes
812 managed and 812 provider refusals. Native-default and Ada-default launches
of that companion deliberately exit 1 with zero stdout, proving T absence never
certifies the omitted campaign. No process output was rewritten.

Actual scalar measurements are retained and copied to ignored diagnostic
sidecars: this native T launch completes at count3/252 extra bytes; Ada at
count5/5,460 extra bytes. Neither number is a positive expectation. Original
memerr reporting and original optimized result32/count0/zero-extra-byte source
remain untouched; this focused measurement does not become a whole-file pass.
Raw process/build/measurement evidence is reports/hook-top/materialized-*.

The independently reviewed private-count feature still needs its honest exact
eligibility, child/anchor and disposable-source reviews, including fresh
runtime/checker bindings after closing changes. Whole memory/file/context,
platform, final immutable-image and GitHub review/merge obligations stay open.

Changed-document UTF-8/LF/link/table checks, author-packet source identities
and git diff whitespace checks pass. The full isolated documentation fixture
blocker remains unimplemented here; no skipped check is called passing.
