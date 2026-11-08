# M3 Conformance Inventory

This directory owns the machine-readable source inventory and coverage ledger
for [M3](../../docs/milestones/m3.md), including accepted bounded scopes and
unresolved obligations. It contains no second Lua implementation or altered
upstream source. A completed scope does not establish full M3 acceptance.

The [independent fixed-buffer feature review](targets/remaining-upstream-compatibility/reviews/api-fixed-buffer-private-bound.independent-feature-review.json)
accepts only the exact eighteen-byte private allocation-bound conjunct as
eligible for an instrumented exclusion. The original mixed assertion remains
required. The separately installed exclusion policy and exact transformation
now bind that child to its original bytes and independent approval. The
[exact lifecycle and calls reviews](../../docs/sessions/2026-11-08-exact-api-calls-equivalents.md)
approve source equivalents without excluding their original parents; the API
composition retains the eighteen-byte exclusion as a separate disposition.
Source approvals supply no passing runtime or whole-target evidence. Fresh
execution and final reconciliation remain required.

The [parser-status binding refresh](../../docs/sessions/2026-11-08-api18-binding-refresh.md)
renews the same eighteen-byte policy/transform against the preserved public C
witness header. Earlier review files remain dated evidence. API941/composition
and memory-verifier implementation bindings require separate review after
hook/pool/adapter changes; they acquire no renewed authority through this edit.

The separately authorized [remaining upstream compatibility target](targets/README.md)
can resolve reviewed T-only private checks as explicit exclusions. Its overlay
never changes the strict upstream completion rule or counts an exclusion as a
pass. Existing scopes and source/API anchors retain their historical meaning.

The baseline is Lua 5.5.1 commit
`7579fc9d7ed90240487251dfb69168f8e64e9294`. The unchanged reference source is
under `references/lua`; all offsets and hashes identify that checkout's bytes.
Existing [Lua copyright notice](../../docs/licenses/lua.md) applies to declaration
text inventoried from the upstream headers.

The reference guard rejects staged and unstaged changes to tracked files, all
untracked source inputs, and every untracked or ignored path under `testes/`.
The last rule includes native libraries and extensionless data because the
runner copies that entire subtree. Unrelated non-source build artifacts at the
reference root are allowed; they are not fixture inputs.

## Files and configurations

`suite.json` records all 34 Lua source files and their SHA-256 hashes:

| Role         | Count | Meaning                                      |
| ------------ | ----- | -------------------------------------------- |
| Orchestrator | 1     | all.lua aggregates the normal test order     |
| Primary      | 30    | Files selected by the upstream orchestration |
| Helper       | 2     | tracegc.lua and bwcoercion.lua               |
| Stress       | 1     | heavy.lua has a separate allocator budget    |

Only tpack.lua, utf8.lua, and bitwise.lua carry historical M2b execution
evidence. That evidence names its exact Ada revision/run and T-absent default
configuration. It does not mark their M3 assertion ledger entries complete.

The two configurations are intentionally distinct. The default uses
`LUA_COMPAT_GLOBAL=1`; upstream `ltests.h` changes it to zero and also changes
compatibility math, RNG representation, extra space, buffers, and semantic
stack limits. Default ABI results must not be inferred from instrumented ones.
The manifest records 26 final acceptance contexts: 18 default jobs, six
instrumented static/shared validation jobs, and Windows static-PIC for both.
The logical `shared` context corresponds to GPR's `relocatable` library kind.

`c-api.jsonl` inventories 473 source entries from lua.h, lauxlib.h, lualib.h,
and luaconf.h: 156 exported function declarations, 298 macro definitions,
18 type/layout declarations, and the lua_ident data declaration. Alternative
conditional definitions remain separate entries. The raw inventory is not an
export-symbol pass or proof that a conditional branch is active on every host.

The target-owned
[public SDK macro audit](targets/remaining-upstream-compatibility/public-sdk-macros.author-audit.json)
keeps the original spans for 59 remaining function-like macro anchors and
proposes separately named operations in the installed C consumer source.
The ordinary SDK program and the client opt-in program are separate mains;
the latter selects `LUA_COMPAT_APIINTCASTS` and `LUA_FAILISFALSE` before header
inclusion. Both retain an ordinary public header role when calling a T runtime.
The protocol records the real C89 selection, ordered operations and actual
stringification bytes. On Windows the pinned SDK selects `LUA_USE_C89` even
when the client compiler uses `-std=c99`.

