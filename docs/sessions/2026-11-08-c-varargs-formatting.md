# Public C varargs formatting checkpoint

Date: 2026-11-08, Asia/Tokyo.

Continue the approved remaining-upstream delivery on
codex/m3-remaining-upstream-compatibility from integrated builtin checkpoint
557b8c0. This component completes two public exports with managed formatting
storage, shared numeric and UTF-8 rendering, C-only nonlocal transfer guards,
and bounded-session work/string enforcement. See
[ADR 0022](../decisions/0022-c-varargs-formatting.md) for the measured pinned
manual/implementation discrepancy and the alternatives considered.

The first strict compile rejected an incorrect access conversion and a
redundant context clause; both causes were corrected. The first C comparison
also rejected a mistaken test length, then exposed the nonthrowing va_list
stack behavior. The implementation and fixture were corrected from actual
pinned source and native execution rather than weakening a failing assertion.

## Local validation

Windows x86-64, Alire 2.1.1, native GNAT 16.1.0 and GPRbuild package 26.0.1
(executable 26.0.0). No toolchain pin or reference revision was changed.

```text
alr -n build --validation -- -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_PREBUILT=false
alr exec -- gprbuild -P c_api/consumer.gpr -p -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_PREBUILT=true
alr -n build --validation --profiles=lua_ada=validation -- -XLUA_ADA_LIBRARY_TYPE=static -XLUA_ADA_PREBUILT=true
alr exec -- bin/static/test_runner.exe
```

The last two commands run in tests/. Strict root, C consumer and test builds
pass. All 1,551 AUnit cases pass, with no failed assertions or unexpected
errors. The two new formatter cases use real C callbacks, verify uncatchable
host work/string aborts, execute a subsequent recovery chunk and inspect zero
live managed blocks after finalization.

The identical format_api_contract.c passes against the Ada image and separately
compiled default and instrumented C images. All three print the same four
named cases and completion marker, with empty stderr and exit zero. Persistent
fault sweeps cover each image's measured allocation-growth sequence; geometry
and allocation counts are intentionally not compared. Each refusal recovers
for successful formatting, and state closure releases every allocator block.

Ignored raw logs are reports/remaining-format-{build,consumer-build,
tests-build,aunit,ada,native,native-t}.log. The observations come from this
component's dirty implementation tree, not an immutable final target revision.
They do not close any global source/API ledger, file scope, platform matrix,
independent acceptance certificate or review gate. Remaining auxiliary APIs,
native module loading, CLI work and complete upstream acceptance stay open.
