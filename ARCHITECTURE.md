# Architecture

This is intended design, not an implemented runtime. Only the root executable
scaffold exists. Accepted [decisions](docs/decisions/README.md) govern the
foundation; detailed runtime representations need focused design evidence.

## Components and dependency direction

The reusable interpreter is central. CLI, Ada embedding, and C compatibility
interfaces share it. The core must not depend on the CLI, test frameworks,
reference sources, or C-facing representations. Do not mirror C source files
as Ada packages.

```text
CLI                 Ada embedding                 C compatibility facade
 |                        |                                |
 +------------------------+--------------------------------+
                          |
              Frontend / bytecode / execution
                          |
               Values / heap / tracing collector
                          |
                 Narrow platform services

Standard libraries use the runtime and platform services.
Tests exercise each layer without becoming runtime dependencies.
```

| Component        | Responsibility                                      |
| ---------------- | --------------------------------------------------- |
| Frontend         | Source bytes, lexer, parser, diagnostics            |
| Bytecode         | Instructions, verified chunks, compatible load/dump |
| Execution        | Frames, calls, closures, errors, yields, coroutines |
| Values and heap  | Scalars, objects, identity, allocation, roots       |
| Collector        | Cyclic tracing, barriers, weak references           |
| Standard library | Lua library semantics and module machinery          |
| Platform         | Files, clocks, processes, locale, module loading    |
| Ada interface    | Owned sessions, rooted handles, typed operations    |
| C facade         | Exports, callbacks, layout and lifecycle adapters   |
| CLI              | Arguments, interactive use, scripts, exit status    |

These are responsibilities, not settled package names or public types.
Private child packages should hide internals. Use tagged interfaces for useful
behavioral substitution, private discriminated types for value distinctions,
and generics for reusable statically typed algorithms. Scalars need not become
class-wide heap objects.

## Ownership and execution

Each Lua universe owns its heap, registry, allocator policy, collector, and
execution contexts. Coroutines share a universe but have distinct execution
state; they are not Ada tasks. Concurrent access requires a future explicit
synchronization contract.

Lua graphs have cycles and shared references. Reference counting and Ada
finalization cannot replace tracing garbage collection. Every reference surviving
an allocation/collection point needs a root or traced owner. Distinguish internal
references from C-observable identities and stable addresses. The allocator
callback contract must be investigated before choosing heap representation.

Controlled types may manage Ada session lifetimes, but do not implement Lua
`__gc`, `__close`, weak tables, or collector semantics. Define invalidation,
cross-universe rejection, cleanup, and errors before exposing handles.

## Safety and interoperability

Use bounded indexes, distinct types, checked conversions, contracts, and explicit
ownership. Preserve Lua integer wrapping through intentional modular operations,
not disabled overflow checks. Strings are bytes; UTF-8 is a library capability.

Isolate numeric parsing/formatting, patterns, locale, I/O, and platform behavior.
Implement portable behavior in Ada where practical. Essential OS bindings and
minimal C ABI glue stay behind narrow interfaces and contain no interpreter.

Do not allow foreign nonlocal jumps across Ada frames without a demonstrated
safe design. Protected calls, nested callbacks, yields, allocator failures, and
cleanup are early ABI feasibility gates. Native loading also requires matching
symbols, numeric configuration, library names, and host ABI. Validate Ada runtime
initialization/finalization from a C-only host.

Future library artifacts must be separated by profile and library kind (static,
static-PIC, relocatable). CLI and test crates will depend on the reusable library.
No library or public runtime API is introduced by this foundation.

## Verification

Use SPARK selectively for bounded representation-independent algorithms. Cyclic
graphs, controlled types, callbacks, and platform services need other techniques;
whole-runtime proof is not promised. AUnit protects local behavior, Lua
differential tests protect semantics, and C clients/modules protect ABI.
See [testing](docs/testing.md) and [compatibility](docs/compatibility.md).
