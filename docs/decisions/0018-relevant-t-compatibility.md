# ADR 0018: Compatibility-relevant T coverage

Date: 2026-11-07, Asia/Tokyo. Status: accepted delivery policy;
implementation and final acceptance remain in progress.

## Context

The maintainer approved completion of the remaining upstream suite from merged
PR #10. They explicitly permit modifying or skipping T checks after feature
review establishes that the checks do not protect third-party compatibility.
This supersedes ADR 0010's requirement to replace every private assertion with
an executed equivalent, and its old branch and no-merge delivery restrictions.
All other ownership, language, ABI and verification requirements remain.

## Decision

Complete one PR on codex/m3-remaining-upstream-compatibility from master
d438f1fb2491006c1c248e0888637b4afa5ae0fc. Preserve the reference sources and pins.
Keep relevant T paths enabled. Public C APIs, Lua-visible results, callbacks,
errors, loading, external-string lifetimes, allocation recovery and collection
safety remain required, regardless of which test interface exercises them.

Prefer actual Ada invariant tests for useful safety checks expressed in C
internals. Permit independently reviewed exclusion of exact optimizer streams,
private bucket/cache geometry, internal free-list layout and exact allocation
or backing-store counts when no public compatibility requirement depends on
them. Preserve semantic assertions sharing those blocks. Uncertainty retains
the requirement; implementation cost alone is not an exclusion reason.

Every exclusion identifies the original source span/hash, affected
configurations, original invariant, compatibility rationale, independent
author/reviewer approval and retained witnesses where applicable. Exclusions
are source-only resolutions, never passing execution evidence. Public header
entries, ordinary or mixed semantic assertions and previously accepted passing
obligations cannot be excluded. Adapt only disposable fixture copies using
source-hashed transformation manifests.

## Alternatives

Exact emulation of C-private representations would impose unnecessary storage
and optimization constraints. Blanket T disabling would omit real C API and
failure-path compatibility. Neither satisfies the approved target.

## Consequences and verification

Preserve historical scope semantics and all original source/header identities.
Report target acceptance, actual passes, equivalents and exclusions separately;
an accepted target with exclusions does not certify every original assertion.
Validate exclusion eligibility and provenance with focused rejection tests.
Retain 26 final contexts, inspect actual results and publish exact-revision
acceptance evidence. One ready PR triggers automatic Codex review. Address all
findings and pass current-head gates before the authorized merge; inspect the
post-merge workflow before reporting completion.
