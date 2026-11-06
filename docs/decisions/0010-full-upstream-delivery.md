# ADR 0010: Complete Upstream Delivery in One PR

Date: 2026-11-06, Asia/Tokyo. Status: accepted implementation contract.

## Context

The maintainer requested completion of every official Lua test file, selected
full M3 coverage including the C API/internal obligations, and approved one major
implementation PR. Merged PR #7 provides the 587-case lifecycle baseline; it
does not provide canonical execution, allocator parity or the full C interface.

## Decision

Implement the remaining M3 gates on codex/m3-upstream-conformance from merged
PR #7, retaining coherent checkpoint commits in one PR. This supersedes the
separate-PR delivery order in ADR 0008 and the limited exception in ADR 0009;
their ownership, safety and compatibility requirements remain in force.
The [milestone](../milestones/m3.md) owns the checkpoints and acceptance target.

First establish allocator-aware indexed storage and real foreign-boundary
feasibility. Then migrate execution to canonical instructions and implement
binary chunks, complete collection/finalization, C APIs, remaining libraries,
debug facilities, CLI behavior and the test adapter. Remove the old packet
backend only after migration/regression evidence. Ordinary native library
callbacks retain explicit continuations; C reentry uses a reviewed execution
portal sharing roots, allocator, protected boundaries and budgets. No foreign
nonlocal jump crosses active internal Ada frames.

Default and instrumented configurations remain distinct. Allocation ceilings
produce catchable Lua allocator refusal; explicit host quotas remain aborts.
Every input-sized allocation, including compilation and temporary storage,
participates in the allocator audit. Memory reports and test counters describe
actual tracked storage, never estimated C object layouts or process RSS.

## Test adapter and equivalence boundary

The unchanged complete ltests.c belongs only to the isolated C oracle. It reads
private C object layouts and cannot become a portable client of the Ada ABI.
The Ada test build instead combines real C public-API drivers with private Ada
inspection of actual prototypes, frames, tables, strings and collector state.
Derived C driver code retains pinned source citations, notices and a reviewed
extraction/change manifest. Its C test programs exercise actual Ada exports,
including errors, yields, panic and nested/cross-state callbacks.

C hash-bucket layouts, optimizer-specific streams and private collector
topology may use source-cited, independently reviewed Ada invariants. Adapter
results must describe real Ada state. Native-platform equivalents require a
matching C observation of the unsupported original assumption. Generated
equivalent aggregates are named and reported separately from unchanged all.lua
execution, preserving ordering, dump/load, return values, cleanup and warnings.
An Ada-only failure is never reclassified as a platform limitation.

## Coverage representation

Keep all pinned candidate anchors and API entries. A source candidate may be
`reviewed` without claiming execution: guards, reports, references and templates
link directly to actual runtime obligations. Only reviewed quoted inert data
has no runtime target. Independent review, source spans/hashes, applicability,
original C observations and per-context runtime evidence remain mandatory where
applicable. No T-absent exit or whole-file audit can stand in for omitted tests.
The [inventory contract](../../tests/conformance/README.md) defines validation.

## Consequences and verification

This is one substantial delivery, not permission to weaken the target to fit a
session. Checkpoint-only results remain partial. Complete all 26 final contexts,
full source/API evidence and independent reviews before PR readiness. Preserve
strict flags/runtime checks, fixture pins and the bounded Ada embedding policy.
No ecosystem fixture source, test execution or LuaRocks work belongs here.
No automatic merge is authorized.

The initial harness extension leaves all 4,490 source anchors and 473 API
entries pending. Its focused regressions validate classification and fail-closed
linkage; they do not establish any new runtime or C ABI conformance.
