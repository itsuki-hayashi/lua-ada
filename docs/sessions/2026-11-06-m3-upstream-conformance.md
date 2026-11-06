# Session: Complete M3 Upstream Conformance

Date: 2026-11-06, Asia/Tokyo. Branch: codex/m3-upstream-conformance.
Baseline: merged PR #7, master f7031f522006abfd9e2d3ef28975088984400faf.
Status: implementation in progress; checkpoint results below are partial.

## Authorized target and boundaries

The maintainer selected full M3 coverage and one major implementation PR. Follow
the [acceptance contract](../milestones/m3.md) and
[ADR 0010](../decisions/0010-full-upstream-delivery.md). Keep all remaining
storage/ABI/canonical/collector/library/CLI/coverage work on this branch, with
intermediate verified commits. Do not report completion after a harness-only
slice. No automatic merge is authorized.

Retain pinned Lua 7579fc9d7ed90240487251dfb69168f8e64e9294 and all reference and
ecosystem fixture revisions. Ecosystem source remains outside the work. Existing
587-case/five-file lifecycle results are the historical baseline, not a new
full-suite pass. The C oracle remains a separate process, never the interpreter
implementation.

## Checkpoint 1: classification and linked obligations

The inventory validator now separates reviewed lexical candidates from executed
runtime obligations. Kind-restricted classifications retain independent review,
applicability and direct same-file links. Graph validation rejects missing/self/
cyclic/classification-only/cross-file links, incomplete applicability and fake
whole-file stamping. A generated template needs an expanded reviewed block;
only independently reviewed inert quoted data has no runtime target. Final mode
requires all targets' real runtime evidence. API validation remains separate.

All 4,490 original source anchors and 473 API entries remain byte-unchanged and
pending. No harness check edits them or turns a T-absent early return into a pass.
The initial code/test work changes no production Ada unit or fixture pin.

Executed commands at this checkpoint:

- scripts/test-conformance-inventory.ps1: 62 focused cases passed, including 21
  new named/commented classification and linkage regressions.
- scripts/check-conformance-inventory.ps1: 34 source files, 4,490 anchors and
  473 header entries structurally valid; all 4,490 source anchors pending.
- Final inventory completion deliberately remains rejected until actual source,
  API, configuration and platform evidence is complete.

The checkpoint 1 inventory contributor ran no Alire builds and makes no new
runtime, ABI, full-suite, proof, fuzz or documentation-rendering claim. Root
integration records subsequent baseline/build and runner results separately.

## Remaining work and next action

Complete the runner acceptance contract and merged baseline verification, then
implement allocator-aware indexed storage and the real C-boundary pilot before
canonical migration. Follow M3-FULL-2 through M3-FULL-8 without replacing their
runtime evidence with structural inventory results. Preserve exact commands,
tool versions, failed cases, seeds and next actions at each implementation
checkpoint. The final handoff requires complete coverage, all 26 contexts and
one ready, unmerged PR against master.

## Runtime ownership and mathematics checkpoint

The merged baseline passed scripts/check.ps1 -Profile validation -LibraryType
static: 587 AUnit cases, 35 CLI cases, eight differential scripts and the five
selected unchanged upstream files. This is retained subset evidence only.

Implemented owner-specific storage subpools, managed vectors/byte buffers,
allocator accounting/refusal controls, stable managed Lua string payloads and
actual pointer-based light userdata/upvalue identities. Table lookup now uses
dense integer indexes and hash chains. Deleted rows are recycled on insertion;
collector ownership vectors compact in one pass. The remaining allocator audit
still includes other runtime/frontend vectors and temporary conversions.

A strict validation build and normal process exit passed 675 AUnit cases, with
zero failed assertions/unexpected errors, in reports/m3-checkpoint-aunit.log.
This includes 88 new cases beyond the merged baseline: 17 storage, 17 vector,
12 table-storage, 38 mathematical and four managed-runtime cases. Subsequent
buffer/loader/source/codec/driver additions require their own run.

