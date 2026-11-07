# Authorized compatibility target exclusions

`remaining-upstream-compatibility` is an explicitly selected acceptance policy.
It permits independently reviewed exclusions of T-only private implementation
checks that have no effect on third-party module compatibility. Its overlay is
`remaining-upstream-compatibility.exclusions.json`. The initially empty overlay
excludes nothing and establishes no new runtime acceptance.

Call `Test-ConformanceInventory -TargetPolicy remaining-upstream-compatibility`
to validate this overlay. Existing callers default to `strict-upstream`, never
read it, and retain the original completion requirements. The overlay does not
rewrite coverage records, accepted scope definitions, or historical evidence.
Each original source anchor remains visible. An exclusion is a separate target
resolution, never a passing test, an internal equivalent, or a platform pass.

An overlay has schema version 1, target identity, pinned `reference_revision`,
`protected_scopes`, and an `exclusions` array. The protected scope identities
contain `id`, repository-relative `path`, and SHA-256 for the exact accepted
`gc-io-events` and `expanded-t-conformance` descriptors. The verifier pins those
hashes independently, rejects missing or changed descriptors, and derives all
protected primary/helper source partitions from them. Those already accepted
partitions need no exclusions; changing a passed record back to pending cannot
make it eligible. Every exclusion contains:

- `id`, `source` (the original Lua filename), `source_sha256`, `byte_offset`,
  `byte_length`, and `anchor_sha256`, matching one pending source `assert-call`
  or `reviewed-block` exactly. Passed records, lexical candidates, inventory
  audits, public header entries and missing/duplicate IDs are ineligible.
- `status: excluded`, `disposition: reviewed-t-internal-exclusion`,
  `configurations: ["upstream-test"]`, and an empty `evidence` array. No process
  pass or omission can act as evidence for exclusion.
- `eligibility: t-only-private-invariant`, explicit false boolean `public_api`,
  `mixed_obligation`, and `module_observable` fields, plus nonempty `invariant`
  and `third_party_irrelevance` explanations. A mixed private/public assertion
  must be split accurately or implemented; the overlay cannot waive its public
  portion. Relevant T-driven public API behavior remains required.
- `t_guard: {mode, byte_offset, byte_length, sha256}`, citing original bytes.
  `positive-guard` requires an actual `if T then ... end` token span containing
  the obligation and ending at its matching block boundary, without an outer
  `else` or `elseif` arm. Nested alternatives entirely within the T arm remain
  eligible. `absent-return`
  requires a preceding top-level literal `if T==nil then ... return end` or
  `if not T then ... return end`, without nested control flow in the reporting
  prefix. Quoted pseudo-guards and function-local returns are rejected. These
  lexical checks supplement independent semantic review; they do not establish
  that a private invariant is irrelevant to public behavior.
- `review: {status, author, reviewer, artifact, artifact_sha256}`, with accepted
  status and distinct author/reviewer. The referenced repository-relative,
  LF/BOM-free UTF-8 approval must match its actual SHA-256.

The approval has schema version 1, `kind: t-exclusion-approval`, exact target,
reference revision and `protected_scopes` bindings, matching author/reviewer,
`decision: accepted`, and
an `exclusion` object containing every semantic exclusion field above except
the referring `review`. It also has `review_evidence: {path, sha256}` for an
independent JSON narrative. That narrative names the reviewer and exclusion ID,
an accepted decision, and nonempty `t_dominance`, `private_invariant`, and
`third_party_irrelevance` source-review conclusions. No artifact hashes its
referring metadata, avoiding circular hash bindings.

The verifier binds every approved field and checks the original full-source,
obligation and guard bytes. An approval cannot be carried onto a broader
invariant or changed span. The reviewer must inspect actual source control
flow, the tested private invariant, and its separation from public behavior;
syntactic validity alone does not grant exclusion authority.

Results retain raw `PendingSourceAnchors`, plus `ExcludedSourceObligations`,
`RequiredPendingSourceAnchors`, and the exact `Exclusions` list. `TargetComplete`
requires explicit `-RequireComplete` and resolution of every required source,
source-link and public API obligation. Original `Complete` remains false when
any exclusion is used, even after target completion. Foundation validation
sets both completion fields false. Reports and final acceptance must preserve
this distinction and disclose all exclusions.

## Full-target matrix reconciliation

The inventory CLI exposes the policy explicitly:

