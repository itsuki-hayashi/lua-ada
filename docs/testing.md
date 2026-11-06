# Testing and Analysis

## M2a frontend checks

The [frontend guide](frontend.md) owns token/parser/opcode campaign details.
Run scripts/check-frontend.ps1 inside alr exec after building the nested tests.
CI runs it in static-validation on each OS. All configurations retain focused
AUnit and CLI coverage. Canonical code generation/execution are separate gates.

Each independently meaningful behavior and boundary condition needs a separate,
descriptively named AUnit case. Comments should explain why the input matters,
the action under test, and the expected Lua behavior. Do not hide unrelated
assertions inside a few broad test procedures. Treat test code as maintained
human-facing documentation of the interpreter contract.

The nested AUnit suite grows with each milestone. Historical M1 acceptance
recorded 171 cases and 19 CLI processes; M2a recorded 347 cases and 30 CLI
processes, with later merged regression additions. M2b adds individually named
library, codec, continuation, metamethod, loading, and recovery cases. Use the
actual final runner result rather than an intermediate build count. The check
driver also exercises static/shared consumers and seven raw-byte differential
fixtures, including 2,366 arithmetic combinations. See [status](status.md) for
actual platform evidence; coverage percentages and full conformance are not
claimed.
See [current tests](../tests/README.md) for working commands.

The [real-world module catalog](../tests/modules/README.md) records eight pinned
consumer fixtures for future parity testing. They are checked-out source only;
no module suites, dependency installation, or parity runners are enabled.
Keep their sources separate from development references and runtime dependencies.

## M2b library and unchanged-file acceptance

The completed [M2b validation](validation-m2b.md) records the initial 475-case suite
and the later 480-case final revision, three unchanged execution files, and all
18 configurations. The commands below
remain the reproducible protocol for later changes.

The [M2b milestone](milestones/m2b.md) owns exact exports and acceptance. Focused
AUnit cases exercise nested Lua/native calls, retained callback roots, error and
resource unwind/recovery, metamethod selection/raw bypass/isolation, pattern
boundaries, packing/float/UTF-8 limits, text-reader environments, module caches
and searchers, and table/math result adjustment. Test comments describe the
setup, action, expectation, and regression; a broad smoke script is insufficient.

After the nested test build, run the disposable runner from the root inside the
Alire environment, choosing the actual library-kind output path:

```text
alr exec -- pwsh -NoProfile -File scripts/check-upstream.ps1 -Interpreter tests/bin/static/upstream_runner
```

Use the platform executable suffix on Windows. The runner copies and verifies
unchanged tpack.lua, utf8.lua, bitwise.lua, and bwcoercion.lua. Each primary file
runs in fresh independent C/Ada processes with the same working directory and
local package path. bwcoercion.lua is a helper, not a fourth suite. No all.lua,
mode flags, T instrumentation, or ecosystem-module tests are run.

Require zero exit status, empty stderr, complete same-host stdout byte equality,
and the expected final marker. Capture raw bytes before decoding diagnostics.
A 120-second timeout, crash, or resource exhaustion fails acceptance. Start with
the default 1,000,000 instructions. Only measured instruction-only exhaustion
permits the explicitly recorded 20,000,000 runner profile; product defaults stay
unchanged. Keep failed inputs/output in ignored reports for diagnosis.

The isolated C99 host-layout probe and Ada layout probe compare native widths,
alignments, endianness, and Lua numeric layout, including long double in maximum
alignment. They are test programs, never production dependencies. Virtual
packsize checks must remain independent of allocation quotas.

Every Windows/Linux/macOS × development/validation/release × static/shared job
must run focused tests, API/CLI consumers, existing regressions, and all three
primary files. Each OS's static-validation job adds layout/differential and ABI
checks; Windows retains static-PIC. A local three-file success cannot substitute
for missing matrix evidence or justify a complete standard-suite claim.

## Test layers

M3 adds a separate [conformance foundation](../tests/conformance/README.md).
Its foundation validation permits pending coverage; final acceptance does not.
Read the [M3 contract](milestones/m3.md) before interpreting a C baseline,
lexical inventory, test-mode result, or successful process exit as Ada coverage.
An unchanged default all.lua run with T absent skips internal/API tests.
Those skips remain unresolved until corresponding real tests or reviewed
equivalents pass. The current Ada runtime is not expected to pass that suite yet.

Every existing matrix job validates the inventory and runs focused harness
self-tests. Each OS's static-validation job also builds both isolated C
configurations, requires their smoke checks, and collects aggregate/heavy
observations as raw CI artifacts. Report-only collection preserves ordinary
native test failures and skips; setup, timeout, resource, crash-like, capture,
and fixture-integrity failures still fail the job. This foundation evidence
does not certify complete C or Ada suite execution.

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

## Mathematics and seeded RNG

The complete local validation/static pipeline builds the owning library, CLI
and AUnit consumers, then discovers mathematics_campaign.lua alongside the
other first-party differential fixtures:

```text
pwsh -NoProfile -File scripts/check.ps1 -Profile validation -LibraryType static
```

