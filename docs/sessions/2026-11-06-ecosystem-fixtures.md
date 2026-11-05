# Ecosystem Module Fixture Setup

Date: 2026-11-06, Asia/Tokyo. Work item: TEST-MOD-001.
Scope: add the eight maintainer-selected real-world module submodules and
documentation for future C Lua/Lua Ada parity work.

Started from master at `de2d75e` after the M1 pull request was merged. The
prepared changes are on `codex/ecosystem-test-fixtures`.

## Changes

Added LPeg, Say, Penlight, LuaSocket, Busted, LuaFileSystem, LuaSQL, and luacheck
under tests/modules. Their full immutable pins and exact upstream URLs are
owned by the [fixture catalog](../../tests/modules/README.md). They are the
inspected upstream master snapshots from this date, checked out detached.

These are consumer test inputs, separate from references/ and excluded from
production/runtime dependency paths. Root contributor instructions and guides
record that they must not be used as implementation/design references.
Documentation records dependency closure requirements, preserved upstream
notices, deliberate update rules, and unrun future platform/ABI evidence.

Penlight and luacheck depend on LuaFileSystem; Busted has additional dependencies
including native modules. Only the eight requested repositories were checked
out. No transitive dependencies, database clients, services, or packages were
installed.

## Setup verification

Resolved upstream HEADs over HTTPS and checked the recorded gitlinks against
their detached worktree commits and origins. Verified all eight checkouts were
clean, had no nested submodule declarations, and retained upstream notices.
The two development-reference gitlinks remain unchanged.

Git: 2.56.0.windows.3. Verified Git metadata, documentation links, aligned
Markdown tables, UTF-8/LF text, and absence of production/test-driver changes.
The root documentation checker passed for 33 Markdown files; a catalog-specific
invocation of the same checks passed for tests/modules/README.md. Module-owned
documents remain untouched. The documented fixture-only recursive checkout
command also completed successfully without executing package code.

## Handoff and limits

Module builds, C-oracle runs, Lua Ada parity runs, upstream module suites,
dependency installation, and new test/CI harnesses were intentionally not
implemented or executed. C Lua 5.5/three-platform suitability is the maintainer's
selection premise, not a new verification claim. Existing M1 evidence remains
dated and unchanged.

Future integration belongs to MOD-001 after the relevant library, loader, and
C ABI work. Follow the catalog's per-snapshot evidence policy; do not infer
compatibility from checkout success.

On follow-up, the user requested a pull request and established a standing
workflow: when an AI contributor creates a task branch and completes the work,
publish the branch and open a PR. This is recorded in AGENTS.md; merging remains
a separate user action or instruction.
