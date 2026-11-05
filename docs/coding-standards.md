# Coding and Writing Standards

Use the [Ada Quality and Style Guide](https://ada-lang.io/docs/style-guide/Ada_Style_Guide/)
as guidance; project Ada 2022 rules take precedence over older examples.

## Ada

- Prefer private types, small packages, strong subtypes, contracts, predicates,
  discriminated records, aggregates, iterators, and generics when they help.
- Use composition and meaningful behavioral interfaces. Document dispatching
  contracts before derived implementations.
- Make ownership, allocation, invalidation, and cleanup explicit. Isolate
  unchecked conversions, foreign imports, addresses, and deallocation.
- Preserve Lua byte strings, numeric distinctions, wrapping, identity,
  truthiness, and error/yield semantics deliberately.
- Use descriptive mixed-case identifiers, three-space indentation, spaces,
  and 79-column lines. Break declarations/expressions naturally.
- Use two spaces after `--` for ordinary full-line comments. Explain reasons
  and invariants instead of narrating assignments.
- Keep standard Ada 2022; do not enable extensions incidentally.

All builds use `-gnat2022 -gnatwa -gnatwe -gnatv -gnaty`. `-gnatwa` enables
most optional warnings, not literally every warning; `-gnatv` controls verbose
diagnostics, not validity checks. Fix style/warning causes rather than suppressing
them. See [GNAT style checks](https://gcc.gnu.org/onlinedocs/gnat_ugn/Style-Checking.html).

## Documentation

Implementation bodies require extensive explanatory comments, not only API
comments. Introduce algorithms and their phases; explain ownership, invariants,
boundary arithmetic, and Lua-specific decisions beside the relevant code. Make
the control flow understandable to a human maintainer without reverse engineering
it. Avoid redundant commentary that merely restates a statement.

Unit tests must be human-readable and narrowly focused. Give each independently
meaningful behavior or edge condition a named AUnit case with comments explaining
its setup, action, expected result, and the regression it guards. Shared helpers
may remove mechanical setup, but must not conceal what a case is asserting.

Use [GNATdoc conventions](api-documentation.md) for declarations. Explain
ownership, contracts, errors, and interoperability assumptions. Keep broader
rationale in architecture and decisions.

Markdown uses UTF-8, LF, a final newline, and prose wrapped near 100 columns.
Use meaningful headings, aligned tables, fenced examples, relative local links,
and blank lines around lists. Separate present behavior, planned requirements,
and historical evidence. Avoid local machine paths in portable instructions.
