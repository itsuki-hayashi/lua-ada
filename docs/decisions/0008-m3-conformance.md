# ADR 0008: M3 Conformance and Compatibility Boundaries

Date: 2026-11-06, Asia/Tokyo. Status: accepted target; implementation staged.

## Context

The accepted [M3 target](../milestones/m3.md) combines remaining language and
library work with canonical execution and the public C interface. The pinned
suite includes assertions about language behavior, public interfaces, C-only
representations, and platform services. Neither an early return when T is absent
nor a platform-specific failure establishes a passing conformance test.

The upstream ltests.h also changes configuration: global compatibility, math
compatibility, the random generator, extra space, and stack limits differ from
the ordinary build. A test-instrumented ABI cannot certify the default ABI.

## Coverage decision

Preserve all reference sources and hashes. Track unchanged execution, reviewed
Ada-internal equivalents, and reviewed native-platform equivalents separately.
Equivalents retain the original source anchor, invariant, C baseline result,
replacement case, and independent review evidence. A missing Ada feature cannot
be relabeled as an internal or platform difference.

The inventory scanner finds lexical assertion and guard sites. Its output is
an audit aid, not proof that every generated assertion or semantic path has been
enumerated. Each file retains an explicit manual-audit obligation. The foundation
validator permits pending coverage; the final acceptance validator rejects it.
No fabricated T values, no-op invariant checks, or inferred successes are allowed.

Run default and upstream-test configurations in isolated output directories.
Reports name the executable, configuration, pin, source hashes, limits, process
outcome, markers, and observed skips. Full-suite output is retained as bytes;
timings, allocation totals, seeds, and expected warnings prevent treating whole
stdout equality or empty stderr as the aggregate acceptance contract.

## Planned runtime decisions

M3 migrates execution to the canonical 85-opcode format while retaining Ada
values, explicit ownership, contracts, and continuation-based native libraries.
Canonical code generation and execution remain unimplemented in M3-01.

One universe owns shared storage; each coroutine owns execution state. Lua
semantic stack errors and allocator refusal become catchable language errors.
Explicit host quotas continue to abort execution. Ada sessions retain bounded
defaults; the planned CLI and standard C-created states use Lua-compatible
defaults. These policies are distinct from test-only safety ceilings.

The future C boundary uses status-returning Ada operations and C-owned guards.
No foreign jump may cross a live internal Ada frame. Arbitrary synchronous C
callbacks require a bounded foreign-API reentry portal using the existing
universe, roots, counters, and protected state. This is a narrow planned exception
to ADR 0007's non-reentrant Ada/native-driver rule, not permission to recurse
through Sessions.Execute or reset budgets. Ordinary Ada/native drivers continue
requesting calls through explicit continuations.

Yields retain their continuation/context in explicit activations. Panic transfers
must reach the outer C-owned entry before invoking a panic callback; returning
from only the innermost Ada helper is insufficient. The real-export feasibility
gate must pass before these mechanisms become compatibility claims.

Allocator-aware storage must include input-sized temporary and compilation
allocations, stable strings/userdata, and the exact configured extra-space prefix.
Public concrete layouts and C stdio streams require real ABI representations.
C glue may implement ABI, varargs, lifecycle, and platform mechanics; interpreter
logic remains Ada. Reference C Lua is an isolated oracle only.

## Delivery and verification

Each M3 gate is a separate implementation task and PR, based on its merged
predecessor. The agent does not merge PRs. Gate M3-01 establishes contracts,
inventory validation, and C baseline tooling; it does not implement the future
runtime/API policy above or close M3.

Every gate retains strict compiler flags and runtime checks, adds focused tests
for its behavior, and records actual results. The final gate requires resolved
coverage for all active upstream blocks, default and instrumented configuration
evidence, all required OS/profile/link jobs, and an open verified acceptance PR.

Optional analysis tools and ecosystem fixtures remain outside this gate.
