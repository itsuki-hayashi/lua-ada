# Compiler limit context and declaration precedence

Date: 2026-11-08, Asia/Tokyo. Component checkpoint; delivery continues.

The canonical compiler now saves the rejected function's defining line before
destroying its partial graph. Its bounded diagnostic formatter distinguishes
the main function from an actual nested function and retains the existing
200-local and 255-upvalue boundaries. Both runtime loading paths use that
scalar context; no freed prototype or source-sized formatting copy is needed.

Unchanged errors.lua then exposed a precedence requirement: its final local
overflow deliberately lacks the function's closing end. Native checks names
as they arrive, before that later grammar error. Compatible parsing now counts
active local declarations owned by the current function, plus not-yet-visible
names in the same list. It excludes outer functions, expired scopes, global
bindings and the chunk's implicit environment upvalue. The private frontend
policy is named Compatible_Limits to describe both stack and declaration
checks. Standalone checking and bounded Ada sessions preserve their previous
host-depth policy and grammar-checking domain. Canonical encoding checks
remain independently enforced.

Ten separately named native-paired cases cover main/nested/parameter context,
the exact local and upvalue boundaries, excess captured upvalues, incomplete
body/parameter precedence, expired scopes and outer-function ownership.
Both local configurations pass all 2,394 AUnit cases. All eight native/Ada
compiler/VM combinations pass the ten-case public Lua fixture. Six strict
tests/C/CLI builds pass serially with Alire 2.1.1 and GNAT 16.1.0; all twenty-six
default and twenty-seven instrumented standalone C executables pass. Required
Ada 2022 flags, warning/style policy and runtime checks remain enabled.

Fresh unchanged errors.lua completes with exit zero and empty stderr in all
four native/Ada default/T executions. Its expected stack-overflow call counts
are implementation dependent; raw outputs are retained rather than presented
as byte-identical output. Both full runs retain the original generated limit
and error assertions without reduced-suite flags or adaptations.

Build and regression evidence is under reports/compiler-limit-contexts;
unchanged-file captures are under reports/combined-reader-failure/
errors-01f60346b2f243d8bed9be1d53159dc2. Independent peer review inspected the
saved compiler context and runtime consumers. Full source-ledger acceptance,
final-head replay, platform matrix and independent certificate remain pending.
No reference/module source or pin changed.
