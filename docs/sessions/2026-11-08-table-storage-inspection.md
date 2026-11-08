# Actual table-storage inspection (2026-11-08)

This component implements the test-only checker required by the independently
reviewed locals-dead-table-storage feature proposal. Feature approval does not
approve replacement source bytes. The original locals.lua and its insertion
refusal sweep remain unchanged; no source adaptation, exclusion, scope or
ledger resolution was authored here.

Verify_Table_Storage locates every collectable key/value pointer in the actual
owned heap before dereferencing it, verifies its value tag against the live
object kind and registry slot, and checks actual dense/hash/free indices.
Bounded chain walks reject out-of-range rows and cycles. Independent per-row
membership checks establish that retained nonnil keys have exactly one index
and nil keys have none. Only after those proofs does the helper call actual
Tables.Find and require its returned row to match. Hash/free counts are derived
from the real chains. No repair, rebuilding, collection, allocator change or
input-sized ordinary temporary vector occurs in the checker.

Indexed nil-valued tombstones and revived live Free_Listed rows are accepted.
The exported test operation 38, T.ada_check_table_storage, returns actual
Members.Length and the number of nonnil row values. It reports neither dense
capacity nor C bucket geometry. The existing generic guarded C inspection
trampoline needs no new C shim. A tiny Engine child under tests/src delegates
private lookup; production source directories/interfaces do not depend on it.

Twenty-five separately named new AUnit cases pass. Twenty-two private cases
exercise empty/mixed storage, tombstones, revival, actual dead-key clearing,
same-table reuse, persistent insertion refusal/retry, inspection without
allocation, actual Lua count delivery and thirteen corrupt graph conditions.
Corruption is restored from exact saved scalar/row evidence before assertions
or physical disposal; no rebuild conceals a failing checker. Every private
fixture closes with zero selected bytes and blocks. Three public Lua cases
cover the original anonymous object key's weak lifetime, reachable key/value
survival and subsequent use of that same table after dead-key collection.
They use no private geometry and execute unchanged under both runtimes.

Both local configurations pass all **2,439 AUnit cases**, retaining the full
2,414-case baseline. The public fixture matches all four actual C/Ada
producer/VM roles in each configuration, stdout SHA-256
`eacc8230eaae6a49f47074a3aed2994553d9e2e8e4c96409acc61c72d5bcf4ec`.
The Ada-only private fixture verifies real four-before/zero-after entries,
original anonymous-key collection and reuse of its retained rows. Actual T
launcher execution ends with zero provider bytes/blocks, completed shutdown
and no accounting fault; stdout SHA-256 is
`fc5bcd55196b1fb9604904ba8c00d1672d2d59072b62f3c68e669bb4e4013f64`.
Default AUnit explicitly installs the real adapter for that private case;
native has no Ada inspector and is not described as passing it.

Six serial static runtime/tests/C-consumer builds pass under GNAT 16.1.0,
Ada 2022 and the unchanged strict warning/style/runtime-check policy. Initial
test compiles caught the private-child visibility restriction and a misspelled
exception name. The test-only delegation and actual Language_Error name fix
those causes. Their failed logs are retained; final builds pass with no
suppressed diagnostics. A pre-build test-package naming collision was corrected
by restoring the existing Lua.Table_Storage_Tests verbatim and placing the new
cases in Lua.Table_Storage_Inspection_Tests; all original registrations remain.

A bounded tool-free Haiku source review cost USD0.007746 and found no
high-confidence defect. Its observations about representation canonicalization
and Prefix_Length are outside this checker contract. Independent inspection
confirmed that dense-index length changes call Rebuild, and comments identify
the finite-chain proof required before the later lookup pass. This review is
component feedback, not independent exact-equivalent approval.

Local reports/debug-metadata/table-storage-* retains build, AUnit, source/
bytecode crossing, native public and private allocator evidence. No configured
native-module or complete C-consumer execution campaign was rerun for this
test-only change. Root owns subsequent exact source review, drift refresh,
original/refined locals execution and final source/platform reconciliation.
