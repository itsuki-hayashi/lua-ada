# ADR 0015: Managed Exact Numeric Scratch

- Date: 2026-11-06
- State: accepted
- Owners: `Lua.Big_Naturals`, `Lua.Number_Parsing`, `Lua.Engine.Formats`

## Context

The runtime's strings, values, tables, programs and execution packets select a
universe storage owner. Exact binary64 parsing and decimal formatting still used
standard-runtime big integers. Their variable-size intermediate storage bypassed
the universe allocator, so a callback provider could not observe or refuse all
numeric conversion work. An allocator-aware wrapper around the final result
cannot repair that ownership gap.

Long valid numerals introduce a separate work risk. A decimal or hexadecimal
mantissa can be extremely long while its exponent cancels to an ordinary finite
value. Retaining every digit creates unnecessary growing integers; saturating
the exponent at an unrelated fixed bound changes valid results.

## Decision

Use one private nonnegative integer core with owner-carrying base-2^32 limbs.
Its deliberately narrow operations support exact binary64 conversion and
formatting: small-factor arithmetic, powers and shifts, comparison, subtraction,
Euclidean division and decimal rendering. It is not a public arbitrary-precision
library. Every variable-size limb list and digit buffer uses an explicit
`Lua.Storage.Owner_Access`; there is no current-owner global or allocator
fallback.

Parse numeric source through one shared private `Lua.Number_Parsing.Read`.
The public `Lua.Numbers.Read` keeps its host convenience interface by creating a
local standard-Ada owner. The scanner and runtime supply their own owner to the
same algorithm. A borrowed source view preserves arbitrary Ada String bounds
without copying the complete input.

Retain at most 1100 significant digits and a nonzero-tail witness while counting
all omitted/fractional digits. Binary64 halfway boundaries have terminating
decimal expansions within 1075 fractional places; this retained precision is
sufficient to distinguish every finite rounding boundary. A discarded nonzero
tail resolves an exact retained-prefix tie upward. Hexadecimal source uses the
same bounded prefix with power-of-two scaling. Exponent saturation is relative
to complete source length, allowing cancellation against the entire mantissa.
Obvious zero, overflow and underflow are classified before allocating limbs.

Finite conversion builds an exact numerator/denominator, finds its binary
binade and rounds an exact quotient using its remainder. Formatting decodes a
binary64 value directly into an exact rational and rounds decimal output with
the same remainder rule. Both use nearest-even rounding without a host locale
or a second approximate floating-point conversion. Hexadecimal rendering uses
the exact representation bits and bounded fixed-width nibble scratch.

Reserve before single-step arithmetic writes. Multi-step powers/division build
private ownerful results and move them into their destinations only after the
entire calculation succeeds. Refusal therefore releases partial scratch and
preserves existing destinations. Managed storage failures retain their real
provider witness if Ada wraps a failed controlled copy in Program_Error; only
that witness permits memory-error classification.

Runtime numeric-string conversion charges its source length once against the
existing bounded execution epoch. Callbacks and protected calls do not restart
that allowance. Helpers that already charge the complete input use the explicit
owner overload to avoid charging twice. Host convenience parsing and frontend
scanning keep their separate existing resource policies.

## Alternatives

- Keep standard big integers: convenient, but growing scratch bypasses the
  selected callback allocator.
- Call host strtod/printf: introduces locale, portability and allocator/control
  differences, and would need additional narrowly justified foreign bindings.
- Implement independent scanner/runtime numeric converters: duplicates semantic
  rules and permits precision/error drift between syntax and execution.
- Retain every source digit: exact but needlessly expensive for balanced long
  numerals; it does not make binary64 output more precise.

## Consequences

The core owns additional arithmetic code and therefore needs independent
boundary, identity and refusal tests. Its operations remain private and small.
Retained capacities are real managed allocations and appear in allocator
statistics; they are not estimates of C Lua object layouts or byte counts.

This decision removes the numeric big-integer bypass. It does not establish
full allocator parity: allocator category tags, emergency retry on every
growth, permanent-refusal error delivery, remaining host snapshots and other
storage boundaries retain separate acceptance obligations.

## Verification

The 2026-11-06 Windows/default/static validation checkpoint passed strict GNAT
16.1.0 compilation and all 916 AUnit cases. Its 39 new focused cases cover limb
arithmetic, seeded quotient/remainder identities, rounding boundaries, source
bounds, scratch ownership, refusal cleanup and bounded-work recovery. A valid
250012-byte balanced hexadecimal numeral converted exactly to 1.0 while managed
scratch remained within a 64 KiB ceiling.

The full `scripts/check.ps1 -Profile validation -LibraryType static` pipeline
also passed the Ada consumer, 35 CLI contracts, 10 binary CLI comparisons, the
five retained unchanged upstream execution files and 10 differential fixtures.
The numeric-format fixture contributes 1435 same-host C/Ada stdout lines. The
retained coroutine file uses its documented default/T-absent coverage; these
checks do not establish complete upstream or other-platform conformance.

Local logs are `reports/m3-managed-numeric-build2.log`,
`reports/m3-managed-numeric-tests1.log` and
`reports/m3-managed-numeric-check1.log`. The first build attempt stopped at an
undefined GPR external before Ada compilation; using the already defaulted
platform variable fixed it. Other profiles/platforms retain their separate
final-revision matrix obligations.