Conditional alternatives retain separate source anchors. Inactive float,
long-double and non-GNU alternatives, later replacement definitions, and pure
stringification eligibility still require independent semantic/applicability
decisions. The audit does not classify them as declaration-only or grant pass
evidence. Its C rows and all 473 global classifications remain pending until
review and fresh paired observations in the required immutable contexts.

The successor author inputs preserve the historical 100 C and 94 AUnit
identities and currently regenerate 605 C and 750 AUnit witnesses. The checked-in
catalogue records its own dated source snapshot and needs regeneration before
reviewing new inputs. Additional return/closing, reader, self-value and diagnostic
cases are named source candidates with empty execution evidence. All 473 global
classifications remain pending semantic review. Regenerating source hashes or
compiled declaration proposals does not renew any independent approval.

The current builtin protocol requires all thirty operations, including actual
injected reader refusal and recovery. Both parser-depth status paths are named
source candidates. External-string observations preserve an explicit argument
array even for a no-argument process, all thirteen ordered ownership/refusal
operations and the five default release-reentry cases. Instrumented native C
instead records its exact ownership-only argument and five-case lock omission;
equal summary counts cannot replace or reorder an operation.

Actual File completion approval requires explicit non-synthetic manifest,
approval and narrative labels, source-only authority flags and empty execution
evidence. Binding regressions may opt into labelled synthetic reviews through
an explicit test-only parameter. The target runner and final matrix never
select that parameter, and raw report fields cannot enable it.

The full twelve-case scalar-closing fixture is a mandatory unfiltered T pair.
Its five T-free public upvalue, mutable-local, weak-root, suspension and jump
bodies also remain byte-identical in an ordinary default companion. Source
classification preserves both routes; it supplies no fresh runtime receipt or
whole locals-source equivalence evidence. The current corpus contains95 Lua
fixtures, with later uncommitted materialized-vararg controls still outside
this dated classification.

Locals counterpart binding version1 keeps its original22 paths and its
independently reviewed dated76 tuple. Current source drift does not renew that
authority. Explicit binding schema2 requires exactly29 counterpart paths,
adding the actual memory checker, both scalar-closing fixtures and the closing
test sources. It retains the same two exact operations, original anchors and
output54481; a pending definition returns only source hashes, never adapted
bytes or runtime authority. New independent exact review and fresh runtime
observations remain required before selecting the successor.

T target contexts also require a separate private-header buffer executable.
It includes the actual pinned `ltests.h`, reports its 23-byte scratch and actual
`luaL_Buffer` layout (56 or 64 bytes on the measured 64-bit hosts), and executes the same 17 ownership,
growth/refusal and cleanup cases as the ordinary SDK client. The default
configuration never builds or executes this smaller receiver. The final
consumer requires the private C/Ada pair even if no individual global API
route selects it. Its declared extraspace value describes the header role;
the buffer witness does not access or certify native T lock storage.

`coroutine_result_portal.lua` is a configured witness: its dedicated native/Ada
campaign measures both executable handshakes and supplies the matching semantic
stack limit (1,000,000 default or 68,000 instrumented). `stack_inspection.lua`
is mandatory in that instrumented campaign with a real T table and all four
ordered operation markers. `primitive_not_refusal.lua` also requires real T;
its six actual scalar/operator cases run through the native and Ada allocator
controls. None of these configured files becomes a default T-absent pass.
The complete T campaign also requires all 22 public API commands, all 14
panic/provider cases, all four reader and four string refusal phases, and all
five actual C-hook transitions.
Optional per-case filters must be absent, and each refusal phase has its own
terminal marker after its unchanged assertions and allocator reset. All seven
T-only files require real T for every operation; no mixed ordinary Lua
assertions are dropped from default execution. The
`targets/configured-fixture-classification.json` source hashes and rationales
bind that classification. Changes require a fresh mixed/default/T source
review. The complete lexical fixture audit fails closed on new T-bearing
files and records every ordinary source as well. Generic fixture selection
derives this classification from the dedicated definitions rather than a
second list of omitted filenames.
`check.ps1` records the default pair before `compare.ps1` consumes its receipt;
`check-instrumented.ps1` records both instrumented pairs. The generic default
comparison requires the dedicated report and its Ada runner explicitly. Raw
reports preserve sources, executables, libraries, arguments, configuration
captures and balanced allocator telemetry. Rejection regressions mutate copies
of actual observations; they do not execute or certify their fabricated data.
Full-target build receipts must reference this separate report. The immutable
image captures it and its raw sidecars as a fifth mandatory build witness;
final replay checks its revision/context and every executable, runtime library
and capture against the frozen file identities. A build log or matching final
marker cannot replace the configured process set.

