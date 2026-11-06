# ADR 0011: Host Mathematical Primitives and Owned Random State

Date: 2026-11-06, Asia/Tokyo. Status: accepted and implemented; full platform
acceptance remains pending. This extends the host-math boundary without changing
the historical [ADR 0005](0005-host-power.md) exponentiation evidence.

## Context

Complete M3 includes the pinned mathematical library, including exceptional
IEEE values and reproducible seeded random sequences. The matching native
C interpreter uses host binary64 mathematical primitives. Standard Ada
elementary functions have exception-based domain contracts and can round
differently; returning an Ada exception for sqrt(-1) or asin(2) would change
Lua behavior. Reimplementing a correctly rounded transcendental library would
also fail to establish the matching host C library's exact rounding contract.

Pinned evidence is [Lua 5.5.1 lmathlib.c](https://github.com/lua/lua/blob/7579fc9d7ed90240487251dfb69168f8e64e9294/lmathlib.c):
lines 42–230 define the host operations and optional arguments, lines 348–644
define the two RNG arithmetic paths and seeding, and lines 672–743 distinguish
compatibility exports from the default table. The reference remains unchanged.

## Decision

Use a private C-convention adapter for sin, cos, tan, asin, acos, atan2, log,
log2, log10, exp, sqrt, sinh, cosh, tanh, pow, frexp and ldexp. Interfaces.C
types describe binary64 arguments/results and the borrowed C int exponent.
These imports contain no interpreter, argument handling or random algorithm.
The system math runtime is already required by ADR 0005; no downloaded runtime
dependency or new vendored source is introduced. The host runtime's license
continues to apply to that system component.

Keep argument validation, numeric-string conversion, degree/radian scaling,
result adjustment and RNG implementation in Ada. Explicit IEEE quotient handling
preserves log(x,1) behavior without an Ada zero-divisor exception. Pinned
luaconf enables LUA_USE_C89 on Windows; its base-two logarithm uses the natural
logarithm quotient, while C99 configurations select host log2. Preserve that
configuration distinction, including rounding and exceptional-value bits. The ldexp
adapter preserves the supported C ABI's integer-cast behavior before the call.
The first published checkpoint exposed an additional arithmetic issue on
macOS AArch64: synthesizing x86 negative NaN for 0/0 changed the bytes later
returned by sin. A narrow first-party C function now performs native binary64
division, and host fmod supplies remainder domain results. Neither helper owns
Lua state or interpreter behavior. Ada keeps conversions, dispatch, floor and
modulo correction, with runtime checks enabled. Exceptional NaNs are not masked
in comparisons. The new focused cases and the same-host differential must
verify this change on every platform.

No cross-operating-system bit-identical transcendental promise follows: each
build must match its own native C oracle.

Implement xoshiro256** with explicit modular types, per-universe state and no
mutable process-wide RNG. Both the native 64-bit and split-32 carry/rotation
paths operate on the same canonical state words and must produce identical
streams. Preserve the pinned sixteen-transition seed warmup, high-53-bit float
extraction, rejection sampling, signed interval projection and draw-before-error
behavior. Explicit two-word seeds reproduce output; automatic seeding uses
unspecified clock/address entropy and makes no cryptographic claim.

Charge rejection retries and execution-time reseeding to the existing shared
budget. Fresh standard-environment initialization precedes execution and does
not consume a bounded session's allowance. Default registration excludes atan2,
cosh, sinh, tanh, pow and log10; the compatibility profile exposes them.

The current standard environment installs one RNG instance per universe.
Repeated public luaopen_math construction must eventually give each returned
library's random closures independent captured state. That remains part of
C-facade integration, not evidence supplied by this singleton registration.

## Verification and consequences

Lua.Mathematics_Tests adds 40 independently named cases for domains, signed zero,
subnormals, result kinds, C exponent casts, seeds, exact streams, rejection,
independence, 32/64-bit equivalence and native budget preservation. The focused
cases must pass after dispatcher and test-runner integration; current status
owns the actual passing counts rather than this decision inventing them.

The first-party mathematics campaign retains seed pairs and encodes binary64
results as bytes. Pinned C runs currently complete with 714 default output lines
and 715 instrumented lines, both with empty stderr. This is oracle fixture
validation; the later Windows/default/static checkpoint also passes the
714-line C/Ada differential. Current status owns its exact scope. C frexp leaves
the exponent unspecified
for infinity/NaN, so those campaign cases compare the fraction; finite cases
compare both results. Retain that boundary in evidence.

The full Windows/Linux/macOS matrix and expanded upstream execution remain
mandatory. This decision does not claim unchanged math.lua, full C API or
complete M3 acceptance.
