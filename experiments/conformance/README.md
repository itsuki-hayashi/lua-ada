# Isolated upstream conformance baseline

This experiment builds pinned C Lua as an independent baseline process. It
does not link C Lua into Lua Ada, implement an Ada `T` module, or establish M3
acceptance. The [milestone contract](../../docs/milestones/m3.md) and
[coverage inventory](../../tests/conformance/README.md) own those requirements.

The runner checks the complete tracked reference tree against commit
`7579fc9d7ed90240487251dfb69168f8e64e9294`, including staged edits, and rejects
untracked or ignored source inputs. Its GPR source lists are explicit. It copies
the complete `references/lua/testes` directory into a fresh disposable run
directory, verifies its bytes against the checkout and the 34-file manifest,
and checks the original copied files again after execution. Reference sources
and future ecosystem fixtures are never edited or used as production inputs.

## Build and run

Run from the repository root with the configured Alire toolchain. Alire builds
must be serialized because its generated configuration is shared.

On Linux, install the host's readline development/runtime package so the pinned
default name `libreadline.so` is loadable (`libreadline-dev` on Ubuntu CI).
The separate C oracle uses this optional system facility; the Ada production
crate gains no dependency. Before recording executions, the runner probes
`-E -W -i` with closed stdin and requires successful initialization and empty
stderr. A missing default readline library is a setup failure, not a platform
equivalent or a successful reduced upstream run.

```powershell
pwsh -NoProfile -File scripts/run-conformance.ps1 `
  -Configuration default -BuildReference -Mode Smoke
pwsh -NoProfile -File scripts/run-conformance.ps1 `
  -Configuration upstream-test -BuildReference -Mode Smoke
pwsh -NoProfile -File scripts/test-conformance-runner.ps1 `
  -ReferenceInterpreter build/conformance/default/bin/lua.exe
