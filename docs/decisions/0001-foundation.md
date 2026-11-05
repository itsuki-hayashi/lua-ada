# ADR 0001: Foundation Policies

Date: 2026-11-05. Status: accepted by the initial project plan.

## Context

The initial repository contained only a nested Alire executable that performed
no work. The project needs durable constraints and management before runtime
implementation. Whole-interpreter development is outside this milestone.

## Decision

- Promote the crate to the root and retain its identity, MIT license, version,
  and no-op behavior. Enforce Ada 2022 and strict diagnostics now.
- Use Windows, Linux, and macOS as target platforms, tracking evidence separately.
- Keep pinned Lua 5.5.1 and ada-lua submodules as reference-only material.
- Require semantic/public API parity; review Ada equivalents of C-internal
  assertions rather than requiring identical internal compiler/collector layouts.
- Allow narrow essential C ABI and OS glue; keep interpreter logic in Ada.
- Use GNAT trailing/public GNATdoc convention. Keep optional tools separate
  from normal builds and production dependencies.
- Maintain owning documents, stable backlog IDs, decisions, and dated handoffs.

## Alternatives and consequences

Retaining the nested crate would preserve an unnecessary entry-point split.
Implementing libraries/tests now would exceed the chosen documentation/layout
scope. Requiring every internal opcode assertion unchanged would constrain the
compiler beyond public compatibility. An absolute Ada-only rule would leave
portable varargs/OS interoperability feasibility unresolved.

These choices permit idiomatic internal design but demand explicit test mappings
and strong C-boundary evidence. Runtime architecture remains design intent;
there are no invented public APIs or compatibility claims.
