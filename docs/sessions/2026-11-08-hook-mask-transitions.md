# Hook mask transitions and literal destinations (2026-11-08)

The retained T API source failed its original line1090 count-to-line hook
sequence, corresponding to line1115 of the separately reviewed API equivalent.
The original hook body and assertion remain unchanged. A condensed native
control reported lines12,13,14; Ada reported an extra line11. Both crossing
directions failed: native execution of Ada bytecode and Ada execution of native
bytecode each reported the extra event. This established independent compiler
and runtime defects rather than an adapter exclusion candidate.

Pinned ldebug.c:luaG_traceexec captures the instruction's hook mask before its
count callback. The pending line phase uses that captured mask and the current
callback pointer. Count-only instructions do not update oldpc. Machine now
retains that mask and a separate trace PC in the actual frame, resetting both
on reuse. Removing the current hook prevents a call, while replacing it with
a count-only callback can still receive the already pending line event.

Pinned ldo.c:rethook restores the real Lua caller's saved PC on function return
even without return hooks. Completion now performs this metadata update before
retiring the actual frame. The interrupted PC remains pending while a real Lua
hook callback returns; ordinary calls use their executed CALL. Immutable C hook
and collector transports do not create a public function activation and cannot
invent that transition. Result ownership, acknowledgement and delivery remain
unchanged. A same-line native control distinguishes an actual Lua hook return
from the direct C hook callback.

Pinned lcode.c:luaK_storevar writes a constant directly into its local
destination. The canonical compiler formerly emitted a temporary load plus a
MOVE for each simple local literal assignment. Its narrow single-target path
now emits the load into the existing local register, preserving actual executed
instruction counts. Varargs, nonliteral expressions, multiple assignments and
indexed/global stores keep their existing evaluation paths. No opcode listing
is substituted and no hook is suppressed to obtain the expected sequence.

Sixteen separately named AUnit cases cover five actual C hook transitions,
two Lua callback transitions, literal count events, captured integer/float/
binary-string/boolean/nil cells, callback RHS ordering, multiple RHS ordering
and indexed-store metamethod behavior. Default tests explicitly install the
real selected-provider C test adapter for the C hook cases; they do not claim
that a T-absent native interpreter executed those controls.

Both configurations pass all **2,400 AUnit cases**, all twenty-six ordinary
standalone C consumer executables and the retained 36-case canonical campaign.
The private T buffer caller also passes in T. The Lua fixture matches all four
actual producer/VM roles in each configuration with stdout SHA-256
`4fb07707e7d56abfafe5779d5fc5b8b6c68fe5a4b186aa20d157036582b87540`.
The actual C hook fixture matches all four matching T producer/VM roles with
stdout SHA-256
`25054fbf435106f0e9861a521ab27b9accd7428dae01aac3da9bc8d6f5ce98c3`.
Its Ada VM roles use the actual T-enabled conformance launcher, rather than
a probe without the adapter. Native default has no T hook-command provider;
the default Lua fixture and explicit-adapter AUnit cases retain that distinction.
The unchanged default db.lua wrapper still produces its previous native-matched
stdout SHA-256 `61d58565c89cd99626c0a10641e6e8a14303a560258ef302fc6b9915e7724897`.

A disposable copy of the separately reviewed API equivalent retains source
SHA-256 `c360ae605ad7d2e7935a38ad684a5bb0fd081e59d6d3cc397527864f75cc77d3`.
Its actual T execution passes the original hook block and advances to generated
line1331, corresponding to original line1306. T.testC on a fresh independent
state under T.alloccount(0) raises "not enough memory" instead of returning
false from rawcheckstack. This whole-file run fails. It then reports 35,227
selected bytes in 88 blocks: the throw bypasses the script's later explicit
T.closestate. The valid diagnostic run records five managed and nine provider
refusals and a 2-GiB ceiling. These are failed progression/cleanup observations,
not passing whole-file evidence. An earlier diagnostic used an invalid telemetry
run ID; it was repeated with a valid UUID and is not used as cleanup evidence.

The default runtime initially rejected a redundant Positive conversion under
the retained warning-as-error policy. Removing the conversion corrected the
cause; the six strict runtime, tests and C consumer builds then passed serially
in the default and T configurations. GNAT16.1.0, Ada2022, runtime checks and all
required warning/style switches remain enabled. Build slots were explicitly
released before immutable-image execution.

A bounded Haiku source review used no tools and cost USD0.0084618. It reported
no high-confidence issue and asked about two surrounding-code conditions.
Independent inspection confirmed that the Assignment branch reads neither
Count nor Open_Last afterward, and Hooks.Enabled means an installed Lua or C
hook, rather than only a return mask. Both concerns are resolved by the actual
source, without weakening checks.

Local reports/debug-metadata/hook-transition-* retains before/after traces,
strict build logs, AUnit/C results and binary crossing evidence. References and
their pins remain unchanged. This component supplies no whole-file, final-head
or platform acceptance; remaining T API C-entry and memory-refusal work stays
required.
