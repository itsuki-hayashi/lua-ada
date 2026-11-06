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