`table_storage_private.lua` is a separate mandatory **Ada-only** instrumented
counterpart. It calls the actual Ada owned-storage inspector and records all
three initial-live/deleted-key/same-table-reuse phases. No native T facade or
default T-absent result can substitute for that process. Its classification
links the current inspector/probe implementation and22 named AUnit cases as
source identities only; these links contain no execution evidence. The target
build receipt and final frozen-image consumer also require all22 actual named
AUnit observations from the source-bound same-context suite report.
`table_storage_public.lua` retains its three ordinary object-key/liveness
cases in the generic comparison on both configurations.

The full21 `call_metadata_windows.lua` cases are mandatory in the paired T
campaign with real allocator/C controls and no `_CALL_METADATA_CASE` filter.
The two independently ordinary case bodies also execute in
`call_metadata_public.lua` through the generic default comparison. Exact span
hashes and byte equality bind both copies to the full provider fixture, so its
T requirement cannot hide those default public assertions.
`code_public_semantics.lua` also remains an ordinary source comparison; its29
source-linked semantic cases grant no private optimizer exclusion authority.
Every configured context additionally records an actual paired public-code
process and requires all29 actual named AUnit counterparts from its bound
suite report. The generic default comparison still executes this ordinary
file even after validating that separate receipt.

The full10 `canonical_tail_ownership.lua` cases likewise require paired realT
with no `_TAIL_OWNERSHIP_CASE` filter. Its five independently ordinary weak-
argument, hook mutation/error, yield and closing bodies remain byte-identical
in `canonical_tail_public.lua` and execute in the generic default comparison.
Both companions' correspondence checks reject stale, changed or omitted
public bodies; complete T protocols remain mandatory separately.

Eligibility version3 implements only the eight exact pinned `code.lua` private
structure candidates. It requires truthful observable=true, no public/mixed/
module compatibility obligation, exact original-anchor links, fixed semantic
contracts, current independent feature and public-retention decisions, and the
unchanged127-byte `checkR`. All51 original records remain required. V1/V2 and
historical scopes retain their previous meaning. No optimizer exclusion is
installed merely because its shape is supported. The V3 security tests use
labelled synthetic, non-execution reviews through a direct test-only switch;
ordinary inventory and final consumers never enable that switch.

`debug_iterator_counts.lua` also runs in both configured campaigns. Its source
explicitly requires one C-compiled graph when comparing exact hook counts.
The measured native interpreter loads that exact text file and dumps its
complete graph to a binary-mode file. Both interpreters then execute
those same captured bytes, with the complete two-count protocol required.
Producer arguments, executable/configuration, binary bytes, input identity,
raw captures and provider cleanup remain bound in the report and frozen image.
The generic source-compiler comparison consumes this dedicated receipt before
selecting the fixture through this route.

The image transport permits source-shaped evidence only at the exact generated
native-module fixture C paths and stdin source fixture path under a unique
`reports/core-image/` run. Their native-fixture and file-IO consumers retain
independent source/hash/operation checks. Implementation/reference trees and
all other source-shaped image destinations remain forbidden.

## Candidate anchors and manual coverage

The 34 `coverage/*.jsonl` partitions currently contain 4,490 pending anchors.
These include lexical assert call sites, if guards, T member references,
Message references, possible quoted assertion templates, and one compulsory
whole-file semantic audit for each source.

