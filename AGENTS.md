# Instructions for AI Contributors

These instructions govern first-party work throughout this repository.
Reference submodules are evidence, not editable production source.

## Required session workflow

1. Read this file, [architecture](ARCHITECTURE.md), [status](docs/status.md),
   [backlog](docs/backlog.md), and the latest [session record](docs/sessions/README.md).
2. Inspect Git status and applicable nested instructions. Preserve user changes.
3. Choose a bounded backlog item. Read its dependencies, acceptance criteria,
   relevant decisions, and pinned upstream sources before implementation.
4. Implement only authorized scope. Keep public interfaces small and documented.
5. Run appropriate checks and inspect their results, not only exit codes.
6. Update affected guides, backlog evidence, and status. Record consequential
   design changes in the decision log and add a dated session handoff.
7. Report changes, validation, and limitations accurately. Missing tools,
   unimplemented checks, and skipped checks must never be called passing tests.
8. When you created a branch for the task and the authorized work is complete,
   commit and publish it, then open a pull request against the default branch
   before handoff. Include verification and scope limits. Do not merge without
   a separate instruction from the user.

Update owning documents rather than duplicating facts. Unchanged Markdown does
not need artificial edits. Historical records remain dated evidence.

## Language and build policy

- Use standard Ada 2022 and the latest stable native GNAT available via Alire.
  Record exact versions; do not add machine-specific compiler pins.
- All first-party Ada builds retain `-gnat2022 -gnatwa -gnatwe -gnatv -gnaty`.
  `-gnatv` requests verbose diagnostics, not validity checking.
- Keep runtime checks enabled in every profile. Resolve warning/style causes;
  do not disable checks or suppress warnings simply to make a build pass.
  Any justified narrow exception needs a reviewed decision and explanation.
- Edit manifest/GPR inputs, never generated `config/` or `alire/` files.
- Follow [coding standards](docs/coding-standards.md). Use strong types,
  encapsulation, contracts, generics, composition, and appropriate tagged
  interfaces instead of mechanical C translation or universal inheritance.
- Use UTF-8, LF, spaces, three-space Ada indentation, and 79-column Ada lines.

## Dependencies and references

- Prefer standard Ada libraries. Document the need, alternatives, license, and
  portability impact before adding a runtime dependency.
- AUnit belongs in the nested test crate; developer tools are not runtime
  dependencies. Ordinary builds must not require optional analysis tools.
- Isolate essential C ABI and OS glue; it must not contain interpreter logic.
- Never link the C reference interpreter into the Ada implementation to claim
  compatibility. Build it separately only as an oracle/test fixture.
- Do not edit reference submodules or update their revisions incidentally.
  Follow [reference maintenance](references/README.md).
- Submodules in `tests/modules/` are future consumer test fixtures, not
  implementation/design references or runtime dependencies. Preserve their
  trees and pins; follow the [fixture catalog](tests/modules/README.md).

## Documentation and verification

- Implementation bodies need extensive, human-readable comments: explain each
  nontrivial algorithm, phase, invariant, ownership transition, and compatibility
  decision at the point where a maintainer needs it. A documented specification
  does not replace comments explaining the implementation. Keep comments current.
- Write focused, separately named AUnit cases for individual behaviors and
  boundary conditions. Explain the setup, action, expected result, and regression
  being protected. Avoid bundling unrelated checks into a few large cases.
- Use adjacent trailing GNATdoc comments and applicable tags. Document
  ownership, lifetimes, contracts, exceptions, and callback requirements.
- Separate architecture intent from implemented capabilities. Do not invent
  APIs, coverage, benchmarks, proof results, or conformance claims.
- Add meaningful AUnit and Lua/C regression tests with implemented behavior.
  Preserve upstream tests unchanged; review any Ada internal-test equivalents.
- Follow [testing](docs/testing.md). Generated empty harnesses are not coverage.
- For SPARK changes, read the GNATprove skill and installed-release manuals.
  Do not add assumptions, axioms, proof suppressions, weakened contracts, or
  proof-excluding bodies simply to make checks disappear.
