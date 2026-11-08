# Panic callbacks and shared test-provider refusal

Date: 2026-11-08, Asia/Tokyo. Component checkpoint within the approved complete
remaining-suite delivery. Source base d6e5ee8; final target acceptance open.

## Implemented behavior

The public T command driver adds alloccount and loadfile, reaching 96 of the
pinned runC's 98 nonempty command names. This is implementation inventory,
not 96 independently passing contracts. Traceback and private printstack remain
outside this checkpoint. The source manifest records the derivation and changes.

Checkpanic creates an actual independent state with the parent allocator,
installs a real panic C function, and catches its C-owned return jump. Jump
context setup and parent result publication are protected so constructor/setup
or publication refusal still releases child ownership. Ordinary public APIs
execute every command; there is no alternate interpreter or private C layout.

Production panic preparation reuses the thread-reset continuation driver and
actual C to-be-closed slots. Lua close handlers finish before the selected panic
function executes, including a closer which replaces the incoming error. Unlike
public reset, panic preserves the final thread status and error. All Ada steps
return before each C callback and before the panic helper's nonlocal jump.
[ADR 0032](../decisions/0032-panic-and-test-provider-controls.md) records the
ownership, alternatives and scope.

The configured launcher's test byte/count controls now apply at its actual
shared provider. Independently constructed states inherit that callback and
cannot bypass the parent test limit. Clearing the test ceiling preserves the
separate configured host ceiling. Provider measurements include actual inherited
blocks and raw external payloads; named heap-object counts still describe the
actual Ada universe rather than fabricated C type tags. Production owner
selection and unconfigured AUnit owner controls retain their existing behavior.

A registry-bound light C leaf transports allocation count as a scalar. Direct
invocation preserves/restores the command caller's slot 1 without allocating a
Lua call activation while growth is refused. Remote modules receive that real
function and owner binding through public API calls, without cross-world xmove.

The child zero-count test exposed fresh canonical register-list and action
copies on every call. Calls/returns now copy directly into retained rooted
packets, and invoke actions borrow that packet while publishing the actual
callee. Helper/return actions keep independent copies where retirement needs
them. The cleanup sweep then exposed pcall's copied arguments and separate
error-vector allocation before protection. Pcall reuses its owned arguments;
recovery adopts abandoned argument/result capacity for false/error. Cached
frames reclaim empty retained result storage when their argument buffer was
consumed, permitting the next control call to clear refusal without growth.

Unrepresentable userdata reports the ordinary runtime error "block too big"
before a provider request. The existing internal oversized-payload regression
keeps its zero-growth assertion and now checks that error class/text instead
of its former memory-error expectation. The pinned native T witness requires
this distinction. The overflow bound uses the actual Ada object type; exact
private C header geometry is not claimed.

## Verification

Windows x86-64 Alire 2.1.1, GNAT 16.1.0 and GPRbuild 26.0.1. Default and
upstream-test static root, tests and C consumers use the strict warning/style
flags and enabled runtime checks. Earlier potentially overlapping build claims
were discarded and replayed under a centrally granted exclusive build lease.
All six source-final builds pass with inspected diagnostics. All 1,973 AUnit
cases pass in each configuration, including the fifteen new named cases and
the unchanged 513-position sweep. Each configured test uses the actual common
provider and finishes with balanced physical ownership.

Fourteen cases in tests/lua/public_panic_controls.lua pass unchanged against
the original native T driver and the identical first-party C helper module
compiled separately against the native T shared library. Ada T executes the
same cases. Their raw stdout SHA256 is
0B43D0F01C02F59496F44E3A1320D5EB2ADEE5C3906D5F97C272E36179CDAC57.
The oracle module preserves native T's real allocation controls and userdata
helper; it does not import Ada inspection symbols or interpreter objects.
Nine non-provider cases also pass using that module on native default. Its
ordinary configuration lacks native T's test-provider functions, so this is
a scoped nine-case observation rather than a full fourteen-case default run.

Fifteen separately named new AUnit cases include those behaviors plus a
first-party provider-count sweep from 0 through 512 after a successful warm
panic. The sweep retains all 513 positions and checks each result after clearing
refusal. It covers stronger guarded setup/publication cleanup; the pinned
helper's unguarded jump setup is not its native oracle. Failure diagnostics now
include the position/status/value rather than weakening the condition.
The interposed provider independently requires physical zero blocks/bytes and
no accounting fault after each attached test world is finalized.

All twenty-one executed retained upstream-test C consumer processes pass after
the final source corrections, including buffer, reset/closing, callbacks,
debug, reader/writer, formatting, operators and public file loading. External
strings use the existing ownership-only T counterpart; reset retains its
explicit warning-reentry skip. The native-module host/import campaign was not
rerun. The existing upstream-test telemetry validation also passes normal,
process-exit, runtime-error and real-refusal children plus its negative checks;
the extra provider_refusals field does not replace managed_refusals.

The bounded read-only Claude Haiku audit cost USD 0.03436804, reached its initial
twelve-turn cap and then produced a no-tools conclusion. It established no
correctness bug in the reviewed panic/jump, provider, packet-copy and owner
paths. Its unresolved post-closer status lead became a separate paired ERRRUN
case. This is a scoped sidekick audit, not the final GitHub review.

Changed records pass scoped UTF-8/LF/link/table checks. Two existing overwide
session-index labels were shortened without changing their destinations. The
full documentation checker then stops at the isolated checkout's uninitialized
busted fixture rockspec; that full run is not passing.

## Remaining work

Unchanged soft T api.lua now passes the panic group and loadfile route, then
fails at line 580's fixed-buffer allocation delta below 400 bytes. That exact
storage-shape assertion remains an unreviewed obligation here; no exclusion or
equivalent is granted. Memerr.lua passes its low-memory panic and oversized
userdata checks, then still fails through checkerr at line 7 with a subsequent
"not enough memory" escape. That permanent-refusal behavior remains under
active implementation and is not a passing full-file claim. GDB identifies the
next attempted growth as Canonical.Step's unary-request argument vector for
the scalar `not stat` expression. A zero-allocation primitive path is the next
separate runtime correction; no diagnostic source copy replaces the original.

The custom C hook and external-release borrowed Lua stack-view gaps remain
assigned followups. Fresh coroutine function slots, remaining relevant T
drivers, complete allocator/native-module/platform acceptance and final source
ledger binding remain open. The main-guard C fallback is implemented, but this
checkpoint does not certify every VM-only main-handler forwarding path.
No reference source/pin or conformance obligation was edited. Local diagnostic
artifacts remain under reports/panic-* and reports/api-driver. The full PR,
automatic Codex review, review fixes and authorized merge belong to the
continuing complete delivery.