```powershell
./scripts/check-conformance-inventory.ps1 -TargetPolicy remaining-upstream-compatibility
```

`check-conformance-matrix.ps1 -Manifest <bundle.json> -TargetPolicy
remaining-upstream-compatibility` selects the separate full-target reconciler.
Add `-RequireTargetAcceptance` for acceptance; this switch cannot be mixed with
historical `-RequireScopedAcceptance`. Old callers still use the old scoped
checker and its unchanged acceptance semantics.

A full-target manifest has schema version 1, `kind: full-target-matrix`, exact
`target`, `reference_revision`, 40-digit implementation `revision`, explicit
boolean `synthetic_fixture`, and the following fields:

- `exclusion_policy: {path, sha256}` identifies the exact checked-in target
  overlay. `retained_evidence: {path, sha256}` identifies the retained named
  C/AUnit and warning index used for final acceptance.
- `operations` contains every scheduled primary `file:<name>` operation,
  `aggregate`, and `heavy`, once in each of the 26 suite contexts: 832 pairs.
  The suite manifest, rather than a caller's file filter, owns that selection.
- `supplemental` contains distinct named `variant` executions. The second real
  constructs template, `constructs-branch-1`, is compulsory in every context.
  Additional variants remain separate operations and need separate review.
- Every pair names `operation`, `context`, `comparison` (`exact` or
  `reviewed-semantic`), `c` and `ada` report identities
  `{report, sha256, artifact_root}`, and an execution `contract: {path, sha256}`.
  Report/contract paths and artifact roots are relative to the manifest bundle.
  `reviewed-semantic` uses the existing independently reviewed contract protocol,
  preserving exact raw streams; it does not authorize arbitrary normalization.
- `review` identifies an accepted independent `full-target-matrix-approval`.
  The approval binds target/reference/revision, policy and retained-index hashes,
  every pair's operation/context/variant/comparison, C/Ada report and contract
  hashes, plus current suite, all 34 coverage partitions and global API ledger
  hashes in `inventory_files`. A hashed independent narrative identifies the
  same target, revision and reviewer with an accepted decision.

Full-target reports retain the generic conformance report fields and add
`target_policy`, `variant` (`primary` for base operations), explicit
`synthetic_fixture`, `exclusion_policy_sha256`, and exact
`excluded_obligations`. They have empty `coverage_scope`; historical scoped
acceptance and original full-M3 acceptance flags stay false. An accepted actual
Ada report has `target_operation_acceptance: true` and the exact execution
contract hash. Default/C reports cannot claim excluded T obligations. An Ada
instrumented report affected by exclusions uses `reviewed-t-adapted`, never
`unchanged`.

The reconciler checks source/executable/library identities, actual hashed raw
streams, configuration and child probes, separate probe lifetimes, per-process
allocator accounting, physical Ada shutdown and all operation-specific limits.
Heavy must demonstrate its own caught refusal under 64 MiB; a child refusal
cannot substitute. Constructs variants require their actual captured branch
witness. Every operation in a context must use the same runtime image.

Final target acceptance also requires the complete selected source ledger and
all 473 global public-header entries, a clean exact checkout, reviewed execution
contracts, and independently reconciled retained warning/named evidence.
Retained evidence uses the existing expanded-scope protocols and all 26 context
reports, with matching runtime images. Synthetic fixtures and diagnostic replay
never grant target acceptance. Exclusions are separately listed and counted;
`original_suite_unchanged_pass` requires original strict completeness and only
unchanged execution. `full_m3_acceptance` remains false for this target.

File execution can replay independently reviewed Ada/internal and native-platform
equivalent manifests and approved T-private transformations. The matrix rebuilds
the expected bytes from the original source, rechecks the independent approval,
and compares the actual generated artifact and execution-contract identity.
Native-platform acceptance additionally needs current original-C applicability
observations for every changed invariant. A narrative alone or an Ada-only
failure cannot establish a platform exception. Aggregate transformation bundles
use the separately reviewed reconstruction described below; an affected
aggregate cannot silently run its original private checks or hide exclusions.

## Explicit execution producer

`run-conformance.ps1 -TargetPolicy remaining-upstream-compatibility` produces
the corresponding reports for `File`, `Aggregate`, or `Heavy`, with a required
host/configuration context. `-RequireTargetAcceptance` selects only target
operation acceptance on the actual Ada target; it cannot be combined with the
historical acceptance selectors. File mode selects the 30 scheduled primaries.
`-ConstructsBranch 1` records the required `constructs-branch-1` variant and
executes the existing seeded wrapper, retaining its actual branch witness.

