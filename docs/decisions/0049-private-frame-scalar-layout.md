# ADR 0049: Group private frame scalars without changing ownership

Date: 2026-11-08. Status: accepted bounded checkpoint correction.

Repeated checkpoint CI at 412ddfd exposed a macOS default/static coroutine
resident watchdog failure: 2,159,149,056 sampled bytes exceeded the unchanged
2 GiB threshold. Earlier default macOS static/shared passes at 122d642 remain
dated observations, not proof of stable margin. Preserve the failed process
capture and exit 137; do not raise the threshold or omit the workload.

Group the existing thirty-five Boolean flags and eleven enum phase fields at
the end of the private Frame record. Keep their strong types and static
defaults, all ownership components, and the relative order of controlled
components. Use ordinary compiler alignment without Pack, representation
clauses, new sidecars or allocation policies. This changes only internal
padding; native consumers see opaque frame addresses. No Lua-visible behavior
or public C/Ada layout changes.

An independent source census confirms identical 137 component declaration
lines by name/type/default and the same relative order for all fifteen
controlled components. Defaults do not depend on component elaboration order.
No streaming, representation clause or component-offset dependency was found.
Active vectors, buffers and stack-view leases remain intact.

The actual Windows GNAT 16.1 measurement changes Frame from 1,232 to 1,160
bytes. A 1,003-active-frame diagnostic retains 2,031,438 raw managed bytes,
versus 2,103,870 before grouping, with the same 3,497 blocks and zero final
ownership. Size and managed accounting are component measurements; the fresh
matrix must establish actual macOS resident behavior. Retain strict flags,
runtime checks, original sources and existing memory/time limits.

The [component session](../sessions/2026-11-08-private-frame-scalar-layout.md)
owns build/test observations. The interim PR owns final checkpoint CI and
merge identities; this decision does not close full upstream acceptance.
