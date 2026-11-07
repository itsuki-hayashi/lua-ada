# Independent events/API/harness review — 2026-11-07

Reviewer: `Codex /root/review_events_harness`, independently assigned after
explicit user authorization. Original implementation/candidates author: Codex
parent agent. Reviewed implementation checkpoint:
`810e25466e3ccec973b4085b9f7298d5592fa3f1`. The findings below distinguish that
checkpoint from subsequent fixes authored by this reviewer. This artifact is
not full scoped acceptance, and does not approve the reviewer's own fixes.

## Source and semantic inventory

Reviewed the complete pinned `references/lua/testes/events.lua`, SHA-256
`90449c1607a12a7c1841123a68237e0d23b7d6e109b8c445937fcd99306897c9`, at reference
revision `7579fc9d7ed90240487251dfb69168f8e64e9294`. Independently recomputed
all 19 contiguous section hashes in `events.candidate.json`; all match the
original bytes. The sections correctly enumerate the actual helper calls,
mutating partial-order comparisons, operand-type checks, raw equality and
key identity, chained delegation, concatenation, basic-type metatables, and
terminal receiver identity. The candidate is accepted as a semantic inventory
of this source, not as execution coverage or proof of all metamethod behavior.

The two T obligations are distinct. Lines 328–356 allocate real full userdata,
exercise uservalues, left/right equality selection, and table-valued userdata
delegation. Lines 382–393 silently omit allocator refusal without T, although
the assignment loop still executes. A default file's single printed omission
must therefore link both obligations to accepted instrumented evidence. No
default run can establish the second obligation merely by reaching `OK`.

Read the relevant production dispatch in `lua-engine-machine.adb`: raw lookup
precedes delegation; functional newindex receives the current delegated
receiver; comparisons reverse greater-than operands before selecting handlers;
equality retains identity/type fast paths and left-before-right selection;
unary handlers duplicate operands. Read the table writer's publication barrier,
allocator retry path, and the separately named refused-weak-set adapter case.
No additional events semantic mismatch was demonstrated in this review.

## Actual evidence inspected

Inspected the 18 Ada events reports retained beneath
`reports/ci-artifacts/810e254-*`, belonging to CI run `42283072557`. Each reports
the exact clean checkpoint above. All five available instrumented contexts
(Windows static, shared and static-PIC; Linux static and shared) report T
available, unchanged execution, successful completion, and exactly one actual
managed allocation refusal. The 13 default contexts report T absent, zero
refusals and the explicit userdata omission. They are incomplete T evidence.

The parent retained and checked all 72 C/Ada file/context pairs for these 18
contexts. This review does not convert their process observations into accepted
coverage records. The eight macOS contexts and final post-fix revision evidence
remain required. Historical reports lack the probe telemetry added below.

## Scoped public API mapping

Independently checked that `api.candidate.json` assigns 77 unique scoped IDs
exactly once and that every recorded C test-source hash still matches. Read the
named assertions in `c_api_consumer.c`, `gc_contract.h`, `io_contract.h`, and
the test adapter's public userdata/warning callbacks. The 11 groupings are
accepted as scoped behavioral mappings, subject to these explicit boundaries:

- Allocator cases establish actual construction/refusal/recovery and release;
  setting the same allocator/data does not prove arbitrary allocator swapping.
- Stack, byte-string, raw-table and userdata assertions exercise concrete
  values, stable payloads, invalid index results and actual public callbacks.
- Callk/pcallk coverage is synchronous/nonyieldable. It does not close general
  continuation or arbitrary yielding C callback obligations.
- Warning cases test literal fragments, data identity, nested callbacks,
  protected errors and allocation-free dispatch. The selected test warning
  handler additionally needs the gc.lua review and enabled-warning execution.
- The public GC contract measures bytes, mode returns, stopped stepping,
  callbacks and physical close; parameter round trips alone do not establish
  every collector parameter's scheduling meaning. The collector reviewer owns
  the phase/age/parameter semantic findings.
- The IO contract proves actual FILE/closer layout and callable openers, not
  all buffering, platform, calendar or shell semantics. Those remain covered
  by the file review and native counterparts.

These decisions approve the *mapping*, not all API execution evidence. Final
ledger entries must name the particular cases and exact-revision artifacts in
every applicable context; compiling a header name is not an API pass.

## Findings and follow-up

1. **Required fix: scoped launcher probe shutdown was unverified.** At the
   reviewed checkpoint `run-conformance.ps1` installed telemetry only before
   the selected file, after parent/bare/arg configuration probes. The matrix
   rechecked their output but had no physical-shutdown records for those
   sessions. This reviewer authored a fix using a separate probe run ID and
   prefix, hashed retained sidecars, unique PID checks, recorded-parent
   membership, exact five-Ada/two-C cardinality and allocator/shutdown replay.
   The parent cross-reviewed the structure; real post-fix runs remain required.

2. **Required regression protection: actual events refusal witness.** T
   presence and `OK` alone would permit a no-op allocfailnext adapter. Available
   instrumented evidence actually records one refusal. This reviewer added a
   Ada production completion requirement of at least one refusal and a negative
   zero-refusal case. The C oracle refuses inside ltests below its outer wrapper
   counter, so its wrapper may correctly report zero; an explicit positive
   control preserves that distinction. This edit needs cross-review and final execution evidence;
   it is not retroactive acceptance authority for historical runs.

3. **Acceptance authority remains insufficiently bound to review artifacts.**
   `New-ConformanceEquivalent.ps1` checks accepted status and nonempty reviewer,
   author and artifact strings; `Assert-MatrixReview` similarly checks metadata.
   Neither proves the named artifact exists, is unchanged, or approves the
   exact source/replacement decision. Current records are pending, so this has
   not produced a claimed pass. Before closure, bind the review artifact by
   path and SHA-256 and validate its source/span/generated-output identities,
   reviewer and explicit relevant decision. Avoid a circular hash dependency
   between a manifest and its review artifact. This gap is reported to the
   parent. Subsequently, at the parent's request, this reviewer authored
   `ConformanceReview.psm1`, generator/matrix integration and 30 binding
   regressions. The concrete schema is documented in this directory's README.
   This fix remains reviewer-authored and needs separate cross-review; no
   pending production mapping was promoted by these changes.

## Independently reviewed buffering counterpart

Cross-reviewed `platform/unbuffered-visibility.lua`, authored by the files
reviewer. It opens a writable stream, enables no buffering, opens a second
real handle, writes 13 bytes including NUL, and requires the reader to see
those bytes before either flush or close. It then closes both handles and
removes the temporary file. This is a valid direct observation of unbuffered
visibility, unlike the upstream read-only example whose failed write is ignored.
This reviewer wired the source-hashed copy into the same measured C/Ada state
before files.lua on every platform, with a required completion witness. The
integration is this reviewer's authored change and requires cross-review;
the counterpart's semantics were reviewed independently from its author.

## Checks of authored harness fixes

`reports/review-probe-matrix-tests.log`: 30 synthetic matrix regressions pass,
including missing/duplicate probe records, wrong probe run, missing recorded
parent, stale telemetry hash, leaked allocation and missing Ada shutdown.
`reports/review-probe-scope-tests.log`: 38 scoped regressions pass, including
missing unbuffered visibility and no-op events fault injection. Synthetic
`reports/review-artifact-binding-tests.log`: 30 review binding regressions pass.
These tests establish validator behavior only. No Alire build was run by this
reviewer, no ledger was promoted, and no complete four-file acceptance is
claimed.