The earlier 614-case assertion run hung during process finalization and was
stopped; it was not accepted as passing. Inspection of the selected GNAT runtime
showed that a raising object finalizer precedes subpool-list detachment. The
owner cleanup now completes that detachment before propagating the exception;
a rerun passed all 614 cases and exited normally. A separate counted-element
case protects finalization ordering between managed vectors and their buffers.

The real Ada-backed static C consumer passed eleven named cases in
reports/m3-c-api-static-consumer.log, including persistent refusal at all 17
cold-construction growth points, balanced cleanup, guarded live refusal/recovery,
empty initial libraries, stacks, numbers, binary strings, raw tables, threads,
registry/extra space and C-owned error transfer. Startup exposed a C tail-padding
mismatch which was repaired before acceptance. C iteration also required
converting Lua next's terminal nil packet to C lua_next's zero-result return.
The corrected fixture was independently checked against pinned C Lua.

This is a C-interface pilot, not complete callback/unwinding, allocator, C API,
shared-library or platform acceptance. The universe descriptor, remaining
containers and some transient conversions remain on the allocation audit.
The public header copies are unchanged and hash-matched to the pinned source;
production C builds do not include reference interpreter source.

Conformance inventory tests pass 62 focused cases with all 4,490 source anchors
still pending. Both C configuration runner builds pass 40 focused harness cases,
including real managed refusal telemetry. Documentation checks cover 61 Markdown
files. Current canonical codec and resumable-driver work remains in verification;
no new whole upstream file or full M3 completion is claimed.

## Owned frontend and canonical execution checkpoint

Implemented the managed frontend arena and single shared scanner, canonical
compiler/model/codec, scalar-register execution through the iterative scheduler,
real ordered capture cells and source/local/upvalue metadata. Shared wrapper
ownership keeps a canonical graph alive while any closure/frame retains it;
operation pins and construction epochs protect allocation retry. Collector roots
honor the active canonical stack top and authoritative open cells. Nil/false
close initializers create no closing obligation. Close snapshots separate an
exiting stack value from a mutable already-closed upvalue.

Strict intermediate checkpoints passed 734, 742, 760, 762, 788, 806 and 814
AUnit cases with normal process exit. The initial 720-case run had one failure:
End_Operation omitted clearing program pins. The corrected lifetime has a
focused regression. The first canonical integration ran 788 cases with two
failures (stale high registers retaining weak values; debug using the old symbol
map). Real stack-top tracing and canonical descriptor names fixed both; all
788 then passed. Eight further inspection/result-boundary cases passed in 814.

The full retained pipeline initially rejected valid math.random()/randomseed()
before native dispatch, then exposed the Windows luaconf C89 log(x)/log(2)
branch. Both were fixed without masking floating bits or relaxing the fixture.
Two separately named Lua-facing RNG tests protect the dispatcher boundary.

Executed final checkpoint command:

- scripts/check.ps1 -Profile validation -LibraryType static: PASS, 816 AUnit,
  zero failed assertions/unexpected errors, Ada consumer, 35 CLI cases, nine
  differential files and five unchanged upstream files. Exact log:
  reports/m3-pre-portal-check5.log. The expected invalid-option check returns
  failure intentionally; the overall inspected script exits zero.
- The five upstream targets remain tpack.lua, utf8.lua, bitwise.lua, goto.lua
  and coroutine.lua. Their earlier configured timeouts and T-absent omissions
  remain unchanged. This is no additional whole-file/full-suite claim.
- Owned-frontend differential: PASS, 85 opcode entries/4,096 words, 10,000 lexer
  byte inputs, 2,000 grammar cases, 2,000 mutations and all 34 upstream lex/parse
  inputs; reports/m3-owned-frontend-differential.log. No Lua executed there.
- Canonical four-way default campaign: 36 cases pass, comparing C source,
  C execution of Ada chunks, Ada execution of Ada chunks and Ada execution of
  C-produced chunks; reports/m3-canonical-four-way-default.log. Each process is
  independent; report artifacts retain fixture/executable hashes and captures.
- Standalone codec campaigns passed against both C profiles: 16 exact native
  roundtrips, eight stripped crossloads and an Ada-built chunk executed by C.
  Instrumented Ada execution remains unverified at this checkpoint.
