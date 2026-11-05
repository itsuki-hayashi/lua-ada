# Backlog

IDs are stable. Use `planned`, `active`, `blocked`, or `done`. A `done` item must
link evidence; dependencies are completion gates, not a substitute for review.

| ID        | Work                                | State   | Depends on |
| --------- | ----------------------------------- | ------- | ---------- |
| FND-001   | Root scaffold, policies, references | done    | None       |
| BUILD-001 | Static/shared library targets       | planned | FND-001    |
| TEST-001  | Nested AUnit crate and runner       | planned | BUILD-001  |
| ABI-001   | C-boundary feasibility experiments  | planned | FND-001    |
| CI-001    | Three-platform build/test matrix    | planned | TEST-001   |
| CORE-001  | Values, ownership, roots design     | planned | ABI-001    |
| COMP-001  | Upstream test inventory/mapping     | planned | FND-001    |

## Acceptance and evidence

**FND-001:** root-level crate; required flags in all profiles; clean pinned
references; linked documentation; goals/management and honest capability status.
Evidence: [foundation session](sessions/2026-11-05-foundation.md) and
[status](status.md).

**BUILD-001:** reusable production library, separate minimal CLI, static and
relocatable library scenarios, profile/kind artifact isolation, documented
consumer builds. No new runtime dependencies without a decision.

**TEST-001:** nested test crate pinned to parent; AUnit test-only dependency;
meaningful implemented-API tests, failure exit status, both library modes.

**ABI-001:** C-only probes for variadic calls, callbacks, protected errors/yields,
allocator failure, extra space, layout, and Ada lifecycle. Record target ABI,
safe control-transfer design, glue needs, and limitations before CORE-001.

**CI-001:** Windows/Linux/macOS jobs for build profiles, library modes, AUnit;
record exact tools and export useful logs. Missing platform evidence stays visible.

**CORE-001:** reviewed representation/ownership decision covering cycles,
roots, allocator callbacks, stable addresses, cleanup, and cross-universe handles;
acceptance tests and incremental implementation tasks before code expansion.

**COMP-001:** inventory all pinned upstream scripts and prerequisites; map
implementation-specific assertions to reviewed Ada equivalents; distinguish
unchanged public tests, adaptations, platform exclusions, and unimplemented work.

Add subsequent M3-M6 items when their interfaces/dependencies are understood.
Keep unresolved engineering choices visible rather than fabricating specifications.
