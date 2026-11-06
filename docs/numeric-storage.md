# Owned Numeric Conversion

[ADR 0015](decisions/0015-managed-numeric-scratch.md) owns the rationale for the
private exact arithmetic and shared numeric parser. The public numeric types
and `Lua.Numbers.Read` interface remain unchanged. This guide explains ownership
and work accounting for maintainers adding numeric consumers.

## Entry points and source lifetime

`Lua.Number_Parsing.Read(Text, Memory, Base)` is the single private byte parser.
It borrows `Text` synchronously and retains no source address after returning.
It accepts arbitrary Ada String lower bounds, including nonempty slices ending
at Integer'Last. Malformed input returns `Lua.Numbers.Invalid`; exact scratch
refusal propagates through the selected owner.

The public `Lua.Numbers.Read` is a host convenience wrapper. It creates a local
standard-Ada owner, calls the same algorithm and releases its scratch before
returning. At that host boundary, actual managed allocation refusal becomes
Storage_Error. A controlled-copy Program_Error is classified as memory failure
only when the owner's explicit refusal witness is present; unrelated invariant
failures retain their original classification.

Production runtime consumers use private Engine.Read_Number overloads:

| Overload                         | Ownership and work policy                 |
| -------------------------------- | ----------------------------------------- |
| State with String or Byte_String | Universe owner; charge source bytes once  |
| Owner with String or Byte_String | Explicit owner; caller accounts its work  |

The State overload charges against the current bounded execution epoch without
resetting its instruction counter. Protected calls cannot catch that host quota
or restart it. Helpers such as UTF-8 argument conversion that already charge the
complete input select the owner overload to avoid double charging. Compatible
execution retains its existing policy without overflowing a numeric work
counter. Frontend scanning uses its compilation-unit owner and its existing
source/token/nesting limits rather than a runtime instruction budget.

A Byte_String is a borrowed immutable payload. Its Lua value must remain in a
traced frame, stack window, operation root or other actual owner throughout
conversion. Creating a view does not extend that lifetime. No numeric runtime
consumer should materialize the complete payload merely to call the parser.

## Bounded precision, exact rounding

Integer scanning retains wrapping 64-bit bits and the decimal signed-overflow
decision. Floating-point conversion scans the complete validated mantissa but
keeps at most 1100 significant digits, its decimal/hexadecimal scale and a sticky
nonzero-tail flag. Work and retained precision therefore remain distinct: a
quarter-million-byte balanced numeral still requires a linear source scan but
does not require a quarter-million-digit integer.

Exponent saturation depends on source length, so a large negative exponent can
cancel a long hexadecimal mantissa correctly. Zero and obvious overflow or
underflow are classified before allocating exact scratch. Ordinary finite
values become an exact nonnegative numerator and denominator. Their bit lengths
locate the binade; exact quotient/remainder rounding then constructs binary64
bits, including subnormals, signed zero, carry into the next exponent and
infinity. The sign is applied separately.

`Lua.Big_Naturals` stores normalized little-endian base-2^32 limbs. Every Number
must receive an explicit owner before growth. Zero has no live limbs; nonzero
values have a nonzero high limb. Copies inherit the owner and have independent
managed buffers. Single-step mutations reserve required growth before writes.
Multi-step powers and division use temporary ownerful results and allocation-
free moves, preserving existing output values on refusal.

The core deliberately supports only the operations needed by conversion and
formatting. Its division has two distinct output objects; zero division and
negative subtraction are private contract errors. The decimal renderer emits
through an owned byte buffer using bounded nine-byte stack scratch. Do not
reintroduce standard-runtime big integers or a current-owner global.

See [owned formatting](number-formatting.md) for exact decimal and hexadecimal
output. The Engine.Image owner overload also routes its finite real round-trip
check through managed parsing. Its returned Ada String and remaining bounded
scalar formatting metadata keep their existing host representation; this
numeric-scratch change does not claim that every runtime/diagnostic snapshot
has been migrated.

## Verification and remaining obligations

The 2026-11-06 Windows/default/static validation checkpoint passed 916 AUnit
cases, including 14 exact-limb and 9 owned-number cases. They separately cover
carry/borrow, word/bit shifts, 4096 seeded native-width divisions, a 2048-bit
identity, aliased inputs, atomic refusal, decimal blocks, arbitrary source
bounds, midpoint/subnormal/sticky rounding, balanced exponents, allocation-free
extremes, cleanup and session recovery. The 250012-byte balanced hexadecimal
case enforces a 64 KiB managed-scratch ceiling. The division campaign seed is
0x5512026; its expected quotient/remainder comes from independent native 64-bit
operations rather than the limb implementation.

The joint 16-case formatting suite and 1435-line C/Ada fixture passed with the
retained acceptance pipeline. Exact commands, logs and the limited platform
claim belong to [ADR 0015](decisions/0015-managed-numeric-scratch.md). Final
matrix evidence remains separate. Numeric ownership does not complete C Lua
allocator parity, allocation-category reporting, emergency retry for all
container growth, permanent-refusal delivery or complete upstream testing.
