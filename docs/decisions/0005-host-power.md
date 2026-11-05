# ADR 0005: Host Exponentiation Primitive

Date: 2026-11-05. Status: accepted for M1 numeric compatibility.

The 2,366-operation differential corpus found that GNAT generic elementary
real exponentiation differs from C Lua's host `pow`: negative bases have a
different domain contract, and positive results can differ by one binary64
unit. Reimplementing a correctly rounded transcendental library is beyond the
interpreter's scope and would still need platform-specific compatibility work.

Use one private C-convention import of the platform `pow` routine. It contains
no interpreter logic and exposes no public API. Decimal/hex conversion, integer
arithmetic, coercion, modulo, formatting, and IEEE comparisons remain Ada.

This uses the system math runtime already required by GNAT, with no downloaded
runtime package or vendored code. The host runtime's license applies to that
system component; there is no new source license in this repository. Linux
links libm, macOS provides system math, and Windows GNAT supplies its C runtime.
The standard-Ada alternative was exercised and rejected on measured parity
grounds. All target CI jobs compare this primitive against their native oracle.

This adapter does not promise bit-identical transcendental results across
different operating systems; each Ada build follows its matching C Lua host.
