# Actual cached string-hash counterpart

Date: 2026-11-08, Asia/Tokyo. Test-only implementation checkpoint; delivery
continues.

The [decision](../decisions/0041-test-string-hash-invariant.md) records the
independent feature assessment: attrib.lua compares same-content normal/external
string hashes, while native signed 32-bit width and physical C bucket positions are
private representations. The new main-state T.hash reads the actual Ada cached
64-bit key hash and preserves every bit through signed integer rendering.
Exactly one string is required. No runtime or C boundary source changes, hash
clone, synthetic constant, payload recomputation, GC/budget reset or physical
table mode is added. Original attrib.lua:343 and its entire mixed block remain
unchanged.

Twelve separately named AUnit cases include retained long-string cached-field
low/high-bit probes, the six original boundaries, binary payloads, strict
argument type, Ada-only extra-argument rejection and default absence. The shared
public fixture uses actual owned/copied/borrowed external strings, key lookup,
update, next, duplicate payloads and collection. Every borrowed source remains
used after collection. The private field probes restore the exact original hash
before result inspection, key lookup or cleanup, including exceptional Cancel.

Four serial strict runtime/test builds pass in default and upstream-test with
Alire 2.1.1/GNAT 16.1.0 and retained Ada 2022 flags/checks. The first default test
compile caught missing visibility for Integer_Value's unary minus in the
high-bit test; the use-type correction was rebuilt without flag changes. Both
complete AUnit runs pass 2,612/2,612, zero failures or unexpected errors. Runtime
builds were needed to resynchronize this worktree with 4c8fb6c; no production
source changed. C consumers and CLI were not rebuilt for this test-only feature.
Six changed Markdown files pass UTF-8, LF and link checks. The complete
documentation checker remains blocked by the uninitialized future Busted
fixture link, tests/modules/busted/busted-scm-1.rockspec; no fixture pin changes.

The public eight-case fixture passes native T, direct Ada T and all four T
producer/VM roles with empty stderr and exact stdout SHA256
e8da16262495dd936c80cf8e82dc6b850457f849e13f8871a75a42ee1ed0f91d.
Native default rejects the mandatory-T fixture; that negative supplies no
omitted hash coverage. The signed 64-bit cache probes and extra-argument restriction
are Ada-specific, with no native table-position/width equivalence claim.

Fresh frozen native/Ada T hosts replay the approved ten-path-literal attrib
source through the original unstripped loadfile/dump/load/tail-call entry. Both
complete original hash/key/iteration/duplicate assertions and return exactly one
value 27. Stdout matches
b5aaea413ec8e08b5611087519dcb1b8aa25f718655fd885f52843f009631cd7,
stderr is empty and both selected providers report zero blocks/bytes. Ada
shutdown completes without accounting fault. Real module sources are separately
compiled and PE-audited against the actual selected image; fallback is absent.
Primary limits remain 900 seconds / 2 GiB with no _soft/no_port mode. The earlier
missing-helper and corrected-marker observations remain dated evidence.

The [source/evidence record](../../tests/conformance/targets/remaining-upstream-compatibility/string-hash.author-observation.json)
binds actual sources and raw artifacts without acceptance authority.
Raw logs are under reports/debug-metadata/string-hash-*; binary crossing is
string-hash-binary-3084980b06294a6096c1546b7e68533f and attrib replay is
attrib-string-hash-b087638779204c2fbcfb9e5b4c50e870. This checkpoint changes an
exact adapter dependency, so current verifier/API/locals bindings require
explicit independent review. No source mapping, exclusion, final immutable
matrix, aggregate or full-target acceptance is renewed automatically.