```

On Linux and macOS, omit `.exe` in the last command. The direct equivalent build
is `alr exec -- gprbuild -P experiments/conformance/oracle.gpr
-XLUA_CONFORMANCE_CONFIGURATION=default`; this command alone does not execute
the runner's source-tree witness. Prefer the runner for recorded evidence.

`reference.gpr` produces an independent shared C library and `oracle.gpr`
builds the original CLI around it. Their default and instrumented outputs are
separate under `build/conformance/<configuration>/`. Native Linux, macOS, and
Windows platform definitions enable the upstream OS and module-loading paths.
The runner builds all five native fixtures from the unchanged copied sources,
including `lib2-v2.so` from `lib22.c`. Windows dependent modules link the real
`lib1` and `lib2` import libraries. Fixture suffixes remain `.so` as required by
the upstream scripts, including on Windows.

| Mode        | Input                     | Wall limit | Lua allocation ceiling |
| ----------- | ------------------------- | ---------- | ---------------------- |
| `Smoke`     | Configuration/native load | 900 s      | 2 GiB                  |
| `File`      | One named manifest file   | 900 s      | 2 GiB                  |
| `Aggregate` | Unchanged `all.lua`       | 3,600 s    | 2 GiB                  |
| `Heavy`     | Unchanged `heavy.lua`     | 600 s      | 64 MiB                 |

`Suite` is an alias for `Aggregate`. Select an individual source with
`-Mode File -File tpack.lua`; select `all.lua` and `heavy.lua` through their
dedicated modes. Per-file runs are independent observations: files requiring
the aggregate harness's globals or module setup may fail independently. The
runner does not synthesize missing harness state or call these failures passes.

Use `-Mode Aggregate -ReportOnly` to collect a known-failing platform baseline
without stopping a later collection step. `ReportOnly` permits a nonpassing
execution observation, but still fails setup errors. Its JSON retains the real
failure, and `gate_acceptance` remains false. A zero collector exit does not
mean Lua conformance. Native Windows incompatibilities in unchanged Unix-centric
tests are failures requiring reviewed future equivalents, not automatic skips.
Timeouts, abnormal exit statuses, resource aborts, capture/output failures, and
fixture mutations still fail `ReportOnly`; collecting an ordinary test failure
does not excuse a broken or unsafe harness run.

## Configuration and allocation contracts

The private `--conformance-config` operation emits the compiled configuration.
Before execution the runner verifies the release, numeric widths, global mode,
extra space, stack/C-call limits, buffer size, RNG and math compatibility flags,
and inherited allocation ceiling. Extra space and buffer sizes are observed in
the compiled library; expected extra space is calculated independently in the
driver from the native pointer or unchanged `struct L_EXTRA` type.

| Setting                  | `default`                | `upstream-test`                 |
| ------------------------ | ------------------------ | ------------------------------- |
| Integers/numbers         | 64-bit/binary64          | 64-bit/binary64                 |
| `LUA_COMPAT_GLOBAL`      | 1                        | 0                               |
| `LUA_EXTRASPACE`         | Native pointer size      | `sizeof(struct L_EXTRA)`        |
| `LUAI_MAXSTACK`          | 1,000,000                | 68,000                          |
| `LUAI_MAXCCALLS`         | 200                      | 180                             |
| `LUAL_BUFFERSIZE`        | Native upstream formula  | 23                              |
| `LUA_RAND32`             | Disabled                 | Enabled                         |
| `LUA_COMPAT_MATHLIB`     | Disabled                 | Enabled                         |
| Internal test module `T` | Absent                   | Real unchanged upstream module  |

The instrumented build uses the actual pinned `ltests.h`, not an approximation
of its macros or a fabricated table named `T`. Test-only wrappers include
unchanged upstream translation units:

- `observed_ldo.c` observes private stack/C-call limits and library layout
  settings without copying their definitions into the reporting driver.
- `bounded_ltests.c` retains the upstream debug allocator, fault injection,
  identity checks, and `MEMLIMIT` behavior. It interposes only backing
  `malloc/free`, adding an independent ceiling that `T.totalmem` cannot remove.
- `conformance_cli.c` includes the original CLI so its options, arguments,
  child invocations, panic/warning behavior, and test paths remain reference
  behavior. In default mode its allocator wrapper retains the original state
  initializer and includes those initial state bytes in subsequent accounting.
- `conformance_exports.h` adds the missing `extern` to Windows DLL API
  declarations. Upstream `ltests.h` declares `l_memcontrol` through `LUA_API`;
  plain `dllexport` would create tentative definitions in every translation
  unit with modern GCC. This preserves its one upstream definition and avoids
  `-fcommon`. `module_exports.h` exports unchanged native fixture entry points.

Default allocation accounting measures live Lua payload bytes. Instrumented
accounting measures upstream debug-allocator backing bytes, including its
headers and marks; the wrapper's own small alignment headers are additional
host overhead. Neither ceiling is a total process-RSS guarantee. In default
mode the small initial state is created by the original initializer before
allocator interposition and then included in the balance. These measurements
are reported explicitly and must not be treated as identical profiles.

The launcher accepts only positive decimal allocation limits, rejecting signed,
whitespace-prefixed, zero, and overflowing values before CLI execution. The
runner chooses 2 GiB or 64 MiB. The environment propagates that profile to
upstream CLI child processes, avoiding a child silently returning to a different
budget. Allocator refusal remains an ordinary catchable C Lua memory error;
it does not prove a heavy test completed. Heavy execution is a separate future
acceptance observation, not part of the quick self-tests.

The child PATH begins with the selected interpreter's binary directory and its
library directory. A Lua `io.popen` probe executes bare `lua` and requires its
configuration record to match the selected parent, including the allocation
ceiling. This protects upstream subprocess tests from an absent or unrelated
system Lua and keeps default/instrumented children in the intended profile.

## Reports and process safety

Each invocation writes `reports/conformance/<run-id>/report.json` unless
`-Report` selects another report path. Disposable fixtures and raw `.stdout`
and `.stderr` files stay under that run directory. JSON schema version 1 records:

- Requested and observed configuration, probe process, and verification state.
- Bare-Lua subprocess configuration probe and its exact raw captures.
- Default REPL preflight process, including raw output and prerequisite failures.
- First-party repository revision and worktree status, including uncommitted
  tracked and untracked inputs, plus OS description, OS/process architecture,
  and PowerShell version. A dirty run is evidence for those exact input hashes,
  not a claim that its changed inputs belong to the recorded commit.
- Full reference C/header and first-party harness input hashes, copied fixture
  hashes, post-execution changes, executable and shared-library hashes.
- Runner, process collector, inventory validator, and suite manifest hashes as
  well as the C/GPR inputs, since these select and classify the observations.
- Exact compiler argument vectors, build process captures, and native fixture
  source/artifact hashes when the runner performs those builds.
- Execution arguments, directory, elapsed time, exit status, timeout/capture
  outcomes, raw stream paths, sizes and SHA-256 digests.
- Conventional Windows high-bit and POSIX signal-like exit statuses, recorded
  as abnormal observations without claiming the exit code alone proves a crash.
- Required completion marker, detected skip/warning lines, execution outcome,
  setup failures, and separate coverage-acceptance state.

Raw byte streams are authoritative. Text is decoded separately to classify
markers and messages, preserving invalid UTF-8 and embedded NUL in the files.
Unavailable locale messages are omissions even when they do not say skipping.
The collector does not compare nondeterministic full-suite output byte for
byte. Warnings and skips stay visible; successful exit and a marker cannot
establish branch-level coverage. `foundation_smoke_passed` applies only to a
verified C smoke with empty stderr. Every report has `gate_acceptance=false`
until the separate coverage and equivalence gates are actually implemented.

Child stdin is closed. Ambient Lua startup/search-path variables are removed
from the child's environment without changing the parent environment. Streams
are drained asynchronously with a 64 MiB limit per stream. Active root
processes exceeding wall/output limits are killed with their descendant tree;
failed termination or pipe draining is an explicit failed observation. An
already exited root whose descendant retains an inherited pipe causes a
bounded drain failure. The current process API cannot promise to discover and
terminate every already-orphaned descendant; runs are not an OS sandbox.

`-Target Ada -Interpreter <path>` only records the current limited interpreter's
execution. It has no verified configuration probe, real upstream `T` module,
or CLI-compatible unlimited profile. Instrumented Ada mode is therefore
rejected. Neither target selection nor a successful Ada smoke promotes it to
baseline parity. `-RuntimeDirectory` supplies shared-library lookup for an Ada
consumer when required.

The focused process/copy self-tests cover byte preservation, empty streams,
warnings, missing markers, skip detection, resource diagnostics, timeouts,
output ceilings, start-failure cleanup, and fixture mutation. The optional
reference executable case verifies negative allocation limits are rejected.
These are harness tests, not Lua semantic coverage. Upstream sources retain
the license notices in the pinned checkout and copied fixtures.
