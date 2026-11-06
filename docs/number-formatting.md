# Owned Numeric Formatting

The private Lua.Engine.Formats implementation produces string-library numeric
output without runtime-library big integers or unbounded string scratch. Its
runtime Render_Into path uses the calling world's storage owner for exact limbs,
decimal digits and final output. Render remains a host/test convenience wrapper
that materializes an ordinary Ada String after the owned operation completes.

## Exact decimal rendering

A finite binary64 value is decoded into its integer mantissa and power of two.
The private Lua.Big_Naturals type retains the exact nonnegative numerator and
denominator. Sign handling, including negative zero, remains separate; exact
zero is represented as 0/1. Scaling by decimal powers never rounds through
another floating-point value.

Division returns the quotient and exact remainder. Comparing twice the remainder
with the denominator decides rounding; an exact halfway case increments only an
odd quotient. This implements nearest-even rounding independently of locale or
the host's real I/O. The decimal exponent is found by digit counts and exact
comparison rather than an approximate logarithm.

Fixed, scientific and general forms assemble bytes directly into owned buffers.
Leading zeroes are virtual digit positions. Removing insignificant trailing
zeroes or the extra digit from a carry changes a view, rather than reallocating
or repeatedly inserting/deleting at the front. A carry updates the exponent
before general formatting chooses its notation.

Integer and real Lua values retain their existing exact data paths. Numeric
strings borrow their immutable payload and invoke the world-owned parser;
malformed trailing bytes remain a language error. No numeric formatting branch
first converts an already numeric value to text and reparses it.

## Hexadecimal and host policy

Binary64 has thirteen hexadecimal fraction digits. A fixed thirteen-character
scalar buffer holds those digits; requested padding is emitted into managed
output. Shortened precision uses the exact discarded bits and tie parity.

Host spelling policy remains distinct from memory ownership. The Windows
pinned C89 configuration rejects hexadecimal modifiers; macOS and Windows
normalize subnormals while the Linux policy retains the minimum normal exponent.
Focused policy-injection tests preserve these distinctions on every host.
Exponent and 64-bit integer images use bounded scalar scratch; variable-width
rendering never creates an input-sized unmanaged temporary.

## Verification

Lua.Managed_Format_Tests defines sixteen separately named and commented cases:
ties, carry, general-format thresholds, alternate zeroes, both binary64 exponent
extremes, negative zero, wide decimal/hexadecimal precision, numeric strings and
their rejection, actual output ownership, scratch balance, first/deep allocation
refusal and recovery. Allocation cases query the real owner and refuse actual
growth; copied limbs and partial output must be released before the world is
reused. They do not substitute sampled process memory for allocator accounting.

tests/lua/formatting_campaign.lua uses seed 0x13579bdf2468ace0, fifteen explicit
rounding/boundary values, and 128 generated finite
binary64 patterns. Its 143 values each use ten format specifications. Numeric
strings, an integer boundary and the completion marker yield 1,435 output lines.
The differential runner compares raw same-host C/Ada output and empty stderr.
The fixture is first-party evidence and leaves every upstream test unchanged.

The local Windows/default/validation/static checkpoint passed all sixteen cases
within **916/916 AUnit tests**, plus the 1,435-line raw C/Ada differential. The
complete retained pipeline also passed five upstream targets, API/CLI consumers
and the other nine first-party differential fixtures. Exact logs are
reports/m3-managed-numeric-build2.log and reports/m3-managed-numeric-check1.log.
This does not establish a whole-file strings.lua or math.lua pass, complete
allocator parity or another platform's formatting behavior.
