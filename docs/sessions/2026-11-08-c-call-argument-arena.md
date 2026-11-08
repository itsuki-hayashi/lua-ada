# Reuse an actual empty C-call argument arena

Date: 2026-11-08, Asia/Tokyo. Author: Codex /root/runtime_gaps.

A temporary shared CLI protected-call transport exposed an existing public C
boundary allocation: Begin_Call copied already rooted C arguments into a new
local vector before entering lua_pcall. The unchanged CLI selected-script
refusal case failed there. GDB located the first refused 223-byte growth in
Append_Root; the actual suspended C caller already owned an empty argument
arena with capacity four. Its scalar window remained the authoritative roots.

The narrow correction lends that empty capacity to synchronous Begin_Call or
Begin_Builtin setup when a live, same-context C activation owns it and it fits.
It does not widen the root-call, cross-context, nonempty or undersized paths.
The local scratch owns actual Value copies, never a borrowed element address.
Setup publishes the real callee and arguments before clearing the scratch and
returning its empty arena. Both normal and exceptional paths return it before
Pump can execute callbacks or retire frames. Bounded execution precharges both
fill and clear before changing ownership. No public stack top, close marker,
semantic capacity or allocator limit changes.

Three separately named additions to builtin_api_contract.c retain all earlier
thirty cases. The same real C callback warms the call, refuses actual provider
growth, and checks trailing nil and table aliasing; a second case checks error
object/retry behavior; a third clears the actual C slots and verifies weak
release while that caller remains live. Each final state has zero provider
bytes and blocks. The unchanged source passes all thirty-three cases with the
default and T C oracles and both Ada configurations.

All eight strict default/T runtime, test, CLI and consumer builds pass in the
combined author draft, as do 2,678 AUnit cases in each configuration. These
images also contain the separate pending CLI interrupt component and peer's
temporary message-handler transport: they are component evidence, not a clean
revision or final CLI-hook parity claim. All retained ordinary C consumers
pass, with the existing native T callback-lock options preserved. The native
module consumer requires its real fixture-directory argument; a first bare
invocation only printed usage and is not credited. Fresh same-image fixtures
then pass its nine cases in both configurations.

Raw author records are reports/cli-interrupt-build/
ef0a24e1e0d640cf82e8e53cb046f8b1 and reports/call-argument-arena/
80e7eb98151a4892967fda537fac60d1. A bounded supplemental Claude Haiku review
cost $0.02500851. Its first eight-turn attempt exhausted its turn limit; the
completed follow-up found no high-confidence issue in the supplied narrow
diff. This is author-side review, not independent conformance authority.

No claim covers every fresh C call under refusal. Physical Lua/C stack
admission, actual callee/result capacity and other operations can still refuse
through their existing typed error protocols. No original assertion, source
adaptation, exclusion or acceptance policy changes in this checkpoint.