- Inspect generated documentation, fuzz crashes, and proof summaries. Record
  missing tools and blocked checks precisely.

## Current implementation boundary

The production crate executes the accepted M1 subset through owned Ada sessions
and a batch CLI. M2b adds native continuations, core metamethods, libraries, and
text/Lua-module loading; read [M2b](docs/milestones/m2b.md) and current status
before making acceptance claims. The [M2b validation](docs/validation-m2b.md)
records its completed platform gates. Private bytecode, lexical captures,
tables, tracing collection, and bounded
diagnostics remain the execution substrate. The implemented
[language lifecycle delivery](docs/milestones/m3-language-lifecycle.md) adds
goto/closing, coroutines, stable cells, weak/ephemeron tracing, debug inspection
and hooks, collection controls and explicit execution policies. Read its
[validation record](docs/validation-m3-lifecycle.md) before extending claims.
Use the shared owned frontend for both checking and execution; never introduce
a second grammar in VM lowering. Canonical opcode definitions form the word layer now used by normal
compilation/execution; the older packet backend remains a migration path.
Native binary loading/dumping has focused host evidence, with complete
acceptance tracked separately. See [frontend compatibility](docs/frontend.md) and
[M2a](docs/milestones/m2a.md) for their distinct acceptance boundaries.
Lua/native callbacks must use explicit activation continuations; never recurse
into the executor. Root retained arguments, captures, and pending results before
VM safe points, and charge native loops/backtracking to the shared budget.
Metamethod lookup/raw operations bypass handlers. Loaded chunks retain their
initial environment, and module registries remain distinct from replaceable
public package fields. Follow [ADR 0007](docs/decisions/0007-native-libraries.md).
Read current status for platform evidence and deferred facilities. A passing
subset never establishes full upstream, C ABI, or LuaRocks compatibility.

M3 follows the ordered gates in [its acceptance contract](docs/milestones/m3.md).
The approved major language-lifecycle plan explicitly combines execution
transfers, goto/closing, coroutines, weak collection, debug support and CLI
policy on codex/m3-language-lifecycle. Keep these checkpoints in one PR; do not
stop after a small infrastructure slice. Preserve separate completion evidence
for canonical execution, C ABI, allocator parity and other deferred gates.
Remaining gates outside this approved combined delivery keep separate tasks
and PRs, starting from updated master after the maintainer merges their
predecessors. Preserve pending obligations in
the conformance ledger. Native C observations, lexical inventory anchors, and
successful harness collection are not passing Ada conformance evidence.

The subsequent approved full-upstream delivery supersedes that separate-PR
rule for all remaining M3 gates. Start from merged PR #7 on
codex/m3-upstream-conformance, retain coherent intermediate commits on that
branch, and deliver one major PR. Follow the checkpoints in the
[M3 acceptance contract](docs/milestones/m3.md) and
[ADR 0010](docs/decisions/0010-full-upstream-delivery.md). Do not stop after
contract, harness or isolated library work and describe the full target as done.
That earlier contract did not authorize merge. Preserve the distinction between reviewed lexical
candidates, actual runtime obligations, unchanged execution and reviewed
equivalents; a T-absent return never certifies the omitted C tests.

The maintainer's 2026-11-08 early-session instruction supersedes the requirement
to finish the remaining upstream target before merging this delivery. Freeze
the completed runtime/tooling checkpoint, preserve unfinished work separately,
run its explicit checkpoint CI, address automatic PR review and merge that
checkpoint. This is not full M3 or remaining-target acceptance. Keep all 26
full-target contexts, pending ledgers and stale-review failures intact; the
full-target workflow remains manually available. Do not resume the deferred
implementation as part of this checkpoint. The
[checkpoint handoff](docs/sessions/2026-11-08-interim-compatibility-checkpoint.md)
owns the cut, backup refs, verification and remaining obligations.
