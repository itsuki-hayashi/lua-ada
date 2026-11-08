# Hidden named varargs (2026-11-08)

Unchanged vararg.lua stopped at line 249: the warmed read-only `notab`
function allocated a named-vararg table on every call. Native Lua uses its
hidden argument window until the resolved parameter escapes, is written,
is captured, or supplies an environment. The canonical compiler now selects
that existing runtime representation using resolved frontend symbol identities.
Direct indexed reads emit GETVARG and evaluate their key once. Assignment
right-hand sides, keys and nested receivers remain reads; actual writes to
the vararg table retain materialization. Bare escapes and captures retain
owned, traced tables. No second grammar or reference changes are involved.

Nine separately named AUnit/Lua cases cover warmed allocation equality,
the native nil debug slot, distinct escaping tables and nil holes, writes
and modified expansion counts, captured lifetime, effectful keys, debug slot
replacement, numeric/nonnumeric boundaries and assignment read contexts.
An older debug test incorrectly required a materialized table despite only
indexed use. Its expectation now follows the measured native nil slot while
still checking the named parameter, indexed value and function metadata.

The previous eight-case checkpoint passed all eight strict static builds,
2,193 AUnit cases per configuration and eight C/Ada producer/VM roles. It also
completed the original unchanged vararg.lua in both default and T modes:
four outputs have SHA256
`b9c8e5332926fab75c3325c589f99aae07d27314573fe55bdc8a83a449d84e06`.
The measured Ada runs used a 2 GiB managed ceiling, no reduced-suite flags,
zero refusals, zero outstanding blocks/bytes, complete shutdown and no
accounting fault. The ninth assignment-context case was added afterward;
final fresh component results are recorded below when inspected.

A bounded Claude Haiku static review found no high-confidence defect in
the initial visitor. Its first attempt exhausted its turn limit; a resumed
conclusion completed. It ran no tests and did not review the later assignment
refinement. Actual dumped chunks are tested through both real native and Ada
VMs, rather than relying on private opcode inspection.

These are local Windows validation/static component observations, not a
26-context file certificate or whole-target acceptance. Other remaining source,
T drivers/equivalents, allocator ownership, aggregate/heavy, platform matrices,
independent reconciliation and GitHub review remain required.

Final nine-case source: all eight strict builds passed; 2,194 AUnit cases
passed in each configuration. All eight producer/VM roles matched. Fresh
unchanged vararg.lua completed in all four native/Ada default/T runs with
the same stdout hash and empty stderr. Logs remain under
reports/lazy-named-vararg; these mutable component reports carry no final-head
acceptance authority.
