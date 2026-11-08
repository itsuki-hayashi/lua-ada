# Approved Windows-path attrib replay

Date: 2026-11-08, Asia/Tokyo. Dated component diagnostics, not final acceptance.

The original attrib.lua previously failed the same separator expectation in
native/Ada default/T. The independent source-only Windows decision f15a06e
permits exactly ten expected-path literal changes to the original D helper.
The [new observation](../../tests/conformance/targets/remaining-upstream-compatibility/attrib-approved-paths.author-observation.json)
records execution of those approved bytes, SHA256
a56021013a850cf69feb421e5385ac0e5f8e6b5841d107c9c7a55ed5ea172dca.
No source assertion, T guard, operation, submodule revision or exclusion changed.

Four fresh full fixture trees used frozen native default/T images and the two
strictly verified 8daf1a7 Ada measured images. They do not inherit final-current-
head authority. The real module sources were separately compiled and PE-audited
against each actual selected DLL or exported static host. The module fallback
message is absent, so the real C-library branch runs. Providers are limited to
2 GiB; primary processes have a 900-second deadline. No _soft or no_port source
mode is enabled. The CLI uses -E to isolate environment initialization.

The entry preserves all.lua:148-156's unstripped loadfile/dump/load and tail call.
It captures the actual result once, requires exactly one value equal to 27, then
prints a receipt. The first campaign's receipt used io.write and failed after
three bodies had already returned correctly: attrib.lua deliberately closes
the default output file at lines 101-105. That harness failure is retained.
Fresh fixture trees reran a corrected print/C-stdout receipt, as all.lua reports.

The corrected native default/T and Ada default processes exit 0, have empty
stderr and exactly matching stdout SHA256
b5aaea413ec8e08b5611087519dcb1b8aa25f718655fd885f52843f009631cd7.
All observe the single-result-27 receipt and no native-module fallback. Ada T
instead stops at original line 343 because T.hash is absent. It has no receipt
and supplies no completion credit. All four raw processes report zero selected
provider blocks/bytes; both Ada shutdowns complete without accounting fault.
Only the approved attrib.lua differs from original copied fixture hashes.
Native-image unload timing is not independently monitored by this raw-file run.

The missing facility has exactly two direct uses in the entire pinned suite,
both in the one line 343 equality: T.hash(str) and T.hash(str1). The mixed
external-string block 335-350 also checks actual callback-produced strings at
lengths 0/10/39/40/41/1000, byte equality, real table-key reads/writes, next key
identity and duplicate external strings. Ada T stops before those post343
assertions; they remain mandatory.

Pinned ltests.c:1078-1095 has a strict string mode returning signed C-int cached
string hash, and a second table argument selecting a physical main-position
index. There is no callsite of that second mode and no asserted numeric hash
literal. Root's proposed test-only Ada invariant reads the real 64-bit
Object.String_Hash consumed by Tables.Hash and preserves all bits through signed
integer rendering. The remaining-suite reviewer independently accepts that
feature/representation choice with strict type/cardinality, actual cached-field
and high-bit tests, original mixed-block retention and no C hash/bucket clone.
This packet implements no helper, source replacement or authority renewal.

Corrected artifacts are retained under
reports/debug-metadata/attrib-approved-cd58ff4a3d8c4293af2b9f9883a00eed;
initial harness failures remain under attrib-approved-250a3c3dd978432c9980fcf8b588d1ec.
The observation binds source spans, wrappers, processes, telemetry, actual host
identities and same-image module linkage. Final immutable images, the T hash
counterpart, whole-file review and target/aggregate gates remain required.
