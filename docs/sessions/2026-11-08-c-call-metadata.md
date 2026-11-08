# Reusable C call metadata and owned result transport

Date: 2026-11-08, Asia/Tokyo. Component checkpoint; full delivery continues.
Base: e40c847. Toolchain: Alire 2.1.1, GNAT 16.1.0 and GCC 13.2.0.

[ADR 0037](../decisions/0037-reusable-c-call-metadata.md) records the selected
owner pool and transactional frame reservations. Actual allocated frame
capacity, including cached/reset/base owners, reserves stable C call records
plus a host spare. Pure Ada frame creation does not construct a C surface.
Dedicated reset owners preserve previously warmed ordinary call depth.
Generations and owner checks protect intrusive records through nested entry,
frame shrink, typed guard acknowledgement, self-close and abandoned callbacks.

Canonical RETURN publishes its actual scalar range, without controlled Action
or Unwind_Results copies. Completion reconstructs only a required owned result
packet, preserves scalar hook/close mutations and retires duplicate roots
before callbacks collect. Both actual root/context result owners retain their
already-sized arenas; genuinely larger cold results still transfer ownership.
Real copy/clear passes remain charged to the shared bounded budget.

Owned Lua windows prepare physical backing for their actual end plus public
Minimum_C_Stack, without publishing semantic top/bound/window changes. Parallel
value/cell/close-link refusal is transactional. Primitive equality uses the
existing comparison when no handler can apply; distinct table/userdata handlers,
NaN and mixed integer/real semantics remain on their actual paths. Bounded
string equality charges its possible byte scan.

Successful assert returns its actual complete tuple using owned storage. The
missing/nil/false diagnostic paths are unchanged. A saved real C assert pointer
publishes into its caller's original argument span without early close calls.
The marked-slot control preserves identity/top until normal outer C return,
closes once and then permits its return hook to edit the outgoing tuple.
Hook events reuse the traced @hook owner's argument buffer. Suppression is
published only after that owner exists; a refused cold owner allocation no
longer suppresses a later healthy hook installation.

Final serialized default/T runtime, nested-test and C consumer builds pass
with the required warning/style/runtime checks. Both configurations pass all
2,448 AUnit cases: 28 new metadata/backing/equality/tuple behaviors and six new
C hook/assert controls, including a 64-position cold refusal/reinstall sweep.
All 26 ordinary default C consumers and 27 instrumented consumers pass without
flags. The native-module host campaign is separate and was not rerun here.
The six new C cases 30 through 35 independently compile with strict public-header C
flags and pass unchanged against both native configurations, with balanced
provider teardown. Original retained refusal/hook/closing assertions remain.

All seventeen Lua cases in tests/lua/call_metadata_windows.lua pass with native
T and Ada T, including unchanged deep(4)/M=0 first and nested entries, numeric
errors, false results, actual byte ceilings, repeated calls, live-record shrink,
successful assert nil tuples and an independently owned fresh state's failed
rawcheckstack. Native/Ada-produced binaries each execute under both VMs with
matching raw stdout SHA256
F95C9FC7342573AF0AF5348C7DB9F02C554404A8C5B71461FEC3A70454621D8A,
empty stderr and balanced Ada shutdown telemetry. Default AUnit fixtures install
T explicitly; an ordinary T-absent run receives no credit for these cases.

Mandatory original errors.lua was copied unchanged, SHA256
57BB9CC9E622B16646F5AEC072E4F9295A2401B886E98AD4AF21F4BD5B19F53D,
and replayed with no soft flag in native/Ada default/T, timeout 900 seconds,
selected allocator limit 2,147,483,648 bytes. All four processes exit 0 with empty
stderr. Final Ada default peaks at 1,870,423,829 bytes with zero refusals; Ada T
peaks at 144,937,341 with one actual managed/provider refusal. Both finish with
zero outstanding bytes/blocks, shutdown_complete=true and accounting_fault=false.
Raw output differs only in printed implementation stack depths: native
999961/67961 versus Ada 999965/67965. This records completion and ceiling
preservation, not byte-identical output or final source-ledger acceptance.
Raw process/telemetry evidence is retained in the isolated reports/hook-top
errors-pool-b2414b4abdae466aac06595651a6ebeb directory.

A supplied-diff Haiku review used tools disabled, one turn and USD 0.02229655.
Its real potential empty-arena overwrite finding was corrected by restricting
the zero-result fallback to Count = 0. Other leads were checked against the
actual typed cleanup, scalar-window and reset-owner paths; the cold-hook
recovery witness exposed and verifies the suppression fix. This is focused
review evidence, not the required final GitHub review or allocation audit.

Changed-document encoding/local-link/table checks and git diff whitespace
checks pass. The full documentation checker remains blocked by this isolated
checkout's missing tests/modules/busted/busted-scm-1.rockspec fixture, and is
not reported passing. No reference tree/pin, allocator limit, original warmup,
upstream assertion or source-exclusion decision changed. Full api.lua,
memerr.lua, final-head/platform matrix and aggregate acceptance remain open.

Root's subsequent review identified a cross-owner ABA possibility in exceptional
pump cleanup: generations are per control, so another context pool could reuse
an address with the same numeric generation. The follow-up captures the actual
pool owner and compares address, owner and generation before discarding a call.
Two public nested-context controls grow/shrink real frame pools, transfer normal
or numeric-error results through both guards, and verify healthy reentry. They
exercise ownership/recovery without claiming deterministic identical-address
reuse by the host allocator. The follow-up passes all six strict builds and all 2,450 AUnit cases in
each mode, plus the same 26/27 ordinary C consumers. All nineteen Lua cases
match all four raw T compiler/VM roles, stdout SHA256
97C45B7B97CF39A7AF8126A225A2F43083F4F9078D42BEBA8C7BBB2EDF5C22E3,
with empty stderr and balanced shutdown. Repeated original errors.lua still
completes in all four processes within the 2 GiB ceiling; raw evidence is
reports/hook-top/errors-pool-e6bcef5d188440388403545c9d786b73.

Post-component unreduced memory diagnostics use the existing exact approved
verifier copy, 7,529 bytes and SHA256
880D83E6EE5B5CF621C59D410FA928340375AC4F4191913C8092A5F385BBDA76,
in a fresh disposable suite, with no soft flags, 900-second timeout and 2 GiB.
The first function-call sweep now requires zero allocations and zero extra
bytes. Ada advances through state/table/string/coroutine and materialized
vararg-table sweeps, then fails adapted line 134/original 133's exact b.aloc==3
assertion: actual Ada count 6 versus native 3. No source decision or optimization
was made to match that representation count. The retained vararg values, type
and actual refusal/recovery obligations still require reviewed treatment.
Ada finishes with zero outstanding bytes/blocks, peak 1,063,891 bytes,
10,323 managed and 18,083 provider refusals, shutdown_complete=true and no
accounting fault. Unchanged native T still fails os.tmpname at original 205
with Permission denied. Both whole-file results remain failures. Raw evidence
is reports/hook-top/memerr-pool-fd614c25f682469aadbb49c197f88aad.
