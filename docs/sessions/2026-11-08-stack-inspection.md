# Actual stack inspection (2026-11-08)

Relevant T reader checks in calls.lua could not execute because stacklevel was
missing. The test-only adapter now returns actual Ada foreign-stack top,
allocated arena bound, native portal nesting and active activation count. The
C inspection wrapper appends its own real local address, after Ada returns.
It never fabricates a constant level or reproduces C-private backing geometry.
The private inspection result record grows from three to five integer cells
on both sides of its C boundary. Existing three-result operations keep their
result count and explicitly zero the unused cells.

The active Ada activation count differs from native C's retained CallInfo
count; the manifest records that distinction. No upstream consumer uses the
fourth or fifth field. Size observations in api.lua/cstack.lua remain real
measurements of Ada's policy and still need assertion-level feature review.

Four individually named AUnit/Lua cases verify all five scalar types, stable
text-reader tops, stable binary-reader tops, and actual increased nesting
inside a protected callback followed by restoration after an error. Native T
and Ada T produce identical PASS output. Both local configurations pass all
2,248 AUnit cases, including the integrated function-definition source-site
checkpoint. All eight strict static runtime/tests/C/CLI builds pass with
GNAT 16.1.0 and retained Ada 2022 warnings/style/runtime checks. The first tests
build correctly rejected a top-level test package's access to private Lua
children and an 87-column line; making it a Lua child and splitting the line
fixed both causes without reducing checks.

Unchanged calls.lua completes native/Ada default and native T. Ada T now
passes the reader checks and reaches line 586, T.listk constant-pool identity
inspection. The file's actual three function results must remain covered while
reviewing that private identity assertion. No T block was silently skipped,
and no new exclusion or source equivalent was installed in this checkpoint.
The default Ada observation uses a 2 GiB managed limit, reports no refusals,
zero outstanding bytes/blocks, complete shutdown and no accounting fault.

A one-turn tool-free Claude Haiku design review found no high-confidence
logical defect in the supplied design. It did not open source or run tests.
Its concrete caveats are checked by same-point sampling, the matching five-cell
C/Ada declarations, fixed 64-bit pinned integer ABI, nonzero active-count/address
assertions and documented private-counter distinctions. This is not final
independent source/platform or GitHub approval.

Mutable reports/stack-inspection contains component observations only. Full
T/public-API source reconciliation, original aggregate/heavy execution,
allocator audit and 26-context final-head acceptance remain open.