The producer isolates bare and arg-selected children on the selected launcher,
retains the existing REPL/native-fixture prerequisites, records separate probe
lifetimes and all available child allocator sidecars, and preserves retained
file/warning/helper witnesses. Global API/source completion is checked before
an acceptance run can start building fixtures or executing Lua. An unresolved
or unimplemented gate is a setup failure, never report-only acceptance.

Default T-absence contracts may link either actual instrumented runtime
coverage or an exclusion already validated by the selected inventory policy.
The latter is returned separately as `excluded_omissions`, with no pass
evidence attached to the omitted invariant. This route is unavailable to strict
callers, instrumented T-absence messages, ordinary omissions, public behavior,
or mixed obligations. The selector alone does not establish coverage.

## Exact-byte transformations

`New-ConformanceTTransform.ps1 -Manifest <path> -Output <reports artifact>`
loads the actual validated target exclusion overlay and accepts only an
independently approved transformation. `run-conformance.ps1` selects it with
`-TAdaptationManifest`; it is restricted to an instrumented Ada File operation,
and cannot combine with an ordinary equivalent manifest. Every applicable
source exclusion must be named exactly once by its actual transformation.

A T manifest has schema version 1, `kind: t-private-transform`, unique `id`,
exact `target`, pinned `reference_revision`, original `source` and
`source_sha256`, `configuration: upstream-test`, `exclusion_policy_sha256`,
`output_sha256`, and `replacements`. Each replacement has `id`, `exclusion_id`,
`start_byte`, `length_bytes`, `source_sha256`, and literal `replacement` text.
Its original span must match the corresponding approved exclusion exactly;
overlapping, duplicate or wider patches fail. Untouched bytes are copied
verbatim, including the original reference line endings.

Replacement text is limited to empty text, safe complete line comments, and
punctuation preserving an enclosing expression. New calls, identifiers,
assignments, T/flag overrides, returns and block comments are unavailable.
Comments must terminate before untouched source. `code.lua`'s entire `checkR`
helper is additionally protected against replacement so its real function
execution and result/type assertions remain present.

`review` names accepted distinct author/reviewer and an actual hash-bound
approval artifact. A `t-private-transform-approval` binds every manifest identity
field, final output hash and policy hash, and exactly one decision per patch.
Each decision binds its ID, exclusion ID, original span and replacement hash,
has a rationale, and explicitly accepts `private_only` and
`preserves_public_assertions`. A hashed reviewer narrative names the transform
ID and explains public-assertion preservation. Diagnostic author previews do
not have production authority; the execution producer does not expose an
unreviewed T-transform bypass. No production exclusions are installed merely
by authoring a transform proposal.

Existing equivalent manifests retain their own approved per-span counterpart
protocol. The full-target producer records their repository-relative manifest
path/hash in `equivalent`; T transformations use `t_adaptation`. Contracts bind
the exact mapping and executed bytes. T contracts also bind the exclusion-policy
hash. Actual references and historical manifests are never modified.

## Native applicability observations

A native-platform File observation can supply `-NativeApplicability <path>`.
Without it an independently reviewed mapping can produce development
observations, but cannot establish target acceptance. The hashed metadata has
`kind: native-platform-applicability`, schema version 1, reference/implementation
revisions, mapping ID/hash, original source/hash, platform/configuration,
explicit `synthetic_fixture` and nonempty `observations`.

Each observation identifies original source spans covering mapping replacements,
an actual hashed `original_c_report`, the observed native limitation, expected
exit code, counted anchored stdout witnesses and enumerated expected stderr.
The original report must identify unchanged matching C Lua, original source
bytes, current clean revision/configuration/platform and measured C ABI, with
actual hashed streams and no timeout/crash/capture failure. All transformed
invariants need coverage by these observations.

A distinct accepted `native-platform-applicability-approval` binds these exact
identities and the SHA-256 of compressed observations JSON, plus a hashed
independent source-linked rationale. Synthetic proof/report fixtures are valid
only for verifier tests and never set `runtime_verified`. Final acceptance
requires actual runtime evidence; observed unsupported C assumptions cannot be
inferred from an Ada failure.

