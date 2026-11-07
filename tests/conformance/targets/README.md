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
remain an explicit pending facility; selecting an aggregate affected by T
exclusions cannot silently run its original private checks or hide them.

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
