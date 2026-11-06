# Unified Ada/C Core Validation

Date: 2026-11-06, Asia/Tokyo. Scope: production core-image evidence for
[ADR 0014](decisions/0014-one-core-library.md). These checks use the production
root library, rather than the earlier reports-only observation prototype.

The later Windows x64 unwind repair preserves -Es and all compiler checks.
Before the repair, the final PE contained overlapping ordinary C unwind ranges;
GDB located the resulting allocator-refusal crash in RtlVirtualUnwind2 during
Ada traceback capture. Decoding the partial object showed its later C rows all
targeting the first zero-offset section symbols. Windows-only C function
sections repair those actual relocations. The rebuilt validation/static image
passes all 32 real C cases in reports/m3-c-unwind-consumer1.log, including the
guarded continued-refusal path and balanced 26-point construction sweep.
Its final exception directory has 11,930 disjoint entries. Eleven focused
PE-reader cases pass. Shared/final-platform evidence for this source repair is
recorded separately; earlier matrix results do not establish its acceptance.

## Verified configurations

The selected GNAT 16.1.0 and GPRbuild 26.0.1 compiled the ordinary default
configuration with runtime checks and all required strict compiler switches.

| Configuration                               | C API consumer  | Mixed Ada/C consumer | C-only startup |
| ------------------------------------------- | --------------- | -------------------- | -------------- |
| Windows development/static/shared           | pass            | pass                 | pass           |
| Windows validation/static/shared            | pass            | pass                 | pass           |
| Windows release/static/shared               | pass            | pass                 | pass           |
| Linux development/static/shared             | pass            | pass                 | pass           |
| Linux validation/static/shared              | pass            | pass                 | pass           |
| Linux release/static/shared                 | pass            | pass                 | pass           |
| macOS development/static/shared             | pass            | pass                 | pass           |
| macOS validation/static/shared              | pass            | pass                 | pass           |
| macOS release/static/shared                 | pass            | pass                 | pass           |
| Instrumented upstream-test                  | pending         | pending              | pending        |

The initial local C API consumer passed eighteen named cases, including the
measured 21-point cold constructor refusal sweep. Later checkpoints expand that
consumer; its [owning guide](../c_api/README.md) records their separate scope.
The mixed consumer executes an Ada
session, constructs a separate real C state, reads its stack/main-thread through
the Ada dispatcher, writes a stack value from Ada, and observes that value in C.
Both interfaces return the same actual stored allocator callback. The actual
Storage.Pool symbol address matches its Ada object address, and GNAT's actual
package-elaboration counter is one before and after construction/closure.
The separate C-only executable repeats construction from an ordinary C main,
without explicit Ada startup calls. GPRbuild still supplies generated binder
glue for this consumer; a bare compiler/linker installation test is separate.

The pool/counter assertions intentionally depend on the selected GNAT symbol
convention. They are test-only observations of the actual production image;
the library contains no extra probe unit or fabricated observer counter.

The final static child-test build/run also passed **851/851 AUnit cases** with
zero failed assertions and zero unexpected errors. This includes the three new
host-arithmetic tests. Existing private child tests remain usable against the
standard standalone library through its explicit interface list.

The later [checkpoint-two matrix](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42201161223)
passed all twelve Linux/Windows profile/link jobs. All six macOS jobs failed
before retained runtime acceptance. Static C clients lacked
__gnat_tasking_runtime_initialize because their final link named only libgnat,
not libgnarl. Shared clients built but their first C API process failed; the
initial driver retained stderr locally without uploading/printing it, so that
failure's exact diagnostic was not available from the original job artifacts.

The repair supplies the selected compiler's tasking archive before its core
archive and explicitly retains the real Darwin tasking-init symbol for shared
flat lookup. The driver now prints failed-child captures and CI uploads the
core-image report directory for every job. The next run exposed two remaining
causes: the importing Ada main also needed GNARL, and the shared loader lacked a
clean adalib path for libgnarl-16.dylib. The root propagates its runtime closure
to importing projects. Drivers discover the actual runtime directory, preserve
clean DYLD paths and embed its LC_RPATH for child processes.

All six macOS jobs in the [940-case checkpoint matrix](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42207946868)
then passed, and every Mac log was inspected: all three core-image consumers,
940 AUnit cases, retained upstream/CLI/binary checks and formatting/math campaigns
completed. Linux core consumers also passed, but that complete run failed its
separate alternate-general formatting differential. These independent outcomes
must not be combined into a green complete-milestone matrix.

The later [1,009-case checkpoint matrix](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42217665982)
passed all eighteen target OS/profile/link jobs and Windows static-PIC. Every
job log was inspected: the C API consumer, mixed Ada/C consumer and C startup
consumer all passed against the one selected core image. The independent
formatting regression also passed at this checkpoint. The suite still covers
five unchanged upstream execution files; report-only C conformance observations
and the unfinished full M3 ledger are separate from this passing retained
matrix. Subsequent output/IO/OS changes need fresh final-revision evidence.

The [1,038-case output-policy checkpoint](https://github.com/itsuki-hayashi/lua-ada/actions/runs/42221667221)
also passed all eighteen jobs and Windows static-PIC. Every log was inspected:
the three core consumers and nine raw-byte output-policy subprocesses passed
on every configuration. Windows logs additionally validate exception-directory
and unwind-table structure in each of those three consumer executables, and
in the shared Lua image when applicable. These checks concern actual linked
images; eleven separate malformed/synthetic-image cases exercise the validator
itself. IO/OS and remaining full-suite obligations still need their later
implementation and final-revision evidence.

## Commands and reports

```powershell
pwsh -File scripts/check-core-image.ps1 -Profile validation -LibraryType static
pwsh -File scripts/check-core-image.ps1 -Profile validation -LibraryType relocatable
alr -C tests build --validation --profiles=lua_ada=validation -- `
  -XLUA_ADA_LIBRARY_TYPE=static
alr -C tests exec -- bin/static/test_runner
alr exec -- gprbuild -P c_api/lua_c_api.gpr -XLUA_ADA_LIBRARY_TYPE=static
```

The passing logs are reports/m3-one-core-production-static-check3.log,
reports/m3-one-core-production-shared-check2.log,
reports/m3-one-core-aunit-build2.log, reports/m3-one-core-aunit.log, and
reports/m3-one-core-legacy-forwarding.log. Per-process output and structured
results live under reports/core-image. A timed-out, nonzero or stderr-producing
consumer fails the driver. The compatibility aggregate compiled no separate
C-facade core; its dependency is the root project alone.

The first strict consumer build needed the same separate Ada main declaration
as existing private-unit probes. Three newly added math-test registrations also
needed wrapping to meet 79 columns. The first shared mixed assertion compared a
host import-thunk address with an actual DLL callback address. The corrected
assertion compares the world's actual callback returned independently through
both interfaces. This is a test correction, not a runtime identity workaround.
All named passing logs are later runs after these failures were corrected.

## Remaining acceptance

scripts/check.ps1 now runs core-image consumers for its selected profile/kind,
and includes the separate binary CLI campaign. Their inclusion is an executable
workflow, not evidence that unrun jobs passed. The complete platform/profile/
linking matrix, upstream-test Ada configuration, static-PIC, dynamic native
modules, concurrent first entry, full C exports and full upstream suite remain
separate acceptance obligations. Ordinary Lua Ada and C consumers now share one
compiled core; that architectural property does not imply complete C ABI parity.