## Development observation and successor witnesses

`observe-target-conformance.ps1` collects physical operations without consulting
the old source-bound scoped acceptance policy. `-Selection Retained` schedules
the 13 previously accepted primaries and both constructs templates: 28 C/Ada
processes per context. `-Selection All` schedules 62 processes for all 30
primaries plus that supplement. `-PlanOnly` validates selection without
executables or builds. Actual collection retains the existing warning protocol,
original streams and failures, and always reports `target_acceptance: false`.
Failed observations produce a nonzero exit; they are not historical acceptance.
Unrelated REPL/native-module prerequisites are deferred to the File operations
that actually need them; main/attrib and Aggregate retain those requirements.
`-GCEquivalentManifest` explicitly selects a separately reviewed successor GC
mapping after its current-source approval; no stale mapping is silently rebound.

`new-target-witness-proposals.ps1` creates separate author-only successor
consumer/AUnit descriptors under this target or a disposable reports directory.
It retains every existing 100 C / 94 AUnit identity and witness protocol, hashes
current source bytes, and marks stale function-level bindings as historical
pending review. Additional cases need explicit separate author inputs; new
registrations are not inferred as passing tests. All successor proposals retain
pending independent review, empty execution evidence and false authority flags.
The old scope descriptors, mappings, approvals and contracts remain unchanged.
Fresh full-target retained indices can reference independently reviewed successor
mappings, with the original required names/protocols still enforced.

Transform unit tests use content-verified frozen predecessor review/source
fixtures rather than inheriting their authority onto changed production files.
They deliberately reject a changed counterpart with an old approval. Current
production replay applicability is reported separately; a frozen fixture pass
does not clear a stale production source binding or establish runtime coverage.

The target-owned `remaining-upstream-compatibility/gc-ada-equivalence.json`
has an independent source-semantic review of its four unchanged predecessor
transformations and current counterpart bindings. Its approval and narrative
remain separate from the historical mapping. The generated source hash is
unchanged; its source review grants no runtime or coverage acceptance. Fresh
GC and named counterpart execution must still bind the final runtime image.

The target-owned `code-private-optimizer.author-proposal.json` and companion
transform proposal are unapproved source-review inputs. They propose eight
narrow private-inspection spans, preserve the exact `checkR` helper and 13 full
static public assertion calls, and leave all actual execution/type assertions,
successful source loads and the oversized-register diagnostic present. Ten
private static assertion sites are linked to proposed obligations. These counts
describe source inventory, not executed coverage. Constant-type and return-arity
implications still require independent review and public runtime witnesses.
The production exclusion overlay is not changed by these author packets.

`file-completion.author-proposal.json` describes the seventeen remaining File
entry protocols. `target-file-completion.lua` runs the selected original or
exact reviewed derived chunk once using all.lua's entry operation: dump/load,
stripped dump/load, direct text loading, or the two big.lua coroutine resumes.
It observes calls.lua's single exported deep function, attrib.lua's single
integer 27, locals.lua's integer 5 plus a function, and verybig.lua's single
integer 10. Other non-coroutine chunks, including T-absent early returns, must
return zero values. Extra results and one nil are distinct return protocols.
The original source marker must precede the wrapper's terminal return witness.
big.lua must suspend with b before its OK and die after returning a. memerr.lua
uses its actual case-sensitive Ok and a consecutive numbered stderr progress
sequence; api.lua must emit its two exact continued warnings. main.lua must
finish its original warning assertions and both interrupt subprocesses before
OK. Its platform applicability remains a separate original-C review obligation.

These descriptors are author-only source proposals, without runtime or ledger
authority. The target runner and observer accept `-FileProtocolManifest` to
select an independently approved successor explicitly. Final target operation
and matrix acceptance require accepted independent source review binding the
wrapper, all.lua and every exact protocol/source span, and the per-context
execution contract must bind `file_completion_protocol_sha256` and
`file_completion_wrapper_sha256`. Matrix replay verifies the copied wrapper,
actual entry arguments, selected original/derived chunk hash and captured
return/yield/warning phases. Existing thirteen-file protocols remain unchanged.
Default api/code/memerr witnesses say T absent and retain the ordinary coverage
omission links; they never certify their omitted instrumented bodies.
The wrapper receives the original source name and selected chunk path as its
two positive CLI arguments and invokes the original chunk with no varargs,
matching all.lua's chunk call. It preserves the actual global arg table: arg[0]
names the wrapper, while positive entries describe those wrapper arguments.
main.lua obtains its selected executable by walking the unchanged negative
argument chain; the wrapper does not replace its raw child commands or their
argument assertions. Other remaining originals do not read these wrapper
arguments outside the subprocess source strings tested by main.lua.