- Documentation checker: 64 Markdown files pass. Git whitespace checks pass.

Tool versions remain Alire 2.1.1, GNAT 16.1.0, AUnit 26.0.0 and GPRbuild package
26.0.1/banner 26.0.0. This is Windows/default/static validation evidence only;
strict flags/runtime checks and the existing floating-validity exception remain.
Source-selected configuration files are first-party inputs, not edited generated
Alire state. A sandbox-only build attempt could not access the installed Alire
settings and tried MSYS2 setup; existing-toolchain escalated builds supersede it.

Next: complete the C-owned callback/reentry portal, move remaining runtime
containers to the owner, migrate normal compilation, and continue the remaining
M3 gates. The unified Ada/C runtime image, full C surface, T adapter, additional
libraries/collector behavior and final 26-context coverage remain open. Keep one
major PR and do not present this checkpoint as complete M3 acceptance.

## Normal canonical execution and runtime ownership

Normal CLI/session compilation now emits canonical words. The first full AUnit
migration run passed 814 of 817; three assertions required real call-site name
inference and closing-variable names. Lazy inspection now reads the actual
saved caller word and reaching definitions only when requested. Short method
keys emit real SELF instructions. The repaired normal-backend pipeline passes
818 cases and all retained API/CLI/five-file/nine-differential checks in
reports/m3-canonical-default-check1.log.

All twelve remaining Engine vector families and three legacy compiler worklists
now select explicit universe owners. Constructors bind contexts, frames,
objects/prototypes and packets; no implicit global allocator fallback exists.
The collector uses intrusive object/prototype queues without scratch allocation,
including emergency collection after refusal. Interrupted marking clears colors
and links safely. Finalization releases retained registry capacities before
closing storage. Six new runtime and four generic cases protect these changes;
existing leak assertions were preserved. reports/m3-managed-runtime-vectors-check1.log
passes the complete retained pipeline with 829 AUnit cases and 65 Markdown
checks, again Windows/default/validation/static only.

The actual C-boundary pilot passed seventeen named cases before that managed
migration: real C callbacks, mutable upvalues, table error objects, nested C
calls and canonical Lua-to-C dispatch. Windows standalone-library partial linking
exceeded normal COFF's section count; its configured BigObj partial-link output
fixed the format limit without disabling any Ada compiler/runtime check.
reports/m3-foreign-portal-c-consumer3.log is the earlier seventeen-case result.
The current managed-container revision is being rebuilt/retested separately.

Implemented Lua-facing string.dump over the selected actual prototype subtree,
native binary recognition in ordinary compilation and mode-filtered load,
initial capture environments and correct nested-function debug classification.
Binary interpreter prefixes drop their LF so native alignment starts at the
signature. Sixteen named public-session cases and three source cases pass within
848 total AUnit cases, with zero assertions/errors and normal exit in
reports/m3-binary-runtime-aunit2.log. Its full API/CLI/upstream pipeline remains
pending; no new whole upstream file is claimed from these component results.

Remaining allocator obligations include numeric/format Big_Numbers scratch,
some large temporary String views/snapshots, unbounded error/output metadata,
bootstrap storage and allocation-free reserved error packet transfers under
sustained refusal. Owner coverage does not establish full memerr.lua parity.
C message handlers/continuations, unified runtime image, additional runtime and
library features, full instrumented coverage and final platforms remain open.

