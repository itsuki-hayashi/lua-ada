# Development Setup

Install [Alire](https://alire.ada.dev/) and use the latest stable native GNAT
available through its index with compatible GPRbuild. Record exact versions;
do not commit local tool paths or silently change global toolchain selections.

```text
alr --version
alr toolchain
alr exec -- gnat --version
alr exec -- gprbuild --version
```

Alire can trigger first-use setup, including MSYS2 on Windows. These commands
are operational instructions, not guaranteed side-effect-free probes. Complete
needed setup in an authorized normal shell if restrictions prevent it.

## Root-level workflow

Run from the repository root in PowerShell or a POSIX shell:

```text
alr build --development
alr run
alr build --validation
alr run
alr build --release
alr run
```

The current executable succeeds without output. To inspect compiler arguments,
force a verbose rebuild of each profile:

```text
alr build --development -- -f -v
alr build --validation -- -f -v
alr build --release -- -f -v
```

The GPR appends `-gnat2022 -gnatwa -gnatwe -gnatv -gnaty` after generated
profile switches. The manifest enables runtime checks for every profile; no
build may silently substitute `-gnatp`. Optimization/debug defaults remain
Alire's. See [profile configuration](https://alire.ada.dev/docs/catalog-format-spec#build-profiles-and-switches).

Generated `config/` and `alire/` state is recreated by Alire. Never copy it from
the old nested crate or edit it. Objects use `obj/<profile>`, executables `bin/`.
Future library builds must also separate artifact directories by library kind.

## Platforms and dependencies

Windows, Linux, and macOS are targets, not automatically validated platforms.
Record OS, architecture, compiler, linker, C runtime, and Lua configuration with
compatibility evidence. No CI or library targets exist yet.

The production crate has no external dependencies. AUnit will belong to a nested
test crate pinned to the local parent. GNATdoc, GNATtest, GNATfuzz, and GNATprove
are developer tools, not prerequisites for ordinary builds.

See [reference maintenance](../references/README.md). Keep reference sources
outside `Source_Dirs`; build C Lua separately as an oracle once tests exist.