`test-target-file-protocols.ps1` uses explicitly synthetic byte/capture/review
fixtures. Its optional `-ReferenceInterpreter` cases run tiny synthetic chunks
to reject incorrect return values and incorrect coroutine termination; those
checks do not execute the original upstream files or establish Ada conformance.

The successor witness producer also emits `global-api.author-proposal.json` for
all 473 global header inventory entries. It preserves the 159 retained semantic
routes and original 100 C/94 AUnit identities, and leaves every classification
pending for fresh independent review. Explicit additional source proposals add
63 source routes for actual public functions, the invoked
`luaL_checkversion`/`lua_getextraspace`/`lua_isfunction` macros, and the linked
`lua_ident` data read. Their `proposed_classification` and
`proposed_context_witnesses` are future evidence obligations; they do not carry
an observed disposition, accepted review or execution evidence. The remaining
251 unretained entries still have empty routes, including 15 functions without
a registered source route. The producer rejects invented
named cases, passing metadata and runtime routes for declaration-only entries;
it does not guess that a macro is a function call or that compilation
of a declaration checks runtime behavior. Appropriate compiled ABI, layout or
header witnesses are required for types/constants/declaration-only entries,
with measured configuration evidence for conditional declarations. Current
source hashes and repository snapshot state are authoring context only. None
of these proposals carries historical execution evidence onto the new tree.

`TargetContext.psm1` derives 26 builds and 130 execution partitions from suite.json:
three shards of ten primary files, Aggregate and Heavy for every context. The
shard owning constructs.lua also owns its mandatory second-template supplement.
Its image transport records the exact revision/context, actual selected
launcher basename, each binary/library/capture byte hash and Unix mode. Restore
can write only generated binary/library and observation paths; source paths,
traversal/aliases, duplicate identities and reparse-point destinations reject.
Payloads remain without runtime or coverage authority. Byte/mode verification
before and after a partition protects the shared context image; successful
transport is not evidence that any Lua, C or AUnit operation passed.

The full-target workflow now builds these contexts once, freezes their selected
Ada host/runtime and C oracle, and downloads that same image into the five
execution partitions. Each File shard runs both implementations; constructs has
its extra real-template pair, and files-1 owns the retained warning campaign.
The build mode in `check.ps1` and `check-instrumented.ps1` is explicit through
`-TargetPolicy` and `-TargetWitnessPolicy`. It retains the actual AUnit, native
C, CLI, binary, allocator, lifecycle and consumer checks, then records fresh
named C/AUnit observations through the successor policy. Its File campaigns
move to the immutable-image jobs instead of invoking frozen historical scope
acceptance on a changed runtime tree. The historical default commands retain
their prior behavior. `-TargetDevelopmentObservation` permits author-only
source mappings for diagnostic collection; it does not authorize acceptance.

Target builds include independently authored formatter, value and auxiliary
consumers (4, 7 and 76 named C cases respectively), the existing reader/writer
(28), debug (32), numeric conversion (11) and common external-string (13)
protocols, the operator contract (17), the integer-index/type contract (27),
and 10 additional AUnit
names: two formatter quotas, six scalar-text boundaries and two auxiliary
quotas. They compare the same C source
against the Ada SAL and the separate pinned C library, bind the actual source
files and library images, and keep the original 100/94 witness identities and
protocols. The staged successor proposals therefore contain 315 C and 104 AUnit
names. These are mapping proposals, not executed-case counts. The retained
API projection's separately added foreign-hook-13 memory-status route is
preserved alongside its older consumer-catalogue routes in the new successor.
The auxiliary oracle uses the same Linux/macOS platform defines as the root
and Ada consumer projects, so its wait-status assertions check the actual
platform branch. Value text requires all 15 indexed records in order, the
source-bound 20,000-value seeded fingerprint and identical same-host C/Ada
bytes. The Windows sample in the author packet records its measured exact
lines and `90eb8de147d180eb` fingerprint without imposing a portable NaN spelling
or establishing any matrix observation. `-AdditionalApiRoutes` only adds
pending source-linked routes; final classification and every actual context
remain independent review and execution obligations.
Reader/writer routes bind both the standalone driver and shared test header;
writer-only cases are separate from the 24 actual reader-loading witnesses.
Each additional consumer requires its own source-bound original-C process and
matching complete bytes, including the integer-index/type and operator
contracts. External strings additionally bind the exact argument vector,
18 default versus 13 instrumented cases, the five named default release-reentry
witnesses and the single instrumented C-lock omission marker. A summary count
cannot substitute for those observations. The 13 common named external cases
are not used to claim that the five omitted instrumented cases ran.

