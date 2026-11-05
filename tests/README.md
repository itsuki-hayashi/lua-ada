# Tests

This is a nested Alire crate. AUnit is a test-only dependency; Lua Ada is pinned
to the local parent. The runner returns a failing process status on any AUnit
failure. Current tests exercise lexical boundaries, strings, locations, errors,
token budgets, seeded arbitrary source bytes, and integer boundary semantics.
They do not execute scripts.

From the repository root with PowerShell 7:

```text
./scripts/check.ps1 -LibraryType static -Profile validation
./scripts/check.ps1 -LibraryType relocatable -Profile validation
./scripts/compare.ps1 -OracleOnly
```

The check driver builds the root library and both consumers, configures shared
library lookup, runs AUnit, and checks CLI help/version/failure behavior.
It does not claim interpreter acceptance. The matrix workflow runs all three
profiles and both link modes on Windows/Linux/macOS.

The comparison driver builds a separate pinned C Lua oracle without changing
reference sources. OracleOnly validates the fixtures, not Ada parity.
Once script execution exists, supply -Interpreter with the Ada executable to
compare exact output and status. Mismatch/timeouts fail the driver.

Keep Lua fixtures in lua/. Future C compatibility clients and GC/session tests
belong to dedicated groups. See [strategy](../docs/testing.md) and
[M1 acceptance](../docs/milestones/m1.md).