The byte-oriented scanner masks Lua comments, short strings, escaped quotes,
and exact-level long delimiters. It counts CR, LF, CRLF, and LFCR as Lua line
boundaries. Hash spans and offsets use original UTF-8 bytes, not UTF-16 indexes.
It discovers review candidates; it does not parse grammar or establish which
branch executes. An assert-looking string may be data rather than generated
source. Aliases, generated programs, and data-driven assertions need human or
independent agent review and additional obligations before M3 completion.

Each stable ID consists of file, anchor kind, and ordinal within the pinned
source. Whole-file and span hashes prevent silently carrying an old status
onto changed source. After deliberate reference updates, source obligations and
their evidence require explicit review; do not regenerate away pending work.

Manual review may append `reviewed-block` units with IDs such as
`LUA-API-REVIEWED-BLOCK-0001`. They must retain accurate byte span, SHA-256, and
line/end-line citations within that same source file. Regenerated lexical
anchors cannot be deleted or changed. A manual-audit unit remains pending
until all generated/dynamic obligations have been inventoried and reviewed.

A mixed assertion retains its original anchor and its required public runtime
behavior. An independently reviewed private subexpression can be represented
by an additional exact-span `reviewed-block`, with an exclusion targeting only
that child. The original assertion still requires actual evidence as a reviewed
equivalent; the child decision cannot supply that evidence or complete the
parent. An exact empty replacement may remove the private conjunct while the
public assertion and surrounding calls remain byte-identical. Author proposal
files supply no authority. The separate API fixed-buffer feature decision now
authorizes only the exact 18-byte private upper-bound child: a pending derived
record and source-only exclusion preserve the pending original mixed assertion.
Its exact-byte transform manifest binds the installed policy hash but remains
blocked pending independent transformation review. Feature approval supplies no
original-parent execution, whole-file result or final matrix acceptance.

Exclusion eligibility version 1 retains its original interpretation and rejects
module-observable decisions. An explicit `eligibility_schema_version: 2`
distinguishes the factual `module_observable` annotation from
`module_compatibility_obligation`. The latter must be a real false boolean;
public API behavior, mixed obligations, ordinary configurations, previous passes
and accepted source partitions remain protected. Version 2 currently permits
only a derived pure numeric comparison conjunct inside a hashed original
assertion. Calls, statements, another Boolean branch and widening to the parent
are rejected. This is an eligibility subset, not a Lua parser or runtime change.

Version 2 requires an approval with schema version 2 and a separate independent
feature decision. That decision binds the observation/compatibility flags, the
retained parent, exact pinned manual bytes, retained counterpart source hashes,
the reason no public bound is promised, and explicit retained behavior. A generic
private-label rationale cannot replace it. A completed original assertion needs
its own `ada-internal-equivalent` evidence and `source_exclusion_ids` linkage;
alternatively, a reviewed reference must retain an unexcluded runtime child
outside the private span. These rules keep visible implementation measurements
from waiving application failure, cleanup or execution requirements.

The pending `memerr-verifier-allocation.equivalent.author-proposal.json` uses
a separate bounded `t-verifier-equivalent` schema. Its one allowed operation
inserts the literal `T.alloccount()` reset after the original helper's protected
application call and before its unchanged false-status/error-text assertion.
It preserves both application calls, the existing following reset and every
later failure campaign byte. This is a source-equivalent proposal with an
explicit empty exclusion set. Its pinned whole-source hash, exact insertion,
retained source spans and native/first-party configuration counterparts all
bind a separate independent exact review. Pending or labelled synthetic review
artifacts cannot authorize actual replay. The separately approved
`memerr-verifier-allocation.equivalent.json` binds the independently reviewed
17-byte insertion and all seven current counterpart hashes.
`scripts/New-ConformanceVerifierEquivalent.ps1` reconstructs approved bytes
only under disposable `reports/` paths, with a source-only receipt. It exposes
no diagnostic or synthetic approval switch. Global acceptance runners still
require explicit integration and operation evidence; generation supplies no
passing source/file evidence and excludes no obligation. Its focused security
regressions execute no Lua. The current component campaign progresses beyond
the original verifier but fails during the later allocation sweep; see the
[session record](../../docs/sessions/2026-11-08-memerr-verifier.md).

