# Tests

This nested Alire crate keeps AUnit out of the production dependencies and pins
Lua Ada to the local parent. The handwritten runner exits unsuccessfully on any
failed assertion or unexpected exception.

There are 167 focused, separately named cases with explanatory comments:
integer (21), lexer (33, including 1,000 seeded byte scans), numbers (30),
language/session (47), and lifecycle/resources/GC (36). Each case represents a
specific behavior or boundary rather than an empty generated skeleton.

From the repository root using PowerShell 7:

```text
./scripts/check.ps1 -LibraryType static -Profile validation
./scripts/check.ps1 -LibraryType relocatable -Profile validation
./scripts/compare.ps1 -Interpreter cli/bin/static/lua_ada
```

Windows accepts the extensionless executable path; the actual file is .exe.
The check driver builds root and both consumers under the requested profile,
sets exact shared-library paths, runs AUnit, 19 CLI process cases, and six
differential fixtures. Matrix CI repeats it on Windows/Linux/macOS in all three
profiles and both link modes.

The comparison driver independently builds pinned C Lua. It compares stdout
and stderr as raw bytes and checks exit status, failing on mismatch or timeout.
The numeric fixture covers 2,366 operand/operator combinations; binary_output
protects NUL/invalid-UTF-8 behavior. OracleOnly is an explicit fixture-only mode
and never establishes Ada parity.

No whole upstream test file is claimed passing. See the complete
[inventory](../docs/upstream-tests.md), [strategy](../docs/testing.md), and
[M1 acceptance](../docs/milestones/m1.md). ABI fixtures are feasibility tests,
not production C API coverage. Optional generated harnesses, fuzzing, proof,
and coverage percentages have no claimed results.
