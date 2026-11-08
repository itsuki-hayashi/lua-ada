# Metamethod argument ownership prerequisite

Date: 2026-11-08, Asia/Tokyo. Scope: retire copied operator inputs after the
actual next activation owns them. This is a dependency for the remaining
public C concatenation-window repair, not its completion.

## Actual ownership transition

Canonical helper requests previously retained their input packet until
result delivery. The private operator helper also retained its input packet
while its real Lua/C metamethod ran. These helpers already own no physical
scalar window. The copied values therefore survived even after a handler
cleared its parameters and used debug.setlocal to remove the original
caller's real operand edges.

The producer now clears its request after Schedule publishes the helper's
owned packet. The four operator helpers clear their input after Dispatch
publishes the actual handler activation. Their metadata, operator, result
continuation, native/yield charges, hooks and real register/cell ownership
remain authoritative. Packet Clear retains allocated capacity and introduces
no allocation or safe point between transfer and retirement. Failure before
dispatch publication leaves the original packet for normal recovery.

No window, getlocal extent, opcode event, collector assertion or reference
source was changed to obtain the expected result.

## Verification

Seven separately named cases cover concat, arithmetic, length, index,
newindex, a suspended metamethod and an error message handler. Each removes
actual caller edges and callback parameters, then observes weak entries at
an explicit collection. All seven independently failed on the pre-fix Ada
binary and pass unchanged on pinned native default/T. They now pass Ada and
all four default producer/runtime combinations.

Strict serial root, nested tests and C consumers pass with GNAT 16.1.0 and
all retained validation flags. All 1,935 integrated local AUnit cases pass,
as do thirty-six retained four-way cases and twenty-one public C consumers.
The native-module consumer's separate image fixtures were not run bare.
Unchanged db.lua still has stdout SHA256
`61D58565C89CD99626C0A10641E6E8A14303A560258EF302FC6B9915E7724897`
and empty stderr.

The named current-pair C witness also passes native default/T: a concat
handler clears both consumed C slots and its own parameters, collects them,
and later drops an intermediate result at the next fold. Actual C concat
windows still require their separately tracked implementation and paired Ada
evidence. Registry-fallback continuations, remaining upstream/T files and
immutable final matrix/review acceptance remain open.
