# Scalar closing links and refusal recovery (2026-11-08)

The approved locals T replay reached its mandatory closing/refusal block and
failed because enter(0)'s returned closing object never became marked. A fresh
minimal native/Ada observation reproduced message='not enough memory' with
closemsg=nil only on Ada. GDB identified the first refused request as the
artificial Cell_Object allocation in Canonical.Mark_Closing, not the intended
later table allocation. Removing only that cell would still leave a new
Close_Lists buffer allocation. No upstream assertion or memory control changed.

[ADR 0038](../decisions/0038-scalar-closing-links.md) records the bounded repair:
canonical marks reuse existing parallel scalar closing links and their actual
frame head. No new prototype/frame reservation or binary format is introduced.
Unwind scope numbers remain relative for canonical functions and absolute for
explicit C-slot cleanup. Checked strict descent validates initialized ownership.
Actual scalar values remain authoritative after open-cell detachment; the
legacy packet list remains separate. Return/tail guards, stack live intervals,
collector roots and the read-only memory checker now recognize those real heads.

Fifteen separately named new cases include the original enter(0) failure and
three-closer replacement error, memory failure inside a closer, cold true/nil/
false functions under permanent refusal, closed-upvalue versus actual-stack
mutation, suspended captured/uncaptured values, generic-for fourth closing
value and goto scope order. Three direct VM cases prove no synthetic capture,
rooting outside debug liveness and safe rejection/recovery of a cyclic link.
The old retirement/prefix tests retain their actual target lifetime/release
assertions, with the genuine prefix published before retiring execution.

All six final serialized strict runtime/tests/C-consumer builds pass for default
and upstream-test with Alire 2.1.1, GNAT 16.1.0, Ada 2022, warning/style checks
and runtime checks. No warnings/style exceptions were introduced. Both complete
AUnit suites pass 2,536/2,536. All 26 ordinary default and 27 T C consumers pass
without flags, including retained close-yield, base C slots, reset, hooks,
allocation sweeps and scalar result tests. The separate native-module host
campaign was not rerun. Default AUnit refusal fixtures explicitly install T.

All twelve public cases pass pinned native T. Native binary -> native/Ada and
Ada binary -> native/Ada runs have identical raw stdout SHA256
CE8D9E56BF50F7D4F4970239EC4D82A48E3792E125CC2513C29A94D6D9EDB03E,
empty stderr and zero outstanding Ada bytes/blocks. Actual provider refusals
are required by the three failure AUnit cases. No diagnostic reset substitutes
for the actual callback lifting the limit in the enter(0) regression.

Mandatory unchanged errors.lua and coroutine.lua were copied without source
edits and executed under native/Ada default/T, no soft flags, timeout 900 seconds
and actual selected-owner ceiling 2,147,483,648 bytes. Every process exits 0 with
empty stderr. Coroutine raw stdout matches native exactly in both modes, hashes
1BA864A5A1252E99B555709EAC4300F63574B0769EF02C1FCCBB319DD6EEB85D
(default) and 67684281E453D226EFF6C1AA9E9DCFFDEC4F631B170E6716D1CA1CD8896DF204
(T). Ada peaks are 1,960,496,074/default and 134,606,693/T for coroutine;
1,870,423,829/default and 144,938,624/T for errors. All finish with zero
outstanding bytes/blocks, shutdown_complete=true, accounting_fault=false.
Errors retains only the previously documented printed implementation-depth
counts; its raw stdout is not called identical. The T errors process observes
one genuine selected/provider refusal and recovers.

Ignored raw evidence is reports/hook-top/scalar-close-* and
reports/hook-top/scalar-close-campaign-c61e89fb4b5f4f12b9d2d1521688770f.
A tools-disabled supplied-diff Claude Haiku review cost USD 0.00773649, one turn.
Its conditional detach concern was checked against the unconditional
Prepare_Close -> Close_Cells -> Stacks.Detach path and the passing native-paired
Closed_Upvalue/Mutable_Stack controls; its omitted-context liveness question is
covered by contiguous Trace.Bounds/Visit and the direct liveness-root case.
No additional concrete regression was identified. This review supplies no
independent source-equivalence approval or full-delivery acceptance.

The adapted whole locals manifest is stale after checker/runtime changes and
was not reused as current authority. Root must renew its source bindings and
replay that exact whole-file source. No reference bytes/pins, source decisions,
allocator limits or original assertions changed. Whole-target/platform,
materialized-vararg counterpart, immutable final-image and GitHub review/merge
obligations remain pending.

Changed-document UTF-8/LF/link/table checks and git diff whitespace checks pass.
The full isolated documentation check remains blocked by the missing
tests/modules/busted/busted-scm-1.rockspec fixture; its pin/tree was not changed.
