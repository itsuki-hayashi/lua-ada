# Testing and Analysis

Each independently meaningful behavior and boundary condition needs a separate,
descriptively named AUnit case. Comments should explain why the input matters,
the action under test, and the expected Lua behavior. Do not hide unrelated
assertions inside a few broad test procedures. Treat test code as maintained
human-facing documentation of the interpreter contract.

The nested AUnit suite has 167 individually named lexical, integer, number,
language, and session/lifetime cases. The check driver exercises static/shared
consumers, 19 CLI processes, and six raw-byte differential fixtures against pinned
C Lua. The arithmetic fixture contains 2,366 combinations. See [status](status.md)
for actual platform evidence; coverage percentages and full conformance are not
claimed.
See [current tests](../tests/README.md) for working commands.

## Test layers

| Layer          | Expected evidence                                         |
| -------------- | --------------------------------------------------------- |
| Ada unit       | AUnit cases for contracts, boundaries, failures           |
| Upstream Lua   | Applicable unchanged tests from the pinned `testes/`      |
| Project Lua    | Regression scripts and differential C/Ada results         |
| C API/ABI      | Existing headers, C-only hosts, callbacks, native modules |
| Build/link     | Static/shared consumers on each supported configuration   |
| Fuzz/proof     | Replayed failures or actual checks for named targets      |

Unit tests must verify behavior, not merely reproduce implementation steps.
Every compatibility fix needs a focused regression where practical. Record
tool versions, commands, test counts, failures, exclusions, and relevant seeds.

## AUnit and GNATtest

The `tests/alire.toml` crate has test-only AUnit and `lua_ada` pinned to `..`.
Its handwritten runner returns a failing process status when any case fails.
Keep AUnit out of production and expand tests as implemented behavior grows.

GNATtest is an optional developer executable, not a linked dependency. Install
it separately if desired, then invoke through the test crate's environment:

```text
alr exec -- gnattest -P ../lua_ada.gpr
```

This is a future invocation from `tests/`, not a working command today. Ensure
the installed executable is on PATH (Alire's install bin may not be added).
There is no `alr gnattest` command.

Before generation, calculate `--tests-root` from the actual object directory:
relative GNATtest output paths resolve against that directory, not the shell's
working directory. Keep handwritten bodies tracked outside build output.
Harnesses and generated specs are disposable; preserve read-only markers in
maintained skeleton bodies. Customize `gnattest_common.gpr`, not generated
harness sources. Override generated Ada 2012 settings with `-cargs:Ada
-gnat2022` when necessary and confirm all mandatory flags remain effective.
Use a test-only non-library GPR for internals if library interface restrictions
would otherwise force exposing private implementation units.

## Lua and C compatibility

Build pinned C Lua separately as an oracle. Run project scripts against both
interpreters with the same locale, environment, fixtures, numeric settings,
arguments, and random seeds. Compare exit status, output, and intended errors;
normalize only documented nondeterminism. Preserve minimized regressions.

Run upstream scripts unchanged from a disposable working copy: the suite can
write fixtures and timing files. Keep submodules clean. Inventory every upstream
test and distinguish language/public API coverage, platform prerequisites, and
C-internal instrumentation. A successful reduced suite is not full conformance.
See [the compatibility contract](compatibility.md) and the complete
[upstream-file inventory](upstream-tests.md).

C tests must cover header/record layout, symbols, callbacks, allocator failures,
protected errors/yields, nested reentry, extra space, lifetime, loading modules,
and C-only host initialization. Validate static/shared linkage independently.

## Optional fuzzing

GNATfuzz is an AdaCore Pro tool with Linux/AFL environment requirements. It is
not needed for ordinary builds. Build the target first, analyze it, inspect
`analyze.json`, select a genuinely fuzzable subprogram, then generate/build
its separate harness and seed corpus. Use a bounded campaign and record limits.

Harness customizations belong in `user_configuration/`, never `generated_src/`.
Do not run concurrent campaigns against one harness. Persistent execution needs
complete setup/teardown; otherwise use an appropriate nonpersistent mode.
Inspect and replay saved crashes before calling them bugs: failed Ada runtime
checks indicate contract/check violations, not necessarily memory corruption.
Keep reviewed seeds and minimized regressions tracked; ignore generated sessions.

## Optional proof

Mark suitable bounded units explicitly with `SPARK_Mode => On`. Read the
installed release's manuals and GNATprove skill. Within an Alire crate use
`alr gnatprove -P lua_ada.gpr --level=0` for an initial scoped investigation;
scope actual units and record generated-check counts. There are no proof
targets today.

Run only one prover instance per project. Set a level explicitly, capture logs,
and inspect `gnatprove.out` for unit coverage, proved/unproved counts, assumptions,
and warnings. No checks generated is not success. Do not use assumptions, axioms,
suppressions, weaker contracts, or `SPARK_Mode => Off` to hide proof failures.
Levels 3/4 require prior agreement under the GNATprove skill. Use incremental
proof normally and a clean measurement only when repeatability requires it.