The API941 and calls586 source-equivalent manifests have separate independent
exact source approvals. They use the existing equivalent approval contract,
with the accepted feature decision and actual public-counterpart sources
required for every patch. Original assertions remain required pending
obligations. Source review supplies no passing runtime or ledger evidence.

API also needs the already reviewed18-byte private allocation edit. The bounded
API composite binds both manifests to the same original1601 source
hash, validates each accepted inner review separately, rejects overlapping
spans and applies the original-coordinate union once. It retains exclusion9001
and required original assertions0125/0195, and requires an additional independent
composition approval, now recorded separately from its inner approvals.
Its source-only reader rejects default/native selection,
pending inner approvals, changed replacements, stale policy/counterparts and
fabricated or labelled synthetic authority. Explicit synthetic unit fixtures
remain diagnostic. File selection uses the explicit `ReviewedSourceManifest`
parameter and a separately hashed `reviewed_source` observation identity.
Aggregate selection uses a `reviewed-source` member under its independently
reviewed complete 34-source selection. Both replay the same bounded inner
decisions. The execution contract and post-observation envelope must bind
the exact selected manifest, output bytes, policy and exclusion set. A generic
equivalent selection cannot bypass this route. The bounded
`New-ConformanceReviewedSource.ps1` generator recognizes only this composite,
the decoded-string equivalent and the memory-verifier equivalent. It
revalidates their independent exact decisions and emits new disposable
`reports/` artifacts with source-only receipts; it exposes no synthetic or
unreviewed mode and cannot overwrite prior artifacts. Ordinary C baselines
continue to use original source. Generation supplies no runtime acceptance.

## Resolution and evidence contract

Pending entries have `status: pending`, `disposition: pending`, no invariant,
no applicability decision, and no pass evidence. A foundation check accepts
that honest incomplete state. It never calls pending assertions passing.

A completed source entry must name an invariant, applicable configuration IDs,
independent review author/reviewer, rationale, and review artifact. Its
disposition is one of `unchanged`, `ada-internal-equivalent`, or
`native-platform-equivalent`; whole-file inventory audits use
`inventory-reviewed`. Every completed runtime source record, including an
unchanged assertion or block, also requires `review.original_c_evidence` for
the original C result. Whole-file inventory reviews are exempt because they
identify obligations rather than execute assertions. Reviewers
must be different from the recorded author.

Every pass evidence item names an acceptance context, exact 40-digit code
revision, case ID, artifact, and `result: passed`. Final mode requires evidence
for every applicable matrix context. Crashes, timeouts, resource exhaustion,
duplicate contexts, missing evidence, and invented M2b passes are rejected.
Structural validation cannot prove the content of a remote artifact: the
recorded independent review must inspect the real results and their invariant.

### Reviewed candidates and linked runtime obligations

The optional source-only `reviewed` status distinguishes semantic inventory
review from executed tests. It uses `disposition: candidate-reviewed`, an
independently reviewed invariant/applicability decision and no execution
evidence. The 4,490 pinned anchors and 473 API entries remain untouched and
pending until their actual reviews and tests are completed. API entries cannot
use this source-review status.

Allowed classifications are constrained by the regenerated source kind:

| Source kind        | Classification | Required linkage                                      |
| ------------------ | -------------- | ----------------------------------------------------- |
| conditional-guard  | guard          | Direct runtime obligations controlled by the guard    |
| skip-report        | report         | Runtime obligations whose omission is being reported  |
| generated-template | template       | Expanded, source-cited reviewed-block obligations     |
| generated-template | data           | No runtime links; independent inert-data review       |
| internal-reference | reference      | The actual assert-call or reviewed-block obligations  |
| assert-call        | reference      | The encompassing runtime obligation being reviewed    |

Every non-data candidate has a nonempty, unique `obligations` list of IDs in
the same file. Targets must directly identify runtime assert-call or
reviewed-block records; links to another candidate, a whole-file audit, another
file, missing records or the candidate itself fail validation. The target
configuration union must cover the classified candidate's configurations.
Generated assertions require expanded reviewed-block records, because an
unrelated static assert token is not evidence for a program assembled in a string.

