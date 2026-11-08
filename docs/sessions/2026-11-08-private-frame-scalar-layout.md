# Private frame scalar layout checkpoint

Date: 2026-11-08, Asia/Tokyo. Author: Codex /root. Independent source reviewer:
Codex /root/runtime_gaps. Scope: the maintainer-authorized interim PR #11.

The repeated macOS default/static lifecycle observation at 412ddfd fails the
unchanged 2 GiB resident watchdog in coroutine.lua. Child PID 22985 exits 137
after 4,235 ms, with only `testing coroutines` on stdout and empty stderr.
Sampled resident memory is 2,159,149,056 bytes. The executable hash is
4410298b38433abab0db14c58790e0eee319b1985fc500dc7a22222e6ded4974.
The verified artifact is 13618564763, digest
7e90c2f08b8674259bf2883c733c2b431847af5dde14d5bc7aa28169b95a3b0f;
its raw lifecycle directory is 240972dd041f4b01a7274b66a03909df.
That observation remains failed despite earlier passing macOS observations.

[ADR 0049](../decisions/0049-private-frame-scalar-layout.md) records the bounded
layout correction. No field, default or owning arena is removed. The source
review confirms all 137 component declarations and the controlled-field order
are preserved. Only static scalar placement changes.

The private actual-size probe reports 1,160 bytes per Frame, down from 1,232.
Its 1,003-active-frame workload retains 2,031,438 raw bytes and 3,497 blocks,
then releases all ownership. Grouping only Boolean fields first measured
1,208 bytes; grouping the existing enum phases as well gives the retained
1,160-byte layout. These are Windows native GNAT measurements, not macOS RSS.

Eight fresh strict Windows validation/static builds pass: runtime, C consumers,
CLI and nested tests in both configurations. Both full AUnit suites pass
2,665 cases with zero assertions/errors. All 26 default and 27 T no-argument
C consumers pass; native module fixture acceptance remains a separate CI gate.
The unchanged goto/coroutine lifecycle comparisons pass both configurations,
including actual T API/hook sections and the unchanged resident watchdog.

The separate four-role coroutine campaign retains actual allocator sidecars.
Ada default peak falls from 1,896,476,423 to 1,824,451,871 managed bytes; the
T peak falls from 130,237,089 to 125,316,537. Both use the same 2 GiB managed
ceiling, have no managed/provider refusals, report zero outstanding bytes and
blocks, and finish shutdown without an accounting fault. These measurements
are not resident-memory measurements and do not establish macOS behavior.
The local raw campaign is remaining-originals-c19379355fe5436da595e90b9f09de6a;
the strict build log directory is table-error-build-45727113006045b6a1df37dc8261935f.

Current-head twelve-context CI must verify the integrated runtime and actual
macOS watchdog. The full 26-context upstream target remains deferred.
