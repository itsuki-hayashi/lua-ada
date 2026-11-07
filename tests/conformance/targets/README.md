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