`TargetWitnessPolicy.psm1` validates all 473 original declarations separately
from the old 159-route projection. Accepted policies require an independent
hash-bound decision for each complete mapping and all 26 context routes.
Each context route states `runtime-observed`, `compiled-observed`, or a reviewed
`compiled-not-applicable` condition, with explicit arrays of `named_c_cases`,
`named_aunit_cases` and `compiled_witnesses`. Function/type classifications
cannot substitute header compilation for a runtime function call or invent a
call for a type. Empty routes, null-array camouflage, unknown case names,
unreviewed changed function bindings and missing conditional proof reject.
Actual named C/AUnit evidence and independently reviewed compiled ABI/layout/
header probes must resolve every route; a passed ledger status is insufficient.

Compiled probes have a target-owned `target-compiled-witness-mapping` with
source/header hashes, applicable contexts, exact argument vectors and exact
assertion output. `run-target-compiled-witnesses.ps1` records actual compiler
and executable processes, output-image hashes and captures. The verifier binds
them to the context's selected compiler hash and rejects source, argument,
compiler, executable, capture, exit and output drift. No compiled probes are
installed by the author catalogue generator: its unmapped declarations remain
pending until meaningful source probes and independent review exist.
Final reconciliation also requires the exact compiled observation index,
executable and every compiler/execution capture in that context's frozen
image file inventory. A report naming the same source/compiler/context without
those immutable image entries cannot close a declaration route.

`collect-target-observations.ps1` assembles raw images, 832 primary pairs, 26
constructs supplements, all warning contexts and current build witnesses into
an observation bundle. Its generated contracts and matrix remain author-only
proposals. It does not turn observations into acceptance or derive semantic
expectations from a successful stdout capture. The workflow's collection stage
is therefore distinct from final independent reconciliation. Actual GitHub
execution is required to validate the complete distributed campaign; local
planner/validator fixtures do not establish that it ran.

Final target reconciliation consumes a separately reviewed
`target-post-observation-envelope` for every original raw report. The envelope
binds its raw SHA, runtime revision, context, source/fixture hashes, measured
configuration, host/library image hashes, reviewed contract and immutable
context image. Its independent approval and narrative are content-addressed.
The envelope, raw report, approval and narrative each require an explicit JSON
boolean `synthetic_fixture: false`. Missing flags, strings and labelled synthetic
reviews fail final reconciliation. Binding unit tests alone may explicitly
request `-AllowSynthetic`; the final matrix never supplies that switch.
The raw `report_only` and `target_operation_acceptance` flags remain unchanged.
Source transformation/exclusion review still precedes adapted execution;
native-platform applicability may independently review the exact original C
baseline capture afterward. The envelope can bind that post-capture review.
For each selected native-platform equivalent, the partition captures an
additional unchanged `ReferenceC` run with variant `native-original` before
the equivalent. Its exit/status is preserved separately from primary pairs:
an expected native failure supplies observations for review and never counts
as a passing source obligation. The collector retains these raw reports and
their mapping/image identities in `native_original_observations`.
The independently reviewed applicability proof, approval and every original
C report must identify the exact acceptance context, including profile and
library type. Final replay also checks the original C host and runtime files
against the same immutable context image as the C/Ada primary pair. Labelled
synthetic applicability approvals or narratives cannot supply runtime proof.
Runtime/harness changes require fresh captures at their real revision; there
is no revision relabeling or implicit tree-diff waiver.

The final image consumer requires four source-bound build inputs: the named
receipt, actual C consumer report, actual AUnit/configuration report and full
compiler/regression log. It replays named cases, native driver source hashes,
capture hashes and runtime DLL/archive identity. `synthetic_fixture: false`
and `repository_dirty: false` alone do not establish a build witness. Envelope
validation alone also grants no runtime/coverage authority: the final matrix
still requires complete source/global API review, every actual context route,
all image/build/runtime protocols and every semantic execution contract.

