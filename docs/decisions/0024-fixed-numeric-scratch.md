# ADR 0024: Fixed scratch for numeric boundaries

- Date: 2026-11-08, Asia/Tokyo.
- Status: implemented reusable primitive; public C wiring remains separate.
- Scope: fixed local backing for the existing exact parser and formatter.

## Context

`lua_stringtonumber` and `lua_numbertocstring` must convert without growing
the Lua allocator. The shared exact parser/formatter use owner-carrying
rational vectors. Refusing ordinary conversion when that provider refuses
would differ from the pinned C contract. A native `strtod` primitive could
avoid managed scratch but would add a conversion boundary around the shared
grammar, hexadecimal distinction and locale rules.

`Number_Parsing.Exact_Real` already scans arbitrary input with 1,100 retained
significant digits and a nonzero-tail witness. Binary64 midpoint decimal
expansions terminate within 1,075 places, so this decides halfway rounding
independently of full input size. Extreme scales are classified before limb
construction. Surviving rational magnitudes stay bounded even when very long
mantissas and exponents cancel.

## Decision

`Lua.Storage.Fixed_Arenas` owns fixed local bytes and an aligned cumulative
bump cursor. `Bind(Arena, Owner)` attaches it once to a fresh ordinary owner.
The arena outlives that owner and every borrower. Typed vectors, allocation
records and controlled finalizers continue using the existing owner/pool.

Growth reserves a fresh region before copying the minimum old/new extent.
Refusal preserves both the old region and cursor. Free retires the real
owner record without resetting/reusing arena bytes. Absolute-address alignment
uses the ownership-header alignment; it assumes no special alignment of the
byte-array starting address. The provider calls no backing allocator.

`Number_Parsing.Read_Without_Allocation` constructs the arena/owner locally
and invokes unchanged `Read`. All rational vectors finalize before its scalar
result returns. No owner, arena address or numeric vector escapes. Grammar,
integer/real distinction, locale point, negative zero, long exponent handling
and exact ties-to-even arithmetic retain one implementation.

The numeric arena is 131,072 bytes, covering cumulative requests including
replaced/freed buffers and ownership/compiler metadata. At 1,100 hexadecimal
digits the largest surviving divisor is below 5,500 bits, at most 172 base-2^32
limbs. Geometric capacity remains at most 256 slots. Five local rationals,
one power scratch and three division temporaries give nine vector lifetimes.
Capacity sums below 512 slots and generous request metadata fit the allowance
on supported native GNAT layouts; decimal bounds are smaller. This is a
capacity argument, not a proof-tool or arbitrary-compiler acceptance claim.
The formatter can reuse the same provider and its existing exact conversion.

## Alternatives and consequences

Using the universe provider introduces incorrect public conversion refusal.
Default-heap scratch would hide ownership. A second grammar or approximate
parser could change rounding. This provider reuses exact arithmetic with
explicit, bounded storage instead. The fixed stack reservation is independent
of input length. Numeric conversion invokes no foreign callback and retains
no arena across a nested executor entry. Capacity refusal remains an ordinary
private allocation exception; it cannot substitute for checking the bound.

## Verification and limits

Strict local Windows/default/static root/tests builds pass. All 1,640 AUnit
cases pass, including seven new cases for cumulative refusal transactions,
copied bytes/release, remote midpoint tails beyond three thousand zeros,
maximum retained decimal/hexadecimal subnormal rationals, ten-thousand-digit
cancellation and shared locale/integer/signed-zero grammar. GDB observations
measure 15,886 and 13,366 cumulative provider bytes in the two large cases.
The [session](../sessions/2026-11-08-fixed-numeric-scratch.md) records commands.
Public C operation wiring/refusal consumers, integrated T/shared/platform
builds and full acceptance remain separate. Existing allocating callers are
unchanged. No reference source or revision changed.
