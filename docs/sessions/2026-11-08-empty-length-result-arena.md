# Empty length results under actual M0

Date: 2026-11-08, Asia/Tokyo. Narrow follow-up to the
[owned length-result correction](2026-11-08-length-result-arena.md).

Independent integration review requested a zero-result handler variant.
The [new mandatory T fixture](../../tests/lua/length_empty_result_refusal.lua)
warms actual call depth, sets the real growth count to zero inside __len,
returns no values, restores allocation only after # receives its result, and
checks that result is nil before healthy allocation. It leaves the previous
integer/multiple-result M0 fixture unchanged.

Native T completed that exact source; the first Ada replay failed with not
enough memory. The GDB trace at reports/length-empty-refusal-gdb.log identifies
223 raw bytes from the new unary normalization's Reserve_Capacity(1). The
capacity trace proves Native_Results has no buffer, while Native_Arguments is
already empty and retains real allocated capacity.

The completed @unary length branch now transfers that empty owned allocation
only when the result capacity is zero, arguments are empty and their capacity
is at least one. Move_Roots performs the actual ownership transfer and restores
the source allocator binding. Nil normalization then fits without growth.
No live argument value is moved, no local vector pretends to be a root, and
no generic scalar helper, equality or other unary operator changes. Existing
work charging precedes publication. The ordinary reserve remains available
when no suitable real arena exists.

All six strict runtime/tests/CLI builds pass in both configurations, with
unchanged Ada 2022 warning/style/runtime-check policy. Both full isolated
AUnit suites pass 2,645 cases, including the separately named empty-callback
M0 case and all previous core/CLI tests. These are combined component counts,
not a Root integration or full-upstream acceptance claim.

Fresh exact-source native T and Ada T processes both exit zero with empty
stderr, no managed refused growth and zero outstanding bytes/blocks. Native
and Ada default processes actually reject REAL T REQUIRED with exit 1 and
empty stdout; those negatives supply no T-body credit. PID/run/configuration
and actual 2 GiB cap are retained in the sidecars. Raw records are under
reports/length-empty-current-882c6699f2e74a9baca731784ea0da49. The earlier failed
replay remains under reports/length-empty-refusal-40b138f61a95403eac5414414d23c30e.

Standalone C relinks and fresh current CLI observation packets are a following
evidence-only step; their older passing captures remain dated and are not
silently rehashed. Parent will perform independent source review and frozen
combined validation. No reference source, upstream assertion, source mapping,
mode flag, count limit or eligibility rule is modified.

Following fresh relinks, all 26 default and 27 instrumented standalone C
contracts pass against this micro runtime with empty stderr. No native-module
argument-driven campaign is included. A new frozen replay satisfies all 166
argument/lifecycle contracts and balances all 110 measured normal-return
sidecars. The fresh current packet records new directories
reports/cli-dynamic-arg/59b124b4074e4f9eaf97139e4805db31 and
reports/cli-arg-lifecycle/f5779a35a7da4b61add5c49eed137f16, preserving the previous
current campaign identities as dated records. The current evidence guard also
checks all 53 retained C records and four empty-M0 positive/absence records;
936 integrity checks pass. This is actual re-execution, not a hash-only renewal.
