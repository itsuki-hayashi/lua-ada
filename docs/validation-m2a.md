# M2a Validation Evidence

Date: 2026-11-06, Asia/Tokyo. **All M2a implementation gates passed.**

Implementation evidence: [18-job acceptance run](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42065684688)
at commit `d8770ef8ea578fd304dac766e6380ee7b9886de6`.
All 18 job logs were inspected, including actual test totals and the three
static-validation oracle/ABI steps. The final handoff adds documentation and
strengthens the existing multiline error-priority test; production sources
remain identical to this accepted implementation.

## Configurations

- Windows Server 2025 / Windows 10.0.26100, x86_64-w64-mingw32:
  development/validation/release, static/shared; validation static-PIC also passed.
- Ubuntu 24.04.5 LTS, x86_64-pc-linux-gnu:
  development/validation/release, static/shared.
- macOS ARM64, aarch64-apple-darwin24.6.0:
  development/validation/release, static/shared. Hosted images reported 26.6.2
  for static-development and shared-development/release, and 26.7.2 for
  static-validation/release and shared-validation.

All jobs selected stable native GNAT 16.1.0 via Alire 2.1.1, GPRbuild package
26.0.1 (banner 26.0.0), and test-only AUnit 26.0.0. No machine-specific pin
was introduced. A local verbose compile of the new parser confirmed
-gnat2022 -gnatwa -gnatwe -gnatv -gnaty, overflow/assertion checks, and the
existing ADR 0003 floating-validity exception; no check suppression was added.

## Per-configuration acceptance

Each of the 18 jobs passed 347 independently named AUnit cases, zero failed
assertions/unexpected errors, the standalone public Ada syntax/session consumer,
30 CLI cases, and all six existing raw-byte execution differential fixtures,
including the 2,366-operation arithmetic matrix.

The 347 cases comprise 21 integer, 33 original lexer, 30 number, 52 session,
37 lifecycle, 89 canonical opcode, 77 syntax, and eight incremental lexer cases.
The numeric-for test now follows Lua 5.5's const control-variable rule.
New syntax cases exercise complete grammar families, attributes, global rules,
label/goto visibility and scope, captures, resource bounds, error priority,
and unsupported-feature rejection before execution.

The Windows static-validation job additionally passed the same acceptance
under static-PIC. All OS static-validation jobs passed the existing isolated
ABI probe. Observed reference layouts remained integer=8, number=8, debug=144,
extraspace=8, and debug.currentline.offset=48; these are measured configurations,
not portable ABI constants or a full facade compatibility claim.

## Frontend and opcode campaign

Each OS static-validation job passed:

- All 85 canonical opcode names, IDs, formats, and metadata; 4,096 arbitrary
  instruction-word field/top comparisons with pinned C Lua.
- 10,000 seeded bounded arbitrary-byte token-stream comparisons, including
  payloads and scanner lines (241,877 protocol records).
- A 10,000-name allocation-pressure lexical failure regression protecting the
  C adapter's rooted diagnostic source label (10,001 records).
- 2,000 generated valid grammar cases and 2,000 mutations, compared for
  acceptance/rejection and reported lines (8,000 records).
- Token and raw-source compile-only comparisons for all 34 unchanged upstream
  files. Both raw interfaces reject the two leading-# loader preambles;
  separate CLI cases verify file BOM/shebang handling.

Seed 551, generation rules, subprocess failure/timeout handling, and corpus
retention are tracked in scripts/check-frontend.ps1. The baseline is unchanged
Lua 5.5.1 commit 7579fc9d7ed90240487251dfb69168f8e64e9294, default contextual
global, ASCII classification, int64, and binary64. No Lua source is executed
by the frontend campaign.

## Scope and limits

The [contract](milestones/m2a.md) and [inventory](frontend.md) own exact bounds.
C register allocation, local/upvalue representation limits, instruction size,
optimizer behavior, and C-stack exhaustion are excluded from grammar parity.
Ada frontend budgets fail as controlled resource results. Error wording is
intentionally Ada's; syntax category and reported lines are compared.

All unchanged upstream trees and eight ecosystem fixtures retain their pins.
No ecosystem test, native module, LuaRocks workflow, complete opcode execution,
canonical code generation, binary chunk interoperability, or full upstream
execution suite was delivered or claimed. GNATdoc rendering, GNATtest generation,
GNATfuzz campaigns, and formal proof were not run.

The [PR](https://github.com/itsuki-hayashi/lua-ada/pull/3) is open for review;
merging requires a separate maintainer instruction.
