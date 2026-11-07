# Independent review artifacts

Candidate inventories describe obligations; they do not approve coverage.
Independent narrative reviews identify findings and semantic decisions. A
narrative can retain `changes-required` while accepting a particular mapping.
The executable acceptance gate binds that particular decision through a
separate approval JSON, rather than interpreting prose or treating any
nonempty reviewer name as approval.

Store repository review artifacts as UTF-8 with LF before calculating hashes.
The verifier hashes actual bytes; it does not normalize line endings, repair
stale hashes, or silently trust a filename. `review.artifact` is a repository
relative path and `review.artifact_sha256` is its lower-case SHA-256. The
approval's `author`, `reviewer` and accepted decision must match the referring
review metadata; author and reviewer must differ.

## Equivalent approval

`ConformanceReview.psm1` accepts this shape (example placeholders are not
review evidence):

```json
{
  "schema_version": 1,
  "kind": "equivalent-approval",
  "author": "implementation author",
  "reviewer": "independent reconciliation reviewer",
  "decision": "accepted",
  "equivalent": {
    "id": "mapping-id",
    "source": "references/lua/testes/example.lua",
    "source_sha256": "original source SHA-256",
    "configuration": "default-and-upstream-test",
    "platform": null,
    "disposition": "ada-internal-equivalent",
    "generated_sha256": "exact generated source SHA-256"
  },
  "decisions": [
    {
      "id": "replacement-id",
      "start_byte": 0,
      "length_bytes": 1,
      "source_sha256": "original span SHA-256",
      "replacement_sha256": "UTF-8 replacement text SHA-256",
      "author": "author of this replacement",
      "reviewer": "independent reviewer of this replacement",
      "decision": "accepted",
      "rationale": "Why this replacement preserves the tested invariant",
      "review_evidence": {
        "path": "tests/conformance/reviews/narrative.json",
        "sha256": "narrative file SHA-256"
      },
      "counterparts": [
        {
          "path": "tests/src/example_tests.adb#Named_Case",
          "sha256": "entire source file SHA-256"
        }
      ]
    }
  ]
}
```

There must be exactly one accepted decision per replacement, with identical
span identity, replacement bytes and counterpart set. Every per-span author
and reviewer must differ. Different spans may have different authors and
reviewers. The referenced narrative must exist, match its SHA-256, and name
the same `reviewer` as the span decision. This permits an independently
cross-reviewed repair without letting its author approve that repair.

Counterpart identities are real repository source paths, optionally followed
by `#Named_Case`. The full identifier must match the manifest; the verifier
hashes the file before `#`. Human-readable labels without a source path do
not suffice. A fragment identifies a case for review; source hashing alone
does not prove that case executed. Actual case evidence remains required.

Neither an approval nor its narrative should hash the referring manifest:
the manifest hashes the approval, so doing both creates a cycle. Bind the
original source, individual spans, replacement text, counterparts and final
generated source instead. Generator acceptance and final matrix acceptance
both repeat the binding checks. Pending diagnostic mappings remain available
only under the explicit diagnostic switch.

## Matrix reconciliation approval

A matrix approval uses `schema_version: 1`, `kind: "matrix-approval"`, matching
`author`, `reviewer`, `decision: "accepted"`, `scope` and exact `revision`.
`review_evidence: {path, sha256}` identifies the reviewer's actual JSON
narrative. Its `operations` array has exactly one item per manifest operation:

```json
{
  "file": "events.lua",
  "context": "upstream-test/linux/validation/shared",
  "decision": "accepted",
  "c_report_sha256": "exact C report SHA-256",
  "ada_report_sha256": "exact Ada report SHA-256",
  "contract_sha256": "exact reviewed execution contract SHA-256"
}
```

The matrix validator separately requires all 104 file/context operations,
complete scoped coverage, final clean revision, actual capture hashes,
configuration, process completion and allocator telemetry. Approval binding
does not replace those checks or authorize incomplete/full-M3 coverage.

`scripts/test-conformance-review.ps1` exercises file/hash/identity/decision,
source/span/generated-source, counterpart and matrix-operation rejection
with synthetic fixtures. It is also invoked by the retained matrix selftest
entrypoint in default and instrumented CI. These fixtures are not real review
authority or execution evidence.

## Source classification checkpoints

The per-file classification proposals are independently reviewed inputs to the
coverage ledgers. Their reviewed byte spans remain immutable; inclusive source
line descriptions are converted to the ledger's exclusive byte-end line
convention when inserting new blocks. `ledger-transformation.cross-review.json`
records the independent comparison of all original anchors and added blocks.
Lexical guard/reference/template review is distinct from runtime acceptance:
runtime entries remain pending with empty evidence until their required actual
contexts and equivalent mappings have been reconciled.

`files-native-branches.lua` supplies separately named native calendar
counterparts. Its source and review artifacts identify the original conditional
spans; the launcher retains a hashed copy and requires unique guard facts plus
all completion markers. C and Ada must report identical native branch facts.
An inactive original branch is never reported as an unchanged assertion pass.
The semantic mapping and diagnostic integration reviews do not by themselves
provide an execution acceptance contract.

`Assert-NativeBranchReviewBinding` verifies the explicit accepted semantic
revision in the native review, its proposal/counterpart hashes, independent
authorship and original byte spans. `Assert-NativeBranchWitnesses` enforces
every mapping-declared completion marker exactly once. The runner records the
review identity and the matrix replays it; supplemental native equivalent IDs
remain separate from unchanged file execution. The native review selftest
exercises malformed authority and missing/duplicate witnesses with disposable
copies, without creating any runtime acceptance evidence.