The verified first checkpoint was published as commit
16bc2aac953642f44a6505eabe0b3537f13581b8 in
[draft PR #8](https://github.com/itsuki-hayashi/lua-ada/pull/8). It is deliberately
not ready for review. The configured local 1Password signing helper failed with
"failed to fill whole buffer"; the authorized GitHub connector created the
commit instead. The remote tree was checked byte-for-byte against the staged
tree b80d4947a5e271ca428dff4db6bb5d9eaf1677c6 before the local branch was
aligned, preserving all subsequent working changes. No signing configuration
was changed and no merge is authorized. Further changes remain on this branch.

## Binary pipeline and first checkpoint CI

reports/m3-binary-runtime-check1.log passes the full retained validation/static
pipeline with 848 AUnit cases, Ada consumer, 35 CLI cases, nine differential
scripts, five upstream files and 65 Markdown checks.
reports/m3-binary-cli1.log adds ten same-host C/Ada native binary comparisons:
plain/BOM/interpreter prefixes, named varargs, initial environments, and Ada
dumps consumed by both interpreters. These results add no whole upstream file.

Published commit 16bc2aac953642f44a6505eabe0b3537f13581b8, CI run42190300713,
completed twelve Linux/Windows jobs. All six macOS jobs passed 816 AUnit cases
and then failed the same mathematics_campaign.lua comparison at byte13748:
C sin(0/0) retained positive NaN, while Ada had synthesized x86 negative NaN.
No exception was accepted and no expected bits were masked. The source repair
uses a tiny native arithmetic quotient plus host fmod; focused regressions and
a complete matrix rerun remain required. The static-validation job also lacked
its later conformance artifact because the earlier failing command stopped it.

## One runtime image and real debug ownership

The unified production root liblua passes static/shared real C, mixed Ada/C
state/pool/callback identity and C-only startup consumers. The tested GNAT
elaboration counter is one. See ADR0014 and reports/m3-one-core-production-
static-check3.log, reports/m3-one-core-production-shared-check2.log. The three
new native-arithmetic regressions pass within 851 cases in
reports/m3-one-core-aunit.log. Legacy c_api/lua_c_api.gpr forwards to the root.

Common initialization now owns the actual registry for both Ada and C states;
the C constructor no longer replaces it. Primitive type metatables share real
number/function families and are traced per universe. Debug metatable bypasses,
getregistry and upvaluejoin operate on those tables/cell references. Missing
setupvalue arguments fail distinctly from explicit nil; invalid upvalueid
indexes return one nil as in pinned C Lua. Fifteen independently named public
session cases pass within 866 AUnit cases, zero assertions/errors, in
reports/m3-runtime-inspection-aunit1.log after strict build3. Build1/2 exposed
only Count_Type visibility, Ada2022 aggregate syntax and line/comment style;
these were corrected without disabling diagnostics. reports/m3-runtime-inspection-check1.log passes the full retained pipeline:
866 AUnit cases, eighteen C API consumer cases, mixed/C-only core image checks,
Ada consumer, 35 CLI cases, ten binary CLI comparisons, nine differential files
and the five retained upstream files. No new whole upstream file is claimed.

## Protected errors, managed numbers and table algorithms

The handler checkpoint passes 877 AUnit cases and 26 real C consumer cases
(reports/m3-message-handler-aunit2.log and c-consumer2.log). Recursive handler
dispatch now returns to the scheduler before further calls, preserving ordinary
recovery when C-depth checks fail. New cases cover handler timing/inspection,
closing, GC, nil normalization, ERRERR, nested C guard application, independent
states, panic after Ada return and one continued-refusal protected return.
The measured constructor failure sweep has 25 growth points. This is not full
memerr.lua acceptance or allocation-free execution in every path.

The joint managed-number/format checkpoint passes 916 AUnit cases plus the
retained full pipeline in reports/m3-managed-numeric-check1.log. Thirty-nine
new cases cover managed limbs/parser/formatting, exact rounding, source-byte
charging, refusal recovery and the balanced 250,012-byte hex numeral under
64 KiB managed scratch. The 1,435-line format campaign matches C Lua. ADR 0015
and the numeric/format guides own algorithm and remaining ownership details.

Sorting and real table capacity hints add twenty public-session and four actual
storage cases. Initial runs passed all new cases but exposed the retained
deleted-key churn regression: a recycled dense row needed a sparse bucket, and
its reuse must not grow an empty dense history. Both transitions were repaired
without weakening that assertion. Strict build7 and tests3 pass all 940 cases.
reports/m3-table-algorithms-check1.log passes the retained full pipeline and
eleven differential fixtures, including 465 seeded table-algorithm records.
A separate documentation check passes 72 Markdown files. No new unchanged
whole upstream file is claimed.

Published checkpoint 1e08fd81c9d416d275cc58377f09a7d84f0d9c3b was inspected in
all twelve successful Linux/Windows jobs of run42201161223, including static-PIC.
Its six macOS jobs stopped in new runtime linking/startup. Commit
a334b29c434973a41782d1a35d9bd856e288f0bc exposed the shared failure as missing
@rpath/libgnarl-16.dylib, while static advanced to a mixed-Ada link missing
GNARL. New selected-runtime archive propagation and clean embedded/runtime
search paths are implemented; macOS evidence still needs a successful rerun.
All reference and ecosystem submodule revisions remain unchanged.

## Stable userdata checkpoint

After the 951-case activation-cache checkpoint, the existing real C consumer
was rebuilt and rerun: all 26 cases pass, exit zero, in
reports/m3-cache-c-consumer-build.log and m3-cache-c-consumer.log. This verifies
that foreign callback windows, mutable captures and protected errors survive
frame reuse before extending their value kinds.

One managed discriminated object now owns a stable inline userdata payload.
An actual C-convention long-double/long-long/pointer union supplies alignment;
physical block padding stays separate from logical size. There is no copied
C private header, fabricated pointer or C interpreter link. The object owns
traced nil-initialized uservalues and its metatable. Equality, hashing, weak
cleanup and ordinary metamethod dispatch recognize the new full userdata kind.
An optional first-party metadata cleanup receives a typed release reason;
actual Lua finalizer scheduling and close/disposal reason selection remain
the following collector/lifecycle work.

The strict validation/static build passes in reports/m3-userdata-build6.log.
Thirteen named and commented storage/GC/identity/error cases pass within
964 total AUnit cases, zero failed assertions or unexpected errors, in
reports/m3-userdata-aunit2.log. Initial builds exposed nonstatic private-address
alignment attributes; replacing an explicit alignment expression with a real
C union carrier fixes the representation without warning suppressions.
Expected-error calls were moved from declaration initialization into handled
statement regions, fixing two test-harness exception-boundary errors.

Four valid public-C-API userdata cases pass against separately linked pinned C
Lua and against the actual root Ada library. The expanded Ada-linked consumer
passes all 30 named cases and exits zero in reports/m3-userdata-c-consumer1.log,
after reports/m3-userdata-c-build1.log. Coverage includes actual aligned mutable
bytes, nil-vs-none and set-pop rules, metatable protection bypass and the last
valid uservalue slot. Pinned lapi.c requires a count below SHRT_MAX, hence
32,766 with the default short width. The cold constructor sweep remains 25
measured growth points with balanced release. See [userdata](../userdata.md).

Seven separately built continuation/resume C fixtures also pass against the
pinned C DLL; they are pending Ada regressions, not Ada continuation evidence.
They confirm that immediate child errors in yieldable lua_pcallk abandon its
original C body and invoke K even without an earlier yield. Public K/resume,
shared scalar windows, finalizers, IO/OS, full allocator categories and final
platform/coverage gates remain pending. No additional whole upstream Lua file
is claimed by this component checkpoint.

reports/m3-userdata-check1.log subsequently passes the full retained
validation/static pipeline, exit zero: 964 AUnit cases, real C/mixed/startup
consumers, Ada consumer, 35 CLI cases, ten binary comparisons, eleven
differential fixtures and the five existing upstream files. The printed
invalid-option subprocess failure is the expected CLI rejection assertion.
All result summaries were inspected; diff whitespace validation also passes.

## Shared scalar-window integration

The 987-case helper checkpoint is now integrated into actual canonical and
native/C execution. One context-owned paired scalar/cell arena replaces each
canonical frame's accumulated register and vararg vectors. Calls use absolute
original function slots; hidden varargs occupy the real shifted prefix and
named varargs create their actual table before overwriting extra arguments.
Debug negative local access reads/writes that storage. Native tail calls keep
the logical Lua caller until the native target completes, fails or resumes.
The collector traces the ordered union of live windows, authoritative cells
and host prefixes; temporary component-test root bridges are removed.

Native windows retain the pinned minimum of 20 slots. Initial semantic stack
space is 40 plus five physical extras, and first semantic overflow installs
the 200-slot error reserve. Ordinary Lua calls consume their real overlapping
register extent. Stack limits come from the selected configuration. Protected
failures retire departing windows before writing overlapping caller results;
the still-stacked error packet remains a GC root throughout publication.

Strict build5 and tests4 pass all 1,009 AUnit cases, zero failed assertions or
unexpected errors. Commands: alr -n -C tests build --validation
--profiles=lua_ada=validation, then alr -C tests exec --
bin/static/test_runner.exe. Evidence: reports/m3-shared-windows-build5.log
and reports/m3-shared-windows-tests4.log. Both new C cases were independently
checked against pinned C before integration; the complete Ada-linked consumer
and retained pipeline pass in reports/m3-shared-windows-check1.log: C32,
mixed/startup, Ada consumer, 35 CLI cases, ten binary CLI comparisons, twelve
differential fixtures and the five retained unchanged upstream files. The
printed invalid-option subprocess failure is the expected rejection check.

Initial integration caught protected-result clearing after overlapping return
publication and a test helper replacing only one half of the paired arena.
Both ownership transitions were corrected. table.unpack had two fast/handler
paths still using summed private slots; both now reserve actual native result
space before looping, through the common nonthrowing stack check. The retained
overflow regression now checks pinned C's own 'too many results to unpack'
diagnostic, dead coroutine and recovery, rather than private-backend wording.
Both C configurations independently return that failure. A separate emergency
GC test originally used a freed address as proof of reclamation; an arena
allocation can legitimately reuse it. It now checks the immutable object
serial in the actual heap, preserving reclamation and paired-growth assertions.

Run42207946868 at a4e5e338a27630bd077bc7f7fe294500f10162b7 passed all six
macOS jobs; each log was inspected. All six Linux jobs exposed the libc
alternate-general carry difference repaired in the later 968-case local run.
That repair and the shared-window implementation need fresh platform evidence.
Remaining C continuations, call-origin accounting, allocation-free span
transfers, physical cache/arena shrinking, collector modes/finalizers, IO/OS,
full ABI/adapter/coverage and final platform gates remain open. No additional
unchanged whole upstream file is claimed.

## Runtime inspection, output and Windows unwind checkpoint

Published checkpoint5 is 9377f4fd00cce2900b27dc1e6cf77b13b653d8d4, tree
afd2217cf12efd7922d02d921e26ecf3b3574dd9. All18 jobs of run42217665982
pass and their full logs were inspected: 1,009 AUnit cases, C32/mixed/startup,
35 CLI cases, ten binary CLI comparisons, twelve differential files and the
five retained upstream files. All six Linux jobs now pass both formatting
campaigns. Windows static-validation also passes static-PIC. Checkout logs
confirm actual PR merge9ec297c6 combines that head with baseline f7031f52;
report revision and workflow head fields intentionally identify different Git
objects. Native C aggregate observations on macOS still fail unchanged
main.lua207's dynamic-readline warning assumption under pinned static readline;
the original fixtures/configurations remain unchanged and M3 acceptance=false.

The next local group adds debug.getuservalue/setuservalue for actual traced
userdata slots and raw registry-selected initial global environments. Eight
focused userdata cases and four independent environment cases pass within
1,021 AUnit cases. A separate real C probe confirms all eight userdata and
three valid-domain registry scenarios against default and upstream-test DLLs.
The host Set_Arguments scenario is an additional Ada ownership regression.
No cached bootstrap global pointer remains as a separate immortal GC root.

Output delivery is now explicit. Ada sessions initialize/reset to Captured;
the CLI and C-created states select Process_Streams. A single byte producer
checks bounded quotas before each fragment, uses actual native stdio for
process writes, and never replays those bytes as captured output. Compatible
policy avoids an unbounded counter. Seventeen named AUnit cases and nine
raw-byte processes cover callbacks, errors, policy changes, reset, quotas,
NUL/0xff bytes and version ordering. GNATdoc guidance was applied to adjacent
public API comments; documentation generation itself was not run.

Strict reports/m3-output-policy-build3.log and tests2.log pass1,038/1,038,
zero failures/errors. reports/m3-output-process-tests1.log passes all nine
process cases. The first complete pipeline exposed a Windows native unwind
crash during the retained protected allocator-refusal case, before emergency
collection or error publication. BigObj inspection found merged C .pdata
references pointing at the first text/xdata section rather than their actual
merged offsets. A guard-only executable reproduces the crash without any
preceding constructor sweep, ruling out earlier cleanup corruption.

Windows x64 C function sections now preserve unique unwind relocation targets
through the SAL partial link. The actual C32 consumer and isolated guard pass;
the new PE structural checker rejects the saved broken image and validates
disjoint ranges in repaired images. Eleven portable parser regressions cover
malformed/overlapping metadata. Ada -Es tracebacks, strict flags and runtime
checks remain unchanged. ADR0014 and the one-core guide own this narrow repair.

reports/m3-output-policy-check2.log passes the complete validation/static
pipeline: 1,038 AUnit, real C32/mixed/startup, Ada consumer, eleven PE cases,
nine output processes, 35 CLI contracts, ten binary CLI comparisons, twelve
differential fixtures and all five retained unchanged upstream files. The
expected invalid-option child exits1 as its rejection assertion requires.
Documentation validation passes74 Markdown files. Finalizer queues, real
collector modes, IO/OS, complete C continuations/ABI, actual test adapter and
full-source/platform acceptance remain in progress; their reports-only drafts
are not executable coverage or additional whole-file passes.

## Warnings, borrowed C callbacks and finalizer components

Published checkpoint6, 852aff6196da38fb7bf4eb5ace26efe74cd9f698, passes all18
retained matrix jobs in run42221667221. Every job log was inspected, including
Windows static-PIC, 1,038 AUnit cases, real core consumers and five retained
whole-file executions. This is retained acceptance, not full M3 acceptance.

The next group adds allocation-free warning events owned by actual activations,
traced message roots, exact callback acknowledgements, and nested C/API warning
handling. Pinned Lua5.5.1 auxiliary states start with warnings ON; bare states
have no handler. Eight focused warning cases and four real C cases cover
fragment ordering, literal control messages, nested calls, guarded failures and
zero allocator activity during native warning publication. See warnings.md.

Ada-started execution can now borrow its existing iterative driver through a
C-owned callback guard. Six real C fixture tests exercise Ada-to-C calls,
C-to-Lua reentry, protected error identity, nested host-budget abort/recovery and
warning callbacks. No recursive Machine.Run/Engine.Execute or abandoned Ada
stack is introduced. Exact frame-plus-serial tokens reject stale replies before
mutation. Native top growth/truncation updates the shared scalar window and its
root packet together; three focused cases exercise those ownership changes.

Private finalizer components add allocation-free registration and pending queues,
current-handler roots, protected non-yieldable Lua callbacks, hook suppression
and five-fragment error warnings. Fourteen queue tests and ten runtime tests
cover ordering, re-enrollment, graph liveness, callback errors, hidden scheduler
phases, hooks and host aborts. These tests explicitly enqueue private fixtures;
production metatable enrollment and collector integration are not selected yet.
A userdata whose finalizer is abandoned by a host abort remains usable when
resurrected; eventual physical release invokes its host-disposal policy once.

An initial optional-finalizer retry loop could starve the interrupted script
when native stack space was unavailable. The controller now consumes a single
collection request, defers the queue and lets the caller progress. A named
regression proves progress and later successful collection. Schedule also
restores the argument packet's allocator owner before copying into a reused
activation; assigning an empty vector had previously lost that owner.

Exact latest commands:

- alr -n -C tests build --validation --profiles=lua_ada=validation
- alr -C tests exec -- bin/static/test_runner.exe
- pwsh -NoProfile -File scripts/check.ps1 -Profile validation -LibraryType static

reports/m3-finalizer-driver-build5.log and tests5.log pass1,086/1,086, zero
assertion failures or unexpected errors. reports/m3-foreign-finalizers-check2.log
passes the complete retained pipeline, including the 39-case C consumer and
five unchanged files. The expected invalid-option child exits1. Optional
GNATdoc generation, fuzzing and proof were not run. Remaining collector, native
continuations, IO/OS, complete ABI/test adapter, full-source coverage and final
26-context acceptance are still open; this checkpoint is not final handoff.