For example, a guard review can use the following additional fields without
claiming that the guard executed its body:

```json
{
  "status": "reviewed",
  "disposition": "candidate-reviewed",
  "classification": "guard",
  "obligations": ["LUA-API-REVIEWED-BLOCK-0001"],
  "evidence": []
}
```

This excerpt omits the unchanged source/span/hash fields, nonempty invariant,
configuration list and independent review fields, all of which remain required.
Foundation validation can retain a reviewed link to a still-pending runtime
obligation with known applicability. Final completion requires that target's
actual C/Ada evidence in all applicable contexts. Lexical guards, skip reports,
templates and internal references cannot instead be stamped `passed` using an
enclosing process result. Pending records cannot hide unaudited classifications.

Review each whole file before its manual-audit obligation is complete. Retain
all generated anchors, classify false-positive/data sites explicitly, and add
reviewed blocks for aliased tests, generated source and data-driven assertions.
An inactive T branch in default configuration remains linked to the real
instrumented tests; its early return is not a runtime pass. Human/independent
agent review must verify these semantic links; the validator enforces graph
shape, source integrity and evidence requirements, not the truth of a review.

C functions, data, and concrete types require real tests. Only a genuinely
conditional macro definition can use `not-applicable` evidence. That requires
a definition-specific inactive compiler/preprocessor artifact, source-derived
conditions, and independent applicability review tied to those conditions.
Header guards do not qualify. A reason string alone cannot waive a public API.

## Checks

Author semantic candidates are available for [events](reviews/events.candidate.json),
[gc](reviews/gc.candidate.json), [gengc](reviews/gengc.candidate.json) and
[files](reviews/files.candidate.json). Their contiguous hashed spans identify
dynamic callbacks, generated code, silent T guards, early returns and shutdown
obligations. They carry no coverage authority and are not independent reviews.
Reviewers must reconcile these candidates with the original source, actual
per-context observations and equivalent counterparts before resolving the ledger.

The [scoped API author candidate](reviews/api.candidate.json) assigns all
77 selected header anchors to 11 semantic groups, with source-hashed existing
test cases and explicit review limits. In particular, synchronous callk/pcallk
cases do not establish yieldable continuations, and parameter round-trip tests
do not alone establish collector parameter semantics. This candidate has no
coverage authority; independent review must connect actual execution evidence
to each applicable invariant before resolving any scoped API record.

The named scope [gc-io-events](scopes/gc-io-events.json) selects events.lua,
files.lua, gc.lua and gengc.lua, including every original anchor and subsequent
reviewed block in those partitions, plus 77 directly exercised public API
entries. Their separate scoped API ledger preserves the original header anchors
while requiring reviewed behavioral invariants; it does not promote the global
C API records or certify unrelated continuation paths. Its selection review
is independently approved for that exact selection. Scope validation first runs
the full structural inventory check; unrelated missing or corrupt entries
cannot be hidden by choosing this scope. The scope requires subprocess, stdio,
temporary-file and platform-counterpart facilities. Unrelated interactive CLI
and native-module prerequisites remain full-M3 gates.

```text
pwsh -NoProfile -File scripts/check-conformance-scope.ps1
pwsh -NoProfile -File scripts/test-conformance-scope.ps1
pwsh -NoProfile -File scripts/check-conformance-scope.ps1 -RequireScopedComplete
```

The last command requires independent selection review and resolved coverage
through all applicable contexts. The gc-io-events scope completed acceptance
in merged PR #9; incomplete scopes still fail this command. It never sets full
M3 completion. The 35 scoped inventory/process regressions
also check out-of-scope corruption, missing files/APIs, self-review, unresolved
runtime obligations, early returns, GC closure ordering, final files output,
physical shutdown, leaked blocks and wrong configurations.
The file completion gate requires IO, flush, large-file, subprocess and date
witnesses in addition to the final date/version, rejects temporary-file skips,
and requires the instrumented partial-write witness. Instrumented gengc must
reach the stop-the-world tests after its default early-return boundary.