Each remaining primary in a final execution partition requires an explicitly
selected independently reviewed `FileProtocolManifest` in its execution policy.
The workflow's named `development_observations` input instead selects the
pending author protocol proposal for diagnostics. This choice remains visible
in partition planning and supplies no final source or execution authority.

Aggregate can select `-AggregateManifest` through its execution policy. A
`target-aggregate-replay` manifest identifies the configuration, implementation,
platform, all 34 original source hashes and a distinct selection per changed
source. Each selection binds an `equivalent` or `t-private` manifest by path and
hash. Every selected transformation must already pass its own independent
source review; the aggregate selection also needs independent approval. The
approval's `selection_sha256` is the canonical `Get-TargetAggregateClaims`
payload hash. Its content-bound narrative explicitly preserves the original
aggregate protocol and public assertions. `new-target-aggregate-proposal.ps1`
creates pending author metadata under `reports/`; it grants no source review.

Execution keeps the original prepared fixture snapshot intact and copies it
to a separate disposable tree. Only selected Lua files receive reconstructed
bytes. Every execution input is hashed before and after the original `all.lua`
runs from that tree. Unselected files, including the driver, retain their
original bytes. The complete 34-file source set, exact T exclusion union,
entry arguments and separate original snapshot remain mandatory. A source
cannot combine overlapping transforms, and an Ada internal equivalent cannot
replace original C execution. Heavy remains a separate operation.

The Aggregate report's `aggregate_replay` records the selection identity,
execution directory/input hashes and any changed inputs. Its disposition is
`reviewed-aggregate-replay`; observations still grant no acceptance. The
reviewed execution contract has `aggregate_replays.Ada` and/or
`aggregate_replays.ReferenceC` identities with `manifest_sha256`,
`selection_sha256`, `executed_sources_sha256`, `setup_sha256` and disposition.
The executed-source digest uses the canonical `{sources: expected_sources}`
object, preserving the suite's source order. The collector copies only these
byte identities into its pending contract proposal and leaves semantic stdout,
warning, omission and completion expectations for independent review.

Native applicability for Aggregate uses a content-bound
`target-aggregate-native-applicability` index with exact context/revision and
one `mappings` entry per native transformation. Each entry identifies `source`,
`manifest_sha256` and its independently reviewed applicability `identity`.
The post-observation envelope may supply that index after original C baseline
capture. Final replay checks every proof and original C host/library image;
the index itself is transport metadata and confers no semantic approval.

`NativeModuleLinkage.psm1` provides structural Windows image tools independently
of Alire/profile selection. `Get-PEImageExports` and `Get-PEImageImports` parse
actual PE byte snapshots. `New-PEHostImportLibrary -Root -ImagePath -DllTool
-OutputDirectory` creates a definition and import archive from the actual
linked image, using its final filesystem basename. It does not inherit the
old name embedded in a copied executable's export directory. Data markers
come from the actual nonexecuting image section; forwarded/missing exports and
unsupported machine identities fail. The default selection is the actual
`lua_`, `luaL_` and `luaopen_` export set. An explicit `-ExportNames` supports
small non-Lua tool regression fixtures. Outputs must be new paths under
`reports/`, and tool/image/definition/import bytes and invocation are retained.

`Assert-PEModuleOwner` reparses actual owner, module and dependency bytes. It
rejects imported APIs from another image, an embedded interpreter export set,
missing dependency symbols and dependency graphs with no route to the selected
owner. This includes transitive fixture imports such as lib11/lib21. These
checks grant no runtime authority; the separately named native module driver
still has to execute the actual host/module ownership and lifetime protocol.
`test-native-module-linkage.ps1` uses synthetic PE parser fixtures; its optional
absolute `-Compiler` runs a non-Lua C loader experiment that compares both real
function and data pointers, rejects an old import after renaming the host and
then rebuilds the import for that exact new basename. It builds no Ada code
and acquires no Alire/profile lease.

Artifact transport follows the official [upload-artifact v7 documentation](https://github.com/actions/upload-artifact/tree/v7.0.2)
and [download-artifact v8 documentation](https://github.com/actions/download-artifact/tree/v8).
Unix mode bits are restored from the content-bound image manifest because the
artifact service transports file bytes without preserving executable modes.
