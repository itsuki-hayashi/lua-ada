# Managed diagnostic text component (2026-11-08)

The new private immutable diagnostic-text component implements ADR 0035. Its
long payloads use the existing selected-owner subpool, short emergency values
use bounded inline storage, and controlled copies share immutable bytes
without allocator growth. Actual runtime failure fields have not migrated yet.

Fourteen separately named AUnit cases pass in both local configurations. They
measure real selected blocks and growth attempts, verify permanent refusal
and atomic failed replacement, preserve a copied message after releasing its
source, exercise self assignment and alias replacement, retain query views
through clearing/replacement/exceptions, and check counted NUL bytes at both
sides of the 96/97-byte boundary. Every case releases all selected blocks.

Both strict validation/static nested test builds pass, compiling the actual
production library dependency with all required Ada 2022 warnings/style and
runtime checks. Their first attempt exposed the missing private unit in the
SAL interface list; adding it to the documented internal closure fixed the
cause without changing Ada visibility or disabling diagnostics. The integrated
label, function-site, return-hook, vararg, C self-value and stack-inspection
implementation passes all 2,281 AUnit cases in each configuration. C consumers
and CLI were not relinked or rerun for this component-only checkpoint.

A one-turn supplied-source Claude Haiku review examined the actual spec/body,
ran no tools/tests and found no high-confidence defect. Root checked its pool
ownership question against Storage's declarations, documented serialization,
and added direct alias-query plus 96/97-boundary cases. The component retains
the existing owner-outlives-borrowers rule; it does not claim to support closing
a universe while its owned values are still in use.

The Ada unit-testing skill informed focused case/cleanup structure. The tests
use the existing nested AUnit crate; no generated empty GNATtest harness or
proof result is counted as coverage. Mutable reports/diagnostic-text logs
are component evidence only. Engine failure-field migration, long Lua error
value propagation without duplicate copies, selected allocation refusal,
remaining upstream/T/aggregate/heavy execution and final 26-context acceptance
remain required before the implementation PR, automatic review and merge.
