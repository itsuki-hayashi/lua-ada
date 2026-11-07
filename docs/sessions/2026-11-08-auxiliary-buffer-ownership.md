# Auxiliary buffer ownership checkpoint

Date: 2026-11-08, Asia/Tokyo. Branch:
`codex/m3-remaining-upstream-compatibility`. This continues the authorized
complete delivery and is not a full-target stopping condition.

## Implementation and source review

The eight public `luaL_Buffer` functions use actual C scratch/layout and Ada
provider-owned dynamic storage. Real C closing slots, userdata resource
cleanup, stable external release and captured allocator/data pairs establish
ownership through normal return, protected errors, refusal and host abort.
See [ADR 0028](../decisions/0028-auxiliary-buffer-ownership.md).

A Haiku consumer draft was inspected and corrected before use. Its original
net-byte release assertion was not an ownership proof across implementations.
The final observer tracks the actual provider region containing public buffer
bytes and preserves its identity through reallocations. The fault campaign
uses a fresh identically configured state for each measured growth, checks
actual refusal, requires the native `LUA_ERRMEM` class, retries in that failed
state and checks balanced close. A seventeenth case measures retained
allocator/function userdata after replacement. No private Lua layout is read.

A bounded read-only Sonnet 5.5 review inspected the implementation and storage
ownership. Its required content/capacity correction caps optional slack in
bounded sessions and adds a near-limit witness. The release-only C callback
uses canonical descriptor ownership instead of raising a diagnostic exception
for transport parameters. Separate scan/copy work charging is documented at
the loops. The review ran no tests and grants no acceptance authority; its
raw record is `reports/remaining-aux-buffer-sonnet-review.json`.

## Local observations

Alire 2.1.1, GNAT 16.1.0 and GPRbuild package 26.0.1 (executable 26.0.0) retain
the strict Ada flags and runtime checks. The current component has strict
Windows validation/static root, nested-test and consumer build observations.
All seventeen C cases match Ada, native default C and native T output:
`881b6d5ab5430e3ef456fc8d345c21731c8a5d574d31d1cc1d1c95a429cc2d7c`.
After the capacity/copy-work refinement, serial strict root/test/consumer
builds pass and all 1,738 AUnit cases pass, with zero assertion failures or
unexpected errors. This includes a valid near-limit growth and direct heap
disposal before any recovery execution or Lua collection. The fifteen
retained C consumers also pass. Local raw logs are
`reports/remaining-aux-buffer-*`.

The AUnit cases reuse seventeen individually named actual public C cases and
add separate bounded-policy regressions. Two storage cases exercise retained
provider identity/data while ordinary storage uses the replacement. These
results do not establish the remaining public auxiliary exports or any new
global source/API classifications.

## Remaining obligations

Complete independently reviewed target witness registration, integrated
instrumented/shared/POSIX and immutable final-head
matrix replay. The remaining auxiliary file, trace, substitution and allocator
exports, relevant T drivers, remaining primary files, aggregate/stress/helper
execution, global reconciliation, GitHub review and authorized merge remain
unfinished. Reference sources, pins and public headers stay unchanged.