Lua.Mathematics_Tests registers 38 separately named cases. They cover host IEEE
domains and signed zero, subnormal frexp decomposition, ldexp's C exponent cast,
numeric-string arguments, pinned integer/float streams, rejection consumption,
invalid-call advancement, independent states, 32/64-bit arithmetic equivalence
and budget-preserving initialization/retries. Setup and expected-error helpers
must execute the tested call inside its handled sequence; declaration-time
failure must not accidentally become an unexpected AUnit exception.

The differential fixture uses explicit pairs (0,0), (17,-9),
(maxinteger,mininteger) and (-1,-1). It encodes binary64 values as bytes, retaining
signed zero and host NaN bits. For C frexp's unspecified infinity/NaN exponent,
only the fraction result is compared; all finite decomposition outputs remain
in scope. Failure messages are compared by controlled outcome rather than
source-path-dependent wording.

The same fixture executes against the isolated instrumented C oracle, where
the compatibility-only math names add one output line. Its current 714/715
default/instrumented C lines and empty stderr are fixture-validation evidence,
not Ada parity or an unchanged math.lua pass. Actual instrumented Ada comparisons
require their separate configured runtime and completed conformance launcher;
do not substitute a default binary or enable names only inside a test script.

The [host mathematics decision](decisions/0011-host-mathematics.md) records the
standard-Ada alternative, narrow libm imports and ownership boundary. Final
acceptance still requires each target OS/profile/link configuration and the full
M3 coverage contract. Optional proof/fuzz tools are not prerequisites here.

## Canonical compiler and codec checks

Standalone canonical prototype/chunk checks use the nested Lua.Chunk_Tests
suite and scripts/check-chunk-codec.ps1. The [codec guide](binary-chunks.md)
owns the native-profile commands and byte-exact/C-crossload evidence boundary.
These checks do not execute canonical instructions in Ada or replace unchanged
upstream runtime acceptance.

Lua.Canonical_Compiler_Tests and scripts/check-canonical-compiler.ps1 separately
cover canonical lowering. Its compiler-only mode executes both C-generated and
Ada-generated programs in isolated C processes; it supplies no Ada VM evidence.
Passing RuntimeProbe with lua-canonical_runtime_probe adds actual Ada execution
of both compilers' chunks, requiring all four outputs to agree. Reports retain
which mode and configuration actually ran.
[Runtime configurations](runtime-configurations.md) documents source selection,
artifact separation and the distinct parser/math configuration witness.

## Shared Ada/C library identity

scripts/check-core-image.ps1 builds the sole production root SAL and its C API,
mixed Ada/C and C-only startup consumers for the requested profile/library kind.
It checks real state/thread/stack/allocator identity and the actual pool address
and GNAT elaboration counter; the latter two are compiler-specific test probes.
No test observer is added to the interpreter library. Raw output, executable/
library hashes and process results are retained under reports/core-image.
[The validation owner](validation-one-core.md) records executed configurations.
scripts/check.ps1 invokes this campaign per job; a missing platform run is not
implied by the workflow. Native module loading and full C exports remain separate.

## Managed numeric formatting

Lua.Managed_Format_Tests registers sixteen independent cases for exact rounding,
exponent boundaries, numeric strings, actual output ownership and partial-growth
refusal/recovery. The deterministic formatting_campaign.lua fixture adds 143
binary64 values across ten formats, retaining seed 0x13579bdf2468ace0 and exact
same-host output. Its 1,435 lines are compared by scripts/compare.ps1 alongside
the other first-party scripts. [Numeric formatting](number-formatting.md) owns
the algorithm and recorded evidence; whole upstream string/math files and other
platforms remain separate acceptance requirements.

## Owned activation storage

Lua.Frame_Cache_Tests registers eleven independent cases for stable reuse,
per-context ownership, retained packet/nested capacity, continuation reset,
cell detachment, root removal, refusal, duplicate retirement, teardown and
active-resumer depth preservation. The teardown case inspects actual live
managed blocks after Finalize; passing printed assertions alone cannot hide
shutdown leaks. [Activation storage](activation-storage.md) owns the cache
contract and the 951-case Windows/default/static checkpoint evidence.

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

## Language lifecycle acceptance

Run scripts/check-lifecycle.ps1 -Interpreter <normal-cli> after building the C
oracle. The runner uses unchanged hash-verified goto.lua and coroutine.lua in
fresh C/Ada processes, compares raw same-host output and empty stderr, requires
OK, and rejects every omission message except the two explicitly inventoried
T-absent coroutine messages. See the [acceptance owner](milestones/m3-language-lifecycle.md)
for every omitted source anchor. Default coroutine execution is not C-API
conformance. Timeout is 900 seconds and the sampled resident-process watchdog is
2 GiB; this is distinct from C managed-allocation accounting.

The product CLI selects compatible quotas. Retained M2b primary files use the
separate bounded upstream_runner profile unchanged. scripts/check.ps1 runs both
groups in every matrix configuration. Runtime_Control_Tests has independently
named/commented cases for state transitions, close paths, cells, weak graphs,
inspection, hooks, native callback yield restrictions and host-policy recovery.
Seeded lifecycle campaigns preserve source and mismatch output as regressions;
crashes, resource failures and timeouts never count as syntax rejection or skips.