run-conformance.ps1 accepts -Scope gc-io-events in File mode. The actual
conformance launcher supports --conformance-config; both bare lua and the
executable selected through arg must reproduce that measured handshake. Scoped
runs retain the 900-second/2 GiB policy, upstream source hashes and balanced
shutdown telemetry. -RequireScopedAcceptance requires an independently reviewed
-AcceptanceContract and -Context, plus the complete scoped ledger. Its report
sets scoped_operation_acceptance separately from gate_acceptance (full M3),
which stays false. One accepted operation does not certify the other files or
contexts: final batch acceptance still requires the complete matrix evidence.

`scripts/check-conformance-matrix.ps1 -Manifest <matrix.json>` reconciles all
104 file/context operations (four files times 26 contexts), with paired C and
Ada reports. `-RequireScopedAcceptance` additionally requires the resolved
scoped ledger, independently reviewed contracts and reconciliation, and a clean
checkout at the reports' exact revision. It never sets full-M3 acceptance.
Without that switch the result is diagnostic, even when every artifact validates.

The matrix manifest has `schema_version: 1`, `scope: "gc-io-events"`, a full
`revision`, a `review` object (`status: "accepted"`, `author`, `reviewer`, `artifact`,
`rationale`), and `operations`. Each operation identifies `file`, `context`,
`c` and `ada` report objects (`report`, `sha256`, `artifact_root`), and an
acceptance `contract` (`path`, `sha256`). Paths are relative to the manifest.
Each artifact root retains the CI `reports/` subtree. The verifier rebases
captured paths across hosts, rehashes output, telemetry and equivalent sources,
replays completion/acceptance checks, and rejects missing or duplicate pairs.
The actual parent/bare-lua/arg-child configuration captures must agree. Compiled
runtime and launcher profiles and launcher library type must match the context;
the reported native host must also match. Recorded binary/library hashes remain
part of the evidence reviewed for provenance.

`scripts/test-conformance-matrix.ps1` uses explicitly synthetic bundles to test
reconciliation and rejection. Those fixtures confer no execution or acceptance
authority. The accepted four-file matrix and final certificates are linked
from [status](../../docs/status.md); new runtime revisions need fresh evidence.

scripts/check-files-scoped.ps1 runs files.lua through this same operation/report
path in both configurations. POSIX selects the original source; Windows selects
the explicit native-platform candidate and builds only its required native
fixtures, recording source and artifact hashes. Parent and child allocator
records are validated separately. Independent native-counterpart runners remain
in the pipeline. macOS uses a separate native-platform candidate for its unavailable
`/dev/full`. Its named buffered-failure counterpart runs before the equivalent
in the same measured C/Ada state; the original POSIX nonblocking-write block
still executes when T is present. Its source-linked mapping is accepted for
gc-io-events; fresh expanded observations and final acceptance are separate.

Both runners measure parent, bare-lua and arg-child settings;
scripts/test-conformance-launcher.ps1 rejects a wrong requested configuration
and a real C executable reached through ambient lookup from an Ada parent.
The main runner also rejects Ada identity when a C baseline was requested.

-EquivalentManifest identifies a source-hashed replacement execution and its
disposition. -AllowUnreviewedEquivalent permits diagnostic observations only;
it cannot be combined with acceptance. Accepted equivalent executions must
identify their exact manifest and executed-source hashes in the review contract.
Default T omissions remain explicit and require resolved instrumented coverage
links before acceptance; matching observed omissions alone do not close them.

## Expanded T scope

[expanded-t-conformance](scopes/expanded-t-conformance.json) retains the nine
previously exercised files and adds constructs.lua, closure.lua, pm.lua and
math.lua. bwcoercion.lua remains a helper, not a fourteenth primary. The scope
selects all 2,493 source anchors in those partitions and 159 selected header
identities with reviewed behavioral witnesses. Other source/API, aggregate and
heavy obligations remain pending. Immutable selection and semantic approvals
bind both source-condition descriptors and API invariants/witness mappings;
changing those claims requires a new independent decision.

