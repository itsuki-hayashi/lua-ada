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

The matrix infrastructure checkpoint deliberately rejects non-unchanged final
execution until exact-byte equivalent/adaptation replay is connected. This is
an explicit incomplete acceptance facility, not evidence that those programs
failed or passed. The follow-up execution producer/replay must close that gate
before any full-target acceptance claim.
