# Development Setup

Use Alire and the latest stable native GNAT available through its index.
Record exact versions; do not silently change globally selected compilers.
Alire first-use operations may install tools/MSYS2 and need normal network access.

## Build and check

The root is now a library crate. CLI and AUnit are separate local-pinned crates.
Run from the root in PowerShell 7:

```text
alr build --development
alr -C cli build
alr -C cli exec -- bin/static/lua_ada --help
./scripts/check.ps1 -LibraryType static -Profile validation
./scripts/check.ps1 -LibraryType relocatable -Profile validation
```

The check driver builds the requested root profile plus both consumers, runs
AUnit, 19 CLI process cases, and six byte-exact C/Ada differential fixtures. Accepts development, validation,
release, and static/static-pic/relocatable. It configures library search paths
and restores the calling environment. See [embedding](embedding.md) for Ada use.

For direct scenario builds, pass -XLUA_ADA_LIBRARY_TYPE=relocatable after the
Alire -- separator. Apply the same scenario to the library and consumers.
Object/library directories include profile and kind; binaries include kind.
The driver explicitly overrides the parent dependency profile to match each
matrix entry; a default AUnit build otherwise uses its validation setting.

Avoid bare alr run when both kinds exist: it finds multiple executable candidates.
Use alr exec with the explicit bin/<kind>/<program> path. Windows adds .exe;
Alire also resolves the documented extensionless path on Windows.

## Compiler and generated state

Every first-party GPR appends -gnat2022 -gnatwa -gnatwe -gnatv -gnaty.
The manifest keeps runtime checks enabled in every profile. Optimization/debug
defaults remain Alire's. Inspect verbose actual commands, not only configuration.

Generated config/ and alire/ files are recreated by Alire; do not copy or edit
them. Production uses standard Ada and one isolated system math primitive (ADR 0005);
AUnit is test-only. Optional
GNATdoc/GNATtest/GNATfuzz/GNATprove tools are not ordinary-build prerequisites.

## References and platforms

See [reference maintenance](../references/README.md),
[ABI experiments](../experiments/abi/README.md), and [tests](../tests/README.md).
The comparison driver builds pinned C Lua independently without changing its
sources. OracleOnly checks fixtures, never Ada parity.

The workflow covers three OS targets, three profiles, and two library modes.
Its existence is not validation: Linux/macOS results remain unverified until
CI runs. Record OS, architecture, compiler, linker, C runtime, and Lua settings
with compatibility claims. Local logs belong in ignored reports/.