```text
pwsh -NoProfile -File scripts/check-conformance-scope.ps1 -Scope expanded-t-conformance
pwsh -NoProfile -File scripts/test-expanded-conformance.ps1
pwsh -NoProfile -File scripts/new-expanded-matrix.ps1 -ArtifactsDirectory <extracted-artifacts> -Revision <40-character-candidate-sha> -Replay
pwsh -NoProfile -File scripts/check-conformance-matrix.ps1 -Manifest <matrix.json> -RequireScopedAcceptance
```

The expanded matrix contains 338 primary file/context pairs plus one additional
constructs template pair per context, for 728 C/Ada process reports. The unchanged
constructs source executes both generated branches through a seeded wrapper.
The bitwise wrapper observes the helper's six installed handlers, fallback,
error paths and caller attribution. Actual source-profile facts determine
numeric/endianness branch applicability; review of an inactive body does not
claim that body ran. The original math random-seed pair remains captured.

The manifest additionally binds 26 warning indices and 170 actual named warning
processes. Its 100 named C and 94 named AUnit witnesses are replayed individually
against approved source-hashed mappings, with the same Ada library and separate
native oracle as the file processes. Raw streams, telemetry, child identities,
equivalent sources, shutdown and configuration facts remain mandatory.

An author observation proposal binds the exact clean matrix and per-obligation
ledger projections. Independent reviewers approve all 142 new runtime entries,
708 retained entries with fresh applicability and 159 scoped API entries by
their exact projection hashes. Historical source semantics and classifications
remain immutable. Contracts receive semantic approval before their final 338
file hashes receive independent index approval; these are separate artifacts
to avoid self-referential hashes. The installer reconstructs approved outputs,
replays actual named/runtime evidence and preserves the old scope before
publishing any approved projection.

Diagnostic collection and successful installation do not establish final
expanded acceptance. The clean publication revision must pass the complete
matrix and independent reconciliation. Its immutable certificate is published
in refs/notes/expanded-t-conformance on the exact tested PR head, avoiding a
self-referential commit SHA in these guides. Until that certificate exists,
final-head acceptance is unestablished. To inspect a published certificate:

```text
git fetch origin refs/notes/expanded-t-conformance:refs/notes/expanded-t-conformance
git notes --ref=expanded-t-conformance show <tested-pr-head>
```

Full M3 completion remains false even after this bounded scope is accepted.

The foreign C consumer's native T allocator lock restricts public reentry from
the payload allocator in hook case24. Paired T processes explicitly select
`--without-release-reentry` and record that native case as omitted, with no
passing claim for it. A separate complete Ada process in the same executable
is mandatory in T contexts. Default native/Ada captures retain the full case.
The verifier reads the hook maximum from the source-bound driver, so later
cases after24 remain required in both paired and complete processes. This
operation protocol is separate from any source-exclusion decision.

Current AUnit collection selects `tests/alire.toml` by running `alr exec` from
the nested test directory. Its inherited-environment child launches the actual
test runner and sibling configuration probe from the repository root, matching
the documented repository-relative fixture paths. Version 2 raw reports bind
both process launch receipts, the selected and observed environment directory,
actual execution directory, executable hashes and the launcher source hashes.
Full-target replay requires those receipts; historical scoped replay retains
its original report contract. The launch regressions run real PowerShell child
processes against a repository-relative fixture and inherited environment
sentinel, without invoking Alire or claiming Ada test execution.

Run from the repository root in PowerShell 7:

```text
pwsh -NoProfile -File scripts/check-conformance-inventory.ps1
pwsh -NoProfile -File scripts/test-conformance-inventory.ps1
pwsh -NoProfile -File scripts/check-conformance-inventory.ps1 -RequireComplete
```

The first validates the complete pinned source/header inventory, candidate
anchor sets, evidence shapes, and acceptance contexts. It also checks the
entire tracked reference tree against HEAD, including staged changes, and
rejects untracked source inputs even when ignore rules hide them.

The second runs focused lexical and negative-ledger regressions. Temporary
inventories and miniature Git repositories are created under ignored reports;
the real reference checkout is never changed. The final command deliberately
fails today because M3 coverage is pending. That failure is the required
fail-closed behavior, not a failed foundation milestone.
