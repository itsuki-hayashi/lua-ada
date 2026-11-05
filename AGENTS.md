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
- Future AUnit belongs in a nested test crate; developer tools are not runtime
  dependencies. Ordinary builds must not require optional analysis tools.
- Isolate essential C ABI and OS glue; it must not contain interpreter logic.
- Never link the C reference interpreter into the Ada implementation to claim
  compatibility. Build it separately only as an oracle/test fixture.
- Do not edit reference submodules or update their revisions incidentally.
  Follow [reference maintenance](references/README.md).

## Documentation and verification

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

## Foundation boundary

There is no interpreter, library target, AUnit harness, or CI workflow yet.
The no-op executable is a bootstrap placeholder. Advance the backlog explicitly
rather than implying these capabilities exist.
